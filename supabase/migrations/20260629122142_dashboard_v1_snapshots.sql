-- Dashboard V1 — bascule en snapshots précalculés (agrégations events trop lourdes en live ;
-- pattern seo_url_snapshot / cpi_daily). SEO par requête reste live. Fenêtres : rolling_28 + rolling_90.
-- NB : la fonction refresh_dashboard_snapshots est FINALISÉE dans la migration suivante
-- (20260629124448_dashboard_v1_perf_per_window_refresh) — version par fenêtre + table temporaire.

CREATE TABLE IF NOT EXISTS public.dashboard_resources_snapshot (
  window_kind text NOT NULL,
  path text NOT NULL,
  theme text,
  unique_visitors bigint, pageviews bigint,
  dwell_median_s numeric, scroll_median numeric,
  gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric,
  best_query text, best_query_clicks bigint, best_query_volume_fr int, best_query_cpc numeric,
  contacts bigint, booking_intent bigint,
  first_impression_day date, first_tracker_day date, days_live int, confidence text,
  cooked_start date, cooked_end date, gsc_start date, gsc_end date,
  refreshed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (window_kind, path)
);

CREATE TABLE IF NOT EXISTS public.dashboard_kpis_snapshot (
  window_kind text PRIMARY KEY,
  label_fr text, cooked_start date, cooked_end date, gsc_start date, gsc_end date,
  gsc_last_day date, lag_days int, is_partial boolean,
  visitors_n bigint, visitors_prev bigint, pageviews_n bigint, pageviews_prev bigint,
  contacts_n bigint, contacts_prev bigint,
  gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_impressions_n bigint, gsc_impressions_prev bigint,
  refreshed_at timestamptz NOT NULL DEFAULT now()
);

-- (Version initiale du refresh — remplacée par la migration de perf suivante.)
CREATE OR REPLACE FUNCTION public.refresh_dashboard_snapshots()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  -- placeholder remplacé par refresh_dashboard_snapshots(text) dans 20260629124448.
  RAISE NOTICE 'superseded by refresh_dashboard_snapshots(text)';
END $fn$;

-- RPC overview : lit le snapshot (instantané).
DROP FUNCTION IF EXISTS public.dashboard_resources_overview(text,int);
DROP FUNCTION IF EXISTS public.dashboard_resources_kpis(text);

CREATE FUNCTION public.dashboard_resources_overview(period_kind text DEFAULT 'rolling_90', max_rows int DEFAULT 100)
RETURNS SETOF public.dashboard_resources_snapshot
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.dashboard_resources_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END
  ORDER BY unique_visitors DESC NULLS LAST
  LIMIT max_rows;
$$;

CREATE FUNCTION public.dashboard_resources_kpis(period_kind text DEFAULT 'rolling_90')
RETURNS SETOF public.dashboard_kpis_snapshot
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.dashboard_kpis_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$$;

REVOKE ALL ON public.dashboard_resources_snapshot FROM public, anon, authenticated;
REVOKE ALL ON public.dashboard_kpis_snapshot FROM public, anon, authenticated;
GRANT SELECT ON public.dashboard_resources_snapshot TO service_role;
GRANT SELECT ON public.dashboard_kpis_snapshot TO service_role;
REVOKE ALL ON FUNCTION public.dashboard_resources_overview(text,int) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.dashboard_resources_kpis(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_resources_overview(text,int) TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_resources_kpis(text) TO service_role;

-- Cron quotidien (08:00 UTC, après l'ingest GSC).
SELECT cron.schedule('refresh-dashboard-snapshots', '0 8 * * *', $$SELECT public.refresh_dashboard_snapshots();$$);
