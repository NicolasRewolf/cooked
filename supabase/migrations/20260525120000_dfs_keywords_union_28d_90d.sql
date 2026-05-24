-- Sprint 33+ (25/05/2026) — dfs_keywords_to_sync : union top 28j + 90j
--
-- Le dashboard /queries trie sur 28j GSC ; le sync ne couvrait que le top
-- 90j → ~60 % des lignes sans volume_fr. On sync l'union (dédupliquée),
-- ordonnée par GREATEST(clics_28j, clics_90j) pour prioriser l'utile partout.

CREATE OR REPLACE FUNCTION public.dfs_keywords_to_sync(limit_n integer DEFAULT 500)
RETURNS TABLE (keyword text, clicks_total bigint)
STABLE
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH bounds AS (
    SELECT
      (now() AT TIME ZONE 'Europe/Paris')::date AS today,
      (now() AT TIME ZONE 'Europe/Paris')::date - 27 AS start_28d,
      (now() AT TIME ZONE 'Europe/Paris')::date - 89 AS start_90d
  ),
  clicks_90 AS (
    SELECT q.query, SUM(q.clicks)::bigint AS clicks_90d
    FROM gsc_query_daily q, bounds b
    WHERE q.day >= b.start_90d
      AND q.day <= b.today
      AND q.query IS NOT NULL
      AND q.query != ''
    GROUP BY q.query
  ),
  clicks_28 AS (
    SELECT q.query, SUM(q.clicks)::bigint AS clicks_28d
    FROM gsc_query_daily q, bounds b
    WHERE q.day >= b.start_28d
      AND q.day <= b.today
      AND q.query IS NOT NULL
      AND q.query != ''
    GROUP BY q.query
  ),
  combined AS (
    SELECT
      COALESCE(a.query, c.query) AS query,
      COALESCE(a.clicks_90d, 0) AS clicks_90d,
      COALESCE(c.clicks_28d, 0) AS clicks_28d
    FROM clicks_90 a
    FULL OUTER JOIN clicks_28 c ON c.query = a.query
  )
  SELECT
    query AS keyword,
    GREATEST(clicks_90d, clicks_28d) AS clicks_total
  FROM combined
  ORDER BY GREATEST(clicks_90d, clicks_28d) DESC, clicks_90d DESC
  LIMIT limit_n;
$$;

COMMENT ON FUNCTION public.dfs_keywords_to_sync(integer) IS
  'Sprint 33+ v2 (25/05/2026) : top N keywords = union clics GSC 28j ∪ 90j (Paris), tri par max(28j,90j). Source dfs_sync.py.';

REVOKE EXECUTE ON FUNCTION public.dfs_keywords_to_sync(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dfs_keywords_to_sync(integer) TO service_role;
