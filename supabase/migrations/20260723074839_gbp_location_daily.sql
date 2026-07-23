-- GBP (Google Business Profile) Performance → Cooked
-- 23/07/2026 — ferme l'angle mort GMB (appels / clics fiche).
--
-- Source : Business Profile Performance API (quotidiens).
-- Ingest : scripts/gbp_ingest.py (OAuth, cron GitHub Actions).
-- Une ligne = un jour × une fiche (location). Mono-site cabinet Plouton.

CREATE TABLE IF NOT EXISTS public.gbp_location_daily (
  day                          date NOT NULL,
  location_id                  text NOT NULL,
  location_title               text,
  call_clicks                  integer NOT NULL DEFAULT 0 CHECK (call_clicks >= 0),
  website_clicks               integer NOT NULL DEFAULT 0 CHECK (website_clicks >= 0),
  direction_requests           integer NOT NULL DEFAULT 0 CHECK (direction_requests >= 0),
  conversations                integer NOT NULL DEFAULT 0 CHECK (conversations >= 0),
  impressions_desktop_maps     integer NOT NULL DEFAULT 0 CHECK (impressions_desktop_maps >= 0),
  impressions_desktop_search   integer NOT NULL DEFAULT 0 CHECK (impressions_desktop_search >= 0),
  impressions_mobile_maps      integer NOT NULL DEFAULT 0 CHECK (impressions_mobile_maps >= 0),
  impressions_mobile_search    integer NOT NULL DEFAULT 0 CHECK (impressions_mobile_search >= 0),
  ingested_at                  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (day, location_id)
);

CREATE INDEX IF NOT EXISTS gbp_location_daily_day_idx
  ON public.gbp_location_daily (day DESC);
CREATE INDEX IF NOT EXISTS gbp_location_daily_location_idx
  ON public.gbp_location_daily (location_id);

ALTER TABLE public.gbp_location_daily ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gbp_location_daily FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gbp_location_daily TO service_role;

COMMENT ON TABLE public.gbp_location_daily IS
  'Métriques quotidiennes Google Business Profile (Performance API). Upsert idempotent (day, location_id).';

-- Dernier jour de données GBP (lag Google typique J-2/J-3).
CREATE OR REPLACE FUNCTION public.gbp_last_data_day()
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT max(day) FROM public.gbp_location_daily;
$function$;

COMMENT ON FUNCTION public.gbp_last_data_day() IS
  'Dernier jour présent dans gbp_location_daily (NULL si jamais ingéré).';

REVOKE EXECUTE ON FUNCTION public.gbp_last_data_day() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gbp_last_data_day() TO service_role;

-- KPIs fiche GMB : période N vs N-1 (mêmes period_kind que GSC).
CREATE OR REPLACE FUNCTION public.site_gbp_kpis_compare(p_period_kind text DEFAULT '28d'::text)
RETURNS TABLE(
  period_kind text,
  period_label_fr text,
  period_n_start date,
  period_n_end date,
  gbp_last_day date,
  lag_days integer,
  period_prev_start date,
  period_prev_end date,
  call_clicks_n bigint,
  website_clicks_n bigint,
  direction_requests_n bigint,
  conversations_n bigint,
  impressions_n bigint,
  call_clicks_prev bigint,
  website_clicks_prev bigint,
  direction_requests_prev bigint,
  conversations_prev bigint,
  impressions_prev bigint,
  call_clicks_delta_pct numeric,
  website_clicks_delta_pct numeric,
  impressions_delta_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_end   date;
  v_start date;
  v_prev_end date;
  v_prev_start date;
  v_days  int;
  v_label text;
  v_lag   int;
BEGIN
  v_end := public.gbp_last_data_day();
  IF v_end IS NULL THEN
    RETURN;
  END IF;

  v_lag := ((now() AT TIME ZONE 'Europe/Paris')::date - v_end);

  CASE lower(coalesce(p_period_kind, '28d'))
    WHEN '7d' THEN
      v_days := 7; v_label := '7 jours';
    WHEN '90d' THEN
      v_days := 90; v_label := '90 jours';
    ELSE
      v_days := 28; v_label := '28 jours';
  END CASE;

  v_start := v_end - (v_days - 1);
  v_prev_end := v_start - 1;
  v_prev_start := v_prev_end - (v_days - 1);

  RETURN QUERY
  WITH agg AS (
    SELECT
      sum(g.call_clicks) FILTER (
        WHERE g.day BETWEEN v_start AND v_end
      )::bigint AS call_n,
      sum(g.website_clicks) FILTER (
        WHERE g.day BETWEEN v_start AND v_end
      )::bigint AS web_n,
      sum(g.direction_requests) FILTER (
        WHERE g.day BETWEEN v_start AND v_end
      )::bigint AS dir_n,
      sum(g.conversations) FILTER (
        WHERE g.day BETWEEN v_start AND v_end
      )::bigint AS conv_n,
      sum(
        g.impressions_desktop_maps + g.impressions_desktop_search
        + g.impressions_mobile_maps + g.impressions_mobile_search
      ) FILTER (WHERE g.day BETWEEN v_start AND v_end)::bigint AS impr_n,
      sum(g.call_clicks) FILTER (
        WHERE g.day BETWEEN v_prev_start AND v_prev_end
      )::bigint AS call_p,
      sum(g.website_clicks) FILTER (
        WHERE g.day BETWEEN v_prev_start AND v_prev_end
      )::bigint AS web_p,
      sum(g.direction_requests) FILTER (
        WHERE g.day BETWEEN v_prev_start AND v_prev_end
      )::bigint AS dir_p,
      sum(g.conversations) FILTER (
        WHERE g.day BETWEEN v_prev_start AND v_prev_end
      )::bigint AS conv_p,
      sum(
        g.impressions_desktop_maps + g.impressions_desktop_search
        + g.impressions_mobile_maps + g.impressions_mobile_search
      ) FILTER (WHERE g.day BETWEEN v_prev_start AND v_prev_end)::bigint AS impr_p
    FROM public.gbp_location_daily g
  )
  SELECT
    lower(coalesce(p_period_kind, '28d'))::text,
    v_label,
    v_start,
    v_end,
    v_end,
    v_lag,
    v_prev_start,
    v_prev_end,
    coalesce(a.call_n, 0),
    coalesce(a.web_n, 0),
    coalesce(a.dir_n, 0),
    coalesce(a.conv_n, 0),
    coalesce(a.impr_n, 0),
    coalesce(a.call_p, 0),
    coalesce(a.web_p, 0),
    coalesce(a.dir_p, 0),
    coalesce(a.conv_p, 0),
    coalesce(a.impr_p, 0),
    CASE WHEN coalesce(a.call_p, 0) = 0 THEN NULL
         ELSE round(100.0 * (a.call_n - a.call_p) / a.call_p, 1) END,
    CASE WHEN coalesce(a.web_p, 0) = 0 THEN NULL
         ELSE round(100.0 * (a.web_n - a.web_p) / a.web_p, 1) END,
    CASE WHEN coalesce(a.impr_p, 0) = 0 THEN NULL
         ELSE round(100.0 * (a.impr_n - a.impr_p) / a.impr_p, 1) END
  FROM agg a;
END;
$function$;

COMMENT ON FUNCTION public.site_gbp_kpis_compare(text) IS
  'KPIs fiche Google Business Profile (appels, clics site, itinéraires, impressions) N vs N-1.';

REVOKE EXECUTE ON FUNCTION public.site_gbp_kpis_compare(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_gbp_kpis_compare(text) TO service_role;

-- Alerte retard GBP (seulement si des données existent déjà — inertes avant 1er ingest).
CREATE OR REPLACE FUNCTION public.alert_rule_gbp_lag()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_lag int; v_last date;
BEGIN
  v_last := public.gbp_last_data_day();
  IF v_last IS NULL THEN
    RETURN; -- pas encore branché : pas d'alerte
  END IF;
  v_lag := ((now() AT TIME ZONE 'Europe/Paris')::date - v_last);
  IF v_lag > 4 THEN
    RETURN QUERY SELECT
      'gbp_lag'::text,
      'warn'::text,
      format(
        'Dernière donnée GBP : J-%s (%s) — ingestion en panne ?',
        v_lag,
        to_char(v_last, 'DD/MM/YYYY')
      );
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.alert_rule_gbp_lag() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.alert_rule_gbp_lag() TO service_role;

-- Trou de jour GBP au milieu de l'historique (90 j couverts).
CREATE OR REPLACE FUNCTION public.alert_rule_gbp_gap()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n bigint; v_detail text; v_last date;
BEGIN
  v_last := public.gbp_last_data_day();
  IF v_last IS NULL THEN
    RETURN;
  END IF;
  BEGIN
    SELECT count(*), string_agg(to_char(d, 'DD/MM/YYYY'), ', ' ORDER BY d)
      INTO v_n, v_detail
    FROM (
      SELECT generate_series(v_last - 90, v_last, interval '1 day')::date AS d
      EXCEPT
      SELECT DISTINCT day FROM public.gbp_location_daily
      WHERE day >= v_last - 90
    ) miss;
    IF v_n >= 1 THEN
      RETURN QUERY SELECT
        'gbp_gap'::text,
        'warn'::text,
        format(
          '%s jour(s) GBP manquant(s) sur 90j couverts : %s — backfill via scripts/gbp_ingest.py',
          v_n, v_detail
        );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT
      'gbp_gap_check_failed'::text,
      'critical'::text,
      SQLERRM;
  END;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.alert_rule_gbp_gap() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.alert_rule_gbp_gap() TO service_role;

-- Branche les nouvelles règles dans le driver mince (C2).
CREATE OR REPLACE FUNCTION public.cooked_alerts_refresh()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  r record;
  v_added int := 0;
BEGIN
  FOR r IN
    SELECT * FROM public.alert_rule_pipeline_dead()
    UNION ALL SELECT * FROM public.alert_rule_double_embed_suspect()
    UNION ALL SELECT * FROM public.alert_rule_rpc_health()
    UNION ALL SELECT * FROM public.alert_rule_form_attribution_degraded()
    UNION ALL SELECT * FROM public.alert_rule_gsc_lag()
    UNION ALL SELECT * FROM public.alert_rule_gsc_gap()
    UNION ALL SELECT * FROM public.alert_rule_cpi_drop()
    UNION ALL SELECT * FROM public.alert_rule_dfs_stale()
    UNION ALL SELECT * FROM public.alert_rule_tracker_drift()
    UNION ALL SELECT * FROM public.alert_rule_gbp_lag()
    UNION ALL SELECT * FROM public.alert_rule_gbp_gap()
  LOOP
    v_added := v_added + public.raise_cooked_alert(r.kind, r.severity, r.detail);
  END LOOP;
  RETURN v_added;
END;
$function$;

-- Soft-check GBP dans pipeline_health (même signature ; issues[] seulement
-- si des données existent déjà — inertes avant le 1er ingest).
CREATE OR REPLACE FUNCTION public.refresh_pipeline_health()
RETURNS TABLE(
  status text,
  snapshot_refreshed_at timestamp with time zone,
  snapshot_age_hours numeric,
  cron_last_status text,
  cron_last_run timestamp with time zone,
  cron_age_hours numeric,
  last_event_at timestamp with time zone,
  last_event_age_minutes numeric,
  events_last_60min bigint,
  gsc_last_day date,
  gsc_data_age_days numeric,
  gsc_last_ingest timestamp with time zone,
  gsc_ingest_age_hours numeric,
  dfs_last_synced_at timestamp with time zone,
  dfs_row_count bigint,
  dfs_sync_age_hours numeric,
  issues text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'cron', 'pg_catalog'
AS $function$
DECLARE
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
  v_gbp_last_day           date;
  v_gbp_data_age_days      numeric;
  v_gbp_last_ingest        timestamptz;
  v_gbp_ingest_age_hours   numeric;
  v_issues                 text[] := array[]::text[];
  v_status                 text   := 'healthy';
BEGIN
  -- 1. Snapshot freshness
  SELECT max(refreshed_at) INTO v_snapshot_refreshed_at FROM public.seo_url_snapshot;
  v_snapshot_age_hours := extract(epoch FROM (now() - v_snapshot_refreshed_at)) / 3600;

  IF v_snapshot_refreshed_at IS NULL THEN
    v_issues := v_issues || 'snapshot_never_refreshed'::text;
    v_status := 'critical';
  ELSIF v_snapshot_age_hours > 36 THEN
    v_issues := v_issues || ('snapshot_stale: '||round(v_snapshot_age_hours,1)||'h old');
    v_status := 'critical';
  ELSIF v_snapshot_age_hours > 25 THEN
    v_issues := v_issues || ('snapshot_aging: '||round(v_snapshot_age_hours,1)||'h old');
    IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
  END IF;

  -- 2. Cron last run status (refresh_seo_url_snapshot)
  SELECT d.status, d.start_time INTO v_cron_last_status, v_cron_last_run
  FROM cron.job j JOIN cron.job_run_details d ON d.jobid = j.jobid
  WHERE j.jobname = 'refresh_seo_url_snapshot'
  ORDER BY d.start_time DESC LIMIT 1;

  v_cron_age_hours := extract(epoch FROM (now() - v_cron_last_run)) / 3600;

  IF v_cron_last_run IS NULL THEN
    v_issues := v_issues || 'cron_no_run_history'::text;
    v_status := 'critical';
  ELSIF v_cron_last_status IS DISTINCT FROM 'succeeded' THEN
    v_issues := v_issues || ('cron_last_failed: status='||coalesce(v_cron_last_status,'NULL'));
    v_status := 'critical';
  ELSIF v_cron_age_hours > 25 THEN
    v_issues := v_issues || ('cron_overdue: '||round(v_cron_age_hours,1)||'h since last run');
    v_status := 'critical';
  END IF;

  -- 3. Ingestion freshness (events table)
  SELECT max(occurred_at) INTO v_last_event_at FROM public.events;
  v_last_event_age_minutes := extract(epoch FROM (now() - v_last_event_at)) / 60;
  SELECT count(*) INTO v_events_last_60min FROM public.events
  WHERE occurred_at >= now() - interval '60 minutes';

  IF v_last_event_at IS NULL THEN
    v_issues := v_issues || 'no_events_ever'::text;
    v_status := 'critical';
  ELSIF v_last_event_age_minutes > 360 THEN
    v_issues := v_issues || ('ingestion_stopped: '||round(v_last_event_age_minutes)||'min since last event');
    v_status := 'critical';
  ELSIF v_last_event_age_minutes > 60 THEN
    v_issues := v_issues || ('ingestion_quiet: '||round(v_last_event_age_minutes)||'min since last event');
    IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
  END IF;

  -- 4. GSC freshness
  SELECT max(day) INTO v_gsc_last_day FROM public.gsc_path_daily;
  SELECT max(ingested_at) INTO v_gsc_last_ingest FROM public.gsc_path_daily;
  v_gsc_data_age_days    := (((now() AT TIME ZONE 'Europe/Paris')::date - v_gsc_last_day))::numeric;
  v_gsc_ingest_age_hours := extract(epoch FROM (now() - v_gsc_last_ingest)) / 3600;

  IF v_gsc_last_day IS NULL THEN
    v_issues := v_issues || 'gsc_no_data'::text;
    v_status := 'critical';
  ELSIF v_gsc_data_age_days > 7 THEN
    v_issues := v_issues || ('gsc_data_stale: '||round(v_gsc_data_age_days)||' days behind');
    v_status := 'critical';
  ELSIF v_gsc_data_age_days > 4 THEN
    v_issues := v_issues || ('gsc_data_aging: '||round(v_gsc_data_age_days)||' days behind');
    IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
  END IF;

  IF v_gsc_last_ingest IS NOT NULL THEN
    IF v_gsc_ingest_age_hours > 72 THEN
      v_issues := v_issues || ('gsc_ingest_stale: '||round(v_gsc_ingest_age_hours,1)||'h since last ingest');
      v_status := 'critical';
    ELSIF v_gsc_ingest_age_hours > 30 THEN
      v_issues := v_issues || ('gsc_ingest_aging: '||round(v_gsc_ingest_age_hours,1)||'h since last ingest');
      IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
    END IF;
  END IF;

  -- 5. DataForSEO keyword volume sync (hebdo)
  SELECT max(last_synced_at), count(*)::bigint INTO v_dfs_last_synced_at, v_dfs_row_count
  FROM public.dfs_keyword_volume;

  IF v_dfs_last_synced_at IS NOT NULL THEN
    v_dfs_sync_age_hours := extract(epoch FROM (now() - v_dfs_last_synced_at)) / 3600;
  END IF;

  IF v_dfs_row_count IS NULL OR v_dfs_row_count = 0 THEN
    v_issues := v_issues || 'dfs_no_data'::text;
    v_status := 'critical';
  ELSIF v_dfs_row_count < 200 THEN
    v_issues := v_issues || ('dfs_partial_sync: '||v_dfs_row_count||' rows (expected ~300-500)');
    IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
  END IF;

  IF v_dfs_last_synced_at IS NULL THEN
    NULL;
  ELSIF v_dfs_sync_age_hours > 240 THEN
    v_issues := v_issues || ('dfs_sync_stale: '||round(v_dfs_sync_age_hours,1)||'h since last sync');
    v_status := 'critical';
  ELSIF v_dfs_sync_age_hours > 192 THEN
    v_issues := v_issues || ('dfs_sync_aging: '||round(v_dfs_sync_age_hours,1)||'h since last sync');
    IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
  END IF;

  -- 6. GBP (optionnel) — uniquement si déjà ingéré une fois
  SELECT max(day), max(ingested_at)
    INTO v_gbp_last_day, v_gbp_last_ingest
  FROM public.gbp_location_daily;

  IF v_gbp_last_day IS NOT NULL THEN
    v_gbp_data_age_days := (((now() AT TIME ZONE 'Europe/Paris')::date - v_gbp_last_day))::numeric;
    v_gbp_ingest_age_hours := extract(epoch FROM (now() - v_gbp_last_ingest)) / 3600;

    IF v_gbp_data_age_days > 7 THEN
      v_issues := v_issues || ('gbp_data_stale: '||round(v_gbp_data_age_days)||' days behind');
      v_status := 'critical';
    ELSIF v_gbp_data_age_days > 4 THEN
      v_issues := v_issues || ('gbp_data_aging: '||round(v_gbp_data_age_days)||' days behind');
      IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
    END IF;

    IF v_gbp_ingest_age_hours > 72 THEN
      v_issues := v_issues || ('gbp_ingest_stale: '||round(v_gbp_ingest_age_hours,1)||'h since last ingest');
      v_status := 'critical';
    ELSIF v_gbp_ingest_age_hours > 30 THEN
      v_issues := v_issues || ('gbp_ingest_aging: '||round(v_gbp_ingest_age_hours,1)||'h since last ingest');
      IF v_status = 'healthy' THEN v_status := 'degraded'; END IF;
    END IF;
  END IF;

  RETURN QUERY SELECT
    v_status, v_snapshot_refreshed_at, round(v_snapshot_age_hours, 2),
    v_cron_last_status, v_cron_last_run, round(v_cron_age_hours, 2),
    v_last_event_at, round(v_last_event_age_minutes, 1), v_events_last_60min,
    v_gsc_last_day, round(v_gsc_data_age_days, 2), v_gsc_last_ingest, round(v_gsc_ingest_age_hours, 2),
    v_dfs_last_synced_at, v_dfs_row_count, round(v_dfs_sync_age_hours, 2),
    v_issues;
END;
$function$;

COMMENT ON FUNCTION public.refresh_pipeline_health() IS
  'Self-diagnostic (snapshot, cron, events, GSC, DFS) + soft-check GBP si données présentes.';
