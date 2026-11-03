// This fixture deliberately exercises a NON-DEPLOYED proposal in disposable PostgreSQL.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createDatabase,root} from './helpers.mjs';

const db=await createDatabase();
let assertions=0;
const signaturesSql=`SELECT p.oid::regprocedure::text AS signature,
  pg_get_function_result(p.oid) AS result,p.prosecdef AS security_definer,p.provolatile AS volatility
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (
    'pages_overview_unified','gsc_pages_overview','top_contact_pages')
  ORDER BY signature`;
try {
  const signaturesBefore=(await db.query(signaturesSql)).rows;
  await db.exec(`CREATE OR REPLACE FUNCTION public.paris_today() RETURNS date LANGUAGE sql STABLE
    AS $$ SELECT date '2026-11-02' $$; SET check_function_bodies=true;`);
  await db.exec(fs.readFileSync(root+'/docs/proposals/analytics-overviews.sql','utf8'));
  async function rows(sql,args=[]){return (await db.query(sql,args)).rows;}
  function equal(actual,expected,label){assert.deepEqual(actual,expected,label);assertions++;}
  async function event(name,session,at,eventPath,props={},url=null){
    await db.query(`INSERT INTO events(id,anonymous_id,session_id,name,path,props,url,occurred_at,received_at,device_type)
      VALUES(gen_random_uuid(),$1||'-aid',$1,$2,$3,$4::jsonb,$5,$6::timestamptz,$6::timestamptz,'mobile')`,
      [session,name,eventPath,JSON.stringify(props),url,at]);
  }
  await db.exec(`TRUNCATE events, page_taxonomy, gsc_path_daily, seo_url_snapshot;
    INSERT INTO gsc_path_daily(day,path,clicks,impressions,position,ctr)
      VALUES('2026-10-29','/exact',10,100,2,0.1);
    INSERT INTO seo_url_snapshot(path,sessions_28d,sessions_90d,avg_dwell_seconds_28d,avg_dwell_seconds_90d,bounce_rate_28d,bounce_rate_90d)
      VALUES('/exact',999,1999,999,1999,17,27);`);
  for(const [session,day] of [
    ['before90','2026-07-31'],['start90','2026-08-01'],['month','2026-10-01'],
    ['start28','2026-10-02'],['beforeweek','2026-10-25'],['week','2026-10-26'],
    ['anchor','2026-10-29'],['after','2026-10-30'],['current','2026-11-02']
  ]){
    await event('pageview',session,day+' 00:00:00 Europe/Paris','/exact');
    await event('cta_phone_click',session,day+' 00:00:00 Europe/Paris','/exact');
  }
  await event('page_exit','anchor','2026-10-29 00:00:02 Europe/Paris','/exact',{duration_seconds:2,max_scroll:30});
  equal(await rows(`SELECT path,cooked_contacts::int,cooked_sessions::int,gsc_clicks::int
    FROM top_contact_pages('today')`),[
    {path:'/exact',cooked_contacts:1,cooked_sessions:1,gsc_clicks:10}
  ],'today contacts must not be divided by 28 days of snapshot sessions');
  for(const [period,sessions] of [['today',1],['week',2],['month',5],['rolling_28',4],['rolling_90',6]]){
    equal(await rows(`SELECT cooked_sessions::int,cooked_contacts::int
      FROM top_contact_pages($1) WHERE path='/exact'`,[period]),[
      {cooked_sessions:sessions,cooked_contacts:sessions}
    ],`top contact pages align sessions and contacts for ${period}`);
    equal(await rows(`SELECT path,cooked_sessions::int,cooked_contacts::int,
      cooked_dwell_avg_s::float,cooked_bounce_rate::float,has_cooked_data
      FROM pages_overview_unified($1) WHERE path='/exact'`,[period]),[
      {path:'/exact',cooked_sessions:sessions,cooked_contacts:sessions,cooked_dwell_avg_s:2,cooked_bounce_rate:100,has_cooked_data:true}
    ],`unified ${period} uses the exact cross-source dates and preserves percentage units`);
  }
  await db.exec(`INSERT INTO gsc_path_daily(day,path,clicks,impressions,position,ctr)
    VALUES('2026-10-29','/outside',2,20,3,0.1);
    INSERT INTO seo_url_snapshot(path,sessions_28d) VALUES('/outside',88);`);
  await event('pageview','outside','2026-10-30 00:00:00 Europe/Paris','/outside');
  equal(await rows(`SELECT path,cooked_sessions_28d::int,cooked_contacts_28d::int,
      cooked_dwell_avg_s_28d::float,cooked_bounce_rate_28d::float,has_cooked_data
    FROM gsc_pages_overview() ORDER BY path`),[
    {path:'/exact',cooked_sessions_28d:4,cooked_contacts_28d:4,cooked_dwell_avg_s_28d:2,cooked_bounce_rate_28d:100,has_cooked_data:true},
    {path:'/outside',cooked_sessions_28d:0,cooked_contacts_28d:0,cooked_dwell_avg_s_28d:null,cooked_bounce_rate_28d:null,has_cooked_data:false}
  ],'GSC overview shares GSC dates; data outside that interval is not coverage');
  // Differential reference uses the real canonical views and independent public
  // aggregation helpers, rather than the simplified fixture views above.
  const viewMigration=fs.readFileSync(root+'/supabase/migrations/20260903220532_t19_country_amputee.sql','utf8');
  for(const name of ['events_main','events_no_bots','events_human']){
    const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
    const match=viewMigration.match(new RegExp(`CREATE VIEW public\\.${escaped} WITH \\(security_invoker = true\\) AS[\\s\\S]*?;`));
    assert.ok(match,`canonical ${name} DDL`);
    await db.exec(match[0].replace('CREATE VIEW','CREATE OR REPLACE VIEW'));
  }
  await db.exec(`TRUNCATE events,noise_sessions,bot_fingerprints,gsc_path_daily;
    CREATE OR REPLACE FUNCTION public.paris_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT date '2026-11-02' $$;
    INSERT INTO gsc_path_daily(day,path,clicks,impressions,position,ctr) VALUES
      ('2026-10-29','/compare',10,100,2,0.1),('2026-10-29','/gsc-only',2,20,3,0.1);
    INSERT INTO bot_fingerprints(anonymous_id) VALUES('known-bot');
    INSERT INTO noise_sessions(session_id) VALUES('noise');`);
  let sequence=0;
  async function canonicalEvent({name='pageview',sid='visitor',aid='human',at='2026-10-29 10:00:00 Europe/Paris',
    eventPath='/compare',hostname='www.jplouton-avocat.fr',ref=null,device='mobile',props={}}={}){
    const id=`00000000-0000-0000-0000-${String(++sequence).padStart(12,'0')}`;
    await db.query(`INSERT INTO events(id,anonymous_id,session_id,name,path,hostname,referrer_hostname,
      device_type,props,occurred_at,received_at) VALUES($1::uuid,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::timestamptz,$10::timestamptz)`,
      [id,aid,sid,name,eventPath,hostname,ref,device,JSON.stringify(props),at]);
  }
  await canonicalEvent({sid:'dup'});
  await canonicalEvent({sid:'dup',name:'cta_phone_click',at:'2026-10-29 10:00:01.100 Europe/Paris'});
  await canonicalEvent({sid:'dup',name:'cta_phone_click',at:'2026-10-29 10:00:01.900 Europe/Paris'});
  for(const suffix of ['100','900'])await canonicalEvent({sid:null,name:'cta_phone_click',at:`2026-10-29 10:01:00.${suffix} Europe/Paris`});
  await canonicalEvent({sid:'anchors',at:'2026-10-29 10:02:00 Europe/Paris'});
  for(const anchor of [null,'',null])await canonicalEvent({sid:'anchors',name:'cta_phone_click',at:'2026-10-29 10:02:01 Europe/Paris',props:anchor===null?{}:{anchor}});
  await canonicalEvent({sid:'bot-first',at:'2026-10-29 10:03:00 Europe/Paris'});
  await canonicalEvent({sid:'bot-first',aid:'known-bot',name:'cta_phone_click',at:'2026-10-29 10:03:01 Europe/Paris'});
  await canonicalEvent({sid:'bot-first',name:'cta_phone_click',at:'2026-10-29 10:03:01 Europe/Paris'});
  // A malformed payload on a rejected event must never reach the numeric aggregate.
  await canonicalEvent({sid:'invalid-exit',aid:'known-bot',name:'page_exit',props:{duration_seconds:'invalid'}});
  await canonicalEvent({sid:'noise'});
  await canonicalEvent({sid:'noise',name:'cta_phone_click'});
  await canonicalEvent({sid:'spam',ref:'baidu.com'});
  await canonicalEvent({sid:'spam',ref:'baidu.com',name:'cta_phone_click'});
  for(const device of ['mobile',null,'server'])await canonicalEvent({sid:'book-'+device,name:'cta_booking_click',device});
  await canonicalEvent({sid:'form',name:'form_submit',device:'server',props:{counts_as_macro:true}});
  await canonicalEvent({sid:'recruitment',name:'form_submit',device:'server',props:{counts_as_macro:false}});
  await canonicalEvent({sid:'chrome'});
  await canonicalEvent({sid:'chrome',name:'cta_anchor_click',at:'2026-10-29 10:00:20 Europe/Paris',props:{anchor:'x',target_section:'menu'}});
  await canonicalEvent({sid:'chrome',name:'cta_anchor_click',at:'2026-10-29 10:00:20 Europe/Paris',props:{anchor:'x'}});
  await canonicalEvent({sid:'google',ref:'google.com'});
  await canonicalEvent({sid:'google',name:'page_exit',ref:'google.com',at:'2026-10-29 10:00:02 Europe/Paris',props:{duration_seconds:2,max_scroll:30}});
  await canonicalEvent({sid:'google-empty',ref:'google.com'});
  await canonicalEvent({sid:'google-multi',ref:'google.com'});
  await canonicalEvent({sid:'google-multi',eventPath:'/second',at:'2026-10-29 10:00:02 Europe/Paris'});
  await canonicalEvent({sid:'outremer',hostname:'outremer.jplouton-avocat.fr'});
  await canonicalEvent({sid:'outremer',hostname:'outremer.jplouton-avocat.fr',name:'cta_phone_click'});
  for(const [sid,at] of [['start','2026-10-02 00:00:00 Europe/Paris'],['before-start','2026-10-01 23:59:59 Europe/Paris'],['after-end','2026-10-30 00:00:00 Europe/Paris']]){
    await canonicalEvent({sid,at});await canonicalEvent({sid,at,name:'cta_phone_click'});
  }
  equal(await rows(`SELECT cooked_phone_clicks::int,cooked_form_submits::int,cooked_contacts::int,cooked_booking_intent::int
    FROM pages_overview_unified('rolling_28') WHERE path='/compare'`),[
    {cooked_phone_clicks:7,cooked_form_submits:1,cooked_contacts:8,cooked_booking_intent:1}
  ],'literal expected counts preserve null sessions, null/empty anchors, raw bot precedence and macro filters');
  const referenceSql=`WITH b AS (SELECT * FROM cooked_period_bounds($1,'cross')),
    c AS (SELECT * FROM seo_pages_overview(cooked_paris_ts_start((SELECT n_start FROM b)),cooked_paris_ts_end_exclusive((SELECT n_end FROM b)))),
    g AS (SELECT * FROM gsc_path_metrics((SELECT n_start FROM b),(SELECT n_end FROM b))),
    m AS (SELECT * FROM macro_contacts_by_path((SELECT n_start FROM b),(SELECT n_end FROM b))),
    p AS (SELECT * FROM pogo_rates_for_period(cooked_paris_ts_start((SELECT n_start FROM b)),cooked_paris_ts_end_exclusive((SELECT n_end FROM b)))),
    ranked AS (SELECT coalesce(c.path,g.path) AS path FROM c FULL JOIN g ON g.path=c.path)
    SELECT r.path,coalesce(g.clicks_total,0) AS gsc_clicks,coalesce(g.impressions_total,0) AS gsc_impressions,
      g.position_avg AS gsc_position_avg,g.ctr_pct AS gsc_ctr_pct,coalesce(c.sessions,0) AS cooked_sessions,
      c.avg_dwell_seconds AS cooked_dwell_avg_s,c.bounce_rate_pct AS cooked_bounce_rate,
      coalesce(m.phone_clicks,0) AS cooked_phone_clicks,coalesce(m.form_submits,0) AS cooked_form_submits,
      coalesce(m.contacts,0) AS cooked_contacts,coalesce(m.booking_intent,0) AS cooked_booking_intent,
      p.pogo_rate AS cooked_pogo_rate,c.path IS NOT NULL AS has_cooked_data
    FROM ranked r LEFT JOIN c ON c.path=r.path LEFT JOIN g ON g.path=r.path
      LEFT JOIN m ON m.path=r.path LEFT JOIN p ON p.path=r.path
    ORDER BY cooked_sessions DESC,gsc_clicks DESC,r.path`;
  for(const period of ['today','rolling_28','rolling_90']){
    equal(await rows('SELECT * FROM pages_overview_unified($1)',[period]),await rows(referenceSql,[period]),
      `set-based overview equals canonical human aggregation for ${period}`);
  }


  equal(await rows(signaturesSql),signaturesBefore,'proposal preserves public signature and result types');
  equal(await rows(`SELECT count(*)::int AS exposed FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('top_contact_pages','pages_overview_unified','gsc_pages_overview')
    AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE')
      OR NOT has_function_privilege('service_role',p.oid,'EXECUTE'))`),[{exposed:0}],
    'proposal remains service-role only');
  console.log(`Non-deployed overview proposal: ${assertions} assertions passed.`);
} finally { await db.close(); }
