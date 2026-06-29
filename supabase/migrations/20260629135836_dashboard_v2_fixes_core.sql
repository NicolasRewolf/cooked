-- Auto-analyse : corrections cœur données.
-- B1 timeout refresh ; M4 partialité ; M11 grade/jour ; fv hors bots ; B2/B3 KPI SEO SQL ; M8 thème requête.
-- NB : refresh_dashboard_snapshots est re-finalisée dans 20260629142922 (no_prev_baseline sur prev_end).

ALTER FUNCTION public.refresh_dashboard_snapshots(text) SET statement_timeout = '600s';

ALTER TABLE public.dashboard_kpis_snapshot
  ADD COLUMN IF NOT EXISTS current_day_partial boolean,
  ADD COLUMN IF NOT EXISTS no_prev_baseline boolean;

-- (refresh v3 — version intermédiaire ; corps final dans la migration de fraîcheur suivante.)
-- M8 : thème de la page captatrice sur le SEO par requête.
DROP FUNCTION IF EXISTS public.dashboard_seo_by_query(text,text,int,int);
CREATE FUNCTION public.dashboard_seo_by_query(
  period_kind text DEFAULT 'rolling_90', scope text DEFAULT 'ressource', min_volume int DEFAULT 0, max_rows int DEFAULT 200)
RETURNS TABLE(
  query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric,
  nb_pages int, top_page text, top_page_clicks bigint, top_page_theme text,
  volume_fr int, cpc numeric, competition_level text,
  capture_pct numeric, is_quick_win boolean, gsc_start date, gsc_end date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
WITH gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
qp AS (
  SELECT d.query, d.path, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
    AND d.query NOT ILIKE '%plouton%'
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query, d.path),
agg AS (SELECT query, SUM(clicks) clicks, SUM(impr) impr, SUM(pos_w) pos_w, COUNT(*) nb_pages FROM qp GROUP BY query),
top AS (SELECT DISTINCT ON (query) query, path top_page, clicks top_clicks FROM qp ORDER BY query, clicks DESC, impr DESC)
SELECT a.query, a.clicks, a.impr,
  ROUND(a.pos_w/NULLIF(a.impr,0),1), ROUND(100.0*a.clicks/NULLIF(a.impr,0),2),
  a.nb_pages::int, t.top_page, t.top_clicks, pt.theme,
  dfs.search_volume, dfs.cpc, dfs.competition_level,
  CASE WHEN dfs.search_volume>0 THEN ROUND(100.0*a.clicks/(dfs.search_volume*(SELECT day_count FROM gb)/30.0),1) END,
  (ROUND(a.pos_w/NULLIF(a.impr,0),1) BETWEEN 5 AND 15 AND COALESCE(dfs.search_volume,0)>=100),
  (SELECT n_start FROM gb), (SELECT n_end FROM gb)
FROM agg a
LEFT JOIN top t ON t.query=a.query
LEFT JOIN page_taxonomy pt ON pt.path=t.top_page
LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=a.query AND dfs.location_code=2250
WHERE COALESCE(dfs.search_volume,0) >= min_volume
ORDER BY a.clicks DESC, a.impr DESC
LIMIT max_rows;
$$;

-- B2/B3 : KPI SEO calculés SQL (total quick wins indépendant du cap ; 2 niveaux de clics).
CREATE OR REPLACE FUNCTION public.dashboard_seo_kpis(period_kind text DEFAULT 'rolling_90', scope text DEFAULT 'ressource')
RETURNS TABLE(
  total_queries bigint, total_quick_wins bigint,
  clicks_named_nonbranded bigint, clicks_path_total bigint, impressions_path_total bigint,
  gsc_start date, gsc_end date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
WITH gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
qp AS (
  SELECT d.query, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
    AND d.query NOT ILIKE '%plouton%'
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query),
qk AS (
  SELECT q.query, q.clicks,
    (ROUND(q.pos_w/NULLIF(q.impr,0),1) BETWEEN 5 AND 15 AND COALESCE(dfs.search_volume,0)>=100) AS qw
  FROM qp q LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=q.query AND dfs.location_code=2250),
pth AS (SELECT COALESCE(SUM(m.clicks_total),0) ct, COALESCE(SUM(m.impressions_total),0) it
        FROM gsc_path_metrics((SELECT n_start FROM gb),(SELECT n_end FROM gb)) m JOIN res ON res.path=m.path)
SELECT (SELECT COUNT(*) FROM qk),
       (SELECT COUNT(*) FILTER (WHERE qw) FROM qk),
       (SELECT COALESCE(SUM(clicks),0) FROM qk),
       (SELECT ct FROM pth), (SELECT it FROM pth),
       (SELECT n_start FROM gb), (SELECT n_end FROM gb);
$$;

REVOKE ALL ON FUNCTION public.dashboard_seo_by_query(text,text,int,int) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.dashboard_seo_kpis(text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_seo_by_query(text,text,int,int) TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_seo_kpis(text,text) TO service_role;
