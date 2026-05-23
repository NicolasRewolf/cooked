-- Sprint 33+ (24/05/2026) — gsc_pages_overview v3 : contacts macro alignés
--
-- La v1 (20260522113000) exposait cooked_conversions_28d = phone + booking
-- (faux). Alignement sur pages_overview_unified v3 :
--   cooked_contacts_28d = phone + form_submit
--   cooked_booking_intent_28d = micro séparé
--
-- Différence produit conservée : uniquement les pages avec signal GSC 28j,
-- tri par clics Google (vue SEO), pas l'univers exhaustif snapshot ∪ GSC.

DROP FUNCTION IF EXISTS public.gsc_pages_overview(integer);

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
    SELECT
      path,
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
    g.path,
    g.clicks_total                              AS gsc_clicks_28d,
    g.impressions_total                         AS gsc_impressions_28d,
    g.position_avg                              AS gsc_position_avg_28d,
    g.ctr_pct                                   AS gsc_ctr_pct_28d,
    COALESCE(s.sessions_28d, 0)                AS cooked_sessions_28d,
    s.avg_dwell_seconds_28d                     AS cooked_dwell_avg_s_28d,
    s.bounce_rate_28d                           AS cooked_bounce_rate_28d,
    COALESCE(s.phone_clicks_28d, 0)::bigint   AS cooked_phone_clicks_28d,
    COALESCE(fs28.form_submits, 0)::bigint     AS cooked_form_submits_28d,
    (COALESCE(s.phone_clicks_28d, 0)
      + COALESCE(fs28.form_submits, 0))::bigint AS cooked_contacts_28d,
    COALESCE(s.booking_cta_clicks_28d, 0)::bigint AS cooked_booking_intent_28d,
    s.pogo_rate_28d                             AS cooked_pogo_rate_28d,
    (s.path IS NOT NULL)                        AS has_cooked_data
  FROM g
    LEFT JOIN seo_url_snapshot s ON s.path = g.path
    LEFT JOIN fs28 ON fs28.path = g.path
  ORDER BY g.clicks_total DESC, g.impressions_total DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_pages_overview(integer) IS
  'Sprint 33+ v3 (24/05/2026) : top pages avec signal GSC 28j, tri clics Google. Contacts macro = phone + form_submit ; booking_intent séparé.';

REVOKE EXECUTE ON FUNCTION public.gsc_pages_overview(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_pages_overview(integer) TO service_role;
