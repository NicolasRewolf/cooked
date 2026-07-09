-- C6 vague 2 — P3+P4 : paris_date sur RPC live restantes

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
    AND public.paris_date(occurred_at) <= b.n_end;

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
    AND public.paris_date(occurred_at) <= b.prev_end;

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
$$;

CREATE OR REPLACE FUNCTION public.cooked_pages_snapshot(
  p_period_kind text DEFAULT 'rolling_28',
  max_rows      integer DEFAULT 15
)
RETURNS TABLE (
  path                text,
  cooked_sessions     bigint,
  cooked_contacts     bigint,
  cooked_phone_clicks bigint,
  cooked_form_submits bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH b AS (
    SELECT n_start, n_end
    FROM public.cooked_period_bounds(p_period_kind, 'live')
    LIMIT 1
  ),
  sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total
    FROM public.events_human e, b
    WHERE e.path IS NOT NULL
      AND public.paris_date(e.occurred_at) >= b.n_start
      AND public.paris_date(e.occurred_at) <= b.n_end
    GROUP BY e.path
  ),
  mc AS (
    SELECT m.path AS p, m.contacts, m.phone_clicks, m.form_submits
    FROM public.macro_contacts_by_path(
      (SELECT n_start FROM b),
      (SELECT n_end FROM b)
    ) m
  )
  SELECT
    coalesce(s.p, mc.p),
    coalesce(s.sessions_total, 0),
    coalesce(mc.contacts, 0),
    coalesce(mc.phone_clicks, 0),
    coalesce(mc.form_submits, 0)
  FROM sess s
    FULL OUTER JOIN mc ON mc.p = s.p
  ORDER BY coalesce(s.sessions_total, 0) DESC, coalesce(mc.contacts, 0) DESC, coalesce(s.p, mc.p)
  LIMIT max_rows;
$$;

CREATE OR REPLACE FUNCTION public.site_pulse(
  p_period_kind         text DEFAULT 'rolling_28',
  delta_threshold_pct   numeric DEFAULT 5.0
)
RETURNS TABLE (
  period_kind                 text,
  period_label_fr             text,
  gsc_period_start            date,
  gsc_period_end              date,
  cooked_period_start         date,
  cooked_period_end           date,
  gsc_clicks_n                bigint,
  gsc_clicks_prev             bigint,
  gsc_delta_pct               numeric,
  cooked_sessions_n           bigint,
  cooked_sessions_prev        bigint,
  cooked_sessions_delta_pct   numeric,
  quadrant                    text
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
  v_gsc_n      bigint;
  v_gsc_prev   bigint;
  v_ck_n       bigint;
  v_ck_prev    bigint;
  v_gsc_delta  numeric;
  v_ck_delta   numeric;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1;
  v_first_seen := public.paris_date(public.tracker_first_seen_global());
  v_has_prev := v_first_seen IS NOT NULL AND v_first_seen <= b.prev_start;

  SELECT coalesce(sum(clicks), 0)::bigint INTO v_gsc_n
  FROM public.gsc_path_daily
  WHERE day >= b.n_start AND day <= b.n_end;

  SELECT coalesce(sum(clicks), 0)::bigint INTO v_gsc_prev
  FROM public.gsc_path_daily
  WHERE day >= b.prev_start AND day <= b.prev_end;

  SELECT count(DISTINCT session_id) FILTER (
           WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
         )::bigint INTO v_ck_n
  FROM public.events_human
  WHERE public.paris_date(occurred_at) >= b.n_start
    AND public.paris_date(occurred_at) <= b.n_end;

  IF v_has_prev THEN
    SELECT count(DISTINCT session_id) FILTER (
             WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
           )::bigint INTO v_ck_prev
    FROM public.events_human
    WHERE public.paris_date(occurred_at) >= b.prev_start
      AND public.paris_date(occurred_at) <= b.prev_end;
  ELSE
    v_ck_prev := NULL;
  END IF;

  v_gsc_delta := CASE WHEN v_gsc_prev > 0
    THEN round((100.0 * (v_gsc_n - v_gsc_prev) / v_gsc_prev)::numeric, 2) ELSE NULL END;
  v_ck_delta := CASE WHEN v_ck_prev IS NOT NULL AND v_ck_prev > 0
    THEN round((100.0 * (v_ck_n - v_ck_prev) / v_ck_prev)::numeric, 2) ELSE NULL END;

  RETURN QUERY SELECT
    b.period_kind_out,
    b.label_fr,
    b.n_start,
    b.n_end,
    b.n_start,
    b.n_end,
    v_gsc_n,
    v_gsc_prev,
    v_gsc_delta,
    v_ck_n,
    v_ck_prev,
    v_ck_delta,
    public.pulse_status(v_gsc_n, v_gsc_prev, v_ck_n, v_ck_prev, delta_threshold_pct);
END;
$$;

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
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, 'cross') LIMIT 1;

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
  WHERE public.paris_date(e.occurred_at) >= b.n_start
    AND public.paris_date(e.occurred_at) <= b.n_end;

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

CREATE OR REPLACE FUNCTION public.cooked_pages_compare(period_kind text DEFAULT 'rolling_28', data_lens text DEFAULT 'cross')
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
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, data_lens) LIMIT 1;
  v_first_seen := public.paris_date(public.tracker_first_seen_global());
  v_has_prev := v_first_seen IS NOT NULL AND v_first_seen <= b.prev_start;

  RETURN QUERY
  WITH n_sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL
      AND public.paris_date(e.occurred_at) >= b.n_start
      AND public.paris_date(e.occurred_at) <= b.n_end
    GROUP BY e.path
  ),
  prev_sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL AND v_has_prev
      AND public.paris_date(e.occurred_at) >= b.prev_start
      AND public.paris_date(e.occurred_at) <= b.prev_end
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

CREATE OR REPLACE FUNCTION public.cooked_page_daily_series(
  target_path text,
  days_back   integer,
  end_date    date DEFAULT NULL
)
RETURNS TABLE (
  day        date,
  sessions   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  with cp as (select canonical_path(target_path) as p),
  series as (
    select gs::date as day
    from generate_series(
      coalesce(end_date, public.paris_today()) - (days_back - 1),
      coalesce(end_date, public.paris_today()),
      interval '1 day'
    ) gs
  )
  select
    s.day,
    coalesce(
      count(distinct e.session_id) filter (
        where e.name = 'pageview' and e.device_type is distinct from 'server'
      ),
      0
    )::bigint as sessions
  from series s
    left join public.events_human e
      on public.paris_date(e.occurred_at) = s.day
     and e.path = (select p from cp)
  group by s.day
  order by s.day;
$$;

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
    AND public.paris_date(e.occurred_at) >= start_date
    AND public.paris_date(e.occurred_at) <= end_date
  GROUP BY e.path;
$$;
