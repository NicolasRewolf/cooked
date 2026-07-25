-- Audit 25/07/2026 — finitions : Baidu centralisé, bounce_rate_pct, VACUUM nuit.
-- Note : temp_file_limit nécessite superuser — non disponible sur Supabase managé.

-- 2) Baidu : filtre central dans cooked_events_window (item 8)
CREATE OR REPLACE PROCEDURE public.cooked_events_window(
  IN p_occurred_from timestamptz,
  IN p_occurred_to   timestamptz,
  IN p_grain         text DEFAULT 'human',
  IN p_site          text DEFAULT 'main'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $procedure$
BEGIN
  IF p_grain NOT IN ('raw', 'clean', 'human') THEN
    RAISE EXCEPTION 'cooked_events_window: grain must be raw|clean|human, got %', p_grain;
  END IF;
  IF p_site NOT IN ('main', 'outremer') THEN
    RAISE EXCEPTION 'cooked_events_window: site must be main|outremer, got %', p_site;
  END IF;

  DROP TABLE IF EXISTS _cooked_ev;
  DROP TABLE IF EXISTS _cooked_ev_raw;

  IF p_grain = 'raw' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    END IF;

  ELSIF p_grain = 'clean' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          )
          AND NOT (
            e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
          );
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          )
          AND NOT (
            e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
          );
    END IF;

  ELSIF p_site = 'main' THEN
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at,
             public.paris_date(e.occurred_at) AS d
      FROM public.events_main e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to
        AND NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
        )
        AND NOT (
          e.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(e.props)
        )
        AND NOT (
          e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
        )
        AND NOT (
          e.name IN (
            'cta_phone_click', 'cta_booking_click', 'cta_anchor_click',
            'click_internal', 'click_outbound'
          )
          AND EXISTS (
            SELECT 1 FROM public.events_main dup
            WHERE dup.session_id = e.session_id
              AND dup.name = e.name
              AND dup.path IS NOT DISTINCT FROM e.path
              AND date_trunc('second', dup.occurred_at) = date_trunc('second', e.occurred_at)
              AND (dup.props->>'anchor') IS NOT DISTINCT FROM (e.props->>'anchor')
              AND dup.id < e.id
          )
        );

  ELSE
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at,
             public.paris_date(e.occurred_at) AS d
      FROM public.events_outremer e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to
        AND NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
        )
        AND NOT (
          e.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(e.props)
        )
        AND NOT (
          e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
        );
  END IF;

  ANALYZE _cooked_ev;
END;
$procedure$;

-- Pulse : même contrat, filtre spam sur sessions Cooked
CREATE OR REPLACE FUNCTION public.site_pulse(
  p_period_kind text DEFAULT 'rolling_28',
  delta_threshold_pct numeric DEFAULT 5.0
)
 RETURNS TABLE(
  period_kind text, period_label_fr text,
  gsc_period_start date, gsc_period_end date,
  cooked_period_start date, cooked_period_end date,
  gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_delta_pct numeric,
  cooked_sessions_n bigint, cooked_sessions_prev bigint, cooked_sessions_delta_pct numeric,
  quadrant text
)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
           WHERE name = 'pageview'
             AND device_type IS DISTINCT FROM 'server'
             AND NOT public.cooked_is_spam_referrer(referrer_hostname)
         )::bigint INTO v_ck_n
  FROM public.events_human
  WHERE public.paris_date(occurred_at) >= b.n_start
    AND public.paris_date(occurred_at) <= b.n_end;

  IF v_has_prev THEN
    SELECT count(DISTINCT session_id) FILTER (
             WHERE name = 'pageview'
               AND device_type IS DISTINCT FROM 'server'
               AND NOT public.cooked_is_spam_referrer(referrer_hostname)
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
    b.period_kind_out, b.label_fr, b.n_start, b.n_end, b.n_start, b.n_end,
    v_gsc_n, v_gsc_prev, v_gsc_delta, v_ck_n, v_ck_prev, v_ck_delta,
    public.pulse_status(v_gsc_n, v_gsc_prev, v_ck_n, v_ck_prev, delta_threshold_pct);
END;
$function$;

CREATE OR REPLACE FUNCTION public.cooked_pages_compare(
  period_kind text DEFAULT 'rolling_28',
  data_lens text DEFAULT 'cross'
)
 RETURNS TABLE(
  path text, sessions_n bigint, sessions_prev bigint, sessions_delta_pct numeric,
  contacts_n bigint, contacts_prev bigint, contacts_delta_pct numeric
)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        WHERE e.name = 'pageview'
          AND e.device_type IS DISTINCT FROM 'server'
          AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)
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
        WHERE e.name = 'pageview'
          AND e.device_type IS DISTINCT FROM 'server'
          AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)
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
$function$;

-- site_context_export : exclure sessions dont la 1re pageview est spam + bounce_rate_pct
DROP FUNCTION IF EXISTS public.site_context_export();
CREATE FUNCTION public.site_context_export()
 RETURNS TABLE(
  global_sessions_28d bigint,
  global_bounce_rate_28d numeric,
  sessions_per_day_median_28d numeric,
  sessions_trend_pct_7d_vs_28d numeric,
  top_sources_28d jsonb,
  global_bounce_rate_pct numeric
)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH first_pv AS (
    SELECT DISTINCT ON (e.session_id)
      e.session_id,
      e.referrer_hostname
    FROM public.events_human e
    WHERE e.name = 'pageview'
      AND e.occurred_at >= now() - interval '28 days'
    ORDER BY e.session_id, e.occurred_at
  ),
  spam_sess AS (
    SELECT session_id FROM first_pv
    WHERE public.cooked_is_spam_referrer(referrer_hostname)
  ),
  ss AS (
    SELECT e.session_id,
      min(e.occurred_at) AS session_start,
      max(e.occurred_at) AS session_end,
      count(*) FILTER (WHERE e.name = 'pageview') AS pages_viewed,
      max(e.referrer_hostname) AS referrer_hostname,
      max(e.utm_source) AS utm_source,
      max(e.utm_medium) AS utm_medium
    FROM public.events_human e
    WHERE e.occurred_at >= now() - interval '28 days'
      AND e.session_id NOT IN (SELECT session_id FROM spam_sess)
    GROUP BY e.session_id
  ),
  agg AS (
    SELECT count(*)::bigint AS s28_total,
      count(*) FILTER (WHERE session_start >= now() - interval '7 days')::bigint AS s7_total,
      count(*) FILTER (
        WHERE pages_viewed = 1
          AND extract(epoch FROM (session_end - session_start)) < 10
      )::numeric AS bounce_count
    FROM ss
  ),
  daily AS (
    SELECT date_trunc('day', session_start)::date AS day, count(*) AS n FROM ss GROUP BY 1
  ),
  median AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY n)::numeric AS v FROM daily
  ),
  sources AS (
    SELECT coalesce(utm_source, referrer_hostname, 'direct') AS source,
      coalesce(utm_medium, CASE WHEN referrer_hostname IS NULL THEN 'none' ELSE 'referral' END) AS medium,
      count(*)::bigint AS sessions
    FROM ss GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5
  ),
  top_sources AS (
    SELECT coalesce(
      jsonb_agg(
        jsonb_build_object('source', source, 'medium', medium, 'sessions', sessions)
        ORDER BY sessions DESC
      ),
      '[]'::jsonb
    ) AS top
    FROM sources
  )
  SELECT a.s28_total,
    coalesce(round(a.bounce_count / nullif(a.s28_total, 0), 4), 0) AS global_bounce_rate_28d,
    coalesce(round(m.v, 1), 0),
    coalesce(round(
      CASE WHEN a.s28_total > 0
        THEN 100.0 * ((a.s7_total::numeric / 7.0) - (a.s28_total::numeric / 28.0))
             / nullif((a.s28_total::numeric / 28.0), 0)
        ELSE 0 END, 2), 0),
    t.top,
    coalesce(round(100.0 * a.bounce_count / nullif(a.s28_total, 0), 2), 0) AS global_bounce_rate_pct
  FROM agg a, median m, top_sources t;
$function$;

REVOKE ALL ON FUNCTION public.site_context_export() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.site_context_export() TO service_role;

-- seo_pages_overview : spam + bounce_rate_pct explicite
DROP FUNCTION IF EXISTS public.seo_pages_overview(timestamptz, timestamptz);
CREATE FUNCTION public.seo_pages_overview(
  date_from timestamptz,
  date_to timestamptz DEFAULT now()
)
 RETURNS TABLE(
  path text, views bigint, unique_visitors bigint, sessions bigint,
  bounce_rate numeric, bounce_rate_pct numeric,
  avg_dwell_seconds numeric, scroll_avg numeric, scroll_median numeric,
  scroll_complete_pct numeric, entry_count bigint, exit_count bigint, outbound_clicks bigint
)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH we AS (
    SELECT * FROM public.events_human
    WHERE occurred_at >= date_from AND occurred_at < date_to
  ),
  pv AS (
    SELECT path,
      count(*) AS views,
      count(DISTINCT anonymous_id) AS unique_visitors,
      count(DISTINCT session_id) AS sessions
    FROM we
    WHERE name = 'pageview'
      AND path IS NOT NULL
      AND NOT public.cooked_is_spam_referrer(referrer_hostname)
    GROUP BY path
  ),
  ss AS (
    SELECT session_id,
      min(occurred_at) AS session_start,
      max(occurred_at) AS session_end,
      count(*) FILTER (WHERE name = 'pageview') AS pages_viewed,
      (array_agg(path ORDER BY occurred_at) FILTER (WHERE name = 'pageview'))[1] AS entry_path,
      (array_agg(path ORDER BY occurred_at DESC) FILTER (WHERE name = 'pageview'))[1] AS exit_path
    FROM we
    GROUP BY session_id
  ),
  sp AS (
    SELECT session_id, path,
      max((props->>'duration_seconds')::numeric) FILTER (WHERE name = 'page_exit') AS dwell,
      coalesce(max((props->>'percent')::numeric) FILTER (WHERE name = 'scroll_depth'), 0) AS max_scroll
    FROM we
    WHERE path IS NOT NULL
    GROUP BY session_id, path
  ),
  scroll_dwell AS (
    SELECT path,
      avg(dwell)::numeric AS avg_dwell,
      avg(max_scroll)::numeric AS scroll_avg,
      (percentile_cont(0.5) WITHIN GROUP (ORDER BY max_scroll))::numeric AS scroll_median,
      (100.0 * count(*) FILTER (WHERE max_scroll >= 100) / nullif(count(*), 0))::numeric AS scroll_complete_pct
    FROM sp
    GROUP BY path
  ),
  entry_exit AS (
    SELECT path,
      sum(is_entry)::bigint AS entry_count,
      sum(is_exit)::bigint AS exit_count,
      sum(is_bounce)::bigint AS bounce_count
    FROM (
      SELECT ss.entry_path AS path, 1 AS is_entry, 0 AS is_exit,
        CASE WHEN ss.pages_viewed = 1
              AND extract(epoch FROM (ss.session_end - ss.session_start)) < 10
             THEN 1 ELSE 0 END AS is_bounce
      FROM ss WHERE ss.entry_path IS NOT NULL
      UNION ALL
      SELECT ss.exit_path, 0, 1, 0 FROM ss WHERE ss.exit_path IS NOT NULL
    ) u
    GROUP BY path
  ),
  oc AS (
    SELECT path, count(*) AS clicks
    FROM we
    WHERE name = 'click_outbound' AND path IS NOT NULL
    GROUP BY path
  )
  SELECT pv.path,
    pv.views::bigint,
    pv.unique_visitors::bigint,
    pv.sessions::bigint,
    coalesce(round((100.0 * ee.bounce_count / nullif(ee.entry_count, 0))::numeric / 100.0, 4), 0) AS bounce_rate,
    coalesce(round((100.0 * ee.bounce_count / nullif(ee.entry_count, 0))::numeric, 2), 0) AS bounce_rate_pct,
    coalesce(round(sd.avg_dwell, 1), 0),
    coalesce(round(sd.scroll_avg, 1), 0),
    coalesce(round(sd.scroll_median, 1), 0),
    coalesce(round(sd.scroll_complete_pct, 1), 0),
    coalesce(ee.entry_count, 0)::bigint,
    coalesce(ee.exit_count, 0)::bigint,
    coalesce(oc.clicks, 0)::bigint
  FROM pv
  LEFT JOIN scroll_dwell sd ON sd.path = pv.path
  LEFT JOIN entry_exit ee ON ee.path = pv.path
  LEFT JOIN oc ON oc.path = pv.path;
$function$;

REVOKE ALL ON FUNCTION public.seo_pages_overview(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seo_pages_overview(timestamptz, timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.cooked_page_daily_series(
  target_path text,
  days_back integer,
  end_date date DEFAULT NULL::date
)
 RETURNS TABLE(day date, sessions bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cp AS (SELECT public.canonical_path(target_path) AS p),
  series AS (
    SELECT gs::date AS day
    FROM generate_series(
      coalesce(end_date, public.paris_today()) - (days_back - 1),
      coalesce(end_date, public.paris_today()),
      interval '1 day'
    ) gs
  )
  SELECT s.day,
    coalesce(
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview'
          AND e.device_type IS DISTINCT FROM 'server'
          AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)
      ),
      0
    )::bigint AS sessions
  FROM series s
  LEFT JOIN public.events_human e
    ON public.paris_date(e.occurred_at) = s.day
   AND e.path = (SELECT p FROM cp)
  GROUP BY s.day
  ORDER BY s.day;
$function$;

-- 3) VACUUM FULL planifié — 26/07/2026 04:00 Paris (= 02:00 UTC)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'events-vacuum-full-audit-20260726') THEN
    PERFORM cron.unschedule((SELECT jobid FROM cron.job WHERE jobname = 'events-vacuum-full-audit-20260726'));
  END IF;
END $$;

SELECT cron.schedule(
  'events-vacuum-full-audit-20260726',
  '0 2 26 7 *',
  $$VACUUM (FULL, ANALYZE) public.events;$$
);

INSERT INTO public.cooked_config (key, value)
VALUES ('events_vacuum_full_scheduled', '26/07/2026 04:00 Paris')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 4) Recalcul alertes CPI (post-correction momentum non-brandé)
UPDATE public.alerts SET acked = true
WHERE NOT acked AND kind = 'cpi_drop';

SELECT public.cooked_alerts_refresh();

INSERT INTO public.annotations (day, kind, label, paths)
SELECT public.paris_today(), 'site_change',
  'Finitions audit 26/07 : Baidu centralisé (cooked_events_window + pulse/context), VACUUM FULL events planifié 04h Paris.',
  NULL::text[]
WHERE NOT EXISTS (
  SELECT 1 FROM public.annotations
  WHERE day = public.paris_today()
    AND label LIKE 'Finitions audit 26/07%'
);
