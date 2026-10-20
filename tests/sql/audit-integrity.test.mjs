import fs from 'node:fs';
import assert from 'node:assert/strict';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const {PGlite}=await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const db=new PGlite();
try {
await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;CREATE ROLE cooked_ci_ro;SET check_function_bodies=false;`);
const rels=JSON.parse(fs.readFileSync(root+'/tests/sql/fixtures/catalog-20261020.json','utf8'));
const eventViews=['events_human','events_main','events_no_bots','events_human_outremer','events_outremer'];
for(const r of rels.filter(r=>!eventViews.includes(r.name))){
 await db.exec(`CREATE TABLE public.${r.name} (${r.columns});`);
}
await db.exec(`ALTER TABLE events ALTER id SET DEFAULT gen_random_uuid();
 ALTER TABLE cooked_config ADD PRIMARY KEY(key);
 ALTER TABLE noise_sessions ADD PRIMARY KEY(session_id);
 ALTER TABLE bot_fingerprints ADD PRIMARY KEY(anonymous_id);
 ALTER TABLE identity_stitch ADD PRIMARY KEY(kind,key);
 ALTER TABLE page_taxonomy ADD PRIMARY KEY(path);
 ALTER TABLE cpi_daily ADD PRIMARY KEY(day,path);
 ALTER TABLE dashboard_assisted_quarter_snapshot ADD PRIMARY KEY(quarter);
 CREATE VIEW events_main AS SELECT * FROM events;
 CREATE VIEW events_outremer AS SELECT * FROM events WHERE false;
 CREATE VIEW events_human AS SELECT * FROM events e WHERE NOT EXISTS(SELECT 1 FROM noise_sessions n WHERE n.session_id=e.session_id) AND NOT EXISTS(SELECT 1 FROM bot_fingerprints b WHERE b.anonymous_id=e.anonymous_id);
 CREATE VIEW events_no_bots AS SELECT * FROM events;
 CREATE VIEW events_human_outremer AS SELECT * FROM events WHERE false;
 INSERT INTO cooked_config(key,value)VALUES('cpi_definition_version','2.2.5');`);
const source=fs.readFileSync(process.env.SQL_RPC_MIRROR ?? root+'/supabase/rpcs.sql','utf8');
for(const chunk of source.split(/\n-- ═══ /).slice(1)) {
 const at=chunk.indexOf('CREATE OR REPLACE');if(at<0)continue;
 const ddl=chunk.slice(at).trim();if(/FUNCTION public.unaccent/.test(ddl))continue;
 try {await db.exec(ddl+';');}catch(e){console.error('baseline',chunk.slice(0,90),e.message);throw e;}
}
const migrationFiles=fs.readdirSync(root+'/supabase/migrations').filter(name=>name.endsWith('_audit_data_integrity_and_ingest_completion.sql'));
assert.equal(migrationFiles.length,1,'exactly one audit migration');
await db.exec(fs.readFileSync(root+'/supabase/migrations/'+migrationFiles[0],'utf8'));
console.log('Migration loaded against existing function signatures and schema.');
if(process.env.SQL_RPC_EXPORT){
 const functions=(await db.query(`select p.oid::regprocedure::text as signature,pg_get_functiondef(p.oid) as ddl
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' order by 1`)).rows;
 fs.writeFileSync(process.env.SQL_RPC_EXPORT,functions.map(f=>`
-- ═══ public.${f.signature} ═══
${f.ddl}`).join('\n'));
 console.log('Post-migration mirror exported for replay verification.');
}

await db.exec('SET check_function_bodies=true');
await db.exec(fs.readFileSync(root+'/tests/sql/fixtures/cpi-before-20261020.sql','utf8'));
for(const name of ['cooked_page_index','behavior_pages_for_period','gsc_page_performance','cooked_web_vitals_window']){
 const [{ddl}]=(await db.query('SELECT pg_get_functiondef(oid) ddl FROM pg_proc WHERE proname=$1',[name])).rows;
 try{await db.exec(ddl);console.log('SQL compiled:',name)}catch(e){console.error('compile',name,e.message);throw e;}
}
for(const sql of ["select * from cooked_refresh_after_gsc_pending()","select dashboard_article_detail('/test','rolling_28')","select * from cooked_page_index(28)","select * from behavior_pages_for_period(now()-interval '28 days',now())","select * from gsc_page_performance('/test')"]){
 try{await db.query(sql);console.log('Executed:',sql.slice(0,80))}catch(e){console.error(sql,e.message);throw e;}
}

let assertions=0;
async function rows(sql,args=[]){return (await db.query(sql,args)).rows;}
async function scalar(sql,args=[]){return Object.values((await rows(sql,args))[0])[0];}
async function equal(sql,expected,label,args=[]){assert.deepEqual(await scalar(sql,args),expected,label);assertions++;}
async function rejected(sql,code,label,args=[]){await assert.rejects(()=>db.query(sql,args),e=>e.code===code,label);assertions++;}

// F13: a partial or failed batch never releases a refresh, nor permits a second writer.
const a='00000000-0000-0000-0000-000000000001',b='00000000-0000-0000-0000-000000000002';
const counts={gsc_path_daily:2,gsc_query_daily:2,gsc_query_page_daily:2};
await equal('select pending from cooked_refresh_after_gsc_pending()',false,'no invented bootstrap completion');
await equal("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",a,'begin', [a]);
await equal("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",a,'idempotent begin', [a]);
await rejected("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",'55P03','concurrent ingestion blocked',[b]);
await equal('select pending from cooked_refresh_after_gsc_pending()',false,'partial blocked');
for(const bad of [{gsc_path_daily:2}, {...counts,gsc_query_page_daily:-1}, {...counts, extra:1}, {...counts,gsc_path_daily:1.5}, {gsc_path_daily:0,gsc_query_daily:0,gsc_query_page_daily:0}]){
 await rejected('select gsc_ingest_complete($1,$2::jsonb)','22023','bad or incomplete manifest',[a,JSON.stringify(bad)]);
}
await db.query('select gsc_ingest_fail($1)',[a]);
await equal('select pending from cooked_refresh_after_gsc_pending()',false,'failed remains blocked');
await db.query('select gsc_ingest_fail($1)',[a]);
await db.query("update gsc_ingest_batches set started_at=now()-interval '4 hours' where run_id=$1",[a]);
await equal("select count(*)::int from alert_rule_refresh_after_gsc_stale() where kind='refresh_after_gsc_stale'",1,'abandoned or failed batch raises operational alert');
await db.query("select gsc_ingest_begin($1,'2026-10-01','2026-10-19')",[b]);
await rejected('select gsc_ingest_complete($1,$2::jsonb)','22023','old run may not complete newer batch',[a,JSON.stringify(counts)]);
await db.query('select gsc_ingest_complete($1,$2::jsonb)',[b,JSON.stringify(counts)]);
await equal('select pending from cooked_refresh_after_gsc_pending()',true,'all three completed releases refresh');
await db.query('select gsc_ingest_complete($1,$2::jsonb)',[b,JSON.stringify(counts)]);
await rejected('select gsc_ingest_complete($1,$2::jsonb)','22023','completion cannot change manifest',[b,JSON.stringify({...counts,gsc_path_daily:3})]);
await rejected('select gsc_ingest_fail($1)','22023','completed run cannot fail',[b]);
await db.query("insert into cooked_config(key,value) values('last_full_refresh_gsc_batch_id',$1)",[b]);
await equal('select pending from cooked_refresh_after_gsc_pending()',false,'exact completed batch consumed');
// Timestamp-only legacy watermark must not suppress a fresh batch.
await db.exec("delete from cooked_config where key='last_full_refresh_gsc_batch_id';insert into cooked_config(key,value)values('last_full_refresh_after_gsc_at',(now()+interval '1 day')::text)");
await equal('select pending from cooked_refresh_after_gsc_pending()',true,'new marker wins over old timestamp');

// F06/F07/F11/F15: realistic aggregates, no business or personal data.
const end=await scalar('select paris_today()-1');
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
await db.query("select refresh_dashboard_snapshots('rolling_28')");
await equal("select dwell_median_s from dashboard_resources_snapshot where path='/post/audit'",'20','NULL ref retained, social omitted');
await equal("select scroll_median from dashboard_resources_snapshot where path='/post/audit'",'40','NULL ref scroll retained');
for(const clickid of ['gclid','gbraid','wbraid'])await event('pageview','ads-'+clickid,'/defense-penale/droit-penal',{},null,'https://www.jplouton-avocat.fr/defense-penale/droit-penal?'+clickid+'=synthetic');
await db.query("select refresh_dashboard_expertises_snapshots('rolling_28')");
await equal("select paid_entries_n from dashboard_expertises_kpis_snapshot where window_kind='rolling_28'",3,'all Ads identifiers flow through driver');

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

// F08: bookings still contribute to the score but never masquerade as a macro contact.
for(let i=0;i<6;i++){
 await event('pageview','organic-'+i,'/post/audit',{},'google.com');
 await event('page_exit','organic-'+i,'/post/audit',{duration_seconds:40,max_scroll:80},'google.com');
}
await event('cta_booking_click','organic-0','/post/audit',{},'google.com');
await equal("select convertit from cooked_page_index(28) where path='/post/audit'",false,'booking only does not convert');
await equal("select convertit from audit_cpi_before(28) where path='/post/audit'",true,'old badge regression reproduced');
await equal("select (select to_jsonb(c)-'convertit' from cooked_page_index(28) c where path='/post/audit') = (select to_jsonb(c)-'convertit' from audit_cpi_before(28) c where path='/post/audit')",true,'all CPI score components unchanged by booking badge repair');
// A session that straddles the period boundary must not import out-of-window bookings.
// Several scored pages make the relative CPI sensitive to this leak (not just its badge).
for(let p=0;p<3;p++){
 for(let i=0;i<6;i++){
  await event('pageview',`control-${p}-${i}`,`/post/control-${p}`,{},'google.com');
  await event('page_exit',`control-${p}-${i}`,`/post/control-${p}`,{duration_seconds:40,max_scroll:80},'google.com');
 }
 for(let i=0;i<p;i++)await event('cta_booking_click',`control-${p}-${i}`,`/post/control-${p}`,{},'google.com');
}
const scoreSql=fn=>`select jsonb_agg(to_jsonb(c)-'convertit' order by path) from ${fn}(28) c`;
const correctedBefore=await scalar(scoreSql('cooked_page_index'));
const originalBefore=await scalar(scoreSql('audit_cpi_before'));
assert.deepEqual(correctedBefore,originalBefore,'in-window score values preserved');assertions++;
await db.exec(`insert into events(id,anonymous_id,session_id,name,path,props,referrer_hostname,occurred_at,device_type)
 select gen_random_uuid(),'organic-0','organic-0','cta_booking_click','/post/audit','{}'::jsonb,'google.com',
 CASE WHEN i%2=0 THEN cooked_paris_ts_start(gsc_last_data_day()-27)-i*interval '1 second'
 ELSE cooked_paris_ts_end_exclusive(gsc_last_data_day())+i*interval '1 second' END,'mobile'
 from generate_series(1,100) AS s(i);`);
assert.deepEqual(await scalar(scoreSql('cooked_page_index')),correctedBefore,'bookings before/after bounds cannot change score');assertions++;
assert.notDeepEqual(await scalar(scoreSql('audit_cpi_before')),originalBefore,'old out-of-window booking leak reproduced');assertions++;
await event('cta_phone_click','organic-0','/post/audit',{},'google.com');
await equal("select convertit from cooked_page_index(28) where path='/post/audit'",true,'macro phone converts');

for(const [mid,revision,value] of [['cpi-doc1',1,1000],['cpi-doc1',2,3000],['cpi-doc2',1,4000]])
 await event('web_vitals','organic-0','/post/audit',{measurement_id:mid,revision,metric:'LCP',value},'google.com');
await equal("select gate from cooked_page_index(28) where path='/post/audit'",'0.93','CPI uses latest LCP per document');

// Form totals include both macro and recruitment and respect Paris day boundaries.
await event('form_submit','webhook-1','/',{objet:'recrutement'},null,null,'2026-10-01T22:30:00Z');
await event('form_submit','webhook-2','/',{objet:'contact'},null,null,'2026-10-02T21:59:59Z');
await event('form_submit','webhook-3','/',{objet:'contact'},null,null,'2026-10-02T22:00:00Z');
await equal("select jsonb_agg(jsonb_build_array(day,submissions) order by day) from form_submission_counts_for_period('2026-10-01','2026-10-02')",[['2026-10-01',0],['2026-10-02',2]],'Paris inclusive days include recruitment');
await rejected("select * from form_submission_counts_for_period('2026-01-01','2026-12-31')",'22023','bounded form count window');
await rejected("select * from site_seo_funnel()",'0A000','legacy misleading funnel disabled');

// Snapshot CWV consumer and orchestration: only an entirely successful chain consumes a batch.
await db.query('select refresh_seo_url_snapshot()');
await equal("select lcp_p75_28d_ms from seo_url_snapshot where path='/post/cwv'",'3750','SEO snapshot latest CWV values');
const assistedDdl=await scalar("select pg_get_functiondef('refresh_dashboard_resources_assisted(text)'::regprocedure)");
await db.exec("CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic stage failure'; END $$;");
const partial=await scalar('select cooked_refresh_after_gsc()');
assert.match(partial,/^partiel:/); assertions++;
await equal('select pending from cooked_refresh_after_gsc_pending()',true,'partial chain does not consume batch');
await db.exec(assistedDdl);
const complete=await scalar('select cooked_refresh_after_gsc()');
assert.match(complete,/^ok:/); assertions++;
await equal('select pending from cooked_refresh_after_gsc_pending()',false,'full chain consumes batch');
await equal("select value from cooked_config where key='last_full_refresh_gsc_batch_id'",b,'exact batch recorded by orchestrator');

// Least privilege: new routines and batch metadata are unavailable to browser roles.
await equal("select bool_and(not has_function_privilege('anon',oid,'EXECUTE') and not has_function_privilege('authenticated',oid,'EXECUTE') and has_function_privilege('service_role',oid,'EXECUTE')) from pg_proc where proname in ('gsc_ingest_begin','gsc_ingest_complete','gsc_ingest_fail','form_submission_counts_for_period','cooked_web_vitals_window')",true,'new RPC ACLs');
await equal("select relrowsecurity from pg_class where oid='gsc_ingest_batches'::regclass",true,'RLS enabled');
await equal("select not has_table_privilege('anon','gsc_ingest_batches','SELECT') and not has_table_privilege('authenticated','gsc_ingest_batches','SELECT')",true,'metadata deny-all to clients');
await equal("select bool_and(proconfig is null and not prosecdef) from pg_proc where proname in ('paris_date','paris_today','cooked_is_main_site','cooked_site_scope','cooked_paris_ts_start','cooked_paris_ts_end_exclusive','cooked_normalize_email','cooked_normalize_phone_fr')",true,'pure INVOKER helpers retain inlining');
console.log(`${assertions} behavior assertions passed on isolated PostgreSQL (PGlite).`);
await db.close();
} catch (error) {console.error(error.message, error.code ?? '', error.detail ?? ''); await db.close(); process.exitCode=1;}
