-- Sprint 33+ (24/05/2026) — fix off-by-one fenêtre 28j sur 5 RPCs cross-source
--
-- Identifié par l'audit qualité data du 24/05 (docs/data-quality-audit-
-- 2026-05-24.md, dimension F.2). Les RPCs ci-dessous utilisaient
--   WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days'
-- qui calcule à today - 28, donnant 29 jours inclusifs (25/04 → 23/05
-- alors qu'on annonce "28 jours").
--
-- Convention canonique business (= site_kpis_compare, site_pulse,
-- site_seo_funnel) : 28j inclusifs = today - 27 jours, soit 26/04 → 23/05.
--
-- Conséquence du bug : ~3 % de sur-compte GSC sur les vues par-page
-- (visible dans tableau /pages, fiche /p/[slug], /queries). Invisible
-- à l'œil business, mais incohérent avec la home.
--
-- Fix : remplacer INTERVAL 'X days' par - (X - 1) dans les bornes
-- temporelles. Aucune signature touchée, juste les WHERE clauses.

-- ============================================================
-- 1. pages_overview_unified v4 — fenêtres 28j et 90j corrigées
-- ============================================================
CREATE OR REPLACE FUNCTION public.pages_overview_unified(max_rows integer DEFAULT 1000)
RETURNS TABLE (
  path                        text,
  gsc_clicks_28d              bigint,
  gsc_impressions_28d         bigint,
  gsc_position_avg_28d        numeric,
  gsc_ctr_pct_28d             numeric,
  cooked_sessions_28d         bigint,
  cooked_dwell_avg_s_28d      numeric,
  cooked_bounce_rate_28d      numeric,
  cooked_phone_clicks_28d     bigint,
  cooked_form_submits_28d     bigint,
  cooked_contacts_28d         bigint,
  cooked_booking_intent_28d   bigint,
  cooked_pogo_rate_28d        numeric,
  has_cooked_data             boolean
)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH all_paths AS (
    SELECT path FROM seo_url_snapshot
    UNION
    SELECT DISTINCT path FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 89  -- 90j inclusifs
  ),
  g28 AS (
    SELECT path,
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2) ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2) ELSE NULL END AS ctr_pct
    FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27  -- 28j inclusifs
    GROUP BY path
  ),
  fs28 AS (
    SELECT path, count(*)::bigint AS form_submits
    FROM events_human
    WHERE name = 'form_submit'
      AND path IS NOT NULL
      AND (occurred_at AT TIME ZONE 'Europe/Paris')::date
          >= (now() AT TIME ZONE 'Europe/Paris')::date - 27  -- 28j inclusifs
    GROUP BY path
  )
  SELECT
    ap.path,
    COALESCE(g28.clicks_total, 0),
    COALESCE(g28.impressions_total, 0),
    g28.position_avg,
    g28.ctr_pct,
    COALESCE(s.sessions_28d, 0),
    s.avg_dwell_seconds_28d,
    s.bounce_rate_28d,
    COALESCE(s.phone_clicks_28d, 0)::bigint,
    COALESCE(fs28.form_submits, 0)::bigint,
    (COALESCE(s.phone_clicks_28d, 0) + COALESCE(fs28.form_submits, 0))::bigint,
    COALESCE(s.booking_cta_clicks_28d, 0)::bigint,
    s.pogo_rate_28d,
    (s.path IS NOT NULL)
  FROM all_paths ap
    LEFT JOIN seo_url_snapshot s ON s.path = ap.path
    LEFT JOIN g28 ON g28.path = ap.path
    LEFT JOIN fs28 ON fs28.path = ap.path
  ORDER BY COALESCE(s.sessions_28d, 0) DESC, COALESCE(g28.clicks_total, 0) DESC, ap.path
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.pages_overview_unified(integer) IS
  'Sprint 33+ v4 (24/05/2026) : fenêtres 28j et 90j en convention inclusive (today - (N-1)).';
REVOKE EXECUTE ON FUNCTION public.pages_overview_unified(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_overview_unified(integer) TO service_role;


-- ============================================================
-- 2. gsc_pages_overview v4
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_pages_overview(max_rows integer DEFAULT 30)
RETURNS TABLE (
  path                        text,
  gsc_clicks_28d              bigint,
  gsc_impressions_28d         bigint,
  gsc_position_avg_28d        numeric,
  gsc_ctr_pct_28d             numeric,
  cooked_sessions_28d         bigint,
  cooked_dwell_avg_s_28d      numeric,
  cooked_bounce_rate_28d      numeric,
  cooked_phone_clicks_28d     bigint,
  cooked_form_submits_28d     bigint,
  cooked_contacts_28d         bigint,
  cooked_booking_intent_28d   bigint,
  cooked_pogo_rate_28d        numeric,
  has_cooked_data             boolean
)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH g AS (
    SELECT path,
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2) ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2) ELSE NULL END AS ctr_pct
    FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
    GROUP BY path
  ),
  fs28 AS (
    SELECT path, count(*)::bigint AS form_submits
    FROM events_human
    WHERE name = 'form_submit'
      AND path IS NOT NULL
      AND (occurred_at AT TIME ZONE 'Europe/Paris')::date
          >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
    GROUP BY path
  )
  SELECT
    g.path,
    g.clicks_total,
    g.impressions_total,
    g.position_avg,
    g.ctr_pct,
    COALESCE(s.sessions_28d, 0),
    s.avg_dwell_seconds_28d,
    s.bounce_rate_28d,
    COALESCE(s.phone_clicks_28d, 0)::bigint,
    COALESCE(fs28.form_submits, 0)::bigint,
    (COALESCE(s.phone_clicks_28d, 0) + COALESCE(fs28.form_submits, 0))::bigint,
    COALESCE(s.booking_cta_clicks_28d, 0)::bigint,
    s.pogo_rate_28d,
    (s.path IS NOT NULL)
  FROM g
    LEFT JOIN seo_url_snapshot s ON s.path = g.path
    LEFT JOIN fs28 ON fs28.path = g.path
  ORDER BY g.clicks_total DESC, g.impressions_total DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_pages_overview(integer) IS
  'Sprint 33+ v4 (24/05/2026) : fenêtre 28j inclusive.';
REVOKE EXECUTE ON FUNCTION public.gsc_pages_overview(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_pages_overview(integer) TO service_role;


-- ============================================================
-- 3. gsc_page_performance v3
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_page_performance(target_path text)
RETURNS TABLE (
  path                        text,
  gsc_clicks_28d              bigint,
  gsc_impressions_28d         bigint,
  gsc_position_avg_28d        numeric,
  gsc_ctr_pct_28d             numeric,
  cooked_sessions_28d         bigint,
  cooked_views_28d            bigint,
  cooked_unique_visitors_28d  bigint,
  cooked_bounce_rate_28d      numeric,
  cooked_dwell_avg_s_28d      numeric,
  cooked_scroll_median_28d    numeric,
  cooked_phone_clicks_28d     bigint,
  cooked_form_submits_28d     bigint,
  cooked_contacts_28d         bigint,
  cooked_booking_intent_28d   bigint,
  cooked_pogo_rate_28d        numeric,
  cooked_google_sessions_28d  bigint,
  lcp_p75_ms                  numeric,
  inp_p75_ms                  numeric,
  cls_p75                     numeric,
  top_referrer_28d            text,
  device_split_28d            jsonb
)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH cp AS (SELECT canonical_path(target_path) AS p),
  g AS (
    SELECT
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2) ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0 THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2) ELSE NULL END AS ctr_pct
    FROM gsc_path_daily, cp
    WHERE gsc_path_daily.path = cp.p
      AND day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
  ),
  s AS (
    SELECT * FROM seo_url_snapshot, cp WHERE seo_url_snapshot.path = cp.p LIMIT 1
  ),
  fs AS (
    SELECT count(*)::bigint AS form_submits
    FROM events_human, cp
    WHERE name = 'form_submit'
      AND events_human.path = cp.p
      AND (occurred_at AT TIME ZONE 'Europe/Paris')::date
          >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
  )
  SELECT
    cp.p,
    COALESCE(g.clicks_total, 0), COALESCE(g.impressions_total, 0),
    g.position_avg, g.ctr_pct,
    COALESCE(s.sessions_28d, 0), COALESCE(s.views_28d, 0), COALESCE(s.unique_visitors_28d, 0),
    s.bounce_rate_28d, s.avg_dwell_seconds_28d, s.scroll_median_28d,
    COALESCE(s.phone_clicks_28d, 0)::bigint,
    COALESCE(fs.form_submits, 0)::bigint,
    (COALESCE(s.phone_clicks_28d, 0) + COALESCE(fs.form_submits, 0))::bigint,
    COALESCE(s.booking_cta_clicks_28d, 0)::bigint,
    s.pogo_rate_28d, COALESCE(s.google_sessions_28d, 0),
    s.lcp_p75_28d_ms, s.inp_p75_28d_ms, s.cls_p75_28d,
    s.top_referrer_28d, s.device_split_28d
  FROM cp LEFT JOIN g ON true LEFT JOIN s ON true LEFT JOIN fs ON true;
$$;

COMMENT ON FUNCTION public.gsc_page_performance(text) IS
  'Sprint 33+ v3 (24/05/2026) : fenêtre 28j inclusive.';
REVOKE EXECUTE ON FUNCTION public.gsc_page_performance(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_page_performance(text) TO service_role;


-- ============================================================
-- 4. gsc_top_queries_for_path v2
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_top_queries_for_path(
  target_path text, days_back integer DEFAULT 28, max_rows integer DEFAULT 20
)
RETURNS TABLE (query text, clicks bigint, impressions bigint,
               position_avg numeric, ctr_pct numeric, days_in_period integer)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH cp AS (SELECT canonical_path(target_path) AS p)
  SELECT gqp.query, SUM(gqp.clicks)::bigint, SUM(gqp.impressions)::bigint,
    CASE WHEN SUM(gqp.impressions) > 0
         THEN ROUND((SUM(gqp.position * gqp.impressions) / SUM(gqp.impressions))::numeric, 2)
         ELSE NULL END,
    CASE WHEN SUM(gqp.impressions) > 0
         THEN ROUND((100.0 * SUM(gqp.clicks) / SUM(gqp.impressions))::numeric, 2)
         ELSE NULL END,
    COUNT(DISTINCT gqp.day)::integer
  FROM gsc_query_page_daily gqp, cp
  WHERE gqp.path = cp.p
    AND gqp.day >= (now() AT TIME ZONE 'Europe/Paris')::date - (days_back - 1)
  GROUP BY gqp.query
  ORDER BY 2 DESC, 3 DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) IS
  'Sprint 33+ v2 (24/05/2026) : fenêtre days_back inclusive.';
REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) TO service_role;


-- ============================================================
-- 5. gsc_top_queries_global v2
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_top_queries_global(
  days_back integer DEFAULT 28, max_rows integer DEFAULT 100
)
RETURNS TABLE (
  query text, clicks bigint, impressions bigint,
  position_avg numeric, ctr_pct numeric,
  nb_pages_targeted integer, top_page text, top_page_clicks bigint
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
    FROM window_data
    GROUP BY query, path
  ),
  query_agg AS (
    SELECT query,
      SUM(clicks)::bigint AS clicks_total,
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
  top_per_query AS (
    SELECT DISTINCT ON (query) query, path AS top_page, path_clicks AS top_clicks
    FROM query_path
    ORDER BY query, path_clicks DESC
  )
  SELECT a.query, a.clicks_total, a.impressions_total,
    a.position_avg, a.ctr_pct, a.nb_pages, tp.top_page, tp.top_clicks
  FROM query_agg a
    LEFT JOIN top_per_query tp ON tp.query = a.query
  ORDER BY a.clicks_total DESC, a.impressions_total DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_top_queries_global(integer, integer) IS
  'Sprint 33+ v2 (24/05/2026) : fenêtre days_back inclusive.';
REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_global(integer, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_top_queries_global(integer, integer) TO service_role;
