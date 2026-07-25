-- Audit 25/07/2026 — tâche #8 (partie 1) : prédicat unique référents spam + site KPIs.

CREATE OR REPLACE FUNCTION public.cooked_is_spam_referrer(p_hostname text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT p_hostname IS NOT NULL
    AND p_hostname IN ('m.baidu.com', 'baidu.com');
$function$;

COMMENT ON FUNCTION public.cooked_is_spam_referrer(text) IS
  'Référents spam (Baidu) exclus des comptages visiteurs dashboard — prédicat unique (audit 25/07).';

-- Contacts macro : formulaires sans path → bucket explicite (tâche #7 corollaire).
CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(start_date date, end_date date)
 RETURNS TABLE(path text, phone_clicks bigint, form_submits bigint, contacts bigint, booking_intent bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    coalesce(e.path, '(non rattaché)'),
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint,
    count(*) FILTER (
      WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
    )::bigint,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (
          WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
        )
    )::bigint,
    count(*) FILTER (
      WHERE e.name = 'cta_booking_click' AND e.device_type != 'server'
    )::bigint
  FROM public.events_human e
  WHERE (
      e.name = 'cta_phone_click'
      OR (e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props))
      OR (e.name = 'cta_booking_click' AND e.device_type != 'server')
    )
    AND public.paris_date(e.occurred_at) >= start_date
    AND public.paris_date(e.occurred_at) <= end_date
  GROUP BY 1;
$function$;

-- KPIs site : exclure les entrées Baidu des sessions/pageviews (aligné dashboard ressources).
CREATE OR REPLACE FUNCTION public.site_kpis_compare(p_period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(period_kind text, period_label_fr text, period_n_start date, period_n_end date, tracker_first_seen date, is_partial_period boolean, sessions_n bigint, pageviews_n bigint, phone_clicks_n bigint, form_submits_n bigint, macro_conversions_n bigint, period_prev_start date, period_prev_end date, sessions_prev bigint, pageviews_prev bigint, phone_clicks_prev bigint, form_submits_prev bigint, macro_conversions_prev bigint, sessions_delta_pct numeric, pageviews_delta_pct numeric, phone_clicks_delta_pct numeric, form_submits_delta_pct numeric, macro_conversions_delta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind, 'live') LIMIT 1;
  v_first_seen := public.paris_date(public.tracker_first_seen_global());

  SELECT
    count(DISTINCT session_id) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    )
  INTO v_sessions_n, v_pageviews_n
  FROM public.events_human
  WHERE public.paris_date(occurred_at) >= b.n_start
    AND public.paris_date(occurred_at) <= b.n_end
    AND NOT public.cooked_is_spam_referrer(referrer_hostname);

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
  WHERE public.paris_date(occurred_at) >= b.prev_start
    AND public.paris_date(occurred_at) <= b.prev_end
    AND NOT public.cooked_is_spam_referrer(referrer_hostname);

  SELECT m.phone_clicks, m.form_submits, m.macro_conversions
  INTO v_phone_prev, v_form_prev, v_macro_prev
  FROM public.site_macro_counts(b.prev_start, b.prev_end) m;

  RETURN QUERY SELECT
    b.period_kind_out, b.label_fr, b.n_start, b.n_end,
    v_first_seen, (v_first_seen IS NOT NULL AND b.n_start < v_first_seen),
    coalesce(v_sessions_n, 0)::bigint, coalesce(v_pageviews_n, 0)::bigint,
    coalesce(v_phone_n, 0)::bigint, coalesce(v_form_n, 0)::bigint, coalesce(v_macro_n, 0)::bigint,
    b.prev_start, b.prev_end,
    coalesce(v_sessions_prev, 0)::bigint, coalesce(v_pageviews_prev, 0)::bigint,
    coalesce(v_phone_prev, 0)::bigint, coalesce(v_form_prev, 0)::bigint, coalesce(v_macro_prev, 0)::bigint,
    CASE WHEN v_sessions_prev > 0 THEN round((100.0 * (v_sessions_n - v_sessions_prev) / v_sessions_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_pageviews_prev > 0 THEN round((100.0 * (v_pageviews_n - v_pageviews_prev) / v_pageviews_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_phone_prev > 0 THEN round((100.0 * (v_phone_n - v_phone_prev) / v_phone_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_form_prev > 0 THEN round((100.0 * (v_form_n - v_form_prev) / v_form_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_macro_prev > 0 THEN round((100.0 * (v_macro_n - v_macro_prev) / v_macro_prev)::numeric, 2) ELSE NULL END;
END;
$function$;

-- bounce_rate_pct explicite (0–100) en plus du ratio historique bounce_rate (0–1).
DROP FUNCTION IF EXISTS public.behavior_pages_for_period(timestamptz, timestamptz);
CREATE FUNCTION public.behavior_pages_for_period(date_from timestamptz, date_to timestamptz)
 RETURNS TABLE(path text, sessions bigint, pages_per_session numeric, avg_session_duration_s numeric, bounce_rate numeric, bounce_rate_pct numeric, scroll_depth_avg numeric, scroll_complete_pct numeric, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, ttfb_p75_ms numeric, outbound_clicks bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH we AS (
    SELECT * FROM public.events_human
    WHERE occurred_at >= date_from AND occurred_at < date_to
  ),
  ss AS (
    SELECT session_id,
      count(*) FILTER (WHERE name = 'pageview') AS pages_viewed,
      extract(epoch FROM max(occurred_at) - min(occurred_at))::numeric AS session_seconds
    FROM we GROUP BY session_id
  ),
  sp AS (
    SELECT DISTINCT e.path, e.session_id
    FROM we e
    WHERE e.name = 'pageview' AND e.path IS NOT NULL
  ),
  per_path_session_stats AS (
    SELECT sp.path,
      avg(ss.pages_viewed)::numeric AS pages_per_session,
      avg(ss.session_seconds)::numeric AS avg_session_seconds
    FROM sp JOIN ss ON ss.session_id = sp.session_id
    GROUP BY sp.path
  ),
  cwv AS (
    SELECT path,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'LCP'))::numeric AS lcp_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'INP'))::numeric AS inp_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'CLS'))::numeric AS cls_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'TTFB'))::numeric AS ttfb_p75
    FROM we
    WHERE name = 'web_vitals' AND path IS NOT NULL
    GROUP BY path
  ),
  oc AS (
    SELECT path, count(*) AS clicks
    FROM we
    WHERE name = 'click_outbound' AND path IS NOT NULL
    GROUP BY path
  ),
  base AS (SELECT * FROM public.seo_pages_overview(date_from, date_to))
  SELECT b.path, b.sessions,
    coalesce(round(pp.pages_per_session, 2), 0),
    coalesce(round(pp.avg_session_seconds, 0), 0),
    coalesce(round(b.bounce_rate / 100.0, 4), 0),
    coalesce(round(b.bounce_rate, 2), 0),
    b.scroll_avg, b.scroll_complete_pct,
    cwv.lcp_p75, cwv.inp_p75, cwv.cls_p75, cwv.ttfb_p75,
    coalesce(oc.clicks, 0)::bigint
  FROM base b
  LEFT JOIN per_path_session_stats pp ON pp.path = b.path
  LEFT JOIN cwv ON cwv.path = b.path
  LEFT JOIN oc ON oc.path = b.path;
$function$;

REVOKE ALL ON FUNCTION public.behavior_pages_for_period(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.behavior_pages_for_period(timestamptz, timestamptz) TO service_role;

INSERT INTO public.annotations (day, kind, label, paths)
SELECT '2026-07-25'::date, 'site_change',
  'Restatement visiteurs site : exclusion référents Baidu unifiée (cooked_is_spam_referrer) — ~−17 % sur 28 j vs ancien comptage.',
  NULL::text[]
WHERE NOT EXISTS (
  SELECT 1 FROM public.annotations
  WHERE day = '2026-07-25'::date
    AND label LIKE 'Restatement visiteurs site : exclusion référents Baidu%'
);
