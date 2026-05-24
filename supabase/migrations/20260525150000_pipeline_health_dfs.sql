-- Sprint 33+ (25/05/2026) — refresh_pipeline_health : axe DataForSEO (5e)
--
-- Signaux :
--   dfs_last_synced_at  : max(last_synced_at) sur dfs_keyword_volume
--   dfs_row_count       : lignes syncées (attendu ~300-500 après run)
--   dfs_sync_age_hours  : heures depuis dernier sync
--
-- Seuils (cron hebdo lundi 07:00 UTC) :
--   sync_age_hours  <= 192 (8j) healthy, 192-240 degraded, > 240 critical
--   row_count       = 0 critical, < 200 degraded

DROP FUNCTION IF EXISTS public.refresh_pipeline_health();

CREATE OR REPLACE FUNCTION public.refresh_pipeline_health()
 RETURNS TABLE(
   status                  text,
   snapshot_refreshed_at   timestamp with time zone,
   snapshot_age_hours      numeric,
   cron_last_status        text,
   cron_last_run           timestamp with time zone,
   cron_age_hours          numeric,
   last_event_at           timestamp with time zone,
   last_event_age_minutes  numeric,
   events_last_60min       bigint,
   gsc_last_day            date,
   gsc_data_age_days       numeric,
   gsc_last_ingest         timestamp with time zone,
   gsc_ingest_age_hours    numeric,
   dfs_last_synced_at      timestamp with time zone,
   dfs_row_count           bigint,
   dfs_sync_age_hours      numeric,
   issues                  text[]
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cron', 'pg_catalog'
AS $function$
declare
  v_snapshot_refreshed_at  timestamptz;
  v_snapshot_age_hours     numeric;
  v_cron_last_status       text;
  v_cron_last_run          timestamptz;
  v_cron_age_hours         numeric;
  v_last_event_at          timestamptz;
  v_last_event_age_minutes numeric;
  v_events_last_60min      bigint;
  v_gsc_last_day           date;
  v_gsc_data_age_days      numeric;
  v_gsc_last_ingest        timestamptz;
  v_gsc_ingest_age_hours   numeric;
  v_dfs_last_synced_at     timestamptz;
  v_dfs_row_count          bigint;
  v_dfs_sync_age_hours     numeric;
  v_issues                 text[] := array[]::text[];
  v_status                 text   := 'healthy';
begin
  -- 1. Snapshot freshness
  select max(refreshed_at) into v_snapshot_refreshed_at
  from public.seo_url_snapshot;

  v_snapshot_age_hours := extract(epoch from (now() - v_snapshot_refreshed_at)) / 3600;

  if v_snapshot_refreshed_at is null then
    v_issues := v_issues || 'snapshot_never_refreshed';
    v_status := 'critical';
  elsif v_snapshot_age_hours > 36 then
    v_issues := v_issues || format('snapshot_stale: %.1fh old', v_snapshot_age_hours);
    v_status := 'critical';
  elsif v_snapshot_age_hours > 25 then
    v_issues := v_issues || format('snapshot_aging: %.1fh old', v_snapshot_age_hours);
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  -- 2. Cron last run status (refresh_seo_url_snapshot)
  select d.status, d.start_time
    into v_cron_last_status, v_cron_last_run
  from cron.job j
  join cron.job_run_details d on d.jobid = j.jobid
  where j.jobname = 'refresh_seo_url_snapshot'
  order by d.start_time desc
  limit 1;

  v_cron_age_hours := extract(epoch from (now() - v_cron_last_run)) / 3600;

  if v_cron_last_run is null then
    v_issues := v_issues || 'cron_no_run_history';
    v_status := 'critical';
  elsif v_cron_last_status is distinct from 'succeeded' then
    v_issues := v_issues || format('cron_last_failed: status=%s', coalesce(v_cron_last_status, 'NULL'));
    v_status := 'critical';
  elsif v_cron_age_hours > 25 then
    v_issues := v_issues || format('cron_overdue: %.1fh since last run', v_cron_age_hours);
    v_status := 'critical';
  end if;

  -- 3. Ingestion freshness (events table)
  select max(occurred_at) into v_last_event_at
  from public.events;

  v_last_event_age_minutes := extract(epoch from (now() - v_last_event_at)) / 60;

  select count(*) into v_events_last_60min
  from public.events
  where occurred_at >= now() - interval '60 minutes';

  if v_last_event_at is null then
    v_issues := v_issues || 'no_events_ever';
    v_status := 'critical';
  elsif v_last_event_age_minutes > 360 then
    v_issues := v_issues || format('ingestion_stopped: %.0fmin since last event', v_last_event_age_minutes);
    v_status := 'critical';
  elsif v_last_event_age_minutes > 60 then
    v_issues := v_issues || format('ingestion_quiet: %.0fmin since last event', v_last_event_age_minutes);
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  -- 4. GSC freshness
  select max(day) into v_gsc_last_day from public.gsc_path_daily;
  select max(ingested_at) into v_gsc_last_ingest from public.gsc_path_daily;

  v_gsc_data_age_days   := (((now() at time zone 'Europe/Paris')::date - v_gsc_last_day))::numeric;
  v_gsc_ingest_age_hours := extract(epoch from (now() - v_gsc_last_ingest)) / 3600;

  if v_gsc_last_day is null then
    v_issues := v_issues || 'gsc_no_data';
    v_status := 'critical';
  elsif v_gsc_data_age_days > 7 then
    v_issues := v_issues || format('gsc_data_stale: %.0f days behind', v_gsc_data_age_days);
    v_status := 'critical';
  elsif v_gsc_data_age_days > 4 then
    v_issues := v_issues || format('gsc_data_aging: %.0f days behind', v_gsc_data_age_days);
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  if v_gsc_last_ingest is not null then
    if v_gsc_ingest_age_hours > 72 then
      v_issues := v_issues || format('gsc_ingest_stale: %.1fh since last ingest', v_gsc_ingest_age_hours);
      v_status := 'critical';
    elsif v_gsc_ingest_age_hours > 30 then
      v_issues := v_issues || format('gsc_ingest_aging: %.1fh since last ingest', v_gsc_ingest_age_hours);
      if v_status = 'healthy' then v_status := 'degraded'; end if;
    end if;
  end if;

  -- 5. DataForSEO keyword volume sync (hebdo)
  select max(last_synced_at), count(*)::bigint
    into v_dfs_last_synced_at, v_dfs_row_count
  from public.dfs_keyword_volume;

  if v_dfs_last_synced_at is not null then
    v_dfs_sync_age_hours := extract(epoch from (now() - v_dfs_last_synced_at)) / 3600;
  end if;

  if v_dfs_row_count is null or v_dfs_row_count = 0 then
    v_issues := v_issues || 'dfs_no_data';
    v_status := 'critical';
  elsif v_dfs_row_count < 200 then
    v_issues := v_issues || format('dfs_partial_sync: %s rows (expected ~300-500)', v_dfs_row_count);
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  if v_dfs_last_synced_at is null then
  elsif v_dfs_sync_age_hours > 240 then
    v_issues := v_issues || format('dfs_sync_stale: %.1fh since last sync', v_dfs_sync_age_hours);
    v_status := 'critical';
  elsif v_dfs_sync_age_hours > 192 then
    v_issues := v_issues || format('dfs_sync_aging: %.1fh since last sync', v_dfs_sync_age_hours);
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  return query select
    v_status,
    v_snapshot_refreshed_at,
    round(v_snapshot_age_hours, 2),
    v_cron_last_status,
    v_cron_last_run,
    round(v_cron_age_hours, 2),
    v_last_event_at,
    round(v_last_event_age_minutes, 1),
    v_events_last_60min,
    v_gsc_last_day,
    round(v_gsc_data_age_days, 2),
    v_gsc_last_ingest,
    round(v_gsc_ingest_age_hours, 2),
    v_dfs_last_synced_at,
    v_dfs_row_count,
    round(v_dfs_sync_age_hours, 2),
    v_issues;
end;
$function$;

COMMENT ON FUNCTION public.refresh_pipeline_health() IS
  'Sprint 33+ v2 (25/05/2026) : 5 axes (snapshot, cron, events, GSC, DataForSEO).';

REVOKE EXECUTE ON FUNCTION public.refresh_pipeline_health() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.refresh_pipeline_health() TO service_role;
