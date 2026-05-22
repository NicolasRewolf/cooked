-- Sprint 33 (22/05/2026) — RPCs cross-source GSC × Cooked
--
-- Première brique de valeur cross-source : permet au dashboard (et aux
-- analyses ad-hoc) de répondre aux questions du type :
--   * "Cette page ranke bien sur Google, mais convertit-elle ?"
--   * "Quelles requêtes amènent sur cette page, et que font les visiteurs ?"
--   * "Top SEO + comportement : où agir en priorité ?"
--
-- Pré-requis : la fonction canonical_path(text) (migration GSC 22/05/2026)
-- et la table seo_url_snapshot rafraîchie quotidiennement.
--
-- Convention de nommage cohérente avec le reste du contrat RPC Cooked :
--   target_path text, days_back integer, max_rows integer
--   SECURITY DEFINER + search_path 'public' + REVOKE public/anon/authenticated
--   + GRANT service_role.
--
-- Fenêtres : la plupart des RPCs s'appuient sur la fenêtre 28d du
-- snapshot. gsc_top_queries_for_path accepte days_back paramétrable
-- (lit directement gsc_query_page_daily).

-- ============================================================
-- RPC 1 — gsc_page_performance(target_path)
-- Fiche complète d'une page sur 28j.
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_page_performance(
  target_path text
)
RETURNS TABLE (
  path                       text,
  gsc_clicks_28d             bigint,
  gsc_impressions_28d        bigint,
  gsc_position_avg_28d       numeric,
  gsc_ctr_pct_28d            numeric,
  cooked_sessions_28d        bigint,
  cooked_views_28d           bigint,
  cooked_unique_visitors_28d bigint,
  cooked_bounce_rate_28d     numeric,
  cooked_dwell_avg_s_28d     numeric,
  cooked_scroll_median_28d   numeric,
  cooked_phone_clicks_28d    bigint,
  cooked_booking_clicks_28d  bigint,
  cooked_pogo_rate_28d       numeric,
  cooked_google_sessions_28d bigint,
  lcp_p75_ms                 numeric,
  inp_p75_ms                 numeric,
  cls_p75                    numeric,
  top_referrer_28d           text,
  device_split_28d           jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH cp AS (SELECT canonical_path(target_path) AS p),
  g AS (
    SELECT
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint      AS clicks_total,
      -- position pondérée par impressions
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      -- CTR pondéré
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_path_daily, cp
    WHERE gsc_path_daily.path = cp.p
      AND day >= (now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days'
  ),
  s AS (
    SELECT *
    FROM seo_url_snapshot, cp
    WHERE seo_url_snapshot.path = cp.p
    LIMIT 1
  )
  SELECT
    cp.p,
    COALESCE(g.clicks_total, 0),
    COALESCE(g.impressions_total, 0),
    g.position_avg,
    g.ctr_pct,
    COALESCE(s.sessions_28d, 0),
    COALESCE(s.views_28d, 0),
    COALESCE(s.unique_visitors_28d, 0),
    s.bounce_rate_28d,
    s.avg_dwell_seconds_28d,
    s.scroll_median_28d,
    COALESCE(s.phone_clicks_28d, 0),
    COALESCE(s.booking_cta_clicks_28d, 0),
    s.pogo_rate_28d,
    COALESCE(s.google_sessions_28d, 0),
    s.lcp_p75_28d_ms,
    s.inp_p75_28d_ms,
    s.cls_p75_28d,
    s.top_referrer_28d,
    s.device_split_28d
  FROM cp
    LEFT JOIN g ON true
    LEFT JOIN s ON true;
$$;

COMMENT ON FUNCTION public.gsc_page_performance(text) IS
  'Sprint 33 : fiche cross-source d''une page sur 28j (GSC + Cooked + CWV).';

REVOKE EXECUTE ON FUNCTION public.gsc_page_performance(text) FROM public;
REVOKE EXECUTE ON FUNCTION public.gsc_page_performance(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.gsc_page_performance(text) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_page_performance(text) TO service_role;


-- ============================================================
-- RPC 2 — gsc_top_queries_for_path(target_path, days_back, max_rows)
-- Top requêtes Google qui amènent sur une page donnée.
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_top_queries_for_path(
  target_path text,
  days_back   integer DEFAULT 28,
  max_rows    integer DEFAULT 20
)
RETURNS TABLE (
  query           text,
  clicks          bigint,
  impressions     bigint,
  position_avg    numeric,
  ctr_pct         numeric,
  days_in_period  integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH cp AS (SELECT canonical_path(target_path) AS p)
  SELECT
    gqp.query,
    SUM(gqp.clicks)::bigint        AS clicks,
    SUM(gqp.impressions)::bigint   AS impressions,
    CASE WHEN SUM(gqp.impressions) > 0
         THEN ROUND((SUM(gqp.position * gqp.impressions) / SUM(gqp.impressions))::numeric, 2)
         ELSE NULL END             AS position_avg,
    CASE WHEN SUM(gqp.impressions) > 0
         THEN ROUND((100.0 * SUM(gqp.clicks) / SUM(gqp.impressions))::numeric, 2)
         ELSE NULL END             AS ctr_pct,
    COUNT(DISTINCT gqp.day)::integer AS days_in_period
  FROM gsc_query_page_daily gqp, cp
  WHERE gqp.path = cp.p
    AND gqp.day >= ((now() AT TIME ZONE 'Europe/Paris')::date - (days_back || ' days')::INTERVAL)::date
  GROUP BY gqp.query
  ORDER BY clicks DESC, impressions DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) IS
  'Sprint 33 : top requêtes GSC qui amènent sur une page (params : path, days_back, max_rows).';

REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) TO service_role;


-- ============================================================
-- RPC 3 — gsc_pages_overview(max_rows)
-- Tableau de bord top pages SEO + comportement (28j).
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_pages_overview(
  max_rows integer DEFAULT 30
)
RETURNS TABLE (
  path                       text,
  gsc_clicks_28d             bigint,
  gsc_impressions_28d        bigint,
  gsc_position_avg_28d       numeric,
  gsc_ctr_pct_28d            numeric,
  cooked_sessions_28d        bigint,
  cooked_dwell_avg_s_28d     numeric,
  cooked_bounce_rate_28d     numeric,
  cooked_conversions_28d     bigint,
  cooked_pogo_rate_28d       numeric,
  has_cooked_data            boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH g AS (
    SELECT
      path,
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint      AS clicks_total,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days'
    GROUP BY path
  )
  SELECT
    g.path,
    g.clicks_total,
    g.impressions_total,
    g.position_avg,
    g.ctr_pct,
    COALESCE(s.sessions_28d, 0)             AS cooked_sessions_28d,
    s.avg_dwell_seconds_28d                  AS cooked_dwell_avg_s_28d,
    s.bounce_rate_28d                        AS cooked_bounce_rate_28d,
    (COALESCE(s.phone_clicks_28d, 0)
      + COALESCE(s.booking_cta_clicks_28d, 0))::bigint AS cooked_conversions_28d,
    s.pogo_rate_28d                          AS cooked_pogo_rate_28d,
    (s.path IS NOT NULL)                     AS has_cooked_data
  FROM g
    LEFT JOIN seo_url_snapshot s ON s.path = g.path
  ORDER BY g.clicks_total DESC, g.impressions_total DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_pages_overview(integer) IS
  'Sprint 33 : top pages SEO 28j × comportement Cooked (params : max_rows).';

REVOKE EXECUTE ON FUNCTION public.gsc_pages_overview(integer) FROM public;
REVOKE EXECUTE ON FUNCTION public.gsc_pages_overview(integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.gsc_pages_overview(integer) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_pages_overview(integer) TO service_role;
