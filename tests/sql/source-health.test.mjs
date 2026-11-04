import assert from 'node:assert/strict';
import {createDatabase} from './helpers.mjs';

const db = await createDatabase();
try {
  await db.exec(`INSERT INTO events(name,path,session_id,anonymous_id,occurred_at,received_at,props)
      VALUES('pageview','/source','health-session','health-visitor',now(),now(),'{}');
    INSERT INTO gsc_path_daily(day,path,clicks,impressions) VALUES(paris_today()-3,'/source',1,1);
    INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,completed_at,row_counts)
      VALUES(gen_random_uuid(),paris_today()-4,paris_today()-3,'completed',now(),
        '{"gsc_path_daily":1,"gsc_query_page_daily":1}');
    INSERT INTO cooked_config(key,value) VALUES('identity_stitch_refreshed_at',now()::text);`);
  const rows = async sql => (await db.query(sql)).rows;
  assert.deepEqual(await rows('SELECT status,issues FROM refresh_pipeline_health()'), [{status:'healthy',issues:[]}]);
  assert.equal((await rows("SELECT count(*)::int AS n FROM latest_rpc_health() WHERE status='missing'"))[0].n,6);
  await db.query('SELECT run_rpc_contract_tests()');
  assert.deepEqual(await rows("SELECT rpc_name,status,detail FROM latest_rpc_health() WHERE status<>'ok'"),[]);
  assert.deepEqual(await rows('SELECT kind FROM alert_rule_rpc_health()'),[]);
  await db.exec(`INSERT INTO rpc_health(rpc_name,status,checked_at) VALUES
    ('retired_reader','failed',now()), ('core_canonical_path','failed',now()+interval '1 second');`);
  assert.deepEqual(await rows('SELECT kind FROM alert_rule_rpc_health()'),[{kind:'rpc_failed_core_canonical_path'}],
    'only failures of current core contracts are actionable');
  await db.exec(`INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,started_at)
    VALUES(gen_random_uuid(),paris_today()-4,paris_today()-3,'failed',now()-interval '4 hours');`);
  assert.deepEqual(await rows('SELECT status,issues FROM refresh_pipeline_health()'),
    [{status:'critical',issues:['gsc_ingest_incomplete']}], 'an earlier complete import cannot hide the latest failed batch');
  assert.equal((await rows("SELECT count(*)::int AS n FROM alert_rule_gsc_ingest_missed() WHERE kind='gsc_ingest_incomplete'"))[0].n,1);
  await db.exec("UPDATE events SET received_at=now()-interval '7 hours' WHERE session_id='health-session'");
  assert.ok((await rows('SELECT issues FROM refresh_pipeline_health()'))[0].issues.includes('ingestion_stopped'));
  console.log('Core health: current sources, six contracts, retired-result exclusion, incomplete GSC and stopped reception verified.');
} finally {
  await db.close();
}
