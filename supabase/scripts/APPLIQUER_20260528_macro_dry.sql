-- Sprint 33+ (28/05/2026) — DRY macro contacts + gsc_top_queries period_kind
--
-- 1. site_macro_counts(start, end) — seule source site-wide phone/form/macro
-- 2. site_kpis_compare / site_seo_funnel — appellent site_macro_counts
-- 3. cooked_pages_compare — contacts via macro_contacts_by_path (pas de FILTER dupliqué)
-- 4. form_submits_per_path — filtre candidatures
-- 5. gsc_top_queries_for_path(target_path, period_kind, max_rows) — fenêtre = cooked_period_bounds

-- ============================================================
-- 1. site_macro_counts
-- ============================================================
CREATE OR REPLACE FUNCTION public.site_macro_counts(
  start_date date,
  end_date   date
)
RETURNS TABLE (
  phone_clicks      bigint,
  form_submits      bigint,
  macro_conversions bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint,
    count(*) FILTER (
      WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
    )::bigint,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (
          WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
        )
    )::bigint
  FROM public.events_human e
  WHERE (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= start_date
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= end_date;
$$;

COMMENT ON FUNCTION public.site_macro_counts(date, date) IS
  'Contacts macro site-wide sur [start_date, end_date] Paris (phone + form_submit filtré).';

REVOKE EXECUTE ON FUNCTION public.site_macro_counts(date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_macro_counts(date, date) TO service_role;


-- ============================================================
-- 2. site_kpis_compare — DRY via site_macro_counts
-- ============================================================
CREATE OR REPLACE FUNCTION public.site_kpis_compare(p_period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  period_kind                 text,
  period_label_fr             text,
  period_n_start              date,
  period_n_end                date,
  tracker_first_seen          date,
  is_partial_period           boolean,
  sessions_n                  bigint,
  pageviews_n                 bigint,
  phone_clicks_n              bigint,
  form_submits_n              bigint,
  macro_conversions_n         bigint,
  period_prev_start           date,
  period_prev_end             date,
  sessions_prev               bigint,
  pageviews_prev              bigint,
  phone_clicks_prev           bigint,
  form_submits_prev           bigint,
  macro_conversions_prev      bigint,
  sessions_delta_pct          numeric,
  pageviews_delta_pct         numeric,
  phone_clicks_delta_pct      numeric,
  form_submits_delta_pct      numeric,
  macro_conversions_delta_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
  v_first_seen date;
  v_sessions_n      bigint;
  v_pageviews_n     bigint;
  v_phone_n         bigint;
  v_form_n          bigint;
  v_macro_n         bigint;
  v_sessions_prev   bigint;
  v_pageviews_prev  bigint;
  v_phone_prev      bigint;
  v_form_prev       bigint;
  v_macro_prev      bigint;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind) LIMIT 1;
  v_first_seen := (public.tracker_first_seen_global() AT TIME ZONE 'Europe/Paris')::date;

  SELECT
    count(DISTINCT session_id) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    )
  INTO v_sessions_n, v_pageviews_n
  FROM public.events_human
  WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
    AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end;

  SELECT m.phone_clicks, m.form_submits, m.macro_conversions
  INTO v_phone_n, v_form_n, v_macro_n
  FROM public.site_macro_counts(b.n_start, b.n_end) m;

  SELECT
    count(DISTINCT session_id) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    )
  INTO v_sessions_prev, v_pageviews_prev
  FROM public.events_human
  WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.prev_start
    AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.prev_end;

  SELECT m.phone_clicks, m.form_submits, m.macro_conversions
  INTO v_phone_prev, v_form_prev, v_macro_prev
  FROM public.site_macro_counts(b.prev_start, b.prev_end) m;

  RETURN QUERY SELECT
    b.period_kind_out,
    b.label_fr,
    b.n_start,
    b.n_end,
    v_first_seen,
    (v_first_seen IS NOT NULL AND b.n_start < v_first_seen),
    coalesce(v_sessions_n, 0)::bigint,
    coalesce(v_pageviews_n, 0)::bigint,
    coalesce(v_phone_n, 0)::bigint,
    coalesce(v_form_n, 0)::bigint,
    coalesce(v_macro_n, 0)::bigint,
    b.prev_start,
    b.prev_end,
    coalesce(v_sessions_prev, 0)::bigint,
    coalesce(v_pageviews_prev, 0)::bigint,
    coalesce(v_phone_prev, 0)::bigint,
    coalesce(v_form_prev, 0)::bigint,
    coalesce(v_macro_prev, 0)::bigint,
    CASE WHEN v_sessions_prev > 0
         THEN round((100.0 * (v_sessions_n - v_sessions_prev) / v_sessions_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN v_pageviews_prev > 0
         THEN round((100.0 * (v_pageviews_n - v_pageviews_prev) / v_pageviews_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN v_phone_prev > 0
         THEN round((100.0 * (v_phone_n - v_phone_prev) / v_phone_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN v_form_prev > 0
         THEN round((100.0 * (v_form_n - v_form_prev) / v_form_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN v_macro_prev > 0
         THEN round((100.0 * (v_macro_n - v_macro_prev) / v_macro_prev)::numeric, 2)
         ELSE NULL END;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.site_kpis_compare(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_kpis_compare(text) TO service_role;


-- ============================================================
-- 3. site_seo_funnel — macro via site_macro_counts
-- ============================================================
CREATE OR REPLACE FUNCTION public.site_seo_funnel(period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  period_start                date,
  period_end                  date,
  impressions                 bigint,
  clicks                      bigint,
  google_sessions             bigint,
  macro_contacts              bigint,
  impr_to_click_pct           numeric,
  click_to_session_pct        numeric,
  session_to_contact_pct      numeric,
  overall_impr_to_contact_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
  v_impressions bigint;
  v_clicks bigint;
  v_google_sessions bigint;
  v_macro bigint;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind) LIMIT 1;

  SELECT
    coalesce(sum(g.impressions), 0)::bigint,
    coalesce(sum(g.clicks), 0)::bigint
  INTO v_impressions, v_clicks
  FROM public.gsc_path_daily g
  WHERE g.day >= b.n_start AND g.day <= b.n_end;

  SELECT count(DISTINCT e.session_id) FILTER (
           WHERE e.name = 'pageview'
             AND e.device_type IS DISTINCT FROM 'server'
             AND (
               e.referrer_hostname LIKE '%google.%'
               OR (e.utm_source = 'google' AND e.utm_medium IN ('organic', 'cpc'))
             )
         )::bigint INTO v_google_sessions
  FROM public.events_human e
  WHERE (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end;

  SELECT m.macro_conversions INTO v_macro
  FROM public.site_macro_counts(b.n_start, b.n_end) m;

  RETURN QUERY SELECT
    b.n_start,
    b.n_end,
    v_impressions,
    v_clicks,
    v_google_sessions,
    coalesce(v_macro, 0),
    CASE WHEN v_impressions > 0
         THEN round((100.0 * v_clicks / v_impressions)::numeric, 2) ELSE NULL END,
    CASE WHEN v_clicks > 0
         THEN round((100.0 * v_google_sessions / v_clicks)::numeric, 2) ELSE NULL END,
    CASE WHEN v_google_sessions > 0
         THEN round((100.0 * v_macro / v_google_sessions)::numeric, 2) ELSE NULL END,
    CASE WHEN v_impressions > 0
         THEN round((100.0 * v_macro / v_impressions)::numeric, 4) ELSE NULL END;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.site_seo_funnel(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_seo_funnel(text) TO service_role;


-- ============================================================
-- 4. cooked_pages_compare — contacts via macro_contacts_by_path
-- ============================================================
CREATE OR REPLACE FUNCTION public.cooked_pages_compare(period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  path                       text,
  sessions_n                 bigint,
  sessions_prev              bigint,
  sessions_delta_pct         numeric,
  contacts_n                 bigint,
  contacts_prev              bigint,
  contacts_delta_pct         numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
  v_first_seen date;
  v_has_prev   boolean;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind) LIMIT 1;
  v_first_seen := (public.tracker_first_seen_global() AT TIME ZONE 'Europe/Paris')::date;
  v_has_prev := v_first_seen IS NOT NULL AND v_first_seen <= b.prev_start;

  RETURN QUERY
  WITH n_sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end
    GROUP BY e.path
  ),
  prev_sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL AND v_has_prev
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.prev_start
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.prev_end
    GROUP BY e.path
  ),
  n_mc AS (
    SELECT mc.path AS p, mc.contacts AS contacts_total
    FROM public.macro_contacts_by_path(b.n_start, b.n_end) mc
  ),
  prev_mc AS (
    SELECT mc.path AS p, mc.contacts AS contacts_total
    FROM public.macro_contacts_by_path(b.prev_start, b.prev_end) mc
    WHERE v_has_prev
  ),
  paths AS (
    SELECT n_sess.p FROM n_sess
    UNION SELECT prev_sess.p FROM prev_sess
    UNION SELECT n_mc.p FROM n_mc
    UNION SELECT prev_mc.p FROM prev_mc
  )
  SELECT
    paths.p,
    coalesce(ns.sessions_total, 0),
    CASE WHEN v_has_prev THEN coalesce(ps.sessions_total, 0) ELSE NULL END,
    CASE WHEN v_has_prev AND coalesce(ps.sessions_total, 0) > 0
         THEN round((100.0 * (coalesce(ns.sessions_total, 0) - ps.sessions_total) / ps.sessions_total)::numeric, 2)
         ELSE NULL END,
    coalesce(nm.contacts_total, 0),
    CASE WHEN v_has_prev THEN coalesce(pm.contacts_total, 0) ELSE NULL END,
    CASE WHEN v_has_prev AND coalesce(pm.contacts_total, 0) > 0
         THEN round((100.0 * (coalesce(nm.contacts_total, 0) - pm.contacts_total) / pm.contacts_total)::numeric, 2)
         ELSE NULL END
  FROM paths
    LEFT JOIN n_sess ns ON ns.p = paths.p
    LEFT JOIN prev_sess ps ON ps.p = paths.p
    LEFT JOIN n_mc nm ON nm.p = paths.p
    LEFT JOIN prev_mc pm ON pm.p = paths.p;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cooked_pages_compare(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cooked_pages_compare(text) TO service_role;


-- ============================================================
-- 5. form_submits_per_path — filtre candidatures
-- ============================================================
CREATE OR REPLACE FUNCTION public.form_submits_per_path(
  start_date date,
  end_date   date
)
RETURNS TABLE (
  path           text,
  form_submits   bigint
)
STABLE
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    e.path,
    count(*)::bigint
  FROM public.events_human e
  WHERE e.name = 'form_submit'
    AND public.form_submit_counts_as_macro(e.props)
    AND e.path IS NOT NULL
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= start_date
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= end_date
  GROUP BY e.path;
$$;

COMMENT ON FUNCTION public.form_submits_per_path(date, date) IS
  'form_submit macro par path (exclut candidatures via form_submit_counts_as_macro).';

REVOKE EXECUTE ON FUNCTION public.form_submits_per_path(date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.form_submits_per_path(date, date) TO service_role;


-- ============================================================
-- 6. gsc_top_queries_for_path — overload period_kind (canonical dashboard)
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_top_queries_for_path(
  target_path   text,
  p_period_kind text DEFAULT 'rolling_28',
  max_rows      integer DEFAULT 20
)
RETURNS TABLE (
  query           text,
  clicks          bigint,
  impressions     bigint,
  position_avg    numeric,
  ctr_pct         numeric,
  days_in_period  integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind) LIMIT 1
  ),
  cp AS (SELECT public.canonical_path(target_path) AS p)
  SELECT
    gqp.query,
    sum(gqp.clicks)::bigint,
    sum(gqp.impressions)::bigint,
    CASE WHEN sum(gqp.impressions) > 0
         THEN round((sum(gqp.position * gqp.impressions) / sum(gqp.impressions))::numeric, 2)
         ELSE NULL END,
    CASE WHEN sum(gqp.impressions) > 0
         THEN round((100.0 * sum(gqp.clicks) / sum(gqp.impressions))::numeric, 2)
         ELSE NULL END,
    count(DISTINCT gqp.day)::integer
  FROM public.gsc_query_page_daily gqp
  CROSS JOIN cp
  CROSS JOIN b
  WHERE gqp.path = cp.p
    AND gqp.day >= b.n_start
    AND gqp.day <= b.n_end
  GROUP BY gqp.query
  ORDER BY 2 DESC, 3 DESC
  LIMIT max_rows;
$$;

COMMENT ON FUNCTION public.gsc_top_queries_for_path(text, text, integer) IS
  'Top requêtes GSC sur une landing — fenêtre = cooked_period_bounds(period_kind).';

REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, text, integer)
  FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_top_queries_for_path(text, text, integer) TO service_role;
