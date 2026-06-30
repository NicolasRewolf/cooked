-- Dashboard V1 — séries journalières (sparklines KPI + graphe principal). 30/06/2026.
-- Approche B (précalcul) : refresh_dashboard_snapshots peuple une petite table
-- dashboard_trend_snapshot (1 ligne/fenêtre, arrays oldest→newest) lue par le RPC
-- dashboard_resources_trend. Active les visuels de la PR redesign-instrument.
-- Re-verrouille aussi dashboard_seo_by_query (ACL ré-ouverte à PUBLIC par le
-- DROP+CREATE du lot pilotage — régression corrigée ici).
-- NB : refresh_dashboard_snapshots est re-corrigé par 2 migrations suivantes
-- (alignement visitors_daily + perf contacts) ; ce fichier en est l'état initial.

-- 1) Table snapshot des séries journalières (RLS deny-all comme les autres snapshots)
CREATE TABLE IF NOT EXISTS public.dashboard_trend_snapshot (
  window_kind           text PRIMARY KEY,
  visitors_daily        numeric[] NOT NULL DEFAULT '{}',
  pageviews_daily       numeric[] NOT NULL DEFAULT '{}',
  contacts_daily        numeric[] NOT NULL DEFAULT '{}',
  gsc_clicks_daily      numeric[] NOT NULL DEFAULT '{}',
  gsc_impressions_daily numeric[] NOT NULL DEFAULT '{}',
  refreshed_at          timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dashboard_trend_snapshot ENABLE ROW LEVEL SECURITY;

-- 2) Refresh : peuple aussi les séries journalières par fenêtre
CREATE OR REPLACE FUNCTION public.refresh_dashboard_snapshots(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text;
  lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int;
  cpi_day date;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;

  DELETE FROM public.dashboard_resources_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_kpis_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_trend_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    SELECT label_fr, n_start, n_end, prev_start, prev_end, paris_today, day_count
      INTO lbl, lns, lne, lps, lpe, lpt, ld FROM cooked_period_bounds(w,'live');
    SELECT n_start, n_end, prev_start, prev_end, gsc_last_day, lag_days
      INTO gns, gne, gps, gpe, glast, glag FROM cooked_period_bounds(w,'gsc');

    DROP TABLE IF EXISTS _ev;
    CREATE TEMP TABLE _ev ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.referrer_hostname AS ref,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        (e.occurred_at AT TIME ZONE 'Europe/Paris')::date AS d
      FROM events e
      JOIN page_taxonomy pt ON pt.path = e.path AND pt.category='ressource'
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
        AND e.occurred_at >= (lps::timestamp AT TIME ZONE 'Europe/Paris')
        AND e.occurred_at <  ((lne + 1)::timestamp AT TIME ZONE 'Europe/Paris');

    DROP TABLE IF EXISTS _evc;
    CREATE TEMP TABLE _evc ON COMMIT DROP AS
      SELECT * FROM _ev
      WHERE NOT EXISTS (SELECT 1 FROM bot_fingerprints bf WHERE bf.anonymous_id=_ev.anonymous_id)
        AND NOT EXISTS (SELECT 1 FROM noise_sessions ns WHERE ns.session_id=_ev.session_id);
    ANALYZE _evc;

    INSERT INTO public.dashboard_resources_snapshot
    WITH res AS (SELECT pt.path, pt.theme FROM page_taxonomy pt WHERE pt.category='ressource'),
    cooked AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY dur)
          FILTER (WHERE name='page_exit' AND d BETWEEN lns AND lne AND ref NOT ILIKE '%linkedin%' AND ref NOT ILIKE '%facebook%')) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY scr)
          FILTER (WHERE name='page_exit' AND d BETWEEN lns AND lne AND ref NOT ILIKE '%linkedin%' AND ref NOT ILIKE '%facebook%')) AS scroll
      FROM _evc GROUP BY path
    ),
    gsc AS (SELECT m.path, m.clicks_total, m.impressions_total, m.position_avg, m.ctr_pct
            FROM gsc_path_metrics(gns,gne) m JOIN res ON res.path=m.path),
    gscp AS (SELECT m.path, m.clicks_total AS clicks_prev
             FROM gsc_path_metrics(gps,gpe) m JOIN res ON res.path=m.path),
    cpi_d AS (SELECT path, cpi, grade, momentum FROM cpi_daily WHERE day = cpi_day),
    gis AS (SELECT path, potentiel, convertit FROM cpi_gisement),
    bestq AS (
      SELECT DISTINCT ON (q.path) q.path, q.query, q.clicks FROM (
        SELECT qp.path, qp.query, SUM(qp.clicks) clicks, SUM(qp.impressions) impr
        FROM gsc_query_page_daily qp JOIN res ON res.path=qp.path
        WHERE qp.day BETWEEN gns AND gne AND qp.query NOT ILIKE '%plouton%'
        GROUP BY qp.path, qp.query) q
      ORDER BY q.path, q.clicks DESC, q.impr DESC
    ),
    contacts AS (SELECT mc.path, mc.contacts, mc.booking_intent
                 FROM macro_contacts_by_path(lns,lne) mc JOIN res ON res.path=mc.path),
    fi AS (SELECT g.path, MIN(g.day) first_impr FROM gsc_path_daily g
           WHERE g.impressions>0 AND g.path IN (SELECT path FROM res) GROUP BY g.path),
    fv AS (SELECT e.path, MIN((e.occurred_at AT TIME ZONE 'Europe/Paris')::date) first_view
           FROM events e
           WHERE e.name='pageview' AND e.path IN (SELECT path FROM res)
             AND NOT EXISTS (SELECT 1 FROM bot_fingerprints bf WHERE bf.anonymous_id=e.anonymous_id)
             AND NOT EXISTS (SELECT 1 FROM noise_sessions ns WHERE ns.session_id=e.session_id)
           GROUP BY e.path)
    SELECT w, res.path, res.theme,
      COALESCE(c.uv,0), COALESCE(c.pv,0), c.dwell, c.scroll,
      COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
      bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
      COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
      fi.first_impr, fv.first_view,
      (lpt - LEAST(COALESCE(fi.first_impr,fv.first_view), COALESCE(fv.first_view,fi.first_impr)))::int,
      CASE WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 1.5 THEN 'A'
           WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 0.5 THEN 'B' ELSE 'C' END,
      lns, lne, gns, gne, now(),
      COALESCE(c.uv_prev,0)::int,
      COALESCE(gp.clicks_prev,0)::int,
      cd.cpi,
      cd.grade,
      cd.momentum,
      gi.potentiel,
      gi.convertit,
      CASE WHEN g.position_avg IS NOT NULL THEN ROUND(ctr_for_position(g.position_avg)*100, 2) END
    FROM res
    LEFT JOIN cooked c ON c.path=res.path
    LEFT JOIN gsc g ON g.path=res.path
    LEFT JOIN gscp gp ON gp.path=res.path
    LEFT JOIN cpi_d cd ON cd.path=res.path
    LEFT JOIN gis gi ON gi.path=res.path
    LEFT JOIN bestq bq ON bq.path=res.path
    LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=bq.query AND dfs.location_code=2250
    LEFT JOIN contacts ct ON ct.path=res.path
    LEFT JOIN fi ON fi.path=res.path
    LEFT JOIN fv ON fv.path=res.path;

    INSERT INTO public.dashboard_kpis_snapshot
      (window_kind, label_fr, cooked_start, cooked_end, gsc_start, gsc_end, gsc_last_day, lag_days,
       is_partial, visitors_n, visitors_prev, pageviews_n, pageviews_prev, contacts_n, contacts_prev,
       gsc_clicks_n, gsc_clicks_prev, gsc_impressions_n, gsc_impressions_prev, refreshed_at,
       current_day_partial, no_prev_baseline)
    SELECT w, lbl, lns, lne, gns, gne, glast, glag,
      ((lne >= lpt) OR (tracker_first_seen_global() > lpe::timestamptz)),
      (SELECT COUNT(DISTINCT anonymous_id) FROM _evc WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(DISTINCT anonymous_id) FROM _evc WHERE d BETWEEN lps AND lpe),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lps AND lpe),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lns,lne) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lps,lpe) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      now(),
      (lne >= lpt),
      (tracker_first_seen_global() > lpe::timestamptz);

    -- Séries journalières (arrays oldest→newest, 0 sur les jours sans donnée)
    INSERT INTO public.dashboard_trend_snapshot
      (window_kind, visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily, refreshed_at)
    SELECT w,
      (SELECT array_agg(COALESCE(v.uv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(DISTINCT anonymous_id) uv FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) v ON v.d = ds.d),
      (SELECT array_agg(COALESCE(p.pv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(*) pv FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) p ON p.d = ds.d),
      (SELECT array_agg(COALESCE(ct.ct,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (
           SELECT (e.occurred_at AT TIME ZONE 'Europe/Paris')::date d, COUNT(*) ct
           FROM events_human e JOIN page_taxonomy pt ON pt.path=e.path AND pt.category='ressource'
           WHERE (e.name='cta_phone_click' OR (e.name='form_submit' AND form_submit_counts_as_macro(e.props)))
             AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date BETWEEN lns AND lne
           GROUP BY 1
         ) ct ON ct.d = ds.d),
      (SELECT array_agg(COALESCE(gd.clicks,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT day, SUM(clicks) clicks FROM gsc_path_daily
                    WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM page_taxonomy WHERE category='ressource') GROUP BY day) gd ON gd.day = ds.d),
      (SELECT array_agg(COALESCE(gd.impr,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT day, SUM(impressions) impr FROM gsc_path_daily
                    WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM page_taxonomy WHERE category='ressource') GROUP BY day) gd ON gd.day = ds.d),
      now();
  END LOOP;
END $function$;

-- 3) RPC de lecture (verrouillé service_role)
CREATE OR REPLACE FUNCTION public.dashboard_resources_trend(period_kind text DEFAULT 'rolling_90')
 RETURNS TABLE(visitors_daily numeric[], pageviews_daily numeric[], contacts_daily numeric[], gsc_clicks_daily numeric[], gsc_impressions_daily numeric[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily
  FROM public.dashboard_trend_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_resources_trend(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_resources_trend(text) TO service_role;

-- 4) Re-verrouille dashboard_seo_by_query (ACL ré-ouverte à PUBLIC par le DROP+CREATE précédent)
REVOKE ALL ON FUNCTION public.dashboard_seo_by_query(text,text,integer,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_seo_by_query(text,text,integer,integer) TO service_role;
