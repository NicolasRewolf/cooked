import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db = await createDatabase();
try {
  await applyMigration(db, '_fix_alert_wall_clock_hours.sql');
  for (const [at, expected] of [
    ['2026-03-28T11:00:00Z',12], ['2026-03-29T10:00:00Z',12],
    ['2026-10-25T11:00:00Z',12], ['2026-10-25T22:00:00Z',23],
    ['2026-10-25T00:30:00Z',2], ['2026-10-25T01:30:00Z',2],
    ['2026-03-29T01:00:00Z',3],
  ]) {
    const {rows:[row]} = await db.query('SELECT cooked_paris_hour($1::timestamptz) AS hour',[at]);
    assert.equal(row.hour,expected,'Paris wall-clock hour at '+at);
  }

  // Freeze the clock at the system boundary in this disposable database only.
  for (const now of ['2026-03-29T10:30:00Z','2026-10-25T11:30:00Z','2026-11-02T11:30:00Z']) {
    const clockDb = await createDatabase();
    try {
    await applyMigration(clockDb, '_fix_alert_wall_clock_hours.sql');
    await clockDb.exec(`CREATE OR REPLACE FUNCTION pg_catalog.now() RETURNS timestamptz
      LANGUAGE sql STABLE AS $$SELECT '${now}'::timestamptz$$;
      DELETE FROM events;
      INSERT INTO events(name,path,session_id,anonymous_id,occurred_at,received_at,props)
      SELECT 'pageview','/clock','history-'||d||'-'||h||'-'||n,'visitor-'||d||'-'||h||'-'||n,
        ((paris_today()-d)::timestamp+make_interval(hours=>h)) AT TIME ZONE 'Europe/Paris',
        ((paris_today()-d)::timestamp+make_interval(hours=>h)) AT TIME ZONE 'Europe/Paris','{}'::jsonb
      FROM generate_series(1,7) d CROSS JOIN (VALUES(11),(12)) hs(h) CROSS JOIN generate_series(1,40) n;
      INSERT INTO events(name,path,session_id,anonymous_id,occurred_at,received_at,props)
      SELECT 'pageview','/clock','current-'||n,'visitor-current-'||n,
        (paris_today()::timestamp+interval '11 hours 10 minutes') AT TIME ZONE 'Europe/Paris',
        (paris_today()::timestamp+interval '11 hours 10 minutes') AT TIME ZONE 'Europe/Paris','{}'::jsonb
      FROM generate_series(1,5) n;`);
    const {rows:volume} = await clockDb.query('SELECT * FROM alert_rule_volume_floor()');
    assert.equal(volume.length,1,'real previous hour compared to the same historical hour: '+now);
    assert.equal(volume[0].kind,'volume_floor');
    assert.match(volume[0].detail,/11h Paris : 5 vs médiane 7 j 40/);

    await clockDb.exec(`DELETE FROM events WHERE occurred_at>=cooked_paris_ts_start(paris_today());
      INSERT INTO events(name,path,occurred_at,received_at,props)
      VALUES('page_exit','/clock',now()-interval '100 minutes',now()-interval '100 minutes','{}');`);
    const {rows:pipeline} = await clockDb.query('SELECT * FROM alert_rule_pipeline_dead()');
    assert.equal(pipeline.length,1,'pipeline uses the same Paris hour in its baseline: '+now);
    assert.equal(pipeline[0].severity,'critical');
    assert.match(pipeline[0].detail,/100 min/);
    } finally { await clockDb.close(); }
  }
  console.log('Alert clock: both DST transitions, repeated hour and actual alert rules verified.');
} finally {
  await db.close();
}
