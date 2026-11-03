import assert from 'node:assert/strict';
import {createDatabase,applyMigration} from './helpers.mjs';

const db=await createDatabase();
let assertions=0;
const signaturesSql=`SELECT p.oid::regprocedure::text AS signature,
  pg_get_function_result(p.oid) AS result,p.prosecdef AS security_definer,p.provolatile AS volatility
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (
    'math_visit_sequences','math_internal_edges','math_refresh_snapshots',
    'content_performance')
  ORDER BY signature`;
try {
  const signaturesBefore=(await db.query(signaturesSql)).rows;
  const cpiBefore=(await db.query("SELECT pg_get_functiondef('cooked_page_index(integer)'::regprocedure) AS ddl")).rows;
  await db.exec(`CREATE OR REPLACE FUNCTION public.paris_today() RETURNS date LANGUAGE sql STABLE
    AS $$ SELECT date '2026-11-02' $$;`);
  await db.exec(`INSERT INTO math_visit_sequences_snapshot(computed_at,window_days,journey,converted,entry_channel,n)
      VALUES('2026-10-20',90,ARRAY['/legacy'],false,'direct',1);
    INSERT INTO math_internal_edges_snapshot(computed_at,window_days,src,dst,kind,placement,weight,dst_resolved)
      VALUES('2026-10-20',90,'/legacy','/other','flow',null,1,false);
    SET check_function_bodies=true;`);
  await applyMigration(db,'_unify_analytics_windows.sql');
  async function rows(sql,args=[]){return (await db.query(sql,args)).rows;}
  function equal(actual,expected,label){assert.deepEqual(actual,expected,label);assertions++;}
  async function event(name,session,at,eventPath,props={},url=null){
    await db.query(`INSERT INTO events(id,anonymous_id,session_id,name,path,props,url,occurred_at,received_at,device_type)
      VALUES(gen_random_uuid(),$1||'-aid',$1,$2,$3,$4::jsonb,$5,$6::timestamptz,$6::timestamptz,'mobile')`,
      [session,name,eventPath,JSON.stringify(props),url,at]);
  }
  // A closed 28-day window includes the whole first Paris day and none of today.
  await event('pageview','start','2026-10-05 00:00:00 Europe/Paris','/post/start');
  await event('cta_phone_click','start','2026-10-05 00:10:00 Europe/Paris','/post/start');
  await event('pageview','before','2026-10-04 23:59:59 Europe/Paris','/post/before');
  await event('cta_phone_click','before','2026-10-04 23:59:59 Europe/Paris','/post/before');
  await event('pageview','today','2026-11-02 00:00:00 Europe/Paris','/post/today');
  await event('cta_phone_click','today','2026-11-02 00:00:00 Europe/Paris','/post/today');
  await event('pageview','ads','2026-10-11 12:00:00 Europe/Paris','/post/ads',{},'https://www.jplouton-avocat.fr/post/ads?gclid=synthetic');
  await event('cta_phone_click','ads','2026-10-11 12:01:00 Europe/Paris','/post/ads');
  await event('pageview','form','2026-11-01 23:50:00 Europe/Paris','/post/form');
  await event('form_submit','webhook-form','2026-11-01 23:59:59 Europe/Paris','/post/form',{
    cooked_aid:'form-aid',cooked_sid:'form',objet_de_ma_demande:'Divorce'
  });
  equal(await rows(`SELECT journey[1] AS path,converted,entry_channel,n::int
    FROM math_visit_sequences(28) ORDER BY path`),[
    {path:'/post/ads',converted:true,entry_channel:'paid',n:1},
    {path:'/post/form',converted:true,entry_channel:'direct',n:1},
    {path:'/post/start',converted:true,entry_channel:'direct',n:1}
  ],'sequences share closed Paris days across phones/forms and preserve Ads identifiers');
  await db.exec("INSERT INTO page_taxonomy(path,category,theme) VALUES('/post/start','ressource','boundary')");
  await event('page_exit','start','2026-10-05 00:02:00 Europe/Paris','/post/start',{duration_seconds:60,max_scroll:50});
  await event('cta_booking_click','start','2026-10-05 00:03:00 Europe/Paris','/post/start');
  equal(await rows(`SELECT pages,sessions::int,dwell_median::float,scroll_median::float,
      booking_intents::int,contacts_assisted::int,contact_rate_pct::float
    FROM content_performance(28) WHERE theme='boundary'`),[
    {pages:1,sessions:1,dwell_median:60,scroll_median:50,booking_intents:1,contacts_assisted:1,contact_rate_pct:100}
  ],'content denominators, reading and contacts cover the same first closed day');
  await db.exec('TRUNCATE events');
  for(const [session,day,prefix] of [['edge','2026-10-05','/edge'],['new','2026-11-02','/new']]){
    await event('pageview',session,day+' 00:00:00 Europe/Paris',prefix+'/start');
    await event('click_internal',session,day+' 00:00:30 Europe/Paris',prefix+'/start',{target_path:prefix+'/end',placement:'body'});
    await event('pageview',session,day+' 00:01:00 Europe/Paris',prefix+'/end');
  }
  equal(await rows(`SELECT src,dst,kind,weight::int FROM math_internal_edges(28) ORDER BY kind,src`),[
    {src:'/edge/start',dst:'/edge/end',kind:'click',weight:1},
    {src:'/edge/start',dst:'/edge/end',kind:'flow',weight:1}
  ],'edge flows and click weights share the sequence window');
  equal(await rows(`SELECT sequences::int,edges::int FROM math_refresh_snapshots(28)`),[
    {sequences:1,edges:2}
  ],'snapshot refresh retains both public row counts');
  equal(await rows(`SELECT DISTINCT window_start::text,window_end::text,calculation_version FROM (
    SELECT window_start,window_end,calculation_version FROM math_visit_sequences_snapshot WHERE window_days=28
    UNION ALL
    SELECT window_start,window_end,calculation_version FROM math_internal_edges_snapshot WHERE window_days=28
  ) s`),[{window_start:'2026-10-05',window_end:'2026-11-01',calculation_version:'paris_j1_v1'}],
    'both math snapshots carry the same actual closed window and version');
  equal(await rows(`SELECT count(DISTINCT computed_at)::int AS runs FROM (
    SELECT computed_at FROM math_visit_sequences_snapshot WHERE window_days=28
    UNION ALL SELECT computed_at FROM math_internal_edges_snapshot WHERE window_days=28
  ) s`),[{runs:1}],'one snapshot refresh has one shared computation timestamp');
  equal(await rows(`SELECT count(*)::int AS legacy_rows FROM (
    SELECT window_start,window_end,calculation_version FROM math_visit_sequences_snapshot WHERE window_days=90
    UNION ALL
    SELECT window_start,window_end,calculation_version FROM math_internal_edges_snapshot WHERE window_days=90
  ) s WHERE window_start IS NULL AND window_end IS NULL AND calculation_version IS NULL`),[{legacy_rows:2}],
    'older snapshots keep unknown provenance instead of invented dates');
  await assert.rejects(()=>db.query('SELECT * FROM math_refresh_snapshots(0)'),e=>e.code==='22023');
  assertions++;
  equal(await rows(signaturesSql),signaturesBefore,'public signatures, result types and execution attributes stay compatible');
  equal(await rows("SELECT pg_get_functiondef('cooked_page_index(integer)'::regprocedure) AS ddl"),cpiBefore,
    'CPI definition is untouched');
  equal(await rows(`SELECT count(*)::int AS exposed FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN ('math_visit_sequences','math_internal_edges','math_refresh_snapshots',
      'content_performance')
    AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE')
      OR NOT has_function_privilege('service_role',p.oid,'EXECUTE'))`),[{exposed:0}],
    'each migrated RPC remains executable only by its intended service role');
  await applyMigration(db,'_unify_analytics_windows.sql');
  equal(await rows(signaturesSql),signaturesBefore,'migration replays without changing public contracts');
  // The autumn day lasts 25 hours: its two 02:30 occurrences both belong to the same closed day.
  await db.exec(`TRUNCATE events;
    CREATE OR REPLACE FUNCTION public.paris_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT date '2026-10-26' $$;`);
  await event('pageview','dst-first','2026-10-25 02:30:00+02','/dst');
  await event('pageview','dst-second','2026-10-25 02:30:00+01','/dst');
  await event('pageview','dst-last','2026-10-25 23:59:59+01','/dst');
  await event('pageview','dst-outside','2026-10-26 00:00:00+01','/dst');
  equal(await rows('SELECT n::int FROM math_visit_sequences(1)'),[{n:3}],
    'a closed Paris day includes both repeated hours and excludes the next midnight');

  console.log(`Analytics windows: ${assertions} assertions passed.`);
} finally { await db.close(); }
