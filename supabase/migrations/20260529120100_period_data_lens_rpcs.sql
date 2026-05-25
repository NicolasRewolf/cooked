-- RPC rewire data_lens (part 2)

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

DROP FUNCTION IF EXISTS public.gsc_pages_compare(text);
CREATE OR REPLACE FUNCTION public.gsc_pages_compare(period_kind text DEFAULT 'rolling_28', data_lens text DEFAULT 'gsc')
RETURNS TABLE (
  path                    text,
  clicks_n                bigint,
  clicks_prev             bigint,
  clicks_delta_pct        numeric,
  impressions_n           bigint,
  impressions_prev        bigint,
  impressions_delta_pct   numeric,
  position_avg_n          numeric,
  position_avg_prev       numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, data_lens) LIMIT 1;

  RETURN QUERY
  WITH n_agg AS (
    SELECT g.path AS p,
      sum(g.clicks)::bigint AS clicks_total,
      sum(g.impressions)::bigint AS imp_total,
      CASE WHEN sum(g.impressions) > 0
           THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
           ELSE NULL END AS position_avg
    FROM public.gsc_path_daily g
    WHERE g.day >= b.n_start AND g.day <= b.n_end
    GROUP BY g.path
  ),
  prev_agg AS (
    SELECT g.path AS p,
      sum(g.clicks)::bigint AS clicks_total,
      sum(g.impressions)::bigint AS imp_total,
      CASE WHEN sum(g.impressions) > 0
           THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
           ELSE NULL END AS position_avg
    FROM public.gsc_path_daily g
    WHERE g.day >= b.prev_start AND g.day <= b.prev_end
    GROUP BY g.path
  ),
  paths AS (SELECT n_agg.p FROM n_agg UNION SELECT prev_agg.p FROM prev_agg)
  SELECT
    paths.p,
    coalesce(n.clicks_total, 0),
    coalesce(pr.clicks_total, 0),
    CASE WHEN coalesce(pr.clicks_total, 0) > 0
         THEN round((100.0 * (coalesce(n.clicks_total, 0) - pr.clicks_total) / pr.clicks_total)::numeric, 2)
         ELSE NULL END,
    coalesce(n.imp_total, 0),
    coalesce(pr.imp_total, 0),
    CASE WHEN coalesce(pr.imp_total, 0) > 0
         THEN round((100.0 * (coalesce(n.imp_total, 0) - pr.imp_total) / pr.imp_total)::numeric, 2)
         ELSE NULL END,
    n.position_avg,
    pr.position_avg
  FROM paths
    LEFT JOIN n_agg n ON n.p = paths.p
    LEFT JOIN prev_agg pr ON pr.p = paths.p;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.gsc_pages_compare(text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_pages_compare(text, text) TO service_role;


DROP FUNCTION IF EXISTS public.cooked_pages_compare(text);
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

REVOKE EXECUTE ON FUNCTION public.cooked_pages_compare(text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cooked_pages_compare(text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.pages_pulse(
  period_kind           text DEFAULT 'rolling_28',
  delta_threshold_pct   numeric DEFAULT 5.0
)
RETURNS TABLE (
  path                        text,
  gsc_clicks_n                bigint,
  gsc_clicks_prev             bigint,
  gsc_delta_pct               numeric,
  cooked_sessions_n           bigint,
  cooked_sessions_prev        bigint,
  cooked_sessions_delta_pct   numeric,
  quadrant                    text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH g AS (
    SELECT gpc.*,
      CASE
        WHEN gpc.clicks_delta_pct IS NULL THEN 'flat'
        WHEN gpc.clicks_delta_pct >=  delta_threshold_pct THEN 'up'
        WHEN gpc.clicks_delta_pct <= -delta_threshold_pct THEN 'down'
        ELSE 'flat'
      END AS gsc_dir
    FROM public.gsc_pages_compare(period_kind, 'cross') gpc
  ),
  c AS (
    SELECT cpc.*,
      CASE
        WHEN cpc.sessions_delta_pct IS NULL THEN 'flat'
        WHEN cpc.sessions_delta_pct >=  delta_threshold_pct THEN 'up'
        WHEN cpc.sessions_delta_pct <= -delta_threshold_pct THEN 'down'
        ELSE 'flat'
      END AS cooked_dir
    FROM public.cooked_pages_compare(period_kind, 'cross') cpc
  ),
  pp AS (SELECT g.path AS p FROM g UNION SELECT c.path FROM c)
  SELECT
    pp.p,
    coalesce(g.clicks_n, 0),
    coalesce(g.clicks_prev, 0),
    g.clicks_delta_pct,
    coalesce(c.sessions_n, 0),
    c.sessions_prev,
    c.sessions_delta_pct,
    public.pulse_status(
      coalesce(g.clicks_n, 0),
      coalesce(g.clicks_prev, 0),
      coalesce(c.sessions_n, 0),
      c.sessions_prev,
      delta_threshold_pct
    )
  FROM pp
    LEFT JOIN g ON g.path = pp.p
    LEFT JOIN c ON c.path = pp.p;
$$;

REVOKE EXECUTE ON FUNCTION public.pages_pulse(text, numeric) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_pulse(text, numeric) TO service_role;

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
  v_first_seen := (public.tracker_first_seen_global() AT TIME ZONE 'Europe/Paris')::date;
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
  WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
    AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end;

  IF v_has_prev THEN
    SELECT count(DISTINCT session_id) FILTER (
             WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
           )::bigint INTO v_ck_prev
    FROM public.events_human
    WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.prev_start
      AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.prev_end;
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

REVOKE EXECUTE ON FUNCTION public.site_pulse(text, numeric) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_pulse(text, numeric) TO service_role;

-- Pages avec contacts sur la fenêtre — léger pour la home dashboard (évite pages_overview_unified).

CREATE OR REPLACE FUNCTION public.top_contact_pages(
  p_period_kind text DEFAULT 'rolling_28',
  max_rows        integer DEFAULT 10
)
RETURNS TABLE (
  path                  text,
  cooked_contacts       bigint,
  cooked_phone_clicks   bigint,
  cooked_form_submits   bigint,
  gsc_clicks            bigint,
  cooked_sessions       bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1
  ),
  mc AS (
    SELECT m.path, m.contacts, m.phone_clicks, m.form_submits
    FROM public.macro_contacts_by_path(
      (SELECT n_start FROM b),
      (SELECT n_end FROM b)
    ) m
    WHERE m.contacts > 0
    ORDER BY m.contacts DESC, m.path
    LIMIT max_rows
  ),
  gsc AS (
    SELECT g.path, sum(g.clicks)::bigint AS clicks_total
    FROM public.gsc_path_daily g
    INNER JOIN mc ON mc.path = g.path
    CROSS JOIN b
    WHERE g.day >= b.n_start AND g.day <= b.n_end
    GROUP BY g.path
  )
  SELECT
    mc.path,
    mc.contacts,
    mc.phone_clicks,
    mc.form_submits,
    coalesce(gsc.clicks_total, 0),
    coalesce(
      CASE
        WHEN lower(trim(coalesce(p_period_kind, 'rolling_28'))) = 'rolling_90'
          THEN s.sessions_90d
        ELSE s.sessions_28d
      END,
      0
    )::bigint
  FROM mc
  LEFT JOIN gsc ON gsc.path = mc.path
  LEFT JOIN public.seo_url_snapshot s ON s.path = mc.path;
$$;

COMMENT ON FUNCTION public.top_contact_pages(text, integer) IS
  'Top pages avec au moins 1 contact macro sur la période (home dashboard).';

REVOKE EXECUTE ON FUNCTION public.top_contact_pages(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.top_contact_pages(text, integer) TO service_role;


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
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1
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

CREATE OR REPLACE FUNCTION public.gsc_top_queries_global(
  period_kind text DEFAULT 'rolling_28',
  max_rows    integer DEFAULT 100
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
  click_yield_pct    numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(period_kind, 'gsc') LIMIT 1
  ),
  b AS (SELECT n_start, n_end, day_count FROM bounds),
  window_data AS (
    SELECT q.query, q.path, q.clicks, q.impressions, q.position
    FROM public.gsc_query_page_daily q, b
    WHERE q.day >= b.n_start AND q.day <= b.n_end
  ),
  query_path AS (
    SELECT query, path,
      sum(clicks)::bigint AS path_clicks,
      sum(impressions)::bigint AS path_impressions
    FROM window_data
    GROUP BY query, path
  ),
  query_agg AS (
    SELECT query,
      sum(clicks)::bigint AS clicks_total,
      sum(impressions)::bigint AS impressions_total,
      count(DISTINCT path)::int AS nb_pages,
      CASE WHEN sum(impressions) > 0
           THEN round((sum(position * impressions) / sum(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN sum(impressions) > 0
           THEN round((100.0 * sum(clicks) / sum(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM window_data
    GROUP BY query
  ),
  top_per_query AS (
    SELECT DISTINCT ON (query) query, path AS top_page, path_clicks AS top_clicks
    FROM query_path
    ORDER BY query, path_clicks DESC
  )
  SELECT
    a.query,
    a.clicks_total,
    a.impressions_total,
    a.position_avg,
    a.ctr_pct,
    a.nb_pages,
    tp.top_page,
    tp.top_clicks,
    dfs.search_volume,
    dfs.cpc,
    CASE WHEN dfs.search_volume > 0
         THEN round((100.0 * a.clicks_total / (dfs.search_volume::numeric * b.day_count / 30.0))::numeric, 2)
         ELSE NULL END
  FROM query_agg a
    CROSS JOIN b
    LEFT JOIN top_per_query tp ON tp.query = a.query
    LEFT JOIN dfs_keyword_volume dfs
      ON dfs.keyword = a.query AND dfs.location_code = 2250
  ORDER BY a.clicks_total DESC, a.impressions_total DESC
  LIMIT max_rows;
$$;

REVOKE EXECUTE ON FUNCTION public.gsc_top_queries_global(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_top_queries_global(text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.gsc_x_dfs_opportunities(
  min_volume          integer DEFAULT 100,
  position_min        numeric DEFAULT 5.0,
  position_max        numeric DEFAULT 15.0,
  period_kind         text DEFAULT 'rolling_28',
  max_rows            integer DEFAULT 30
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
  lost_potential       integer,
  top_page             text
)
STABLE
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(period_kind, 'cross') LIMIT 1
  ),
  b AS (SELECT n_start, n_end, day_count FROM bounds),
  our_perf AS (
    SELECT
      q.query,
      sum(q.clicks)::bigint AS clicks,
      sum(q.impressions)::bigint AS impressions,
      CASE WHEN sum(q.impressions) > 0
           THEN round((sum(q.position * q.impressions) / sum(q.impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN sum(q.impressions) > 0
           THEN round((100.0 * sum(q.clicks) / sum(q.impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_query_daily q, b
    WHERE q.day >= b.n_start AND q.day <= b.n_end
      AND q.query IS NOT NULL
    GROUP BY q.query
  ),
  top_pages AS (
    SELECT DISTINCT ON (query) query, path
    FROM (
      SELECT query, path, sum(clicks) AS path_clicks
      FROM gsc_query_page_daily, b
      WHERE day >= b.n_start AND day <= b.n_end
      GROUP BY query, path
    ) x
    ORDER BY query, path_clicks DESC
  )
  SELECT
    op.query,
    op.position_avg AS our_position,
    op.clicks AS our_clicks,
    op.impressions AS our_impressions,
    op.ctr_pct AS our_ctr_pct,
    dfs.search_volume AS volume_fr,
    dfs.cpc,
    (100 * ctr_for_position(1.0))::numeric AS estimated_ctr_pos_1,
    greatest(
      round((
        dfs.search_volume::numeric * b.day_count / 30.0
        * (ctr_for_position(1.0) - coalesce(ctr_for_position(op.position_avg), 0))
      ))::integer,
      0
    ) AS lost_potential,
    tp.path AS top_page
  FROM our_perf op
    CROSS JOIN b
    INNER JOIN dfs_keyword_volume dfs
      ON dfs.keyword = op.query AND dfs.location_code = 2250
    LEFT JOIN top_pages tp ON tp.query = op.query
  WHERE op.position_avg BETWEEN position_min AND position_max
    AND dfs.search_volume IS NOT NULL
    AND dfs.search_volume >= min_volume
  ORDER BY lost_potential DESC NULLS LAST
  LIMIT max_rows;
$$;

REVOKE EXECUTE ON FUNCTION public.gsc_x_dfs_opportunities(integer, numeric, numeric, text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_x_dfs_opportunities(integer, numeric, numeric, text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.gsc_page_performance(
  target_path text,
  period_kind text DEFAULT 'rolling_28'
)
RETURNS TABLE (
  path                    text,
  gsc_clicks              bigint,
  gsc_impressions         bigint,
  gsc_position_avg        numeric,
  gsc_ctr_pct             numeric,
  cooked_sessions         bigint,
  cooked_views            bigint,
  cooked_unique_visitors  bigint,
  cooked_bounce_rate      numeric,
  cooked_dwell_avg_s      numeric,
  cooked_scroll_median    numeric,
  cooked_phone_clicks     bigint,
  cooked_form_submits     bigint,
  cooked_contacts         bigint,
  cooked_booking_intent   bigint,
  cooked_pogo_rate        numeric,
  cooked_google_sessions  bigint,
  lcp_p75_ms              numeric,
  inp_p75_ms              numeric,
  cls_p75                 numeric,
  top_referrer            text,
  device_split            jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(period_kind, 'cross') LIMIT 1
  ),
  b AS (SELECT n_start, n_end FROM bounds),
  ts AS (
    SELECT
      (b.n_start::timestamp AT TIME ZONE 'Europe/Paris') AS date_from,
      ((b.n_end + 1)::timestamp AT TIME ZONE 'Europe/Paris') AS date_to
    FROM b
  ),
  cp AS (SELECT public.canonical_path(target_path) AS p),
  g AS (
    SELECT
      coalesce(sum(gd.clicks), 0)::bigint AS clicks_total,
      coalesce(sum(gd.impressions), 0)::bigint AS impressions_total,
      CASE WHEN sum(gd.impressions) > 0
           THEN round((sum(gd.position * gd.impressions) / sum(gd.impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN sum(gd.impressions) > 0
           THEN round((100.0 * sum(gd.clicks) / sum(gd.impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM public.gsc_path_daily gd, cp, b
    WHERE gd.path = cp.p AND gd.day >= b.n_start AND gd.day <= b.n_end
  ),
  cooked AS (
    SELECT o.*
    FROM public.seo_pages_overview((SELECT date_from FROM ts), (SELECT date_to FROM ts)) o, cp
    WHERE o.path = cp.p
    LIMIT 1
  ),
  mc AS (
    SELECT m.*
    FROM public.macro_contacts_by_path((SELECT n_start FROM b), (SELECT n_end FROM b)) m, cp
    WHERE m.path = cp.p
  ),
  pogo AS (
    SELECT pr.pogo_rate
    FROM public.pogo_rates_for_period(
      (SELECT date_from FROM ts),
      (SELECT date_to FROM ts)
    ) pr, cp
    WHERE pr.path = cp.p
    LIMIT 1
  ),
  google_sess AS (
    SELECT count(DISTINCT e.session_id)::bigint AS n
    FROM public.events_human e, cp, b, ts
    WHERE e.path = cp.p
      AND e.name = 'pageview'
      AND e.device_type IS DISTINCT FROM 'server'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      AND (
        e.referrer_hostname LIKE '%google.%'
        OR (e.utm_source = 'google' AND e.utm_medium IN ('organic', 'cpc'))
      )
  ),
  ref_top AS (
    SELECT e.referrer_hostname AS ref, count(*) AS cnt
    FROM public.events_human e, cp, ts
    WHERE e.path = cp.p AND e.name = 'pageview'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      AND e.referrer_hostname IS NOT NULL
    GROUP BY e.referrer_hostname
    ORDER BY cnt DESC
    LIMIT 1
  ),
  dev AS (
    SELECT jsonb_object_agg(device_type, cnt) AS split
    FROM (
      SELECT coalesce(e.device_type, 'unknown') AS device_type, count(*)::bigint AS cnt
      FROM public.events_human e, cp, ts
      WHERE e.path = cp.p AND e.name = 'pageview'
        AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      GROUP BY e.device_type
    ) d
  ),
  cwv AS (
    SELECT
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'LCP') AS lcp,
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'INP') AS inp,
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'CLS') AS cls
    FROM public.events_human e, cp, ts
    WHERE e.path = cp.p AND e.name = 'web_vitals'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
  )
  SELECT
    cp.p,
    coalesce(g.clicks_total, 0),
    coalesce(g.impressions_total, 0),
    g.position_avg,
    g.ctr_pct,
    coalesce(cooked.sessions, 0),
    coalesce(cooked.views, 0),
    coalesce(cooked.unique_visitors, 0),
    cooked.bounce_rate,
    cooked.avg_dwell_seconds,
    cooked.scroll_median,
    coalesce(mc.phone_clicks, 0),
    coalesce(mc.form_submits, 0),
    coalesce(mc.contacts, 0),
    coalesce(mc.booking_intent, 0),
    pogo.pogo_rate,
    coalesce(google_sess.n, 0),
    cwv.lcp,
    cwv.inp,
    cwv.cls,
    ref_top.ref,
    dev.split
  FROM cp
    LEFT JOIN g ON true
    LEFT JOIN cooked ON true
    LEFT JOIN mc ON true
    LEFT JOIN pogo ON true
    LEFT JOIN google_sess ON true
    LEFT JOIN ref_top ON true
    LEFT JOIN dev ON true
    LEFT JOIN cwv ON true;
$$;

REVOKE EXECUTE ON FUNCTION public.gsc_page_performance(text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_page_performance(text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.pages_overview_unified(
  period_kind text DEFAULT 'rolling_28',
  max_rows    integer DEFAULT 1000
)
RETURNS TABLE (
  path                    text,
  gsc_clicks              bigint,
  gsc_impressions         bigint,
  gsc_position_avg        numeric,
  gsc_ctr_pct             numeric,
  cooked_sessions         bigint,
  cooked_dwell_avg_s      numeric,
  cooked_bounce_rate      numeric,
  cooked_phone_clicks     bigint,
  cooked_form_submits     bigint,
  cooked_contacts         bigint,
  cooked_booking_intent   bigint,
  cooked_pogo_rate        numeric,
  has_cooked_data         boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_kind text := lower(trim(coalesce(period_kind, 'rolling_28')));
BEGIN
  -- ── Fast path : snapshot nocturne (évite seo_pages_overview sur tout events_human)
  IF v_kind IN ('rolling_28', 'rolling_90') THEN
    RETURN QUERY
    WITH b AS (
      SELECT * FROM public.cooked_period_bounds(v_kind, 'cross') LIMIT 1
    ),
    ranked AS (
      SELECT s.path
      FROM public.seo_url_snapshot s
      ORDER BY
        CASE WHEN v_kind = 'rolling_90'
             THEN coalesce(s.sessions_90d, 0)
             ELSE coalesce(s.sessions_28d, 0)
        END DESC,
        s.path
      LIMIT max_rows
    ),
    gsc AS (
      SELECT
        g.path,
        sum(g.impressions)::bigint AS impressions_total,
        sum(g.clicks)::bigint AS clicks_total,
        CASE WHEN sum(g.impressions) > 0
             THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
             ELSE NULL END AS position_avg,
        CASE WHEN sum(g.impressions) > 0
             THEN round((100.0 * sum(g.clicks) / sum(g.impressions))::numeric, 2)
             ELSE NULL END AS ctr_pct
      FROM public.gsc_path_daily g
      INNER JOIN ranked r ON r.path = g.path
      CROSS JOIN b
      WHERE g.day >= b.n_start AND g.day <= b.n_end
      GROUP BY g.path
    ),
    mc AS (
      SELECT m.*
      FROM public.macro_contacts_by_path(
        (SELECT n_start FROM b),
        (SELECT n_end FROM b)
      ) m
      INNER JOIN ranked r ON r.path = m.path
    )
    SELECT
      r.path,
      coalesce(g.clicks_total, 0)::bigint,
      coalesce(g.impressions_total, 0)::bigint,
      g.position_avg,
      g.ctr_pct,
      CASE WHEN v_kind = 'rolling_90'
           THEN coalesce(s.sessions_90d, 0)
           ELSE coalesce(s.sessions_28d, 0)
      END::bigint,
      CASE WHEN v_kind = 'rolling_90'
           THEN s.avg_dwell_seconds_90d
           ELSE s.avg_dwell_seconds_28d
      END,
      CASE WHEN v_kind = 'rolling_90'
           THEN s.bounce_rate_90d
           ELSE s.bounce_rate_28d
      END,
      coalesce(mc.phone_clicks, 0)::bigint,
      coalesce(mc.form_submits, 0)::bigint,
      coalesce(mc.contacts, 0)::bigint,
      coalesce(mc.booking_intent, 0)::bigint,
      CASE WHEN v_kind = 'rolling_90' THEN NULL::numeric ELSE s.pogo_rate_28d END,
      (
        CASE WHEN v_kind = 'rolling_90'
             THEN coalesce(s.sessions_90d, 0)
             ELSE coalesce(s.sessions_28d, 0)
        END > 0
      )
    FROM ranked r
    INNER JOIN public.seo_url_snapshot s ON s.path = r.path
    LEFT JOIN gsc g ON g.path = r.path
    LEFT JOIN mc ON mc.path = r.path
    ORDER BY
      CASE WHEN v_kind = 'rolling_90'
           THEN coalesce(s.sessions_90d, 0)
           ELSE coalesce(s.sessions_28d, 0)
      END DESC,
      coalesce(g.clicks_total, 0) DESC,
      r.path;
    RETURN;
  END IF;

  -- ── Dynamic path (today / week / month) — fenêtre courte, pas de union snapshot
  RETURN QUERY
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(v_kind, 'cross') LIMIT 1
  ),
  b AS (SELECT n_start, n_end FROM bounds),
  ts AS (
    SELECT
      (b.n_start::timestamp AT TIME ZONE 'Europe/Paris') AS date_from,
      ((b.n_end + 1)::timestamp AT TIME ZONE 'Europe/Paris') AS date_to
    FROM b
  ),
  gsc_n AS (
    SELECT * FROM public.gsc_path_metrics((SELECT n_start FROM b), (SELECT n_end FROM b))
  ),
  cooked AS (
    SELECT o.* FROM public.seo_pages_overview(
      (SELECT date_from FROM ts),
      (SELECT date_to FROM ts)
    ) o
  ),
  ranked_paths AS (
    SELECT coalesce(c.path, g.path) AS path
    FROM cooked c
    FULL OUTER JOIN gsc_n g ON g.path = c.path
    ORDER BY coalesce(c.sessions, 0) DESC, coalesce(g.clicks_total, 0) DESC, coalesce(c.path, g.path)
    LIMIT max_rows
  ),
  pogo AS (
    SELECT p.path, p.pogo_rate
    FROM public.pogo_rates_for_period(
      (SELECT date_from FROM ts),
      (SELECT date_to FROM ts)
    ) p
    INNER JOIN ranked_paths rp ON rp.path = p.path
  ),
  mc AS (
    SELECT m.*
    FROM public.macro_contacts_by_path(
      (SELECT n_start FROM b),
      (SELECT n_end FROM b)
    ) m
    INNER JOIN ranked_paths rp ON rp.path = m.path
  )
  SELECT
    rp.path,
    coalesce(g.clicks_total, 0),
    coalesce(g.impressions_total, 0),
    g.position_avg,
    g.ctr_pct,
    coalesce(c.sessions, 0),
    c.avg_dwell_seconds,
    c.bounce_rate,
    coalesce(mc.phone_clicks, 0),
    coalesce(mc.form_submits, 0),
    coalesce(mc.contacts, 0),
    coalesce(mc.booking_intent, 0),
    pg.pogo_rate,
    (c.path IS NOT NULL)
  FROM ranked_paths rp
    LEFT JOIN gsc_n g ON g.path = rp.path
    LEFT JOIN cooked c ON c.path = rp.path
    LEFT JOIN pogo pg ON pg.path = rp.path
    LEFT JOIN mc ON mc.path = rp.path
  ORDER BY coalesce(c.sessions, 0) DESC, coalesce(g.clicks_total, 0) DESC, rp.path;
END;
$$;

COMMENT ON FUNCTION public.pages_overview_unified(text, integer) IS
  'v7 perf (28/05/2026) : rolling_28/90 via seo_url_snapshot + GSC filtré top N ; autres périodes sans union exhaustive all_paths.';

REVOKE EXECUTE ON FUNCTION public.pages_overview_unified(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_overview_unified(text, integer) TO service_role;

DROP FUNCTION IF EXISTS public.gsc_page_daily_series(text, integer);
CREATE OR REPLACE FUNCTION public.gsc_page_daily_series(
  target_path text,
  days_back   integer,
  end_date    date DEFAULT NULL
)
RETURNS TABLE (
  day      date,
  clicks   bigint
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
      coalesce(end_date, (now() at time zone 'Europe/Paris')::date) - (days_back - 1),
      coalesce(end_date, (now() at time zone 'Europe/Paris')::date),
      interval '1 day'
    ) gs
  )
  select
    s.day,
    coalesce(sum(g.clicks), 0)::bigint as clicks
  from series s
    left join public.gsc_path_daily g
      on g.day = s.day
     and g.path = (select p from cp)
  group by s.day
  order by s.day;
$$;

COMMENT ON FUNCTION public.gsc_page_daily_series(text, integer, date) IS
  'Sprint 33+ (24/05/2026) : série quotidienne clics GSC par page sur N jours (sparkline fiche page). Jours sans data = 0.';

REVOKE EXECUTE ON FUNCTION public.gsc_page_daily_series(text, integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_page_daily_series(text, integer, date) TO service_role;

DROP FUNCTION IF EXISTS public.cooked_page_daily_series(text, integer);
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
      coalesce(end_date, (now() at time zone 'Europe/Paris')::date) - (days_back - 1),
      coalesce(end_date, (now() at time zone 'Europe/Paris')::date),
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
      on (e.occurred_at at time zone 'Europe/Paris')::date = s.day
     and e.path = (select p from cp)
  group by s.day
  order by s.day;
$$;

COMMENT ON FUNCTION public.cooked_page_daily_series(text, integer, date) IS
  'Sprint 33+ (24/05/2026) : série quotidienne visites Cooked par page sur N jours (sparkline fiche page). Jours sans data = 0.';

REVOKE EXECUTE ON FUNCTION public.cooked_page_daily_series(text, integer, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cooked_page_daily_series(text, integer, date) TO service_role;
