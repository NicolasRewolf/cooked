import assert from 'node:assert/strict';
import {createDatabase,root} from './helpers.mjs';
import fs from 'node:fs';

const db=await createDatabase();
try {
  await db.exec("CREATE OR REPLACE FUNCTION public.paris_today() RETURNS date LANGUAGE sql STABLE AS $$SELECT date '2026-11-04'$$;");
  await db.exec('SET check_function_bodies=true;');
  for(const c of JSON.parse(fs.readFileSync(root+'/contracts/canonical_path_vectors.json','utf8')).path_cases) {
    assert.equal((await db.query('SELECT canonical_path($1) AS p',[c.input])).rows[0].p,c.expected,c.id);
  }
  for (const [host, props, expected] of [
    [null, null, true], ['', {}, true], ['www.jplouton-avocat.fr', {}, true],
    ['outremer.jplouton-avocat.fr', {}, false], ['www.jplouton-avocat.fr', {cooked_site:'outremer'}, false],
  ]) assert.equal((await db.query('SELECT cooked_is_main_site($1,$2) AS main', [host,props])).rows[0].main, expected);

  const rows=async(sql,args=[]) => (await db.query(sql,args)).rows;
  async function event(name,sid,at,path,props={},aid=sid+'-aid') {
    const result=await rows(`INSERT INTO events(anonymous_id,session_id,name,occurred_at,path,props,device_type,hostname)
      VALUES($1,$2,$3,$4,$5,$6,'desktop','www.jplouton-avocat.fr') RETURNING id`,
      [aid,sid,name,at,path,JSON.stringify(props)]);
    return result[0].id;
  }
  // A visit enters before midnight, keeps reading, then contacts after midnight.
  const entry=await event('pageview','cross','2026-11-02T22:50:00Z','/post/%C3%A9preuve/');
  await event('engagement_tick','cross','2026-11-02T23:10:00Z','/post/épreuve');
  await event('cta_phone_click','cross','2026-11-02T23:20:00Z','/post/épreuve');
  await event('form_submit','webhook-cross','2026-11-02T23:22:00Z',null,{cooked_sid:'cross',cooked_aid:'cross-aid'});
  const contacts=await rows(`SELECT visit_id,entry_path,entry_at::text
    FROM cooked_visit_events('2026-11-03','2026-11-03') WHERE counts_as_macro ORDER BY occurred_at`);
  assert.equal(contacts.length,2);
  assert.deepEqual(contacts.map(c=>c.visit_id),[entry,entry]);
  assert.deepEqual(contacts.map(c=>c.entry_path),['/post/épreuve','/post/épreuve']);
  assert.equal(contacts[0].entry_at,contacts[1].entry_at);
  const [contract]=await rows("SELECT * FROM cooked_visit_events('2026-11-03','2026-11-03') LIMIT 1");
  assert.deepEqual(Object.keys(contract),['event_id','event_name','occurred_at','path',
    'counts_as_macro','visit_id','entry_at','entry_path'],'only the eight fields used by the readers are returned');
  assert.deepEqual(await rows(`SELECT row_kind,path,entries::int,contact_visits::int FROM page_visits('2026-11-03','2026-11-03')`),
    [{row_kind:'coverage',path:null,entries:null,contact_visits:null}]);
  // Never create an entry in the later window because a continuation page is seen.
  await event('pageview','cross','2026-11-02T23:25:00Z','/expertise');
  assert.deepEqual(await rows(`SELECT path,visits::int,entries::int,contact_visits::int FROM page_visits('2026-11-03','2026-11-03') WHERE row_kind='page'`),
    [{path:'/expertise',visits:1,entries:0,contact_visits:0}]);

  // Repeated actions and phone + form are one converted visit, never >100%.
  const newEntry=await event('pageview','new','2026-11-03T11:00:00Z','/landing');
  await event('cta_phone_click','new','2026-11-03T11:01:00Z','/landing');
  await event('cta_phone_click','new','2026-11-03T11:02:00Z','/landing');
  await event('form_submit','webhook-new','2026-11-03T11:03:00Z',null,{cooked_sid:'new'});
  await event('pageview','new','2026-11-03T11:04:00Z','/future');
  const newContacts=await rows(`SELECT visit_id,entry_path FROM cooked_visit_events('2026-11-03','2026-11-03')
    WHERE counts_as_macro AND entry_path='/landing'`);
  assert.equal(newContacts.length,3);
  assert.ok(newContacts.every(c=>c.visit_id===newEntry && c.entry_path==='/landing'),
    'a later page does not replace the entry of earlier contacts');
  assert.deepEqual(await rows(`SELECT visits::int,entries::int,phone_visits::int,form_visits::int,contact_visits::int,contact_rate_pct::float
    FROM page_visits('2026-11-03','2026-11-03') WHERE path='/landing'`),
    [{visits:1,entries:1,phone_visits:1,form_visits:1,contact_visits:1,contact_rate_pct:100}]);

  // Vitaux tardifs cannot keep the old visit alive. A contact before a future
  // pageview also remains unknown, regardless of the same device key.
  await event('pageview','stale','2026-11-03T09:00:00Z','/stale');
  await event('web_vitals','stale','2026-11-03T09:25:00Z','/stale');
  await event('cta_phone_click','stale','2026-11-03T09:40:00Z','/stale');
  const futureEntry=await event('pageview','stale','2026-11-03T09:41:00Z','/too-late');
  await event('form_submit','webhook-no-id','2026-11-03T11:02:00Z','/landing');
  await event('form_submit','webhook-job','2026-11-03T11:02:30Z','/landing',{objet_de_ma_demande:'Nous rejoindre'});
  const coverage=(await rows(`SELECT unattributed_phone_events::int AS phone,unattributed_form_events::int AS form
    FROM page_visits('2026-11-03','2026-11-03') WHERE row_kind='coverage'`))[0];
  assert.deepEqual(coverage,{phone:1,form:1});
  assert.deepEqual(await rows(`SELECT visit_id,entry_at,entry_path,counts_as_macro
    FROM cooked_visit_events('2026-11-03','2026-11-03')
    WHERE event_name='form_submit' AND visit_id IS NULL ORDER BY occurred_at`),
    [{visit_id:null,entry_at:null,entry_path:null,counts_as_macro:true},
      {visit_id:null,entry_at:null,entry_path:null,counts_as_macro:false}]);
  assert.deepEqual(await rows(`SELECT visit_id,entry_at,entry_path
    FROM cooked_visit_events('2026-11-03','2026-11-03')
    WHERE event_name='cta_phone_click' AND path='/stale'`),
    [{visit_id:null,entry_at:null,entry_path:null}],
    'a page seen after a contact never attributes that earlier contact');
  assert.deepEqual(await rows(`SELECT visit_id,entry_path
    FROM cooked_visit_events('2026-11-03','2026-11-03') WHERE event_id=$1`,[futureEntry]),
    [{visit_id:futureEntry,entry_path:'/too-late'}]);

  // IDs are stable across window cuts and old aliases are genuinely stitched.
  await event('pageview','old-a','2026-06-01T10:00:00Z','/old',{},'same-old-aid');
  await event('pageview','old-b','2026-06-01T10:02:00Z','/second',{},'same-old-aid');
  await event('cta_phone_click','old-b','2026-06-01T10:03:00Z','/second',{},'same-old-aid');
  const sharedFallback='a'.repeat(32);
  await event('pageview','fallback-a','2026-06-01T12:00:00Z','/fallback-a',{},sharedFallback);
  await event('pageview','fallback-b','2026-06-01T12:01:00Z','/fallback-b',{},sharedFallback);
  await db.query('SELECT refresh_identity_stitch(90)');
  assert.equal((await rows("SELECT count(DISTINCT visitor_key)::int AS n FROM identity_stitch WHERE kind='sid' AND key IN ('old-a','old-b')"))[0].n,1);
  assert.equal((await rows("SELECT count(*)::int AS n FROM identity_stitch WHERE key=$1",[sharedFallback]))[0].n,0);
  assert.deepEqual(await rows(`SELECT entry_path FROM cooked_visit_events('2026-06-01','2026-06-01') WHERE event_name='cta_phone_click'`),[{entry_path:'/old'}]);
  assert.deepEqual(await rows(`SELECT entries::int,contact_visits::int FROM page_visits('2026-06-01','2026-06-01') WHERE path='/old'`),[{entries:1,contact_visits:1}]);
  assert.deepEqual(await rows(`SELECT entry_path FROM cooked_visit_events('2026-06-01','2026-06-01') WHERE path LIKE '/fallback-%' ORDER BY path`),
    [{entry_path:'/fallback-a'},{entry_path:'/fallback-b'}]);

  // Conflicting explicit identities are unknown, never silently assigned to SID.
  await event('pageview','conflict-a','2026-11-03T14:00:00Z','/conflict-a');
  await event('pageview','conflict-b','2026-11-03T14:00:00Z','/conflict-b');
  await event('form_submit','webhook-conflict','2026-11-03T14:01:00Z',null,{cooked_sid:'conflict-a',cooked_aid:'conflict-b-aid'});
  await db.query('SELECT refresh_identity_stitch(90)');
  const conflicting=await rows(`SELECT visit_id,entry_at,entry_path FROM cooked_visit_events('2026-11-03','2026-11-03')
    WHERE event_name='form_submit' AND occurred_at='2026-11-03T14:01:00Z'`);
  assert.deepEqual(conflicting,[{visit_id:null,entry_at:null,entry_path:null}]);

  // Exactly thirty minutes stays in the visit; one extra second starts a new one.
  const boundaryEntry=await event('pageview','boundary','2026-11-03T16:00:00Z','/boundary');
  const exactPhone=await event('cta_phone_click','boundary','2026-11-03T16:30:00Z','/boundary');
  const continuedPhone=await event('cta_phone_click','boundary','2026-11-03T17:00:00Z','/boundary');
  const nextEntry=await event('pageview','boundary','2026-11-03T17:30:01Z','/boundary');
  const nextPhone=await event('cta_phone_click','boundary','2026-11-03T18:00:01Z','/boundary');
  assert.deepEqual(await rows(`SELECT event_id,visit_id FROM cooked_visit_events('2026-11-03','2026-11-03')
    WHERE event_id=ANY($1::uuid[]) ORDER BY occurred_at`,[[exactPhone,continuedPhone,nextPhone]]),
    [{event_id:exactPhone,visit_id:boundaryEntry},{event_id:continuedPhone,visit_id:boundaryEntry},
      {event_id:nextPhone,visit_id:nextEntry}]);
  assert.deepEqual(await rows(`SELECT visits::int,entries::int,phone_visits::int,contact_visits::int,contact_rate_pct::float
    FROM page_visits('2026-11-03','2026-11-03') WHERE path='/boundary'`),
    [{visits:2,entries:2,phone_visits:2,contact_visits:2,contact_rate_pct:100}]);

  // Equal timestamps still place the pageview before its contact in the visit.
  const simultaneousPhone=await event('cta_phone_click','simultaneous','2026-11-03T18:30:00Z','/simultaneous');
  const simultaneousEntry=await event('pageview','simultaneous','2026-11-03T18:30:00Z','/simultaneous');
  assert.deepEqual(await rows(`SELECT visit_id,entry_path FROM cooked_visit_events('2026-11-03','2026-11-03')
    WHERE event_id=$1`,[simultaneousPhone]),[{visit_id:simultaneousEntry,entry_path:'/simultaneous'}]);

  // Long chains need more than three propagation rounds to converge.
  for(let n=0;n<10;n++){
    await event('pageview','chain-'+n,'2026-06-02T10:00:00Z','/chain',{},'chain-aid-'+n);
    await event('pageview','chain-'+n,'2026-06-02T10:00:01Z','/chain',{},'chain-aid-'+(n+1));
  }
  await db.query('SELECT refresh_identity_stitch(90)');
  assert.equal((await rows("SELECT count(DISTINCT visitor_key)::int AS n FROM identity_stitch WHERE key LIKE 'chain-%'"))[0].n,1);

  // The 25-hour DST day includes both repeated hours and its last minute.
  await event('pageview','dst','2026-10-25T02:30:00+02','/dst');
  await event('cta_phone_click','dst','2026-10-25T02:30:00+01','/dst');
  await event('pageview','end','2026-10-25T23:59:59+01','/dst');
  await event('cta_phone_click','end','2026-10-26T00:00:00+01','/dst');
  const dst=await rows("SELECT count(*)::int AS n FROM cooked_visit_events('2026-10-25','2026-10-25')");
  assert.equal(dst[0].n,3);
  const dstKnown=await rows("SELECT visit_id FROM cooked_visit_events('2026-10-25','2026-10-25') WHERE counts_as_macro");
  assert.equal(dstKnown[0].visit_id,null,'repeated local hour actually has sixty minutes inactivity');

  // Phone and form contacts use the same entry cohort regardless of source.
  await event('pageview','organic','2026-11-03T15:00:00Z','/organic');
  await db.query("UPDATE events SET referrer_hostname='www.google.com' WHERE session_id='organic'");
  await event('cta_phone_click','organic','2026-11-03T15:01:00Z','/organic');
  await event('cta_phone_click','organic','2026-11-03T15:02:00Z','/organic');
  await event('form_submit','webhook-organic','2026-11-03T15:03:00Z',null,{cooked_sid:'organic'});
  assert.deepEqual(await rows(`SELECT entries::int,contact_visits::int,phone_visits::int,form_visits::int,
    contact_rate_pct::float FROM page_visits('2026-11-03','2026-11-03') WHERE path='/organic'`),
    [{entries:1,contact_visits:1,phone_visits:1,form_visits:1,contact_rate_pct:100}]);

  // Every filtered macro event remains present, including unknown attribution.
  const [{total}]=await rows(`SELECT count(*)::int AS total FROM events_human
    WHERE occurred_at>=cooked_paris_ts_start('2026-11-03') AND occurred_at<cooked_paris_ts_end_exclusive('2026-11-03')
      AND (name='cta_phone_click' OR (name='form_submit' AND form_submit_counts_as_macro(props)))`);
  assert.equal((await rows("SELECT count(*)::int AS n FROM cooked_visit_events('2026-11-03','2026-11-03') WHERE counts_as_macro"))[0].n,total);
  for (const signature of ['cooked_visit_events(date,date)','page_visits(date,date)','refresh_identity_stitch(integer)']) {
    const [acl]=await rows("SELECT has_function_privilege('anon',$1,'EXECUTE') AS anon,has_function_privilege('authenticated',$1,'EXECUTE') AS authenticated,has_function_privilege('service_role',$1,'EXECUTE') AS service",[signature]);
    assert.deepEqual(acl,{anon:false,authenticated:false,service:true});
  }
  await assert.rejects(()=>db.query("SELECT * FROM page_visits('2026-11-03','2026-11-04')"),e=>e.code==='22023');
  await assert.rejects(()=>db.query("SELECT * FROM page_visits('2026-11-03','2026-11-02')"),e=>e.code==='22023');
  // Changing the extraction window never reassigns an event or invents an entry.
  for (const [start,end] of [['2026-08-06','2026-11-03'],['2026-05-08','2026-08-05'],['2026-11-03','2026-11-03']]) {
    assert.deepEqual(await rows('SELECT * FROM cooked_visit_events($1,$2) ORDER BY event_id',[start,end]),
      await rows(`SELECT * FROM cooked_visit_events('2026-05-08','2026-11-03')
        WHERE occurred_at>=cooked_paris_ts_start($1) AND occurred_at<cooked_paris_ts_end_exclusive($2)
        ORDER BY event_id`,[start,end]),
      `all eight event fields stay stable across the extraction window ${start} to ${end}`);
  }
  console.log('Canonical visits verified: inactivity, entry boundaries, certain attribution, historical stitch, rates, ACL.');
} catch(e) {
  console.error(e.message,e.detail??'');
  throw e;
} finally {await db.close();}
