-- T-03 (mission 02/09/2026, issue #104) — constats d-01 (P0) et d-04 (P1), invariant I5 (contrat d'unités).
-- 1. behavior_pages_for_period : bounce_rate re-divisé par 100 (fraction déjà 0-1) et bounce_rate_pct recevant la
--    fraction — 100× trop faibles depuis le 26/07/2026. Corrigé.
-- 2. cooked_bounce_rate : même nom, deux unités (0,2298 dans gsc_page_performance, 32,08 dans pages_overview_unified
--    chemin rapide, 1,0000 dans son chemin lent). Unifié en pourcentage 0-100 (= seo_url_snapshot).
-- 3. seo_pages_overview : les sessions à referrer spam entraient dans le dénominateur du rebond (ss/entry_exit)
--    sans être des rebonds (1 pageview + ticks ≥ 10 s) — cause de l'écart résiduel 21,7 % vs 32,1 %.
-- 4. run_rpc_contract_tests : quatre contrats d'unités (exact 0 ligne en violation).
-- Restatement : behavior_pages_for_period (×100, contract-tests + ad-hoc ; le dashboard ne la lit pas),
-- gsc_page_performance.cooked_bounce_rate (×100 + hors bot), pages_overview_unified chemin lent (×100).
-- Annotation posée le jour de l'application.

CREATE OR REPLACE FUNCTION public.behavior_pages_for_period(date_from timestamp with time zone, date_to timestamp with time zone)
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
    coalesce(round(b.bounce_rate, 4), 0),      -- T-03 (d-01) : fraction 0-1 déjà produite par seo_pages_overview
    coalesce(round(b.bounce_rate_pct, 2), 0),  -- T-03 (d-01) : pourcentage 0-100
    b.scroll_avg, b.scroll_complete_pct,
    cwv.lcp_p75, cwv.inp_p75, cwv.cls_p75, cwv.ttfb_p75,
    coalesce(oc.clicks, 0)::bigint
  FROM base b
  LEFT JOIN per_path_session_stats pp ON pp.path = b.path
  LEFT JOIN cwv ON cwv.path = b.path
  LEFT JOIN oc ON oc.path = b.path;
$function$;

CREATE OR REPLACE FUNCTION public.seo_pages_overview(date_from timestamp with time zone, date_to timestamp with time zone DEFAULT now())
 RETURNS TABLE(path text, views bigint, unique_visitors bigint, sessions bigint, bounce_rate numeric, bounce_rate_pct numeric, avg_dwell_seconds numeric, scroll_avg numeric, scroll_median numeric, scroll_complete_pct numeric, entry_count bigint, exit_count bigint, outbound_clicks bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH we AS (
    SELECT * FROM public.events_human
    WHERE occurred_at >= date_from AND occurred_at < date_to
      -- T-03 (d-04) : les sessions à referrer spam (bot Baidu, UA 'pc') sortaient déjà de pv mais pas de ss :
      -- 99 entrées sur 152 pour /honoraires-rendez-vous étaient le bot (03/09/2026), d'où 21,7 % vs 32,1 % de rebond.
      AND NOT public.cooked_is_spam_referrer(referrer_hostname)
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

CREATE OR REPLACE FUNCTION public.gsc_page_performance(target_path text, period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_views bigint, cooked_unique_visitors bigint, cooked_bounce_rate numeric, cooked_dwell_avg_s numeric, cooked_scroll_median numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, cooked_google_sessions bigint, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, top_referrer text, device_split jsonb)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    cooked.bounce_rate_pct,   -- T-03 (d-04) : même unité (0-100) que pages_overview_unified et seo_url_snapshot
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
$function$;

CREATE OR REPLACE FUNCTION public.pages_overview_unified(period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 1000)
 RETURNS TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_dwell_avg_s numeric, cooked_bounce_rate numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, has_cooked_data boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    c.bounce_rate_pct,   -- T-03 (d-04) : chemin lent aligné sur le chemin rapide (0-100)
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
$function$;

CREATE OR REPLACE FUNCTION public.run_rpc_contract_tests()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '900s'
AS $function$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('snapshot_pages_export',
       $q$select count(*) from public.snapshot_pages_export() where refreshed_at is not null$q$,
       1, NULL),

      ('site_context_export',
       $q$select count(*) from public.site_context_export() where global_sessions_28d > 0$q$,
       NULL, 1),

      ('cta_breakdown_for_path',
       $q$select count(*) from public.cta_breakdown_for_path('/', 28)
          where cta_type in ('phone', 'email', 'booking')
            and placement in ('header', 'footer', 'body', 'sticky')$q$,
       NULL, NULL),

      ('outbound_destinations_for_path',
       $q$select count(*) from public.outbound_destinations_for_path('/', 28)$q$,
       NULL, NULL),

      ('behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())$q$,
       NULL, NULL),

      ('engagement_density_for_path',
       $q$select count(*) from public.engagement_density_for_path('/', 28)$q$,
       NULL, NULL),

      ('tracker_first_seen_global',
       $q$select count(*) from (select public.tracker_first_seen_global() v) s where s.v is not null$q$,
       NULL, 1),

      ('refresh_pipeline_health',
       $q$select count(*) from public.refresh_pipeline_health()$q$,
       NULL, 1),

      -- Ajoute le 28/07/2026 : le module Lecture (CONTEXT.md § Lecture).
      -- Cout d'ajout d'un test au contrat : une ligne. C'etait tout l'objet
      -- de ce depliage. `source` doit rester 'page_exit' tant que la
      -- reconstruction engagement_tick n'est pas decidee et annotee.
      ('page_reads',
       $q$select count(*) from public.page_reads(7) where source = 'page_exit'$q$,
       1, NULL),

      -- T-03 (mission 02/09/2026, invariant I5) : contrat d'unités — *_rate ∈ [0,1], *_pct ∈ [0,100],
      -- et un même nom de colonne = une même unité. exact_rows = 0 : aucune ligne ne doit violer.
      ('units_behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),

      ('units_seo_pages_overview',
       $q$select count(*) from public.seo_pages_overview(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),

      ('units_cooked_bounce_rate_range',
       $q$select count(*) from (
            select cooked_bounce_rate from public.gsc_page_performance('/', 'rolling_28')
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u where cooked_bounce_rate > 100 or cooked_bounce_rate < 0$q$,
       NULL, 0),

      -- Un lot de ≥ 20 pages dont le max ≤ 1 = une fraction 0-1 publiée sous un nom en pourcentage.
      ('units_cooked_bounce_rate_unit',
       $q$select case when count(*) >= 20 and max(cooked_bounce_rate) <= 1 then 1 else 0 end from (
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u$q$,
       NULL, 0)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;

  -- Retention 90j
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;
