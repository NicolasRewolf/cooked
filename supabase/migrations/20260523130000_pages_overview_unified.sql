-- Sprint 33+ (23/05/2026) — pages_overview_unified(max_rows)
--
-- Différence avec gsc_pages_overview :
--   gsc_pages_overview        ordonne par clicks GSC (vue SEO performance,
--                             rate les pages dont le trafic vient
--                             d'AdWords / nav interne).
--   pages_overview_unified    ordonne par sessions Cooked (vue business
--                             exhaustive). Inclut TOUTES les pages avec
--                             du trafic Cooked, même celles à 0 clic SEO.
--
-- Source : seo_url_snapshot (snapshot quotidien, denormalisé). LEFT JOIN
-- vers gsc_path_daily 28j pour récupérer clicks / impressions / position.
-- Filtre : sessions_28d > 0 (on ne retourne pas les pages mortes).

CREATE OR REPLACE FUNCTION public.pages_overview_unified(
  max_rows integer DEFAULT 100
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
    s.path,
    COALESCE(g.clicks_total, 0)              AS gsc_clicks_28d,
    COALESCE(g.impressions_total, 0)         AS gsc_impressions_28d,
    g.position_avg                            AS gsc_position_avg_28d,
    g.ctr_pct                                 AS gsc_ctr_pct_28d,
    COALESCE(s.sessions_28d, 0)              AS cooked_sessions_28d,
    s.avg_dwell_seconds_28d                   AS cooked_dwell_avg_s_28d,
    s.bounce_rate_28d                         AS cooked_bounce_rate_28d,
    (COALESCE(s.phone_clicks_28d, 0)
      + COALESCE(s.booking_cta_clicks_28d, 0))::bigint AS cooked_conversions_28d,
    s.pogo_rate_28d                           AS cooked_pogo_rate_28d,
    TRUE                                      AS has_cooked_data
  FROM seo_url_snapshot s
    LEFT JOIN g ON g.path = s.path
  WHERE COALESCE(s.sessions_28d, 0) > 0
  ORDER BY s.sessions_28d DESC NULLS LAST,
           COALESCE(g.clicks_total, 0) DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.pages_overview_unified(integer) IS
  'Sprint 33+ : pages 28j ordonnées par sessions Cooked (vue business — inclut pages AdWords, nav interne, etc.). Voir gsc_pages_overview pour la vue SEO pure.';

REVOKE EXECUTE ON FUNCTION public.pages_overview_unified(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_overview_unified(integer) TO service_role;
