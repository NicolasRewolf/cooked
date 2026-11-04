import assert from 'node:assert/strict';
import {createDatabase} from './helpers.mjs';

const db = await createDatabase();
try {
  await db.exec('SET check_function_bodies=true');
  const rows = async (sql, args=[]) => (await db.query(sql,args)).rows;
  await db.exec(`INSERT INTO gsc_path_daily(day,path,impressions,clicks,position,ctr) VALUES
    (paris_today()-2,'/post/audit',1000,20,2,0.02),(paris_today()-1,'/post/audit',10,0,50,0);
    INSERT INTO gsc_query_page_daily(day,path,query,impressions,clicks,position,ctr) VALUES
    (paris_today()-2,'/post/audit','audit query',900,10,2,0.011111),
    (paris_today()-1,'/post/audit','audit query',10,0,50,0);`);
  assert.deepEqual(await rows(`SELECT clicks_total::int,impressions_total::int,position_avg::float,ctr_pct::float
    FROM gsc_path_metrics(paris_today()-2,paris_today()-1)`),
    [{clicks_total:20,impressions_total:1010,position_avg:2.48,ctr_pct:1.98}], 'page totals and position weighted by impressions');
  assert.deepEqual(await rows(`SELECT query,clicks::int,impressions::int,position_avg::float,ctr_pct::float
    FROM gsc_top_queries_for_path('/post/audit/')`),
    [{query:'audit query',clicks:10,impressions:910,position_avg:2.53,ctr_pct:1.1}],
    'revealed queries retain their own coverage and weighted position, with canonical page lookup');

  async function event(name,session,path,props={},at=null,hostname='www.jplouton-avocat.fr') {
    await db.query(`INSERT INTO events(anonymous_id,session_id,name,path,props,hostname,occurred_at,device_type)
      VALUES($2,$2,$1,$3,$4,$6,coalesce($5::timestamptz,cooked_paris_ts_start(paris_today()-1)+interval '12 hours'),'mobile')`,
      [name,session,path,JSON.stringify(props),at,hostname]);
  }
  await event('pageview','fast-phone','/post/fast');
  await event('cta_phone_click','fast-phone','/post/fast');
  await event('pageview','empty-prefetch','/post/fast');
  await event('pageview','outremer','/post/outremer',{},null,'outremer.jplouton-avocat.fr');
  await event('pageview','props-outremer','/post/outremer',{cooked_site:'outremer'});
  await db.query('SELECT refresh_noise_sessions()');
  assert.deepEqual(await rows("SELECT session_id FROM noise_sessions WHERE session_id IN ('fast-phone','empty-prefetch') ORDER BY session_id"),
    [{session_id:'empty-prefetch'}], 'an intentional fast contact is not discarded as prefetch');
  assert.equal((await rows("SELECT count(*)::int AS n FROM events_human WHERE path='/post/outremer'"))[0].n,0,
    'site scope is preserved by the real shared views');

  for (let n=0;n<22;n++) {
    await event('pageview','synthetic-crawler','/crawler/'+n);
    await event('pageview','synthetic-reader','/reader/'+n);
  }
  await event('scroll_depth','synthetic-reader','/reader/0',{percent:25});
  await db.query('SELECT refresh_bot_fingerprints()');
  assert.deepEqual(await rows("SELECT anonymous_id FROM bot_fingerprints WHERE anonymous_id IN ('synthetic-crawler','synthetic-reader')"),
    [{anonymous_id:'synthetic-crawler'}], 'the crawler filter retains its scroll exception');
  assert.equal((await rows("SELECT count(*)::int AS n FROM events_human WHERE anonymous_id='synthetic-crawler'"))[0].n,0);

  // Daily reconciliation includes recruitment; contact metrics separately exclude it.
  await event('form_submit','webhook-1','/',{objet_de_ma_demande:'Nous rejoindre'},'2026-10-01T22:30:00Z');
  await event('form_submit','webhook-2','/',{objet_de_ma_demande:'Divorce'},'2026-10-02T21:59:59Z');
  await event('form_submit','webhook-3','/',{objet_de_ma_demande:'Divorce'},'2026-10-02T22:00:00Z');
  assert.deepEqual(await rows(`SELECT day::text,submissions::int FROM form_submission_counts_for_period('2026-10-01','2026-10-02')`),
    [{day:'2026-10-01',submissions:0},{day:'2026-10-02',submissions:2}], 'reconciliation uses inclusive Paris days');
  assert.equal((await rows("SELECT form_submit_counts_as_macro('{\"objet_de_ma_demande\":\"Nous rejoindre\"}') AS macro"))[0].macro,false);
  await assert.rejects(db.query("SELECT * FROM form_submission_counts_for_period('2026-01-01','2026-12-31')"),e=>e.code==='22023');
  assert.equal((await rows("SELECT relrowsecurity FROM pg_class WHERE oid='gsc_ingest_batches'::regclass"))[0].relrowsecurity,true);
  for (const role of ['anon','authenticated']) {
    assert.equal((await rows("SELECT has_table_privilege($1,'gsc_ingest_batches','SELECT') AS allowed",[role]))[0].allowed,false);
  }
  console.log('Core integrity: weighted GSC positions/coverage, actual site/bot/noise filters, Paris form reconciliation and private batch metadata verified.');
} finally {
  await db.close();
}
