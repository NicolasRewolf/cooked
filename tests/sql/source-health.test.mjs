import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db = await createDatabase();
try {
  // Freeze only time in this disposable database; evaluate the real SQL functions.
  await db.exec(`CREATE OR REPLACE FUNCTION pg_catalog.now() RETURNS timestamptz
      LANGUAGE sql STABLE AS $$SELECT timestamptz '2026-11-04 13:00:00+00'$$;
    INSERT INTO events(name,path,session_id,anonymous_id,occurred_at,received_at,props)
      VALUES('pageview','/source','health-session','health-visitor',now(),now(),'{}');
    INSERT INTO gsc_path_daily(day,path,clicks,impressions) VALUES(paris_today()-3,'/source',1,1);
    INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,completed_at,row_counts)
      VALUES(gen_random_uuid(),paris_today()-4,paris_today()-3,'completed',now(),
        '{"gsc_path_daily":1,"gsc_query_page_daily":1}');
    INSERT INTO cooked_config(key,value) VALUES('identity_stitch_refreshed_at',now()::text);`);
  const contractSql = `INSERT INTO freshness_contract
    (source,label,last_point_sql,cadence,normal_lag_days,warn_after_days,critical_after_days,enabled)
    VALUES('gsc_path_daily','Google pages','SELECT max(day) FROM public.gsc_path_daily','daily',3,6,10,true)`;
  await db.exec(contractSql);
  const rows = async (sql, params = []) => (await db.query(sql, params)).rows;
  const health = () => rows('SELECT status,issues FROM refresh_pipeline_health()');
  const expectHealth = async (status, issues, message) =>
    assert.deepEqual(await health(), [{status,issues}], message);
  const setDataAge = age => db.query('UPDATE gsc_path_daily SET day=paris_today()-$1::int', [age]);
  const baseline = await rows('SELECT * FROM refresh_pipeline_health()');
  await applyMigration(db, '_reuse_freshness_rules.sql');
  assert.deepEqual(await rows('SELECT * FROM refresh_pipeline_health()'), baseline,
    'the migration preserves every healthy observation with the current contract');
  await expectHealth('healthy', []);

  assert.equal((await rows("SELECT count(*)::int AS n FROM latest_rpc_health() WHERE status='missing'"))[0].n,6);
  await db.query('SELECT run_rpc_contract_tests()');
  assert.deepEqual(await rows("SELECT rpc_name,status,detail FROM latest_rpc_health() WHERE status<>'ok'"),[]);
  assert.deepEqual(await rows('SELECT kind FROM alert_rule_rpc_health()'),[]);
  await db.exec(`INSERT INTO rpc_health(rpc_name,status,checked_at) VALUES
    ('retired_reader','failed',now()), ('core_canonical_path','failed',now()+interval '1 second');`);
  assert.deepEqual(await rows('SELECT kind FROM alert_rule_rpc_health()'),[{kind:'rpc_failed_core_canonical_path'}],
    'only failures of current core contracts are actionable');

  // Thresholds remain strict and changing the single contract changes both readers.
  for (const [warn, critical, age, severity] of [
    [6,10,6,null], [6,10,7,'warn'], [6,10,10,'warn'], [6,10,11,'critical'],
    [6,10,-2,null], [4,8,5,'warn'], [4,8,9,'critical'], [4,null,30,'warn'],
  ]) {
    await db.query(`UPDATE freshness_contract SET warn_after_days=$1,critical_after_days=$2
      WHERE source='gsc_path_daily'`, [warn,critical]);
    await setDataAge(age);
    const state = severity === 'critical' ? 'critical' : severity ? 'degraded' : 'healthy';
    const issue = severity === 'critical' ? 'gsc_source_stale' : 'gsc_source_delayed';
    await expectHealth(state, severity ? [issue] : [], `contract ${warn}/${critical}, age ${age}`);
    assert.deepEqual(await rows("SELECT severity FROM alert_rule_freshness() WHERE kind='gsc_path_daily_stale'"),
      severity ? [{severity}] : []);
    assert.equal(Number((await rows('SELECT gsc_data_age_days AS age FROM refresh_pipeline_health()'))[0].age), age,
      'diagnostic age remains the raw observed age, including a future date');
  }
  await db.exec(`UPDATE freshness_contract SET warn_after_days=6,critical_after_days=10;
    DELETE FROM gsc_path_daily;`);
  await expectHealth('critical', ['gsc_source_stale'], 'missing data remains critical');
  assert.deepEqual(await rows("SELECT severity FROM alert_rule_freshness() WHERE kind='gsc_path_daily_stale'"),
    [{severity:'critical'}]);

  // Gap and other-source alerts retain their own scope, outside this pipeline summary.
  await db.exec(`INSERT INTO gsc_path_daily(day,path,clicks,impressions)
      VALUES(paris_today()-2,'/source',1,1),(paris_today(),'/source',1,1);
    UPDATE freshness_contract SET gap_relation='gsc_path_daily',gap_day_column='day',gap_window_days=90;
    INSERT INTO freshness_contract
      (source,label,last_point_sql,cadence,normal_lag_days,warn_after_days,critical_after_days,enabled)
      VALUES('form_submit','Forms','SELECT NULL::date','event',0,2,4,true);`);
  assert.deepEqual(await rows('SELECT kind,severity FROM alert_rule_freshness() ORDER BY kind'),
    [{kind:'form_submit_stale',severity:'critical'}, {kind:'gsc_path_daily_gap',severity:'warn'}]);
  await expectHealth('healthy', [], 'unrelated source and gap alerts do not broaden the summary');
  await db.exec(`DELETE FROM freshness_contract WHERE source='form_submit';
    UPDATE freshness_contract SET gap_relation=NULL,gap_day_column=NULL,gap_window_days=NULL;
    DELETE FROM gsc_path_daily WHERE day<paris_today();`);

  await db.exec("UPDATE freshness_contract SET enabled=false WHERE source='gsc_path_daily'");
  await expectHealth('critical', ['gsc_freshness_contract_unavailable'], 'disabled contract cannot imply healthy');
  await db.exec("DELETE FROM freshness_contract WHERE source='gsc_path_daily'");
  await expectHealth('critical', ['gsc_freshness_contract_unavailable'], 'missing contract cannot imply healthy');
  await db.exec(contractSql);

  // The UTC-noon alert stays distinct from the summary's elapsed-hour thresholds.
  await db.exec("UPDATE gsc_ingest_batches SET completed_at=now()-interval '24 hours'");
  assert.deepEqual(await rows('SELECT kind FROM alert_rule_gsc_ingest_missed()'), [{kind:'gsc_ingest_missed'}]);
  await expectHealth('healthy', [], 'a missed UTC-day import alone does not change summary scope');
  for (const [age, status, issues] of [
    ['30 hours','healthy',[]], ['30 hours 17 seconds','healthy',[]],
    ['30 hours 19 seconds','degraded',['gsc_source_delayed']],
    ['72 hours','degraded',['gsc_source_delayed']],
    ['72 hours 17 seconds','degraded',['gsc_source_delayed']],
    ['72 hours 19 seconds','critical',['gsc_source_stale']],
  ]) {
    await db.query('UPDATE gsc_ingest_batches SET completed_at=now()-$1::interval', [age]);
    await expectHealth(status, issues, `import age is rounded before comparison: ${age}`);
  }
  await db.exec("UPDATE gsc_ingest_batches SET completed_at=now()");
  await db.exec(`INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,started_at)
    VALUES(gen_random_uuid(),paris_today()-4,paris_today()-3,'failed',now()-interval '4 hours');`);
  for (const batchStatus of ['failed','running']) {
    for (const [age, incomplete] of [['3 hours',false], ['3 hours 1 second',true]]) {
      await db.query(`UPDATE gsc_ingest_batches SET status=$1,started_at=now()-$2::interval
        WHERE batch_no=(SELECT max(batch_no) FROM gsc_ingest_batches)`, [batchStatus,age]);
      await expectHealth(incomplete ? 'critical' : 'healthy', incomplete ? ['gsc_ingest_incomplete'] : [],
        `the latest ${batchStatus} batch is not hidden by an earlier completed import`);
      assert.deepEqual(await rows("SELECT kind FROM alert_rule_gsc_ingest_missed() WHERE kind='gsc_ingest_incomplete'"),
        incomplete ? [{kind:'gsc_ingest_incomplete'}] : []);
    }
  }
  await db.exec("DELETE FROM gsc_ingest_batches WHERE status<>'completed'");

  for (const [age, stopped] of [['360 minutes',false], ['360 minutes 2 seconds',false], ['360 minutes 4 seconds',true]]) {
    await db.query("UPDATE events SET received_at=now()-$1::interval WHERE session_id='health-session'", [age]);
    await expectHealth(stopped ? 'critical' : 'healthy', stopped ? ['ingestion_stopped'] : [],
      `reception age is rounded before comparison: ${age}`);
  }
  await db.exec(`UPDATE events SET received_at=now()-interval '60 minutes';
    INSERT INTO events(name,path,occurred_at,received_at,props)
      VALUES('web_vitals','/source',now(),now(),'{}');`);
  assert.equal(Number((await rows('SELECT events_last_60min AS n FROM refresh_pipeline_health()'))[0].n), 2,
    'the diagnostic counts all raw events and includes the exact 60-minute boundary');

  await db.exec(`UPDATE events SET received_at=now()-interval '7 hours';
    UPDATE gsc_path_daily SET day=paris_today()-11;
    INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,started_at)
      VALUES(gen_random_uuid(),paris_today()-4,paris_today()-3,'failed',now()-interval '4 hours');`);
  await expectHealth('critical', ['ingestion_stopped','gsc_source_stale','gsc_ingest_incomplete'],
    'multiple failures retain their original order');
  await db.exec(`DELETE FROM events; DELETE FROM gsc_ingest_batches;`);
  await expectHealth('critical', ['ingestion_stopped','gsc_source_stale'], 'empty reception and import history remain critical');
  console.log('Core health: shared freshness thresholds, scope, incomplete batches, rounding, missing contracts and six core checks verified.');
} finally {
  await db.close();
}
