-- Sprint 33+ (25/05/2026) — Source unique contacts macro/micro par path
--
-- Avant : CTE fs28 (form_submit) recollée dans pages_overview_unified,
-- gsc_pages_overview, gsc_page_performance (+ dérive phone/booking snapshot).
-- Après : 1 fonction, 3 RPCs en LEFT JOIN.
--
-- Taxonomie (CLAUDE.md) :
--   contacts       = cta_phone_click + form_submit
--   booking_intent = cta_booking_click (micro, device humain uniquement)

CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(days_back integer DEFAULT 28)
RETURNS TABLE (
  path             text,
  phone_clicks     bigint,
  form_submits     bigint,
  contacts         bigint,
  booking_intent   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH bounds AS (
    SELECT
      (now() AT TIME ZONE 'Europe/Paris')::date AS today,
      (now() AT TIME ZONE 'Europe/Paris')::date - (days_back - 1) AS start_day
  )
  SELECT
    e.path,
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint AS phone_clicks,
    count(*) FILTER (WHERE e.name = 'form_submit')::bigint AS form_submits,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (WHERE e.name = 'form_submit')
    )::bigint AS contacts,
    count(*) FILTER (
      WHERE e.name = 'cta_booking_click' AND e.device_type != 'server'
    )::bigint AS booking_intent
  FROM events_human e
  CROSS JOIN bounds b
  WHERE e.path IS NOT NULL
    AND (
      e.name IN ('cta_phone_click', 'form_submit')
      OR (e.name = 'cta_booking_click' AND e.device_type != 'server')
    )
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.start_day
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.today
  GROUP BY e.path;
$$;

COMMENT ON FUNCTION public.macro_contacts_by_path(integer) IS
  'Contacts macro (phone + form_submit) et intent RDV (cta_booking_click) par path, fenêtre N jours Paris inclusifs.';

REVOKE EXECUTE ON FUNCTION public.macro_contacts_by_path(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.macro_contacts_by_path(integer) TO service_role;


-- ============================================================
-- pages_overview_unified v5 — macro_contacts_by_path(28)
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
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 89
  ),
  g28 AS (
    SELECT path,
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
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
    COALESCE(mc.phone_clicks, 0),
    COALESCE(mc.form_submits, 0),
    COALESCE(mc.contacts, 0),
    COALESCE(mc.booking_intent, 0),
    s.pogo_rate_28d,
    (s.path IS NOT NULL)
  FROM all_paths ap
    LEFT JOIN seo_url_snapshot s ON s.path = ap.path
    LEFT JOIN g28 ON g28.path = ap.path
    LEFT JOIN macro_contacts_by_path(28) mc ON mc.path = ap.path
  ORDER BY COALESCE(s.sessions_28d, 0) DESC, COALESCE(g28.clicks_total, 0) DESC, ap.path
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.pages_overview_unified(integer) IS
  'Sprint 33+ v5 (25/05/2026) : contacts via macro_contacts_by_path(28).';

REVOKE EXECUTE ON FUNCTION public.pages_overview_unified(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_overview_unified(integer) TO service_role;


-- ============================================================
-- gsc_pages_overview v5
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
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH g AS (
    SELECT path,
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_path_daily
    WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
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
    COALESCE(mc.phone_clicks, 0),
    COALESCE(mc.form_submits, 0),
    COALESCE(mc.contacts, 0),
    COALESCE(mc.booking_intent, 0),
    s.pogo_rate_28d,
    (s.path IS NOT NULL)
  FROM g
    LEFT JOIN seo_url_snapshot s ON s.path = g.path
    LEFT JOIN macro_contacts_by_path(28) mc ON mc.path = g.path
  ORDER BY g.clicks_total DESC, g.impressions_total DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_pages_overview(integer) IS
  'Sprint 33+ v5 (25/05/2026) : contacts via macro_contacts_by_path(28).';

REVOKE EXECUTE ON FUNCTION public.gsc_pages_overview(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_pages_overview(integer) TO service_role;


-- ============================================================
-- gsc_page_performance v4
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
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH cp AS (SELECT canonical_path(target_path) AS p),
  g AS (
    SELECT
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_path_daily, cp
    WHERE gsc_path_daily.path = cp.p
      AND day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
  ),
  s AS (
    SELECT * FROM seo_url_snapshot, cp WHERE seo_url_snapshot.path = cp.p LIMIT 1
  ),
  mc AS (
    SELECT m.*
    FROM macro_contacts_by_path(28) m, cp
    WHERE m.path = cp.p
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
    COALESCE(mc.phone_clicks, 0),
    COALESCE(mc.form_submits, 0),
    COALESCE(mc.contacts, 0),
    COALESCE(mc.booking_intent, 0),
    s.pogo_rate_28d,
    COALESCE(s.google_sessions_28d, 0),
    s.lcp_p75_28d_ms,
    s.inp_p75_28d_ms,
    s.cls_p75_28d,
    s.top_referrer_28d,
    s.device_split_28d
  FROM cp
    LEFT JOIN g ON true
    LEFT JOIN s ON true
    LEFT JOIN mc ON true;
$$;

COMMENT ON FUNCTION public.gsc_page_performance(text) IS
  'Sprint 33+ v4 (25/05/2026) : contacts via macro_contacts_by_path(28).';

REVOKE EXECUTE ON FUNCTION public.gsc_page_performance(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_page_performance(text) TO service_role;
