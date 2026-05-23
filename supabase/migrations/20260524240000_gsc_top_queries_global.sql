-- Sprint 33+ (24/05/2026) — gsc_top_queries_global
--
-- Vue "requêtes" du dashboard : top queries du site sur fenêtre N
-- avec attribution page (nombre de pages qui rankent + top page).
--
-- Source : gsc_query_page_daily (brique d'attribution Sprint 32,
-- ~1M rows). Permet de répondre à "quelle requête amène du monde,
-- vers quelle page, est-ce qu'elle convertit ?" — question Adrien
-- du panel multi-persona.
--
-- Note volume : GSC anonymise les requêtes peu fréquentes (~54 % du
-- volume impressions non attribuable). Les clics restent quasi-tous
-- attribuables (~100 %). Donc cette RPC reflète le top SEO réel.

CREATE OR REPLACE FUNCTION public.gsc_top_queries_global(
  days_back integer DEFAULT 28,
  max_rows  integer DEFAULT 100
)
RETURNS TABLE (
  query              text,
  clicks             bigint,
  impressions        bigint,
  position_avg       numeric,
  ctr_pct            numeric,
  nb_pages_targeted  integer,
  top_page           text,
  top_page_clicks    bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH window_data AS (
    SELECT query, path, clicks, impressions, position
    FROM public.gsc_query_page_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date
                 - (days_back * INTERVAL '1 day')
      AND day <= (now() AT TIME ZONE 'Europe/Paris')::date
  ),
  -- Agrégat par couple (query, path)
  query_path AS (
    SELECT query, path,
      SUM(clicks)::bigint      AS path_clicks,
      SUM(impressions)::bigint AS path_impressions
    FROM window_data
    GROUP BY query, path
  ),
  -- Totaux par query
  query_agg AS (
    SELECT
      query,
      SUM(clicks)::bigint      AS clicks_total,
      SUM(impressions)::bigint AS impressions_total,
      COUNT(DISTINCT path)::int AS nb_pages,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM window_data
    GROUP BY query
  ),
  -- Pour chaque query, la page qui capture le plus de clics
  top_per_query AS (
    SELECT DISTINCT ON (query)
      query,
      path        AS top_page,
      path_clicks AS top_clicks
    FROM query_path
    ORDER BY query, path_clicks DESC
  )
  SELECT
    a.query,
    a.clicks_total,
    a.impressions_total,
    a.position_avg,
    a.ctr_pct,
    a.nb_pages,
    tp.top_page,
    tp.top_clicks
  FROM query_agg a
    LEFT JOIN top_per_query tp ON tp.query = a.query
  ORDER BY a.clicks_total DESC, a.impressions_total DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_top_queries_global(integer, integer) IS
  'Sprint 33+ (24/05/2026) : top N requêtes du site sur N jours avec attribution page (nb_pages, top_page). Source : gsc_query_page_daily.';

REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_global(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_top_queries_global(integer, integer) TO service_role;
