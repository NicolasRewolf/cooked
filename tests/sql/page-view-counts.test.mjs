import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

async function applyCountingVersions(db) {
  await applyMigration(db, '_page_view_counts.sql');
  await applyMigration(db, '_page_view_counts_timeout.sql');
  const {rows: [{definition}]} = await db.query(
    "SELECT pg_get_functiondef('public.page_view_counts(integer)'::regprocedure) AS definition");
  await db.exec(definition.replace('FUNCTION public.page_view_counts(',
    'FUNCTION public.page_view_counts_before_grouping('));
  await applyMigration(db, '_page_view_counts_group_paths.sql');
}

async function compareCounts(db, days = 90) {
  const {rows: [{result, before}]} = await db.query(`SELECT
    page_view_counts($1) AS result, page_view_counts_before_grouping($1) AS before`, [days]);
  assert.deepEqual(result, before, 'grouping paths preserves the complete JSON result for ' + days + ' days');
  return result;
}

const db = await createDatabase();
try {
  await applyCountingVersions(db);
  const {rows: [settings]} = await db.query(
    "SELECT proconfig FROM pg_proc WHERE oid='public.page_view_counts(integer)'::regprocedure");
  assert.ok(settings.proconfig.includes('statement_timeout=30s'),
    'the REST deadline is scoped to this aggregate, without changing role defaults');
  const at = async (stamp) => db.exec(`CREATE OR REPLACE FUNCTION pg_catalog.now()
    RETURNS timestamptz LANGUAGE sql STABLE AS $$SELECT '${stamp}'::timestamptz$$;`);
  const counts = (days = 90) => compareCounts(db, days);
  const event = async (path, {
    name = 'pageview', stamp = '2026-11-03T12:00:00Z',
    aid = 'reader', sid = 'same-visit', hostname = 'www.jplouton-avocat.fr', props = {},
  } = {}) => db.query(`INSERT INTO events(name,path,occurred_at,anonymous_id,session_id,hostname,props)
    VALUES($1,$2,$3,$4,$5,$6,$7)`, [name,path,stamp,aid,sid,hostname,JSON.stringify(props)]);

  await at('2026-11-04T12:00:00Z');
  assert.deepEqual(await counts(), {
    period_start: '2026-08-06', period_end: '2026-11-03', expected_days: 90,
    observed_days: 0, inventory_checked_at: null, pages: [],
  }, 'an empty inventory stays explicit, with no invented page');
  assert.deepEqual((await db.query('SELECT page_view_counts() AS result')).rows[0].result,
    await counts(90), 'omitting the SQL parameter selects 90 days');

  await db.exec(`INSERT INTO page_taxonomy(path,category,is_published,publication_checked_at) VALUES
    ('/',NULL,true,'2026-11-04T08:00:00Z'),
    ('/defense-penale',NULL,true,'2026-11-03T08:00:00Z'),
    ('/defense-penale/garde-a-vue',NULL,true,'2026-11-04T08:00:00Z'),
    ('/post/été','classique',true,'2026-11-04T08:00:00Z'),
    ('/post/ressource','ressource',true,'2026-11-04T08:00:00Z'),
    ('/post/zero','classique',true,'2026-11-04T08:00:00Z'),
    ('/blog/categories/penal',NULL,true,'2026-11-04T08:00:00Z'),
    ('/post/retired','classique',false,'2026-11-04T08:00:00Z'),
    ('/post/unknown','classique',NULL,NULL);`);

  // Three page views in one visit remain three views. Encoded/decomposed
  // variants join the same published URL through the shared canonical path.
  for (const path of ['/post/été', '/post/%C3%A9t%C3%A9/', '/post/e\u0301te\u0301']) await event(path);
  for (const path of ['/defense-penale', '/defense-penale/garde-a-vue', '/post/ressource']) await event(path);
  await event('/post/retired', {stamp: '2026-11-02T12:00:00Z'});
  await event('/post/unknown');
  await event('/not-in-inventory');
  for (const path of [null, '']) await event(path, {stamp: '2026-11-01T12:00:00Z'});
  await event('/post/été', {name: 'page_exit'});
  await event('/post/été', {name: 'cta_phone_click'});
  await event('/post/été', {aid: 'known-bot'});
  await event('/post/été', {sid: 'known-noise'});
  await event('/post/été', {hostname: 'outremer.jplouton-avocat.fr'});
  await event('/post/été', {props: {cooked_site: 'outremer'}});
  await db.exec(`INSERT INTO bot_fingerprints(anonymous_id) VALUES('known-bot');
    INSERT INTO noise_sessions(session_id) VALUES('known-noise');`);

  const result = await counts(30);
  assert.equal(result.pages.length, 7, 'only currently published inventory pages are listed');
  assert.equal(result.pages.reduce((n, page) => n + page.views, 0), 6,
    'non-pageview events, bots, noise and both Outremer markers are excluded');
  assert.equal(result.pages.find(p => p.path === '/post/été').views, 3);
  assert.equal(result.pages.find(p => p.path === '/post/zero').views, 0, 'published page without traffic remains visible');
  assert.equal(result.pages.find(p => p.path === '/').views, 0, 'missing paths are never attributed to the homepage');
  assert.deepEqual(result.pages.map(p => [p.path, p.page_type, p.category]), [
    ['/post/été', 'post', 'classique'],
    ['/defense-penale', 'hub', null],
    ['/defense-penale/garde-a-vue', 'expertise', null],
    ['/post/ressource', 'post', 'ressource'],
    ['/', 'cabinet', null],
    ['/blog/categories/penal', 'blog-nav', null],
    ['/post/zero', 'post', 'classique'],
  ], 'existing taxonomy is preserved, sorted by views then path');
  assert.equal(result.observed_days, 3, 'coverage is sitewide, including views without a current published URL');
  assert.equal(new Date(result.inventory_checked_at).toISOString(), '2026-11-03T08:00:00.000Z',
    'oldest published observation dates inventory coverage');

  // The 30/60/90 day windows cross autumn DST. Midnight is 22:00 UTC at
  // their summer starts and 23:00 UTC at the November end, never a fixed offset.
  for (const [days, start, lower, beforeLower] of [
    [30, '2026-10-05', '2026-10-04T22:00:00Z', '2026-10-04T21:59:59.999Z'],
    [60, '2026-09-05', '2026-09-04T22:00:00Z', '2026-09-04T21:59:59.999Z'],
    [90, '2026-08-06', '2026-08-05T22:00:00Z', '2026-08-05T21:59:59.999Z'],
  ]) {
    await db.exec('DELETE FROM events');
    for (const stamp of [beforeLower, lower, '2026-10-25T00:30:00Z', '2026-10-25T01:30:00Z',
      '2026-11-03T22:59:59.999Z', '2026-11-03T23:00:00Z']) await event('/', {stamp});
    const period = await counts(days);
    assert.equal(period.period_start, start);
    assert.equal(period.period_end, '2026-11-03');
    assert.equal(period.expected_days, days);
    assert.equal(period.pages.find(p => p.path === '/').views, 4,
      'inclusive Paris start, both repeated-hour views, exclusive midnight today: ' + days);
    assert.equal(period.observed_days, 3);
  }

  // A separate database avoids reusing an inlined plan from the frozen
  // autumn clock when substituting PostgreSQL's now() for this second scenario.
  const summerDb = await createDatabase();
  try {
    await applyCountingVersions(summerDb);
    await summerDb.exec(`CREATE OR REPLACE FUNCTION pg_catalog.now()
      RETURNS timestamptz LANGUAGE sql STABLE AS $$SELECT '2026-07-02T12:00:00Z'::timestamptz$$;
      INSERT INTO page_taxonomy(path,is_published,publication_checked_at)
        VALUES('/',true,'2026-07-02T08:00:00Z');
      INSERT INTO events(name,path,occurred_at) VALUES
        ('pageview','/','2026-07-01T21:59:59.999Z'),('pageview','/','2026-07-01T22:00:00Z');`);
    const summer = await compareCounts(summerDb, 30);
    assert.equal(summer.period_start, '2026-06-02');
    assert.equal(summer.period_end, '2026-07-01');
    assert.equal(summer.pages.find(p => p.path === '/').views, 1, 'today is excluded during summer time too');
  } finally {
    await summerDb.close();
  }

  // Repeated raw paths span several days and aliases merge only after their
  // individual counts. Coverage still includes unpublished/missing paths.
  await db.exec(`DELETE FROM events;
    INSERT INTO events(name,path,occurred_at,anonymous_id,session_id)
    SELECT 'pageview',
      (ARRAY['/post/été','/post/%C3%A9t%C3%A9/','/post/été','/post/retired',NULL,''])[1 + (n % 6)],
      '2026-11-03T12:00:00Z'::timestamptz - (n % 95) * interval '1 day',
      'repeated-reader','repeated-session'
    FROM generate_series(0,2999) AS n;`);
  for (const days of [30,60,90]) {
    const repeated = await counts(days);
    assert.equal(repeated.observed_days, days);
    assert.equal(repeated.pages.find(p => p.path === '/').views, 0);
    assert.equal(repeated.pages.find(p => p.path === '/post/zero').views, 0);
  }

  const {rows: [routine]} = await db.query(`SELECT provolatile,prosecdef,proconfig
    FROM pg_proc WHERE oid='public.page_view_counts(integer)'::regprocedure`);
  assert.equal(routine.provolatile, 's');
  assert.equal(routine.prosecdef, true);
  assert.deepEqual(routine.proconfig, ['search_path=public, pg_catalog','statement_timeout=30s']);

  for (const days of [null, 0, -30, 1, 29, 31, 91]) {
    await assert.rejects(counts(days), error => error.code === '22023');
  }
  for (const [role, expected] of [['anon', false], ['authenticated', false], ['service_role', true]]) {
    const {rows: [privilege]} = await db.query(
      "SELECT has_function_privilege($1,'public.page_view_counts(integer)','EXECUTE') AS allowed", [role]);
    assert.equal(privilege.allowed, expected, 'RPC access for ' + role);
  }
  await db.exec('SET ROLE service_role');
  assert.equal((await counts(30)).pages.length, 7, 'the server role can read the aggregate through the existing protected sources');
  await db.exec('RESET ROLE');
  console.log('Page view counts: published inventory, zeroes, repeated views, shared filters, canonical paths, Paris 30/60/90 windows, coverage and ACL verified.');
} finally {
  await db.close();
}
