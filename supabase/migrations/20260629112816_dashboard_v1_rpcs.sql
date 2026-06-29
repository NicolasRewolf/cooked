-- Dashboard V1 (articles ressources) — couche données.
-- Source de vérité unique : ces objets figent les leçons de mesure (Baidu exclu, visiteurs uniques,
-- lecteurs réels, totaux GSC depuis gsc_path_daily, branded exclu, volume DFS comme référence).
-- Tous service_role only (REVOKE public/anon/authenticated + GRANT service_role).
-- Composent les helpers existants : cooked_period_bounds, gsc_path_metrics, macro_contacts_by_path,
-- page_taxonomy, dfs_keyword_volume, gsc_query_page_daily.

-- 1. Base propre : events_human moins le spam Baidu (anti-join ; usage ad-hoc / doc).
CREATE OR REPLACE VIEW public.events_human_clean AS
SELECT e.*
FROM public.events_human e
WHERE NOT EXISTS (
  SELECT 1 FROM public.events b
  WHERE b.anonymous_id = e.anonymous_id
    AND b.referrer_hostname IN ('m.baidu.com','baidu.com')
);
COMMENT ON VIEW public.events_human_clean IS
  'events_human moins les sessions référées Baidu (spam non attrapé par le filtre bot). Les RPC dashboard inlinent le même anti-join pour la stabilité du plan.';

-- 2. Overview des articles ressources (1 ligne / article).
CREATE OR REPLACE FUNCTION public.dashboard_resources_overview(
  period_kind text DEFAULT 'rolling_90',
  max_rows int DEFAULT 100
)
RETURNS TABLE(
  path text, theme text,
  unique_visitors bigint, pageviews bigint,
  dwell_median_s numeric, scroll_median numeric,
  gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric,
  best_query text, best_query_clicks bigint, best_query_volume_fr int, best_query_cpc numeric,
  contacts bigint, booking_intent bigint,
  first_impression_day date, first_tracker_day date, days_live int,
  confidence text,
  cooked_start date, cooked_end date, gsc_start date, gsc_end date
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
WITH lb AS (SELECT * FROM cooked_period_bounds(period_kind,'live')),
     gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path, pt.theme FROM page_taxonomy pt WHERE pt.category='ressource'),
baidu AS (SELECT DISTINCT anonymous_id FROM events
          WHERE referrer_hostname IN ('m.baidu.com','baidu.com') AND anonymous_id IS NOT NULL),
cooked AS (
  SELECT e.path,
    COUNT(DISTINCT e.anonymous_id) FILTER (WHERE e.name='pageview') AS unique_visitors,
    COUNT(*) FILTER (WHERE e.name='pageview') AS pageviews,
    -- lecture sur lecteurs réels : page_exit hors social (LinkedIn/Facebook) et hors Baidu
    ROUND(percentile_cont(0.5) WITHIN GROUP (
      ORDER BY (e.props->>'duration_seconds')::numeric)
      FILTER (WHERE e.name='page_exit'
              AND e.referrer_hostname NOT ILIKE '%linkedin%'
              AND e.referrer_hostname NOT ILIKE '%facebook%')) AS dwell_median_s,
    ROUND(percentile_cont(0.5) WITHIN GROUP (
      ORDER BY (e.props->>'max_scroll')::numeric)
      FILTER (WHERE e.name='page_exit'
              AND e.referrer_hostname NOT ILIKE '%linkedin%'
              AND e.referrer_hostname NOT ILIKE '%facebook%')) AS scroll_median
  FROM events_human e
  JOIN res ON res.path = e.path
  LEFT JOIN baidu b ON b.anonymous_id = e.anonymous_id
  WHERE b.anonymous_id IS NULL
    AND e.name IN ('pageview','page_exit')
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date BETWEEN (SELECT n_start FROM lb) AND (SELECT n_end FROM lb)
  GROUP BY e.path
),
gsc AS (
  SELECT m.path, m.clicks_total, m.impressions_total, m.position_avg, m.ctr_pct
  FROM gsc_path_metrics((SELECT n_start FROM gb),(SELECT n_end FROM gb)) m
  JOIN res ON res.path = m.path
),
bestq AS (
  SELECT DISTINCT ON (q.path) q.path, q.query, q.clicks
  FROM (
    SELECT qp.path, qp.query, SUM(qp.clicks) clicks, SUM(qp.impressions) impr
    FROM gsc_query_page_daily qp
    JOIN res ON res.path = qp.path
    WHERE qp.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
      AND qp.query NOT ILIKE '%plouton%'
    GROUP BY qp.path, qp.query
  ) q
  ORDER BY q.path, q.clicks DESC, q.impr DESC
),
contacts AS (
  SELECT mc.path, mc.contacts, mc.booking_intent
  FROM macro_contacts_by_path((SELECT n_start FROM lb),(SELECT n_end FROM lb)) mc
  JOIN res ON res.path = mc.path
),
firsts AS (
  SELECT res.path,
    (SELECT MIN(g.day) FROM gsc_path_daily g WHERE g.path=res.path AND g.impressions>0) AS first_impr,
    (SELECT MIN((ev.occurred_at AT TIME ZONE 'Europe/Paris')::date)
       FROM events_human ev WHERE ev.path=res.path AND ev.name='pageview') AS first_view
  FROM res
)
SELECT res.path, res.theme,
  COALESCE(c.unique_visitors,0), COALESCE(c.pageviews,0),
  c.dwell_median_s, c.scroll_median,
  COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
  bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
  COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
  f.first_impr, f.first_view,
  ((SELECT paris_today FROM lb) - LEAST(COALESCE(f.first_impr,f.first_view), COALESCE(f.first_view,f.first_impr)))::int,
  CASE WHEN COALESCE(c.unique_visitors,0) >= 50 THEN 'A'
       WHEN COALESCE(c.unique_visitors,0) >= 15 THEN 'B' ELSE 'C' END,
  (SELECT n_start FROM lb), (SELECT n_end FROM lb), (SELECT n_start FROM gb), (SELECT n_end FROM gb)
FROM res
LEFT JOIN cooked c ON c.path=res.path
LEFT JOIN gsc g ON g.path=res.path
LEFT JOIN bestq bq ON bq.path=res.path
LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword = bq.query AND dfs.location_code=2250
LEFT JOIN contacts ct ON ct.path=res.path
LEFT JOIN firsts f ON f.path=res.path
ORDER BY COALESCE(c.unique_visitors,0) DESC
LIMIT max_rows;
$$;

-- 3. KPI d'en-tête du lot ressources (N vs N-1).
CREATE OR REPLACE FUNCTION public.dashboard_resources_kpis(period_kind text DEFAULT 'rolling_90')
RETURNS TABLE(
  label_fr text, cooked_start date, cooked_end date, gsc_start date, gsc_end date,
  gsc_last_day date, lag_days int, is_partial boolean,
  visitors_n bigint, visitors_prev bigint,
  pageviews_n bigint, pageviews_prev bigint,
  contacts_n bigint, contacts_prev bigint,
  gsc_clicks_n bigint, gsc_clicks_prev bigint,
  gsc_impressions_n bigint, gsc_impressions_prev bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
WITH lb AS (SELECT * FROM cooked_period_bounds(period_kind,'live')),
     gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
baidu AS (SELECT DISTINCT anonymous_id FROM events
          WHERE referrer_hostname IN ('m.baidu.com','baidu.com') AND anonymous_id IS NOT NULL),
ev AS (
  SELECT e.anonymous_id, (e.occurred_at AT TIME ZONE 'Europe/Paris')::date AS d
  FROM events_human e
  JOIN res ON res.path = e.path
  LEFT JOIN baidu b ON b.anonymous_id = e.anonymous_id
  WHERE b.anonymous_id IS NULL AND e.name='pageview'
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date BETWEEN (SELECT prev_start FROM lb) AND (SELECT n_end FROM lb)
),
ck AS (
  SELECT
    COUNT(DISTINCT anonymous_id) FILTER (WHERE d BETWEEN (SELECT n_start FROM lb) AND (SELECT n_end FROM lb)) AS visitors_n,
    COUNT(DISTINCT anonymous_id) FILTER (WHERE d BETWEEN (SELECT prev_start FROM lb) AND (SELECT prev_end FROM lb)) AS visitors_prev,
    COUNT(*) FILTER (WHERE d BETWEEN (SELECT n_start FROM lb) AND (SELECT n_end FROM lb)) AS pageviews_n,
    COUNT(*) FILTER (WHERE d BETWEEN (SELECT prev_start FROM lb) AND (SELECT prev_end FROM lb)) AS pageviews_prev
  FROM ev
),
ct_n AS (SELECT COALESCE(SUM(mc.contacts),0) c FROM macro_contacts_by_path((SELECT n_start FROM lb),(SELECT n_end FROM lb)) mc JOIN res ON res.path=mc.path),
ct_p AS (SELECT COALESCE(SUM(mc.contacts),0) c FROM macro_contacts_by_path((SELECT prev_start FROM lb),(SELECT prev_end FROM lb)) mc JOIN res ON res.path=mc.path),
g_n AS (SELECT COALESCE(SUM(m.clicks_total),0) clk, COALESCE(SUM(m.impressions_total),0) impr FROM gsc_path_metrics((SELECT n_start FROM gb),(SELECT n_end FROM gb)) m JOIN res ON res.path=m.path),
g_p AS (SELECT COALESCE(SUM(m.clicks_total),0) clk, COALESCE(SUM(m.impressions_total),0) impr FROM gsc_path_metrics((SELECT prev_start FROM gb),(SELECT prev_end FROM gb)) m JOIN res ON res.path=m.path)
SELECT (SELECT label_fr FROM lb),
  (SELECT n_start FROM lb),(SELECT n_end FROM lb),(SELECT n_start FROM gb),(SELECT n_end FROM gb),
  (SELECT gsc_last_day FROM gb),(SELECT lag_days FROM gb),
  ((SELECT n_end FROM lb) > (SELECT n_start FROM lb) AND tracker_first_seen_global() > ((SELECT n_start FROM lb)::timestamptz)),
  ck.visitors_n, ck.visitors_prev, ck.pageviews_n, ck.pageviews_prev,
  ct_n.c, ct_p.c, g_n.clk, g_p.clk, g_n.impr, g_p.impr
FROM ck, ct_n, ct_p, g_n, g_p;
$$;

-- 4. SEO par requête (scope ressource en V1 ; branded exclu ; volume DFS).
CREATE OR REPLACE FUNCTION public.dashboard_seo_by_query(
  period_kind text DEFAULT 'rolling_90',
  scope text DEFAULT 'ressource',
  min_volume int DEFAULT 0,
  max_rows int DEFAULT 200
)
RETURNS TABLE(
  query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric,
  nb_pages int, top_page text, top_page_clicks bigint,
  volume_fr int, cpc numeric, competition_level text,
  capture_pct numeric, is_quick_win boolean,
  gsc_start date, gsc_end date
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
WITH gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
qp AS (
  SELECT d.query, d.path, SUM(d.clicks) clicks, SUM(d.impressions) impr,
         SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
    AND d.query NOT ILIKE '%plouton%'
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query, d.path
),
agg AS (
  SELECT query, SUM(clicks) clicks, SUM(impr) impr, SUM(pos_w) pos_w, COUNT(*) nb_pages
  FROM qp GROUP BY query
),
top AS (
  SELECT DISTINCT ON (query) query, path AS top_page, clicks AS top_clicks
  FROM qp ORDER BY query, clicks DESC, impr DESC
)
SELECT a.query, a.clicks, a.impr,
  ROUND(a.pos_w/NULLIF(a.impr,0),1) AS position_avg,
  ROUND(100.0*a.clicks/NULLIF(a.impr,0),2) AS ctr_pct,
  a.nb_pages::int, t.top_page, t.top_clicks,
  dfs.search_volume, dfs.cpc, dfs.competition_level,
  CASE WHEN dfs.search_volume > 0
       THEN ROUND(100.0*a.clicks/(dfs.search_volume*(SELECT day_count FROM gb)/30.0),1) END AS capture_pct,
  (ROUND(a.pos_w/NULLIF(a.impr,0),1) BETWEEN 5 AND 15 AND COALESCE(dfs.search_volume,0) >= 100) AS is_quick_win,
  (SELECT n_start FROM gb), (SELECT n_end FROM gb)
FROM agg a
LEFT JOIN top t ON t.query=a.query
LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=a.query AND dfs.location_code=2250
WHERE COALESCE(dfs.search_volume,0) >= min_volume
ORDER BY a.clicks DESC, a.impr DESC
LIMIT max_rows;
$$;

-- Sécurité : aligner sur la convention du repo.
REVOKE ALL ON FUNCTION public.dashboard_resources_overview(text,int) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.dashboard_resources_kpis(text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.dashboard_seo_by_query(text,text,int,int) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_resources_overview(text,int) TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_resources_kpis(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_seo_by_query(text,text,int,int) TO service_role;
REVOKE ALL ON public.events_human_clean FROM public, anon, authenticated;
GRANT SELECT ON public.events_human_clean TO service_role;
