import assert from 'node:assert/strict';
import {createDatabase} from './helpers.mjs';
const db=await createDatabase();
try {
await db.exec('SET check_function_bodies=true');
let assertions=0;
async function rows(sql,args=[]){return (await db.query(sql,args)).rows;}
async function scalar(sql,args=[]){return Object.values((await rows(sql,args))[0])[0];}
async function equal(sql,expected,label,args=[]){assert.deepEqual(await scalar(sql,args),expected,label);assertions++;}
async function rejected(sql,code,label,args=[]){await assert.rejects(()=>db.query(sql,args),e=>e.code===code,label);assertions++;}

// A partial/failed batch cannot complete, nor permit a concurrent writer.
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002';
const counts={gsc_path_daily:2,gsc_query_daily:2,gsc_query_page_daily:2};
await equal("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",a,'begin', [a]);
await equal("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",a,'idempotent begin', [a]);
await rejected("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",'55P03','concurrent ingestion blocked',[b]);
for(const bad of [{gsc_path_daily:2}, {...counts,gsc_query_page_daily:-1}, {...counts, extra:1}, {...counts,gsc_path_daily:1.5}, {gsc_path_daily:0,gsc_query_daily:0,gsc_query_page_daily:0}]){
 await rejected('select gsc_ingest_complete($1,$2::jsonb)','22023','bad or incomplete manifest',[a,JSON.stringify(bad)]);
}
await db.query('select gsc_ingest_fail($1)',[a]);
await db.query('select gsc_ingest_fail($1)',[a]);
await db.query("update gsc_ingest_batches set started_at=now()-interval '4 hours' where run_id=$1",[a]);
await db.query("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",[b]);
await rejected('select gsc_ingest_complete($1,$2::jsonb)','22023','old run may not complete newer batch',[a,JSON.stringify(counts)]);
await db.query('select gsc_ingest_complete($1,$2::jsonb)',[b,JSON.stringify(counts)]);
await db.query('select gsc_ingest_complete($1,$2::jsonb)',[b,JSON.stringify(counts)]);
await rejected('select gsc_ingest_complete($1,$2::jsonb)','22023','completion cannot change manifest',[b,JSON.stringify({...counts,gsc_path_daily:3})]);
await rejected('select gsc_ingest_fail($1)','22023','completed run cannot fail',[b]);

// F06/F07/F11/F15: realistic aggregates, no business or personal data.
await db.exec(`INSERT INTO page_taxonomy(path,category,theme) VALUES('/post/audit','ressource','test');
INSERT INTO gsc_path_daily(day,path,impressions,clicks,position,ctr) VALUES
(paris_today()-2,'/post/audit',1000,20,2,0.02),(paris_today()-1,'/post/audit',10,0,50,0);
INSERT INTO gsc_query_page_daily(day,path,query,impressions,clicks,position,ctr) VALUES
(paris_today()-2,'/post/audit','audit query',1000,20,2,0.02),(paris_today()-1,'/post/audit','audit query',10,0,50,0);
INSERT INTO cpi_daily(day,path,cpi,cpi_version)VALUES
(paris_today()-2,'/post/audit',40,'2.2.5'),(paris_today()-1,'/post/audit',40,'2.2.6');`);
await equal("select dashboard_article_detail('/post/audit')->'gsc'->>'position'",'2.5','weighted article position');
await equal("select dashboard_article_detail('/post/audit')->'top_queries'->0->>'position'",'2.5','weighted query position');
await equal("select dashboard_article_detail('/post/audit')->'gsc'->'ctr_expected'",null,'unsupported expected CTR neutralized');
await equal("select jsonb_path_query_array(dashboard_article_detail('/post/audit'),'$.cpi_series[*].cpi_version')",['2.2.5','2.2.6'],'version transmitted per point');
async function event(name,session,path,props={},ref=null,url=null,at=null){
 await db.query(`insert into events(id,anonymous_id,session_id,name,path,props,referrer_hostname,url,occurred_at,device_type)
 values(gen_random_uuid(),$2,$2,$1,$3,$4::jsonb,$5,$6,coalesce($7::timestamptz,cooked_paris_ts_start(paris_today()-1)+interval '12 hours'),'mobile')`,[name,session,path,JSON.stringify(props),ref,url,at]);
}
for(const [session,ref,dur,scroll] of [['read-null',null,10,20],['read-other','example.org',30,60],['read-li','www.linkedin.com',100,100],['read-fb','m.facebook.com',80,90]]){
 await event('pageview',session,'/post/audit',{},ref);
 await event('page_exit',session,'/post/audit',{duration_seconds:dur,max_scroll:scroll},ref);
}

// Fast intentional actions must not be classified as prefetch noise.
await event('pageview','fast-phone','/post/fast');
await event('cta_phone_click','fast-phone','/post/fast');
await event('pageview','no-action','/post/fast');
await db.query('select refresh_noise_sessions()');
await equal("select count(*)::int from noise_sessions where session_id='fast-phone'",0,'phone survives prefetch heuristic');
await equal("select count(*)::int from noise_sessions where session_id='no-action'",1,'empty prefetch remains filtered');

// F14: revisions are a single document sample, legacy records remain separate.
await event('pageview','cwv','/post/cwv',{},'google.com');
for(const [mid,revision,value] of [['doc1',1,1000],['doc1',2,3000],['doc2',1,4000]])
 await event('web_vitals','cwv','/post/cwv',{measurement_id:mid,revision,metric:'LCP',value},'google.com');
await equal("select count(*)::int from cooked_web_vitals_window(now()-interval '28 days',now()) where path='/post/cwv'",2,'two documents, not three emissions');
await equal("select lcp_p75_ms from behavior_pages_for_period(now()-interval '28 days',now()) where path='/post/cwv'",'3750','behavior latest CWV values');
await equal("select lcp_p75_ms from gsc_page_performance('/post/cwv')",'3750','page performance latest CWV values');
await event('web_vitals','legacy','/post/legacy',{metric:'CLS',value:0.1});
await event('web_vitals','legacy','/post/legacy',{metric:'CLS',value:0.1});
await equal("select count(*)::int from cooked_web_vitals_window(now()-interval '28 days',now()) where path='/post/legacy'",2,'legacy events have separate observations');

// Form totals include both macro and recruitment and respect Paris day boundaries.
await event('form_submit','webhook-1','/',{objet:'recrutement'},null,null,'2026-10-01T22:30:00Z');
await event('form_submit','webhook-2','/',{objet:'contact'},null,null,'2026-10-02T21:59:59Z');
await event('form_submit','webhook-3','/',{objet:'contact'},null,null,'2026-10-02T22:00:00Z');
await equal("select jsonb_agg(jsonb_build_array(day,submissions) order by day) from form_submission_counts_for_period('2026-10-01','2026-10-02')",[['2026-10-01',0],['2026-10-02',2]],'Paris inclusive days include recruitment');
await rejected("select * from form_submission_counts_for_period('2026-01-01','2026-12-31')",'22023','bounded form count window');

await equal("select relrowsecurity from pg_class where oid='gsc_ingest_batches'::regclass",true,'RLS enabled');
await equal("select not has_table_privilege('anon','gsc_ingest_batches','SELECT') and not has_table_privilege('authenticated','gsc_ingest_batches','SELECT')",true,'metadata deny-all to clients');
await equal("select bool_and(proconfig is null and not prosecdef) from pg_proc where proname in ('paris_date','paris_today','cooked_is_main_site','cooked_site_scope','cooked_paris_ts_start','cooked_paris_ts_end_exclusive','cooked_normalize_email','cooked_normalize_phone_fr')",true,'pure INVOKER helpers retain inlining');
console.log(`${assertions} behavior assertions passed on isolated PostgreSQL (PGlite).`);
await db.close();
} catch (error) {console.error(error.message, error.code ?? '', error.detail ?? ''); await db.close(); process.exitCode=1;}
