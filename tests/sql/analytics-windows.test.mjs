import assert from 'node:assert/strict';
import {createDatabase} from './helpers.mjs';

const db=await createDatabase();
try {
  await db.exec(`CREATE OR REPLACE FUNCTION public.paris_today() RETURNS date LANGUAGE sql STABLE
    AS $$ SELECT date '2026-11-02' $$;`);
  async function event(name,session,at,eventPath,props={},url=null){
    await db.query(`INSERT INTO events(id,anonymous_id,session_id,name,path,props,url,occurred_at,received_at,device_type)
      VALUES(gen_random_uuid(),$1||'-aid',$1,$2,$3,$4::jsonb,$5,$6::timestamptz,$6::timestamptz,'mobile')`,
      [session,name,eventPath,JSON.stringify(props),url,at]);
  }
  await event('pageview','start','2026-10-05 00:00:00 Europe/Paris','/post/start');
  await event('cta_phone_click','start','2026-10-05 00:10:00 Europe/Paris','/post/start');
  await event('pageview','before','2026-10-04 23:59:59 Europe/Paris','/post/before');
  await event('cta_phone_click','before','2026-10-04 23:59:59 Europe/Paris','/post/before');
  await event('pageview','today','2026-11-02 00:00:00 Europe/Paris','/post/today');
  await event('cta_phone_click','today','2026-11-02 00:00:00 Europe/Paris','/post/today');
  await event('pageview','form','2026-11-01 23:50:00 Europe/Paris','/post/form');
  await event('form_submit','webhook-form','2026-11-01 23:59:59 Europe/Paris','/post/form',{
    cooked_aid:'form-aid',cooked_sid:'form',objet_de_ma_demande:'Divorce'
  });
  await db.exec("INSERT INTO page_taxonomy(path,category,theme) VALUES('/post/start','ressource','boundary')");
  await event('page_exit','start','2026-10-05 00:02:00 Europe/Paris','/post/start',{duration_seconds:60,max_scroll:50});
  await event('cta_booking_click','start','2026-10-05 00:03:00 Europe/Paris','/post/start');
  assert.deepEqual((await db.query(`SELECT path,visits::int,entries::int,contact_visits::int,contact_rate_pct::float
    FROM page_visits('2026-10-05','2026-11-01') WHERE path='/post/start'`)).rows,
    [{path:'/post/start',visits:1,entries:1,contact_visits:1,contact_rate_pct:100}],
    'entry and contact denominators share the first completed day');
  assert.equal((await db.query("SELECT count(*)::int AS n FROM cooked_visit_events('2026-10-05','2026-11-01') WHERE path IN ('/post/before','/post/today')")).rows[0].n,0);
  // The autumn day lasts 25 hours; both 02:30 occurrences belong to one closed day.
  await db.exec(`TRUNCATE events;
    CREATE OR REPLACE FUNCTION public.paris_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT date '2026-10-26' $$;`);
  await event('pageview','dst-first','2026-10-25 02:30:00+02','/dst');
  await event('pageview','dst-second','2026-10-25 02:30:00+01','/dst');
  await event('pageview','dst-last','2026-10-25 23:59:59+01','/dst');
  await event('pageview','dst-outside','2026-10-26 00:00:00+01','/dst');
  assert.deepEqual((await db.query("SELECT sum(visits)::int AS n FROM page_visits('2026-10-25','2026-10-25') WHERE row_kind='page'")).rows,[{n:3}],
    'one closed Paris day contains both repeated hours and excludes the next midnight');
  console.log('Analytics windows: closed days, visit counts and autumn transition verified.');
} finally { await db.close(); }
