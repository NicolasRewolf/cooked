import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db = await createDatabase();
try {
  await applyMigration(db, '_page_view_counts_group_paths.sql');
  const {rows: [{definition}]} = await db.query(
    "SELECT pg_get_functiondef('public.page_view_counts(integer)'::regprocedure) AS definition");
  await db.exec(definition.replace('FUNCTION public.page_view_counts(', 'FUNCTION public.page_views_before_contacts('));
  await applyMigration(db, '_editorial_metrics_readers.sql');
  await db.exec(`CREATE OR REPLACE FUNCTION pg_catalog.now()
    RETURNS timestamptz LANGUAGE sql STABLE AS $$SELECT '2026-11-04T12:00:00Z'::timestamptz$$;
    INSERT INTO page_taxonomy(path,category,is_published,publication_checked_at) VALUES
      ('/post/été','ressource',true,'2026-11-04T08:00:00Z'),
      ('/post/b','classique',true,'2026-11-03T08:00:00Z'),
      ('/post/zero','classique',true,'2026-11-04T08:00:00Z'),
      ('/','cabinet',true,'2026-11-04T08:00:00Z'),
      ('/retired',NULL,false,'2026-11-04T08:00:00Z');`);
  const event = async (name,path,stamp,visitor,props={},hostname='www.jplouton-avocat.fr') => {
    if (name === 'form_submit' && visitor) props = {...props,cooked_aid:visitor,cooked_sid:visitor};
    await db.query(`INSERT INTO events(name,path,occurred_at,anonymous_id,session_id,props,hostname)
      VALUES($1,$2,$3,$4,$4,$5,$6)`, [name,path,stamp,visitor,JSON.stringify(props),hostname]);
  };
  const a='/post/été';
  // A current entry with repeated page views, two forms and a phone click on
  // another page: one contact visit attributed to the entry, not three leads.
  await event('pageview',a,'2026-10-10T12:00:00Z','current');
  await event('pageview','/post/%C3%A9t%C3%A9/','2026-10-10T12:01:00Z','current');
  await event('pageview','/post/e\u0301te\u0301','2026-10-10T12:02:00Z','current');
  await event('pageview','/post/b','2026-10-10T12:03:00Z','current');
  await event('cta_phone_click','/post/b','2026-10-10T12:04:00Z','current');
  await event('form_submit','/post/b','2026-10-10T12:05:00Z','current');
  await event('form_submit','/post/b','2026-10-10T12:06:00Z','current');
  await event('pageview',a,'2026-09-15T12:00:00Z','previous');
  await event('cta_phone_click',a,'2026-09-15T12:01:00Z','previous');

  // Crossing current/previous boundary while the visit remains continuous.
  await event('pageview',a,'2026-10-04T21:50:00Z','boundary');
  await event('cta_phone_click',a,'2026-10-04T22:05:00Z','boundary');
  await event('pageview','/post/b','2026-10-04T22:06:00Z','boundary');
  // Entry older than the previous period: its contact must not enter the cohort.
  await event('pageview',a,'2026-09-04T21:50:00Z','before-window');
  await event('cta_phone_click',a,'2026-09-04T22:05:00Z','before-window');
  // The current entry remains counted; its contact is today and stays excluded.
  await event('pageview',a,'2026-11-03T22:50:00Z','today-contact');
  await event('form_submit',a,'2026-11-03T23:05:00Z','today-contact');

  await event('form_submit',a,'2026-09-20T12:00:00Z',null);
  await event('cta_phone_click',a,'2026-11-02T12:00:00Z','no-page');
  await event('form_submit',a,'2026-11-02T12:01:00Z',null);
  await event('form_submit',a,'2026-11-02T12:02:00Z',null,{objet_de_ma_demande:'Nous rejoindre'});
  await event('form_submit',a,'2026-11-02T12:03:00Z',null,{counts_as_macro:false});
  await event('pageview',null,'2026-10-12T12:00:00Z','null-page');
  await event('cta_phone_click',a,'2026-10-12T12:01:00Z','null-page');
  await event('pageview','','2026-10-13T12:00:00Z','empty-page');
  // A later page must not retroactively give a preceding contact an entry.
  await event('cta_phone_click','/post/b','2026-10-14T12:00:00Z','future-page');
  await event('pageview','/post/b','2026-10-14T12:01:00Z','future-page');
  await event('pageview','/retired','2026-10-15T12:00:00Z','retired');
  await event('form_submit','/retired','2026-10-15T12:01:00Z','retired');
  await event('pageview',a,'2026-10-16T12:00:00Z','candidate');
  await event('form_submit',a,'2026-10-16T12:01:00Z','candidate',{objet_de_ma_demande:'Nous rejoindre'});
  for (const visitor of ['known-bot','known-noise']) {
    await event('pageview',a,'2026-10-17T12:00:00Z',visitor);
    await event('cta_phone_click',a,'2026-10-17T12:01:00Z',visitor);
  }
  await event('pageview',a,'2026-10-18T12:00:00Z','outremer',{},'outremer.jplouton-avocat.fr');
  await event('pageview',a,'2026-10-18T12:01:00Z','outremer-props',{cooked_site:'outremer'});
  await db.exec("INSERT INTO bot_fingerprints(anonymous_id) VALUES('known-bot'); INSERT INTO noise_sessions(session_id) VALUES('known-noise');");

  const fields=['entries','phone_visits','form_visits','contact_visits','contact_rate_pct'];
  for (const days of [30,60,90]) {
    const {rows:[{actual,legacy}]}=await db.query(`SELECT page_view_counts($1) AS actual,
      page_views_before_contacts($1) AS legacy`,[days]);
    const projected=Object.fromEntries(Object.keys(legacy).map(key=>[key,actual[key]]));
    projected.pages=actual.pages.map(({path,page_type,category,views})=>({path,page_type,category,views}));
    assert.deepEqual(projected,legacy,'all old view fields preserved for '+days);
    for (const previous of [false,true]) {
      const period=previous?actual.previous:actual;
      const {rows:reference}=await db.query('SELECT * FROM page_visits($1,$2)',[period.period_start,period.period_end]);
      const pages=new Map(reference.filter(r=>r.row_kind==='page').map(r=>[r.path,r]));
      const coverage=reference.find(r=>r.row_kind==='coverage');
      for (const page of actual.pages) {
        const metric=previous?page.previous:page;
        const ref=pages.get(page.path);
        for (const field of fields) {
          const expected=ref ? ref[field]===null ? null : Number(ref[field]) : field==='contact_rate_pct' ? null : 0;
          assert.equal(metric[field],expected,`${days} days previous=${previous} ${page.path} ${field}`);
        }
        const {rows:[{views}]}=await db.query(`SELECT count(*)::integer AS views FROM events_human
          WHERE name='pageview' AND nullif(path,'') IS NOT NULL AND canonical_path(path)=$1
          AND occurred_at>=cooked_paris_ts_start($2) AND occurred_at<cooked_paris_ts_end_exclusive($3)`,
        [page.path,period.period_start,period.period_end]);
        assert.equal(metric.views,views,'views retain their independent event counting');
        assert.ok(metric.contact_visits<=metric.entries,'cohort union never exceeds entries');
        assert.ok(metric.contact_visits>=Math.max(metric.phone_visits,metric.form_visits));
        assert.ok(metric.contact_visits<=metric.phone_visits+metric.form_visits);
      }
      for (const field of ['unattributed_phone_events','unattributed_form_events']) {
        assert.equal(period[field],Number(coverage[field]),`${days} previous=${previous} ${field}`);
      }
    }
  }
  const {rows:[{result}]}=await db.query('SELECT page_view_counts(30) AS result');
  const page=result.pages.find(p=>p.path===a);
  assert.equal(page.entries,3); // current, today-contact, candidature
  assert.equal(page.contact_visits,1);
  assert.equal(page.phone_visits,1);
  assert.equal(page.form_visits,1);
  assert.equal(page.contact_rate_pct,33.33);
  assert.equal(page.previous.entries,2); // previous and boundary
  assert.equal(page.previous.contact_visits,1,'cross-period contact excluded');
  assert.equal(result.unattributed_phone_events,3);
  assert.equal(result.unattributed_form_events,1);
  assert.equal(result.previous.unattributed_form_events,1);
  assert.equal(result.pages.find(p=>p.path==='/').views,0);
  assert.equal(result.pages.find(p=>p.path==='/post/zero').contact_rate_pct,null);
  assert.equal(result.pages.find(p=>p.path==='/post/b').contact_visits,0,'contact action page is not its entry');
  assert.equal(result.pages.some(p=>p.path==='/retired'),false);

  for (const routine of ['page_view_counts(integer)','page_query_counts(text,integer)']) {
    const {rows:[settings]}=await db.query('SELECT provolatile,prosecdef,proconfig FROM pg_proc WHERE oid=$1::regprocedure',[routine]);
    assert.equal(settings.provolatile,'s');
    assert.equal(settings.prosecdef,true);
    assert.deepEqual(settings.proconfig,['search_path=public, pg_catalog','statement_timeout=30s']);
    for (const [role,expected] of [['anon',false],['authenticated',false],['service_role',true]]) {
      const {rows:[{allowed}]}=await db.query('SELECT has_function_privilege($1,$2,\'EXECUTE\') AS allowed',[role,routine]);
      assert.equal(allowed,expected,role+' access to '+routine);
    }
  }
  await db.exec('SET ROLE service_role');
  assert.equal((await db.query('SELECT page_view_counts(30) AS result')).rows[0].result.pages.length,4);
  await db.exec('RESET ROLE');
  console.log('Editorial metrics: legacy views, both page_visits reference windows, cohorts, union, attribution, exclusions and ACL verified.');
} finally {await db.close();}
