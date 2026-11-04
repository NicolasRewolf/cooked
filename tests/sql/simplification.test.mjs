import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createDatabase,applyMigration,root} from './helpers.mjs';

const db=await createDatabase();
try {
  await applyMigration(db,'_canonical_visits_and_identity.sql');
  await db.exec(`
    CREATE SCHEMA cron;
    CREATE TABLE cron.job(jobid bigint,jobname text,active boolean,schedule text);
    CREATE TABLE cron.job_run_details(jobid bigint,start_time timestamptz,status text);
    -- PGlite n’embarque pas pg_cron : reproduire son API, pas modifier sa table
    -- depuis la migration. Ce double ne valide pas les privilèges de l’extension.
    CREATE FUNCTION cron.alter_job(job_id bigint, schedule text DEFAULT NULL,
      command text DEFAULT NULL, database text DEFAULT NULL,
      username text DEFAULT NULL, active boolean DEFAULT NULL)
    RETURNS void LANGUAGE plpgsql AS $cron$
    BEGIN
      IF command IS NOT NULL OR database IS NOT NULL OR username IS NOT NULL THEN
        RAISE EXCEPTION 'cron test double supports schedule and active only';
      END IF;
      UPDATE cron.job SET schedule=coalesce($2,cron.job.schedule),
        active=coalesce($6,cron.job.active) WHERE jobid=$1;
      IF NOT FOUND THEN RAISE EXCEPTION 'unknown cron job'; END IF;
    END;
    $cron$;
    INSERT INTO cron.job VALUES
      (1,'cooked-refresh-after-gsc',true,'0 6-21 * * *'),
      (2,'cpi-calibration-monthly',true,'0 5 1 * *'),
      (3,'math-refresh-snapshots-weekly',true,'10 5 * * 0'),
      (4,'refresh_seo_url_snapshot',true,'0 3 * * *'),
      (5,'refresh-identity-stitch',true,'40 3 * * *'),
      (6,'run_rpc_contract_tests',true,'30 3 * * *');
    ALTER TABLE rpc_health ALTER checked_at SET DEFAULT now();
    INSERT INTO alerts(kind,severity,detail,acked) VALUES
      ('cpi_daily_stale','warn','synthetic',false),
      ('refresh_step_failed_cooked_cpi_snapshot','critical','synthetic',false),
      ('gsc_path_daily_gap','warn','synthetic',false),
      ('form_submit_dropped','critical','synthetic',false);
    INSERT INTO freshness_contract(source,enabled) VALUES
      ('cpi_daily',true),('cpi_calibration_checks',true),
      ('dashboard_resources_snapshot',true),('dfs_keyword_volume',true),
      ('math_visit_sequences_snapshot',true),('seo_url_snapshot',true),
      ('gsc_path_daily',true);
    INSERT INTO cpi_daily(day,path,cpi) VALUES ('2026-05-01','/archive',42);
    INSERT INTO seo_url_snapshot(path,refreshed_at) VALUES ('/archive','2026-05-01');
    INSERT INTO dashboard_resources_snapshot(window_kind,path) VALUES ('rolling_90','/archive');
    INSERT INTO math_visit_sequences_snapshot(window_days,journey,n) VALUES(28,ARRAY['/archive'],1);
    INSERT INTO conversion_weekly(week_start,contact_kind) VALUES('2026-05-04','phone');
    INSERT INTO gsc_path_daily(day,path,clicks,impressions) VALUES(public.paris_today()-3,'/source',1,1);
    INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,completed_at,row_counts)
      VALUES(gen_random_uuid(),public.paris_today()-4,public.paris_today()-3,'completed',now(),
        '{"gsc_path_daily":1,"gsc_query_daily":1,"gsc_query_page_daily":1}');
    INSERT INTO events(name,path,session_id,anonymous_id,occurred_at,received_at,props)
      VALUES('pageview','/source','observed-session','observed-visitor',now(),now(),'{}');
    INSERT INTO cooked_config(key,value) VALUES('identity_stitch_refreshed_at',now()::text)
      ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value;
  `);
  const historyTables=['cpi_daily','seo_url_snapshot','dashboard_resources_snapshot',
    'math_visit_sequences_snapshot','conversion_weekly'];
  async function history(){
    return Promise.all(historyTables.map(async t=>(await db.query(`SELECT to_jsonb(t) AS row FROM public.${t} t`)).rows));
  }
  const oldHistory=await history();
  await applyMigration(db,'_retire_legacy_calculations.sql');
  assert.deepEqual(await history(),oldHistory,'retired calculations preserve all historical rows');
  assert.deepEqual((await db.query('SELECT jobname,active FROM cron.job ORDER BY jobid')).rows,[
    {jobname:'cooked-refresh-after-gsc',active:false},
    {jobname:'cpi-calibration-monthly',active:false},
    {jobname:'math-refresh-snapshots-weekly',active:false},
    {jobname:'refresh_seo_url_snapshot',active:false},
    {jobname:'refresh-identity-stitch',active:true},
    {jobname:'run_rpc_contract_tests',active:true},
  ]);
  assert.equal((await db.query("SELECT schedule FROM cron.job WHERE jobname='run_rpc_contract_tests'")).rows[0].schedule,'50 3 * * *');
  assert.deepEqual((await db.query('SELECT source FROM freshness_contract WHERE enabled ORDER BY source')).rows,[{source:'gsc_path_daily'}]);
  assert.deepEqual((await db.query('SELECT kind,acked FROM alerts ORDER BY kind')).rows,[
    {kind:'cpi_daily_stale',acked:true},{kind:'form_submit_dropped',acked:false},
    {kind:'gsc_path_daily_gap',acked:false},{kind:'refresh_step_failed_cooked_cpi_snapshot',acked:true},
  ],'only explicitly retired alert families are closed');
  const migrationName=fs.readdirSync(root+'/supabase/migrations').find(name=>name.endsWith('_retire_legacy_calculations.sql'));
  const retired=fs.readFileSync(root+'/supabase/migrations/'+migrationName,'utf8')
    .matchAll(/DROP FUNCTION IF EXISTS (.+);/g);
  for(const [,signature] of retired){
    assert.equal((await db.query('SELECT to_regprocedure($1) AS f',[signature.replace(/\b\w+ (integer|text|date)(?=[,)])/g,'$1')])).rows[0].f,null,signature);
  }
  assert.equal((await db.query("SELECT count(*)::int n FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'dashboard\\_%'")).rows[0].n,16,'all dashboard readers remain');
  for(const signature of ['refresh_pipeline_health()','latest_rpc_health()','alert_rule_rpc_health()',
    'run_rpc_contract_tests()','alert_rule_gsc_ingest_missed()']){
    const {rows:[acl]}=await db.query(`SELECT
      has_function_privilege('anon',$1,'EXECUTE') AS anon,
      has_function_privilege('authenticated',$1,'EXECUTE') AS authenticated,
      has_function_privilege('service_role',$1,'EXECUTE') AS service`,[signature]);
    assert.deepEqual(acl,{anon:false,authenticated:false,service:true},signature+' preserves its ACL');
  }
  const {rows:[health]}=await db.query('SELECT * FROM refresh_pipeline_health()');
  assert.equal(health.status,'healthy','frozen derived sources do not trigger an incident');
  assert.equal(health.cron_last_status,'suspended');
  assert.deepEqual(health.issues,[]);
  assert.equal((await db.query('SELECT * FROM latest_rpc_health()')).rows.length,6);
  assert.equal((await db.query("SELECT count(*)::int n FROM latest_rpc_health() WHERE status='missing'")).rows[0].n,6);
  // Public exposure is tested with the actual routines, restoring the production ACL pattern.
  await db.exec('REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC,anon,authenticated;');
  await db.exec('SELECT run_rpc_contract_tests()');
  assert.deepEqual((await db.query("SELECT rpc_name,status,detail FROM latest_rpc_health() WHERE status<>'ok'")).rows,[]);
  assert.equal((await db.query('SELECT * FROM alert_rule_rpc_health()')).rows.length,0);
  await db.exec(`INSERT INTO rpc_health(rpc_name,status,checked_at) VALUES
    ('dashboard_resources_overview','failed',now()),
    ('core_canonical_path','failed',now()+interval '1 second');`);
  assert.deepEqual((await db.query('SELECT kind FROM alert_rule_rpc_health()')).rows,[{kind:'rpc_failed_core_canonical_path'}],
    'current contract failure is surfaced, retired historical failure is excluded');
  await db.exec(`INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,started_at)
    VALUES(gen_random_uuid(),public.paris_today()-4,public.paris_today()-3,'failed',now()-interval '4 hours');`);
  assert.equal((await db.query("SELECT count(*)::int n FROM alert_rule_gsc_ingest_missed() WHERE kind='gsc_ingest_incomplete'")).rows[0].n,1,
    'a failed source batch still alerts after downstream retirement');
  assert.equal((await db.query('SELECT status FROM refresh_pipeline_health()')).rows[0].status,'critical');
  await applyMigration(db,'_retire_legacy_calculations.sql');
  assert.deepEqual(await history(),oldHistory,'replaying retirement preserves history');
  if(process.env.SQL_SIMPLIFIED_EXPORT){
    const definitions=(await db.query(`SELECT p.oid::regprocedure::text AS signature,pg_get_functiondef(p.oid) AS ddl
      FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.prokind IN('f','p') ORDER BY 1`)).rows;
    fs.writeFileSync(process.env.SQL_SIMPLIFIED_EXPORT,definitions.map(d=>`\n-- ═══ public.${d.signature} ═══\n${d.ddl}`).join('\n'));
  }
  console.log('Simplification: archive preservation, schedules, scoped alert resolution, contracts and source health verified.');
} catch(error) {
  console.error(error.message,error.detail ?? '',error.where ?? ''); process.exitCode=1;
} finally {
  await db.close();
}
