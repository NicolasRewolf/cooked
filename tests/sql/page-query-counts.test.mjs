import assert from 'node:assert/strict';
import {createDatabase, applyMigration} from './helpers.mjs';

const db=await createDatabase();
try {
  await applyMigration(db,'_editorial_metrics_readers.sql');
  await db.exec(`CREATE OR REPLACE FUNCTION pg_catalog.now() RETURNS timestamptz LANGUAGE sql STABLE
    AS $$SELECT '2026-11-04T12:00:00Z'::timestamptz$$;`);
  const read=async(path='/post/été',days=30)=>(await db.query('SELECT page_query_counts($1,$2) AS result',[path,days])).rows[0].result;
  const empty=await read();
  assert.deepEqual(empty,{path:'/post/été',period_start:null,period_end:null,expected_days:30,observed_days:0,
    previous:{period_start:null,period_end:null,observed_days:0},queries:[]});

  // Global coverage comes from both grains, even when this page has no row.
  await db.exec(`INSERT INTO gsc_path_daily(day,path,impressions,clicks,position,ctr)
    SELECT day,'/global',100,10,4,0.1 FROM generate_series('2026-05-01'::date,'2026-11-01'::date,interval '1 day') day;
    INSERT INTO gsc_query_page_daily(day,path,query,impressions,clicks,position,ctr)
    SELECT day,'/global','global query',100,10,4,0.1 FROM generate_series('2026-05-01'::date,'2026-11-01'::date,interval '1 day') day;
    INSERT INTO gsc_path_daily(day,path,impressions,clicks,position,ctr) VALUES
      ('2026-11-02','/global',100,10,4,0.1),('2026-11-04','/global',100,10,4,0.1);
    INSERT INTO gsc_query_page_daily(day,path,query,impressions,clicks,position,ctr) VALUES
      ('2026-11-03','/global','global query',100,10,4,0.1),('2026-11-04','/global','global query',100,10,4,0.1);
    INSERT INTO gsc_ingest_batches(day_start,day_end,status,completed_at,row_counts) VALUES
      ('2026-05-01','2026-11-04','completed','2026-11-04T08:00:00Z','{"gsc_path_daily":200,"gsc_query_page_daily":200}');`);
  await db.exec(`INSERT INTO gsc_query_page_daily(day,path,query,impressions,clicks,position,ctr) VALUES
    ('2026-09-15','/post/été','perdue',100,12,5,0.12),
    ('2026-10-30','/post/été','nouvelle',100,10,3,0.1),
    ('2026-09-10','/post/été','mixte',50,2,20,0.04),
    ('2026-09-20','/post/été','mixte',150,3,10,0.02),
    ('2026-10-03','/post/été','mixte',100,4,2,0.04),
    ('2026-10-04','/post/été','mixte',300,8,10,0.026667),
    ('2026-10-05','/post/été','alpha',100,5,7,0.05),
    ('2026-10-05','/post/été','beta',100,5,7,0.05),
    ('2026-09-05','/post/été','plus de clics',100,5,9,0.05),
    ('2026-10-05','/post/été','plus de clics',100,10,6,0.1),
    ('2026-10-05','/post/été','sans impressions',0,0,7,0),
    ('2026-09-02','/post/été','avant fenêtre',100,20,7,0.2),
    ('2026-11-03','/post/été','grain incomplet',100,20,7,0.2),
    ('2026-11-04','/post/été','aujourd’hui',100,20,7,0.2);
    INSERT INTO gsc_query_page_daily(day,path,query,impressions,clicks,position,ctr)
    SELECT '2026-10-20','/post/été','petite requête '||n,10,0,42,0 FROM generate_series(1,25) n;`);
  const result=await read('/post/%C3%A9t%C3%A9/');
  assert.equal(result.path,'/post/été');
  assert.equal(result.period_start,'2026-10-03');
  assert.equal(result.period_end,'2026-11-01','last common real day, not the declared batch end');
  assert.deepEqual(result.previous,{period_start:'2026-09-03',period_end:'2026-10-02',observed_days:30});
  assert.equal(result.observed_days,30,'coverage is sitewide, not target-page days');
  assert.equal(result.queries.length,32,'all queries returned, with no current top-20 cutoff');
  assert.deepEqual(result.queries.slice(0,6),[
    {query:'perdue',clicks:0,previous_clicks:12,position_avg:null,previous_position_avg:5},
    {query:'nouvelle',clicks:10,previous_clicks:0,position_avg:3,previous_position_avg:null},
    {query:'mixte',clicks:12,previous_clicks:5,position_avg:8,previous_position_avg:12.5},
    {query:'plus de clics',clicks:10,previous_clicks:5,position_avg:6,previous_position_avg:9},
    {query:'alpha',clicks:5,previous_clicks:0,position_avg:7,previous_position_avg:null},
    {query:'beta',clicks:5,previous_clicks:0,position_avg:7,previous_position_avg:null},
  ]);
  assert.equal(result.queries.find(q=>q.query==='sans impressions').position_avg,null);
  for (const days of [30,60,90]) {
    const period=await read('/no-query',days);
    assert.equal(period.expected_days,days);
    assert.equal(period.observed_days,days);
    assert.equal(period.previous.observed_days,days);
    assert.deepEqual(period.queries,[],'a page without queries retains the real source coverage');
    assert.equal((Date.parse(period.period_end)-Date.parse(period.period_start))/86400000+1,days);
    assert.equal(Date.parse(period.previous.period_end)+86400000,Date.parse(period.period_start));
  }

  // A later failed/running overlapping import can have overwritten data.
  // It cannot be certified by the earlier completed batch.
  await db.exec(`INSERT INTO gsc_ingest_batches(day_start,day_end,status) VALUES('2026-10-03','2026-10-03','failed');`);
  const partial=await read();
  assert.equal(partial.period_end,'2026-11-01');
  assert.equal(partial.observed_days,29);
  assert.equal(partial.queries.find(q=>q.query==='mixte').clicks,8);
  assert.equal(partial.queries.find(q=>q.query==='mixte').position_avg,10);
  await db.exec(`INSERT INTO gsc_ingest_batches(day_start,day_end,status) VALUES('2026-10-31','2026-11-03','running');`);
  assert.equal((await read()).period_end,'2026-10-30');
  await db.exec(`INSERT INTO gsc_ingest_batches(day_start,day_end,status,completed_at,row_counts) VALUES
    ('2026-10-01','2026-11-03','completed','2026-11-04T09:00:00Z','{"gsc_path_daily":100,"gsc_query_page_daily":100,"legacy_source":1}');`);
  assert.deepEqual(await read(),result,'completed historical three-grain manifest remains valid for its two retained grains');

  for (const days of [null,0,29,31,91]) await assert.rejects(read('/post/été',days),e=>e.code==='22023');
  for (const path of [null,'','   ']) await assert.rejects(read(path),e=>e.code==='22023');
  await db.exec('SET ROLE service_role');
  assert.deepEqual(await read(),result);
  await db.exec('RESET ROLE');
  await db.exec('DELETE FROM gsc_ingest_batches');
  assert.deepEqual(await read(),result,'observed history before the batch registry remains available');
  // A present but unusable manifest is different from no historical manifest.
  for (const [status,completedAt,rowCounts] of [
    [null,null,{gsc_path_daily:100,gsc_query_page_daily:100}],
    ['completed','2026-11-04T09:00:00Z',null],
    ['completed','2026-11-04T09:00:00Z',{gsc_path_daily:100}],
    ['failed',null,{gsc_path_daily:100,gsc_query_page_daily:100}],
  ]) {
    await db.exec('DELETE FROM gsc_ingest_batches');
    await db.query(`INSERT INTO gsc_ingest_batches(day_start,day_end,status,completed_at,row_counts)
      VALUES('2026-10-31','2026-11-03',$1,$2,$3)`,[status,completedAt,rowCounts]);
    assert.equal((await read()).period_end,'2026-10-30','a present incomplete or unusable latest batch excludes its days');
  }
  await db.exec('DELETE FROM gsc_query_page_daily');
  assert.deepEqual(await read(),empty,'one observed grain alone does not establish common coverage');
  console.log('Page queries: shared observed coverage, pre-registry history, date bounds, lost queries, weighted positions, invalid/partial batches and service access verified.');
} finally {await db.close();}
