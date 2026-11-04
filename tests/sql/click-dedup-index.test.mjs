import assert from 'node:assert/strict';
import {createDatabase,applyMigration} from './helpers.mjs';
const db=await createDatabase();
try {
  // The old predicate is deliberately kept here as the independent reference.
  const oldIds=`SELECT e.id FROM events_no_bots e
    WHERE NOT EXISTS(SELECT 1 FROM noise_sessions n WHERE n.session_id=e.session_id)
      AND NOT(e.name='cta_anchor_click' AND cooked_is_chrome_anchor(e.props))
      AND NOT(e.name IN ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound')
        AND EXISTS(SELECT 1 FROM events_main d WHERE d.session_id=e.session_id AND d.name=e.name
          AND d.path IS NOT DISTINCT FROM e.path
          AND date_trunc('second',d.occurred_at)=date_trunc('second',e.occurred_at)
          AND d.props->>'anchor' IS NOT DISTINCT FROM e.props->>'anchor' AND d.id<e.id))
    ORDER BY id`;
  let seq=0;
  async function add(name,at,path,anchor,sid='visit'){
    seq++;
    await db.query(`INSERT INTO events(id,anonymous_id,session_id,name,path,props,occurred_at)
      VALUES($1,'person',$2,$3,$4,$5,$6)`,[
        '00000000-0000-0000-0000-'+String(seq).padStart(12,'0'),sid,name,path,
        JSON.stringify(anchor===null?{}:{anchor}),at]);
  }
  for(const name of ['cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound']){
    await add(name,'2026-10-25T02:30:00.100+02','/page','content');
    await add(name,'2026-10-25T02:30:00.200+02','/page','content'); // duplicate
    await add(name,'2026-10-25T02:30:00.300+02','/page','other anchor');
    await add(name,'2026-10-25T02:30:00.400+02','/another','content');
    await add(name,'2026-10-25T02:30:01.100+02','/page','content');
    await add(name,'2026-10-25T02:30:00.100+01','/page','content'); // other repeated hour
    await add(name,'2026-10-25T02:30:00.200+01',null,null);
    await add(name,'2026-10-25T02:30:00.300+01',null,null); // duplicate nulls
  }
  await add('pageview','2026-10-25T02:30:00.100+02','/page',null);
  await add('pageview','2026-10-25T02:30:00.200+02','/page',null); // not a click
  await add('cta_anchor_click','2026-10-25T02:30:00.100+02','/page','Tout accepter');
  await add('cta_phone_click','2026-10-25T02:30:00.100+02','/page',null,'noise');
  await db.exec("INSERT INTO noise_sessions(session_id) VALUES('noise')");
  await applyMigration(db,'_index_click_dedup.sql');
  for(const zone of ['UTC','Europe/Paris','Australia/Lord_Howe']){
    await db.exec("SET TIME ZONE '"+zone+"'");
    const before=(await db.query(oldIds)).rows;
    const after=(await db.query('SELECT id FROM events_human ORDER BY id')).rows;
    assert.equal(before.length,32);
    assert.deepEqual(after,before,'identical row IDs in '+zone);
  }
  assert.deepEqual((await db.query("SELECT reloptions FROM pg_class WHERE oid='events_human'::regclass")).rows,
    [{reloptions:['security_invoker=true']}]);
  await applyMigration(db,'_index_click_dedup.sql');
  console.log('Click dedup index: identical IDs, 5 click types, nullable dimensions, chrome/noise, DST and invoker security.');
} finally {await db.close();}
