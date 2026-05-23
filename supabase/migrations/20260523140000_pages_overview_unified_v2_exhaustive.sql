-- Sprint 33+ (23/05/2026) — pages_overview_unified v2 (univers exhaustif)
--
-- Évolution de la première version (20260523130000) :
--   v1 : SOURCE = seo_url_snapshot, WHERE sessions_28d > 0.
--        → Ratait les pages SEO sans visite Cooked, et les pages
--          jamais indexées par Google.
--   v2 : SOURCE = UNION (snapshot Cooked 365j) ∪ (GSC 90j).
--        → Inclut les pages avec 0 signal Cooked OU 0 signal GSC.
--          Permet de voir explicitement les pages qui ne marchent pas.
--
-- Volume résultant attendu : ~490-500 paths (vs ~380 v1). Cohérent avec
-- l'ordre de grandeur "440 pages" du site jplouton-avocat.fr selon Nicolas.
-- Pour les pages mortes sur cette fenêtre, tous les chiffres sont à 0
-- ou null. has_cooked_data = false si la page n'est pas dans le snapshot.

CREATE OR REPLACE FUNCTION public.pages_overview_unified(max_rows integer DEFAULT 1000)
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
  WITH all_paths AS (
    SELECT path FROM seo_url_snapshot
    UNION
    SELECT DISTINCT path FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '90 days'
  ),
  g28 AS (
    SELECT path,
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
    ap.path,
    COALESCE(g28.clicks_total, 0)              AS gsc_clicks_28d,
    COALESCE(g28.impressions_total, 0)         AS gsc_impressions_28d,
    g28.position_avg                            AS gsc_position_avg_28d,
    g28.ctr_pct                                 AS gsc_ctr_pct_28d,
    COALESCE(s.sessions_28d, 0)                AS cooked_sessions_28d,
    s.avg_dwell_seconds_28d                     AS cooked_dwell_avg_s_28d,
    s.bounce_rate_28d                           AS cooked_bounce_rate_28d,
    (COALESCE(s.phone_clicks_28d, 0)
      + COALESCE(s.booking_cta_clicks_28d, 0))::bigint AS cooked_conversions_28d,
    s.pogo_rate_28d                             AS cooked_pogo_rate_28d,
    (s.path IS NOT NULL)                        AS has_cooked_data
  FROM all_paths ap
    LEFT JOIN seo_url_snapshot s ON s.path = ap.path
    LEFT JOIN g28 ON g28.path = ap.path
  ORDER BY
    COALESCE(s.sessions_28d, 0) DESC,
    COALESCE(g28.clicks_total, 0) DESC,
    ap.path
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.pages_overview_unified(integer) IS
  'Sprint 33+ v2 : univers exhaustif (snapshot Cooked 365j ∪ GSC 90j). Inclut les pages mortes (0 signal Cooked ou 0 signal GSC).';

REVOKE EXECUTE ON FUNCTION public.pages_overview_unified(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_overview_unified(integer) TO service_role;
