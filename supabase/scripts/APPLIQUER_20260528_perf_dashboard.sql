-- Sprint 33+ (28/05/2026) — pages_overview_unified perf
-- Problème : all_paths = seo_url_snapshot ∪ tous paths GSC ∪ tous paths events
-- puis agrégats lourds AVANT le LIMIT → timeout Supabase (~8s).
-- Fix : fast path snapshot (rolling_28/90) + dynamic path sans union exhaustive.

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
      SELECT * FROM public.cooked_period_bounds(v_kind) LIMIT 1
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
    SELECT * FROM public.cooked_period_bounds(v_kind) LIMIT 1
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
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind) LIMIT 1
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
