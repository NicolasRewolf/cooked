-- Sprint 33+ (29/05/2026) — 3 zones dashboard : live / gsc / cross
-- live  : n_end = aujourd'hui Paris (Cooked pur)
-- gsc   : n_end = gsc_last_data_day() (GSC pur)
-- cross : idem gsc — Cooked tronqué au même jour pour métriques honnêtes

-- ============================================================
-- 1. gsc_last_data_day()
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_last_data_day()
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT max(day) FROM public.gsc_path_daily;
$$;

COMMENT ON FUNCTION public.gsc_last_data_day() IS
  'Dernier jour calendaire avec données GSC ingérées (source unique lag/crop).';

REVOKE EXECUTE ON FUNCTION public.gsc_last_data_day() FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_last_data_day() TO service_role;


-- ============================================================
-- 2. cooked_period_bounds(period_kind, data_lens)
-- ============================================================
DROP FUNCTION IF EXISTS public.cooked_period_bounds(text);

CREATE OR REPLACE FUNCTION public.cooked_period_bounds(
  period_kind text,
  data_lens   text DEFAULT 'live'
)
RETURNS TABLE (
  period_kind_out text,
  label_fr        text,
  n_start         date,
  n_end           date,
  prev_start      date,
  prev_end        date,
  day_count       integer,
  paris_today     date,
  gsc_last_day    date,
  lag_days        integer,
  data_lens_out   text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_kind      text;
  v_lens      text;
  v_today     date := (now() AT TIME ZONE 'Europe/Paris')::date;
  v_gsc_last  date;
  v_anchor    date;
  v_n_start   date;
  v_n_end     date;
  v_prev_start date;
  v_prev_end   date;
  v_label     text;
  v_days      integer;
  v_lag       integer;
BEGIN
  v_kind := lower(trim(coalesce(period_kind, 'rolling_28')));
  v_lens := lower(trim(coalesce(data_lens, 'live')));
  IF v_lens NOT IN ('live', 'gsc', 'cross') THEN
    v_lens := 'live';
  END IF;

  v_gsc_last := public.gsc_last_data_day();
  v_lag := CASE WHEN v_gsc_last IS NOT NULL THEN (v_today - v_gsc_last)::integer ELSE NULL END;

  IF v_lens = 'live' THEN
    v_anchor := v_today;
  ELSE
    v_anchor := coalesce(v_gsc_last, v_today);
  END IF;

  v_n_end := v_anchor;

  CASE v_kind
    WHEN 'today' THEN
      v_n_start := v_anchor;
      v_prev_start := v_anchor - 1;
      v_prev_end := v_anchor - 1;
      v_label := 'Aujourd''hui';

    WHEN 'week' THEN
      v_n_start := date_trunc('week', v_anchor::timestamp)::date;
      v_prev_start := v_n_start - 7;
      v_prev_end := v_n_end - 7;
      v_label := 'Semaine en cours';

    WHEN 'month' THEN
      v_n_start := date_trunc('month', v_anchor::timestamp)::date;
      v_prev_end := (v_n_end::timestamp - interval '1 month')::date;
      v_prev_start := date_trunc('month', v_prev_end::timestamp)::date;
      v_label := 'Mois en cours';

    WHEN 'rolling_90' THEN
      v_n_start := v_anchor - 89;
      v_prev_end := v_n_start - 1;
      v_prev_start := v_prev_end - 89;
      v_label := '3 derniers mois';

    ELSE
      v_kind := 'rolling_28';
      v_n_start := v_anchor - 27;
      v_prev_end := v_n_start - 1;
      v_prev_start := v_prev_end - 27;
      v_label := '28 derniers jours';
  END CASE;

  v_days := (v_n_end - v_n_start + 1)::integer;

  RETURN QUERY SELECT
    v_kind,
    v_label,
    v_n_start,
    v_n_end,
    v_prev_start,
    v_prev_end,
    v_days,
    v_today,
    v_gsc_last,
    v_lag,
    v_lens;
END;
$$;

COMMENT ON FUNCTION public.cooked_period_bounds(text, text) IS
  'Bornes N/N-1 Paris. live=today ; gsc/cross=ancré sur gsc_last_data_day().';

REVOKE EXECUTE ON FUNCTION public.cooked_period_bounds(text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cooked_period_bounds(text, text) TO service_role;


-- ============================================================
-- 3. site_gsc_kpis_compare — zone Google
-- ============================================================
CREATE OR REPLACE FUNCTION public.site_gsc_kpis_compare(p_period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  period_kind            text,
  period_label_fr        text,
  period_n_start         date,
  period_n_end           date,
  paris_today            date,
  gsc_last_day           date,
  lag_days               integer,
  period_prev_start      date,
  period_prev_end        date,
  clicks_n               bigint,
  impressions_n          bigint,
  ctr_pct_n              numeric,
  position_avg_n         numeric,
  clicks_prev            bigint,
  impressions_prev       bigint,
  ctr_pct_prev           numeric,
  position_avg_prev      numeric,
  clicks_delta_pct       numeric,
  impressions_delta_pct  numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
  v_clicks_n  bigint;
  v_imp_n     bigint;
  v_clicks_p  bigint;
  v_imp_p     bigint;
  v_ctr_n     numeric;
  v_ctr_p     numeric;
  v_pos_n     numeric;
  v_pos_p     numeric;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind, 'gsc') LIMIT 1;

  SELECT
    coalesce(sum(g.clicks), 0)::bigint,
    coalesce(sum(g.impressions), 0)::bigint,
    CASE WHEN sum(g.impressions) > 0
         THEN round((100.0 * sum(g.clicks) / sum(g.impressions))::numeric, 2) ELSE NULL END,
    CASE WHEN sum(g.impressions) > 0
         THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2) ELSE NULL END
  INTO v_clicks_n, v_imp_n, v_ctr_n, v_pos_n
  FROM public.gsc_path_daily g
  WHERE g.day >= b.n_start AND g.day <= b.n_end;

  SELECT
    coalesce(sum(g.clicks), 0)::bigint,
    coalesce(sum(g.impressions), 0)::bigint,
    CASE WHEN sum(g.impressions) > 0
         THEN round((100.0 * sum(g.clicks) / sum(g.impressions))::numeric, 2) ELSE NULL END,
    CASE WHEN sum(g.impressions) > 0
         THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2) ELSE NULL END
  INTO v_clicks_p, v_imp_p, v_ctr_p, v_pos_p
  FROM public.gsc_path_daily g
  WHERE g.day >= b.prev_start AND g.day <= b.prev_end;

  RETURN QUERY SELECT
    b.period_kind_out,
    b.label_fr,
    b.n_start,
    b.n_end,
    b.paris_today,
    b.gsc_last_day,
    b.lag_days,
    b.prev_start,
    b.prev_end,
    v_clicks_n,
    v_imp_n,
    v_ctr_n,
    v_pos_n,
    v_clicks_p,
    v_imp_p,
    v_ctr_p,
    v_pos_p,
    CASE WHEN v_clicks_p > 0
         THEN round((100.0 * (v_clicks_n - v_clicks_p) / v_clicks_p)::numeric, 2) ELSE NULL END,
    CASE WHEN v_imp_p > 0
         THEN round((100.0 * (v_imp_n - v_imp_p) / v_imp_p)::numeric, 2) ELSE NULL END;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.site_gsc_kpis_compare(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_gsc_kpis_compare(text) TO service_role;


-- ============================================================
-- 4. cooked_pages_snapshot — zone Activité (Cooked pur)
-- ============================================================
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
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end
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

REVOKE EXECUTE ON FUNCTION public.cooked_pages_snapshot(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cooked_pages_snapshot(text, integer) TO service_role;

-- ============================================================
-- 5. Rebrancher RPCs — data_lens
-- ============================================================

-- site_kpis_compare → live
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

REVOKE EXECUTE ON FUNCTION public.site_kpis_compare(text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_kpis_compare(text) TO service_role;
