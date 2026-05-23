-- Sprint 33+ (24/05/2026) — Unifier la définition « Contacts »
--
-- Problème identifié en review code :
--   pages_overview_unified et gsc_page_performance comptaient
--   "cooked_conversions_28d" = phone_clicks + booking_cta_clicks.
--   C'est faux : booking_cta_click est une micro-conversion (intent
--   déclaré, pas matérialisé). La vraie définition macro selon
--   CLAUDE.md cooked est phone + form_submit. site_kpis_compare a
--   toujours été correct, mais les RPCs par path ne l'étaient pas.
--
-- Cause technique : seo_url_snapshot n'a pas de colonne form_submits_*
-- par path. Le snapshot a phone_clicks_* et booking_cta_clicks_*.
-- form_submit est inséré par form-webhook avec un path = page d'origine
-- du formulaire (resolvePageSource depuis Wix). Donc events_human
-- a bien le path attribué.
--
-- Fix : sub-CTE fs28 dans pages_overview_unified et gsc_page_performance
-- qui agrège count(*) FILTER (name='form_submit') par path sur 28j.
-- On expose maintenant :
--   - cooked_phone_clicks_28d  (séparé)
--   - cooked_form_submits_28d  (nouveau, par path)
--   - cooked_contacts_28d      (= phone + form, vraie macro)
--   - cooked_booking_intent_28d (= booking, micro séparé)
--
-- Le total renommé "Contacts" colle au vocabulaire CLAUDE.md et au
-- KPI hero "Contacts générés" de la home.

-- ============================================================
-- pages_overview_unified v3 — contacts macro corrects
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
  ),
  fs28 AS (
    SELECT path, count(*)::bigint AS form_submits
    FROM events_human
    WHERE name = 'form_submit'
      AND path IS NOT NULL
      AND (occurred_at AT TIME ZONE 'Europe/Paris')::date
          >= (now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days'
    GROUP BY path
  )
  SELECT
    ap.path,
    COALESCE(g28.clicks_total, 0)                  AS gsc_clicks_28d,
    COALESCE(g28.impressions_total, 0)             AS gsc_impressions_28d,
    g28.position_avg                                AS gsc_position_avg_28d,
    g28.ctr_pct                                     AS gsc_ctr_pct_28d,
    COALESCE(s.sessions_28d, 0)                    AS cooked_sessions_28d,
    s.avg_dwell_seconds_28d                         AS cooked_dwell_avg_s_28d,
    s.bounce_rate_28d                               AS cooked_bounce_rate_28d,
    COALESCE(s.phone_clicks_28d, 0)::bigint        AS cooked_phone_clicks_28d,
    COALESCE(fs28.form_submits, 0)::bigint         AS cooked_form_submits_28d,
    (COALESCE(s.phone_clicks_28d, 0)
      + COALESCE(fs28.form_submits, 0))::bigint    AS cooked_contacts_28d,
    COALESCE(s.booking_cta_clicks_28d, 0)::bigint  AS cooked_booking_intent_28d,
    s.pogo_rate_28d                                 AS cooked_pogo_rate_28d,
    (s.path IS NOT NULL)                            AS has_cooked_data
  FROM all_paths ap
    LEFT JOIN seo_url_snapshot s ON s.path = ap.path
    LEFT JOIN g28  ON g28.path  = ap.path
    LEFT JOIN fs28 ON fs28.path = ap.path
  ORDER BY
    COALESCE(s.sessions_28d, 0) DESC,
    COALESCE(g28.clicks_total, 0) DESC,
    ap.path
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.pages_overview_unified(integer) IS
  'Sprint 33+ v3 (24/05/2026) : ajout fs28 (form_submits 28j par path) + colonnes contacts/booking séparées (macro vs micro, conforme CLAUDE.md).';

REVOKE EXECUTE ON FUNCTION public.pages_overview_unified(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_overview_unified(integer) TO service_role;


-- ============================================================
-- gsc_page_performance v2 — contacts macro corrects + form_submit exposé
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
      SUM(clicks)::bigint      AS clicks_total,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
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
  ),
  fs AS (
    SELECT count(*)::bigint AS form_submits
    FROM events_human, cp
    WHERE name = 'form_submit'
      AND events_human.path = cp.p
      AND (occurred_at AT TIME ZONE 'Europe/Paris')::date
          >= (now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days'
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
    COALESCE(s.phone_clicks_28d, 0)::bigint,
    COALESCE(fs.form_submits, 0)::bigint,
    (COALESCE(s.phone_clicks_28d, 0) + COALESCE(fs.form_submits, 0))::bigint,
    COALESCE(s.booking_cta_clicks_28d, 0)::bigint,
    s.pogo_rate_28d,
    COALESCE(s.google_sessions_28d, 0),
    s.lcp_p75_28d_ms,
    s.inp_p75_28d_ms,
    s.cls_p75_28d,
    s.top_referrer_28d,
    s.device_split_28d
  FROM cp
    LEFT JOIN g  ON true
    LEFT JOIN s  ON true
    LEFT JOIN fs ON true;
$$;

COMMENT ON FUNCTION public.gsc_page_performance(text) IS
  'Sprint 33+ v2 (24/05/2026) : ajout form_submits par path + colonnes contacts/booking séparées (macro vs micro, conforme CLAUDE.md).';

REVOKE EXECUTE ON FUNCTION public.gsc_page_performance(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_page_performance(text) TO service_role;
