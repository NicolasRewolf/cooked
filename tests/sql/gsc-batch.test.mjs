import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db = await createDatabase();
try {
  const historical = '00000000-0000-0000-0000-000000000000';
  const oldManifest = {gsc_path_daily: 2, gsc_query_daily: 2, gsc_query_page_daily: 2};
  await db.query(`INSERT INTO gsc_ingest_batches(run_id,day_start,day_end,status,completed_at,row_counts)
    VALUES($1,'2026-09-01','2026-09-30','completed',now(),$2)`, [historical, JSON.stringify(oldManifest)]);
  await applyMigration(db, '_gsc_two_grain_batches.sql');
  assert.deepEqual((await db.query('SELECT row_counts FROM gsc_ingest_batches WHERE run_id=$1', [historical])).rows[0].row_counts,
    oldManifest, 'historical manifests are not rewritten');

  const a = '00000000-0000-0000-0000-000000000001';
  const b = '00000000-0000-0000-0000-000000000002';
  const counts = {gsc_path_daily: 2, gsc_query_page_daily: 2};
  const begin = id => db.query("SELECT gsc_ingest_begin($1,'2026-10-01','2026-10-19')", [id]);
  const complete = (id, manifest) => db.query('SELECT gsc_ingest_complete($1,$2::jsonb)', [id, JSON.stringify(manifest)]);
  const fail = id => db.query('SELECT gsc_ingest_fail($1)', [id]);
  const reject = (request, code) => assert.rejects(request, error => error.code === code);
  await begin(a);
  await begin(a);
  await reject(begin(b), '55P03');
  for (const invalid of [
    {gsc_path_daily: 2}, {gsc_query_page_daily: 2}, oldManifest,
    {...counts, gsc_query_page_daily: -1}, {...counts, gsc_path_daily: 1.5},
    {...counts, gsc_path_daily: '2'}, {gsc_path_daily: 0, gsc_query_page_daily: 0}, null,
  ]) await reject(complete(a, invalid), '22023');
  assert.equal((await db.query('SELECT status FROM gsc_ingest_batches WHERE run_id=$1', [a])).rows[0].status,
    'running', 'a missing or invalid grain never publishes the batch');
  await fail(a);
  await fail(a);
  await begin(b);
  await reject(complete(a, counts), '22023');
  // Google may reveal no query even while page totals exist. Both grains have
  // completed successfully; a zero counter is distinct from a missing key.
  const completeWithoutQueries = {gsc_path_daily: 2, gsc_query_page_daily: 0};
  await complete(b, completeWithoutQueries);
  await complete(b, completeWithoutQueries);
  await reject(complete(b, counts), '22023');
  await reject(fail(b), '22023');
  assert.equal((await db.query('SELECT status FROM gsc_ingest_batches WHERE run_id=$1', [b])).rows[0].status, 'completed');
  console.log('GSC two grains: complete/partial/empty manifests, concurrency, retries and historical manifests verified.');
} finally {
  await db.close();
}
