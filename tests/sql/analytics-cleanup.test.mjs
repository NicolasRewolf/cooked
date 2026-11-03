import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db = await createDatabase();
try {
  await db.exec(`INSERT INTO page_taxonomy(path,category) VALUES('/post/cleanup','ressource');
    INSERT INTO events(name,path,anonymous_id,session_id,occurred_at,props)
    SELECT event_name,'/post/cleanup','visitor-'||days_ago,'session-'||days_ago,
      cooked_paris_ts_start(paris_today()-days_ago)+interval '12 hours'+offset_time,'{}'::jsonb
    FROM (VALUES(2),(30),(100)) d(days_ago)
    CROSS JOIN (VALUES('pageview',interval '0 seconds'),('cta_phone_click',interval '30 seconds')) e(event_name,offset_time);
    INSERT INTO gsc_query_daily(day,query,clicks,impressions) VALUES
      (paris_today()-80,'older winner',20,100),
      (paris_today()-2,'recent query',10,100),
      (paris_today()-40,'recent query',5,100),
      (paris_today()-90,'outside window',100,100),
      (paris_today()-2,'',100,100);`);

  const snapshots = async () => {
    await db.query('SELECT refresh_dashboard_resources_assisted()');
    return (await db.query(`SELECT window_kind,path,assisted_contacts::int,assisted_prev::int
      FROM dashboard_resources_assisted_snapshot ORDER BY window_kind,path`)).rows;
  };
  const expectedSnapshots = [
    {window_kind:'rolling_28',path:'/post/cleanup',assisted_contacts:1,assisted_prev:1},
    {window_kind:'rolling_90',path:'/post/cleanup',assisted_contacts:2,assisted_prev:1},
  ];
  assert.deepEqual(await snapshots(), expectedSnapshots, 'baseline attribution over both periods');
  const beforeKeywords = (await db.query('SELECT keyword,clicks_total::int FROM dfs_keywords_to_sync(10)')).rows;
  assert.deepEqual(beforeKeywords, [
    {keyword:'older winner',clicks_total:20}, {keyword:'recent query',clicks_total:15},
  ], 'baseline selection uses ninety-day totals');

  await applyMigration(db, '_remove_redundant_analytics_work.sql');
  await db.exec('SET check_function_bodies=true');
  assert.deepEqual(await snapshots(), expectedSnapshots, 'assisted refresh keeps exact attribution counts');
  assert.deepEqual((await db.query('SELECT keyword,clicks_total::int FROM dfs_keywords_to_sync(10)')).rows,
    beforeKeywords, 'simplified DFS selection preserves its ninety-day result');
  await assert.rejects(() => db.query("SELECT refresh_dashboard_resources_assisted('today')"),
    e => e.code === 'P0001', 'unsupported snapshot window stays rejected');
  assert.deepEqual(await snapshots(), expectedSnapshots, 'rejected window leaves snapshots intact');

  for (const signature of ['refresh_dashboard_resources_assisted(text)','dfs_keywords_to_sync(integer)','purge_old_events()']) {
    const {rows:[access]} = await db.query(`SELECT
      has_function_privilege('anon',$1,'EXECUTE') AS anon,
      has_function_privilege('authenticated',$1,'EXECUTE') AS authenticated,
      has_function_privilege('service_role',$1,'EXECUTE') AS service`, [signature]);
    assert.deepEqual(access,{anon:false,authenticated:false,service:true}, signature+' stays private');
  }
  console.log('Analytics cleanup: attribution, selection, rejected input and privileges verified.');
} finally {
  await db.close();
}
