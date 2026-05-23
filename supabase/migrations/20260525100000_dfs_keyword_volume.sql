-- Sprint 33+ (25/05/2026) — Enrichissement GSC × DataForSEO
--
-- Objectif business : croiser les clics GSC réels du cabinet avec le
-- volume de recherche mensuel France (DataForSEO) pour calculer :
--   1. Click Yield : part du volume captée sur les requêtes où on ranke
--   2. Lost Potential : clics manqués vs si on était en position 1
--   3. CPC : proxy valeur business (ce que Plouton paierait en AdWords)
--
-- Périmètre v1 (validé par Nicolas) : top 500 requêtes par clics GSC 90j,
-- localisation France entière (location_code DFS = 2250), métriques
-- search_volume + cpc + competition + monthly_searches.

-- ============================================================
-- 1. Table dfs_keyword_volume
-- ============================================================
CREATE TABLE IF NOT EXISTS public.dfs_keyword_volume (
  keyword            text NOT NULL,
  location_code      integer NOT NULL,             -- 2250 = France
  language_code      text NOT NULL DEFAULT 'fr',
  search_volume      integer,                       -- moyenne mensuelle 12 mois
  cpc                numeric(10, 2),
  competition        numeric(4, 3),                 -- 0.000 - 1.000 (Google Ads)
  competition_level  text,                          -- LOW / MEDIUM / HIGH
  monthly_searches   jsonb,                         -- [{year, month, search_volume}, ...]
  last_synced_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (keyword, location_code)
);

CREATE INDEX IF NOT EXISTS dfs_kw_volume_keyword_idx ON public.dfs_keyword_volume(keyword);
CREATE INDEX IF NOT EXISTS dfs_kw_volume_volume_idx  ON public.dfs_keyword_volume(search_volume DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS dfs_kw_volume_synced_idx  ON public.dfs_keyword_volume(last_synced_at);

ALTER TABLE public.dfs_keyword_volume ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.dfs_keyword_volume IS
  'Sprint 33+ (25/05/2026) : volume de recherche mensuel par keyword × location, depuis DataForSEO Google Ads search_volume API. Sync hebdo via dfs-weekly-sync GitHub Actions.';

-- ============================================================
-- 2. RPC : dfs_keywords_to_sync(limit_n)
-- Liste les top N keywords par clics GSC 90j à syncer par le script Python.
-- ============================================================
CREATE OR REPLACE FUNCTION public.dfs_keywords_to_sync(limit_n integer DEFAULT 500)
RETURNS TABLE (keyword text, clicks_total bigint)
STABLE
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT query, SUM(clicks)::bigint AS clicks_total
  FROM gsc_query_daily
  WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 89  -- 90j inclusifs
    AND query IS NOT NULL
    AND query != ''
  GROUP BY query
  ORDER BY SUM(clicks) DESC NULLS LAST
  LIMIT limit_n;
$$;

COMMENT ON FUNCTION public.dfs_keywords_to_sync(integer) IS
  'Sprint 33+ : top N keywords par clics GSC 90j (Paris). Source pour le sync DataForSEO.';

REVOKE EXECUTE ON FUNCTION public.dfs_keywords_to_sync(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.dfs_keywords_to_sync(integer) TO service_role;


-- ============================================================
-- 3. Helper : ctr_for_position (CTR estimé Google par position)
-- Source benchmark : Sistrix / FirstPageSage 2024 (moyennes globales).
-- ============================================================
CREATE OR REPLACE FUNCTION public.ctr_for_position(pos numeric)
RETURNS numeric
IMMUTABLE
LANGUAGE sql
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN pos IS NULL OR pos < 1 THEN NULL
    WHEN pos <  1.5 THEN 0.280  -- pos 1
    WHEN pos <  2.5 THEN 0.150  -- pos 2
    WHEN pos <  3.5 THEN 0.110  -- pos 3
    WHEN pos <  4.5 THEN 0.080  -- pos 4
    WHEN pos <  5.5 THEN 0.060  -- pos 5
    WHEN pos <  6.5 THEN 0.040  -- pos 6
    WHEN pos <  7.5 THEN 0.030  -- pos 7
    WHEN pos <  8.5 THEN 0.025  -- pos 8
    WHEN pos <  9.5 THEN 0.020  -- pos 9
    WHEN pos < 10.5 THEN 0.015  -- pos 10
    WHEN pos < 20.5 THEN 0.005  -- pos 11-20
    ELSE 0.001                  -- pos 21+
  END;
$$;

COMMENT ON FUNCTION public.ctr_for_position(numeric) IS
  'Sprint 33+ : CTR moyen Google par position (Sistrix/FirstPageSage 2024). Pos 1 = 28%, pos 5 = 6%, pos 10 = 1.5%.';

REVOKE EXECUTE ON FUNCTION public.ctr_for_position(numeric) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.ctr_for_position(numeric) TO service_role;


-- ============================================================
-- 4. RPC : gsc_x_dfs_opportunities
-- Requêtes à fort volume où on est en position 5-15 = quick wins SEO.
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_x_dfs_opportunities(
  min_volume    integer DEFAULT 100,
  position_min  numeric DEFAULT 5.0,
  position_max  numeric DEFAULT 15.0,
  days_back     integer DEFAULT 28,
  max_rows      integer DEFAULT 30
)
RETURNS TABLE (
  query                text,
  our_position         numeric,
  our_clicks           bigint,
  our_impressions      bigint,
  our_ctr_pct          numeric,
  volume_fr            integer,
  cpc                  numeric,
  estimated_ctr_pos_1  numeric,
  lost_potential       integer,   -- clics manqués sur fenêtre (28j par défaut)
  top_page             text       -- page sur laquelle on ranke (la + cliquée)
)
STABLE
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH our_perf AS (
    -- Agrégat clicks/imp/position par query sur la fenêtre
    SELECT
      q.query,
      SUM(q.clicks)::bigint                AS clicks,
      SUM(q.impressions)::bigint           AS impressions,
      CASE WHEN SUM(q.impressions) > 0
           THEN ROUND((SUM(q.position * q.impressions) / SUM(q.impressions))::numeric, 2)
           ELSE NULL END                    AS position_avg,
      CASE WHEN SUM(q.impressions) > 0
           THEN ROUND((100.0 * SUM(q.clicks) / SUM(q.impressions))::numeric, 2)
           ELSE NULL END                    AS ctr_pct
    FROM gsc_query_daily q
    WHERE q.day >= (now() AT TIME ZONE 'Europe/Paris')::date - (days_back - 1)
      AND q.query IS NOT NULL
    GROUP BY q.query
  ),
  top_pages AS (
    -- Pour chaque query, la page qui capture le plus de clics
    SELECT DISTINCT ON (query) query, path
    FROM (
      SELECT query, path, SUM(clicks) AS path_clicks
      FROM gsc_query_page_daily
      WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - (days_back - 1)
      GROUP BY query, path
    ) x
    ORDER BY query, path_clicks DESC
  )
  SELECT
    op.query,
    op.position_avg AS our_position,
    op.clicks       AS our_clicks,
    op.impressions  AS our_impressions,
    op.ctr_pct      AS our_ctr_pct,
    dfs.search_volume AS volume_fr,
    dfs.cpc,
    (100 * ctr_for_position(1.0))::numeric AS estimated_ctr_pos_1,
    -- Lost potential : (CTR pos 1 - CTR actuel) × volume × period/30 (mensuel → period)
    GREATEST(
      ROUND((
        dfs.search_volume::numeric * days_back / 30.0
        * (ctr_for_position(1.0) - COALESCE(ctr_for_position(op.position_avg), 0))
      ))::integer,
      0
    ) AS lost_potential,
    tp.path AS top_page
  FROM our_perf op
    INNER JOIN dfs_keyword_volume dfs
      ON dfs.keyword = op.query
     AND dfs.location_code = 2250
    LEFT JOIN top_pages tp ON tp.query = op.query
  WHERE op.position_avg BETWEEN position_min AND position_max
    AND dfs.search_volume IS NOT NULL
    AND dfs.search_volume >= min_volume
  ORDER BY lost_potential DESC NULLS LAST
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_x_dfs_opportunities(integer, numeric, numeric, integer, integer) IS
  'Sprint 33+ : top opportunités SEO (position 5-15 + volume DFS ≥ min). Lost_potential = clics manqués si on était en pos 1 (CTR Sistrix).';

REVOKE EXECUTE ON FUNCTION public.gsc_x_dfs_opportunities(integer, numeric, numeric, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_x_dfs_opportunities(integer, numeric, numeric, integer, integer) TO service_role;


-- ============================================================
-- 5. gsc_top_queries_global v2 — ajout volume_fr / cpc / click_yield_pct
-- Changement de signature → DROP + CREATE.
-- ============================================================
DROP FUNCTION IF EXISTS public.gsc_top_queries_global(integer, integer);

CREATE OR REPLACE FUNCTION public.gsc_top_queries_global(
  days_back integer DEFAULT 28, max_rows integer DEFAULT 100
)
RETURNS TABLE (
  query              text,
  clicks             bigint,
  impressions        bigint,
  position_avg       numeric,
  ctr_pct            numeric,
  nb_pages_targeted  integer,
  top_page           text,
  top_page_clicks    bigint,
  volume_fr          integer,
  cpc                numeric,
  click_yield_pct    numeric   -- 100 * clicks / (volume_fr * days_back/30)
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH window_data AS (
    SELECT query, path, clicks, impressions, position
    FROM public.gsc_query_page_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - (days_back - 1)
      AND day <= (now() AT TIME ZONE 'Europe/Paris')::date
  ),
  query_path AS (
    SELECT query, path,
      SUM(clicks)::bigint AS path_clicks,
      SUM(impressions)::bigint AS path_impressions
    FROM window_data GROUP BY query, path
  ),
  query_agg AS (
    SELECT query,
      SUM(clicks)::bigint AS clicks_total,
      SUM(impressions)::bigint AS impressions_total,
      COUNT(DISTINCT path)::int AS nb_pages,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2) ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2) ELSE NULL END AS ctr_pct
    FROM window_data GROUP BY query
  ),
  top_per_query AS (
    SELECT DISTINCT ON (query) query, path AS top_page, path_clicks AS top_clicks
    FROM query_path
    ORDER BY query, path_clicks DESC
  )
  SELECT a.query, a.clicks_total, a.impressions_total,
    a.position_avg, a.ctr_pct, a.nb_pages, tp.top_page, tp.top_clicks,
    dfs.search_volume AS volume_fr,
    dfs.cpc,
    CASE WHEN dfs.search_volume > 0
         THEN ROUND((100.0 * a.clicks_total / (dfs.search_volume::numeric * days_back / 30.0))::numeric, 2)
         ELSE NULL END AS click_yield_pct
  FROM query_agg a
    LEFT JOIN top_per_query tp ON tp.query = a.query
    LEFT JOIN dfs_keyword_volume dfs
      ON dfs.keyword = a.query
     AND dfs.location_code = 2250
  ORDER BY a.clicks_total DESC, a.impressions_total DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_top_queries_global(integer, integer) IS
  'Sprint 33+ v2 (25/05/2026) : top requêtes + attribution page + enrichissement DFS (volume FR, CPC, click_yield_pct). LEFT JOIN dfs_keyword_volume (null si pas syncé).';

REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_global(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_top_queries_global(integer, integer) TO service_role;
