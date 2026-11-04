import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db = await createDatabase();
try {
  await db.exec(`INSERT INTO page_taxonomy(path,category,theme,source)
    VALUES('/post/existing','classique','manual-theme','manual'),('/post/retired','ressource','old','manual');`);
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
  const preview = await sync(inventory, true);
  await applyMigration(db, '_complete_wix_inventory_only.sql');
  assert.deepEqual(await sync(inventory, true), preview, 'complete-inventory preview survives the migration');
  assert.equal(preview.inserted, 3);
  assert.deepEqual(await rows(), before, 'dry-run changes neither taxonomy nor publication');
  assert.equal(await writes(), 0);
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
    assert.equal(await writes(), writesBeforeReplay);
  }
  // Only a complete observation can update the inventory, even in dry-run mode.
  const legacy = Array.from({length:300}, (_,i) => ({slug:i===0?'existing':`legacy-${i}`,category:'classique'}));
  for (const bad of [legacy, [], null, 'historical|r|2026-09-03', 12, true, {}]) {
    for (const dry of [false, true]) {
      await assert.rejects(sync(bad, dry));
      assert.deepEqual(await rows(), current, 'legacy and scalar input cannot change any row');
      assert.equal(await writes(), writesBeforeReplay);
    }
  }
  await assert.rejects(db.query('SELECT * FROM page_taxonomy_sync_wix(NULL,false)'));
  assert.deepEqual(await rows(), current);
  assert.equal(await writes(), writesBeforeReplay);

  // A later observation discovers a new article independently of event traffic.
  const nextStamp = (await db.query('SELECT clock_timestamp()::text AS stamp')).rows[0].stamp;
  const nextInventory = {...inventory, observed_at:nextStamp,
    counts:{...inventory.counts, posts:2},
    pages:[...inventory.pages, {path:'/post/newly-published', category:'classique'}]};
  const nextPreview = await sync(nextInventory, true);
  assert.deepEqual(nextPreview, {inserted:1, updated:0, unpublished:1,
    inserted_paths:['/post/newly-published'], updated_paths:[]});
  assert.deepEqual(await rows(), current);
  assert.equal(await writes(), writesBeforeReplay);
  assert.deepEqual(await sync(nextInventory), nextPreview);
  const previousPaths = current.map(r => r.path);
  current = await rows();
  assert.equal(current.find(r => r.path === '/post/newly-published').is_published, true);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM events')).rows[0].n, 0);
  assert.ok(previousPaths.every(path => current.some(r => r.path === path)), 'all historical pages remain stored');
  assert.equal(current.find(r => r.path === '/post/retired').is_published, false);
  assert.equal(current.find(r => r.path === '/post/existing').is_published, true);
  const writesAfterNewArticle = await writes();
  await sync(nextInventory);
  assert.deepEqual(await rows(), current);
  assert.equal(await writes(), writesAfterNewArticle, 'replaying the new observation writes nothing');

  // A storage failure after inserts rolls back the entire complete snapshot.
  await db.exec(`CREATE FUNCTION fail_inventory() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'simulated database failure'; END; $$;
    CREATE TRIGGER fail_inventory BEFORE UPDATE OF is_published ON page_taxonomy
    FOR EACH ROW EXECUTE FUNCTION fail_inventory();`);
  const failureStamp = (await db.query('SELECT clock_timestamp()::text AS stamp')).rows[0].stamp;
  await assert.rejects(sync({...nextInventory, observed_at:failureStamp,
    pages:nextInventory.pages.map(p=>p.path==='/post/existing'?{...p,path:'/post/brand-new'}:p)}),
  /simulated database failure/);
  assert.deepEqual(await rows(), current);
  assert.equal(await writes(), writesAfterNewArticle);
  for (const role of ['anon','authenticated']) {
    assert.equal((await db.query(`SELECT has_function_privilege($1,'public.page_taxonomy_sync_wix(jsonb,boolean)','execute') AS allowed`, [role])).rows[0].allowed, false);
  }
  console.log('Published inventory: new zero-traffic articles, atomic update, idempotency, stale/partial/legacy rejection and permissions verified.');
} finally {
  await db.close();
}
