import assert from 'node:assert/strict';
import {createDatabase} from './helpers.mjs';

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

  const beforeKeywords = (await db.query('SELECT keyword,clicks_total::int FROM dfs_keywords_to_sync(10)')).rows;
  assert.deepEqual(beforeKeywords, [
    {keyword:'older winner',clicks_total:20}, {keyword:'recent query',clicks_total:15},
  ], 'baseline selection uses ninety-day totals');

  console.log('Analytics source helpers: DFS ninety-day selection verified.');
} finally {
  await db.close();
}
