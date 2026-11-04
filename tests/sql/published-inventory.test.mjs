import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db = await createDatabase();
try {
  await db.exec(`INSERT INTO page_taxonomy(path,category,theme,source)
    VALUES('/post/existing','classique','manual-theme','manual'),('/post/retired','ressource','old','manual');`);
  await applyMigration(db, '_published_page_inventory.sql');
  await applyMigration(db, '_filter_publication_updates.sql');
  // Count physical publication updates, not just equal final values. This
  // catches a replay that needlessly writes every row again.
  await db.exec(`CREATE TEMP TABLE inventory_write_count(total integer);
    INSERT INTO inventory_write_count VALUES(0);
    CREATE FUNCTION pg_temp.count_inventory_write() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN UPDATE inventory_write_count SET total=total+1; RETURN NEW; END; $$;
    CREATE TRIGGER count_inventory_write AFTER UPDATE OF is_published, publication_checked_at
    ON page_taxonomy FOR EACH ROW EXECUTE FUNCTION pg_temp.count_inventory_write();`);
  const writes = async () => (await db.query('SELECT total FROM inventory_write_count')).rows[0].total;
  const rows = async () => (await db.query('SELECT * FROM page_taxonomy ORDER BY path')).rows;
  assert.equal((await rows()).every(r => r.is_published === null && r.publication_checked_at === null), true);
  const stamp = (await db.query('SELECT clock_timestamp()::text AS stamp')).rows[0].stamp;
  const inventory = {
    observed_at: stamp,
    counts: {posts: 1, categories: 1, static: 2},
    pages: [{path: '/', category: null}, {path: '/suivi-de-dossier', category: null},
      {path: '/blog/categories/penal', category: null}, {path: '/post/existing', category: 'ressource'}],
  };
  const sync = async (value, dry = false) => (await db.query(
    'SELECT * FROM page_taxonomy_sync_wix($1::jsonb,$2)', [JSON.stringify(value), dry])).rows[0];
  const before = await rows();
  assert.equal((await sync(inventory, true)).inserted, 3);
  assert.deepEqual(await rows(), before, 'dry-run changes neither taxonomy nor publication');
  const result = await sync(inventory);
  assert.deepEqual([result.inserted, result.updated, result.unpublished], [3,1,1]);
  let current = await rows();
  assert.equal(current.find(r => r.path === '/suivi-de-dossier').is_published, true, 'no traffic needed');
  assert.equal(current.find(r => r.path === '/post/retired').is_published, false);
  assert.equal(current.find(r => r.path === '/post/existing').theme, 'manual-theme');
  assert.equal(current.find(r => r.path === '/post/existing').source, 'manual');
  assert.equal(await writes(), current.length, 'the first inventory observes every current and absent page');
  const writesBeforeReplay = await writes();
  assert.deepEqual(await sync(inventory), {inserted:0, updated:0, unpublished:1, inserted_paths:[], updated_paths:[]});
  assert.deepEqual(await rows(), current, 'replaying an inventory is idempotent');
  assert.equal(await writes(), writesBeforeReplay, 'an exact replay does not rewrite publication rows');
  const corruptions = [
    {...inventory, counts:{posts:1,categories:1,static:1}},
    {...inventory, pages:inventory.pages.slice(1)},
    {...inventory, pages:[...inventory.pages, inventory.pages[0]]},
    {...inventory, pages:inventory.pages.map(p => p.path==='/' ? {...p,path:'https://elsewhere.fr/'} : p)},
    {...inventory, observed_at:null},
    {...inventory, observed_at:'2099-01-01T00:00:00Z'},
    {...inventory, observed_at:new Date(Date.parse(stamp)-1000).toISOString()},
  ];
  for (const bad of corruptions) {
    await assert.rejects(sync(bad));
    assert.deepEqual(await rows(), current, 'invalid/incomplete/stale input is atomic');
  }
  // Legacy scripts still update categories, but cannot unpublish any static page.
  const legacy = Array.from({length:300}, (_,i) => ({slug:i===0?'existing':`legacy-${i}`,category:'classique'}));
  await sync(legacy);
  assert.equal((await rows()).find(r=>r.path==='/post/existing').category, 'classique');
  assert.equal((await rows()).find(r=>r.path==='/suivi-de-dossier').is_published, true);
  assert.equal((await rows()).find(r=>r.path==='/post/legacy-1').is_published, null);
  current = await rows();
  // A storage failure after inserts rolls back the entire complete snapshot.
  await db.exec(`CREATE FUNCTION fail_inventory() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'simulated database failure'; END; $$;
    CREATE TRIGGER fail_inventory BEFORE UPDATE OF is_published ON page_taxonomy
    FOR EACH ROW EXECUTE FUNCTION fail_inventory();`);
  await assert.rejects(sync({...inventory, pages:inventory.pages.map(p=>p.path==='/post/existing'?{...p,path:'/post/brand-new'}:p)}));
  assert.deepEqual(await rows(), current);
  for (const role of ['anon','authenticated']) {
    assert.equal((await db.query(`SELECT has_function_privilege($1,'public.page_taxonomy_sync_wix(jsonb,boolean)','execute') AS allowed`, [role])).rows[0].allowed, false);
  }
  console.log('Published inventory: zero-traffic, complete atomic update, idempotency, stale/partial rejection, legacy and permissions verified.');
} finally {
  await db.close();
}
