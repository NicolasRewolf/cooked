-- dashboard_expertises_tab
-- Onglet « Expertises » : clone scopé cooked_page_type='expertise' de la Synthèse
-- (articles ressources). Spécificité CANAL — les pages expertise reçoivent ~40 %
-- d'Adwords (vs ~100 % organique pour les articles), donc, pour ne pas mentir :
--   * lecture (dwell/scroll) = entrées ORGANIQUES uniquement (comme le CPI) ;
--   * paid_share_pct par page + paid/organic/total_entries_n au KPI header
--     (base = session d'entrée : 1er pageview GLOBAL de la session, classify_channel) ;
--   * visiteurs = pageview-only distinct anon (convention T-16), tous canaux.
-- Tables + fonctions SÉPARÉES (zéro touche aux objets _resources_*). Refresh via
-- fonction dédiée + cron sibling (le corps articles reste INTACT = garantie zéro
-- régression). Scope path = cooked_page_type='expertise' + guard canonique
-- ^(/[a-z0-9-]+)+$ (exclut les artefacts type /defense-penale/droit-penal').

-- ============ 1. Tables (miroir des _resources_ + colonnes canal) ============
CREATE TABLE IF NOT EXISTS public.dashboard_expertises_snapshot
  (LIKE public.dashboard_resources_snapshot INCLUDING DEFAULTS);
ALTER TABLE public.dashboard_expertises_snapshot
  ADD COLUMN IF NOT EXISTS paid_share_pct numeric;

CREATE TABLE IF NOT EXISTS public.dashboard_expertises_kpis_snapshot
  (LIKE public.dashboard_kpis_snapshot INCLUDING DEFAULTS);
ALTER TABLE public.dashboard_expertises_kpis_snapshot
  ADD COLUMN IF NOT EXISTS paid_entries_n bigint,
  ADD COLUMN IF NOT EXISTS organic_entries_n bigint,
  ADD COLUMN IF NOT EXISTS total_entries_n bigint;

CREATE TABLE IF NOT EXISTS public.dashboard_expertises_trend_snapshot
  (LIKE public.dashboard_trend_snapshot INCLUDING DEFAULTS);

ALTER TABLE public.dashboard_expertises_snapshot       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dashboard_expertises_kpis_snapshot  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dashboard_expertises_trend_snapshot ENABLE ROW LEVEL SECURITY;

-- ============ 2. Fonctions read (miroir _resources_) ============
CREATE OR REPLACE FUNCTION public.dashboard_expertises_kpis(period_kind text DEFAULT 'rolling_90')
 RETURNS SETOF public.dashboard_expertises_kpis_snapshot
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.dashboard_expertises_kpis_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$$;
CREATE OR REPLACE FUNCTION public.dashboard_expertises_overview(period_kind text DEFAULT 'rolling_90', max_rows integer DEFAULT 100)
 RETURNS SETOF public.dashboard_expertises_snapshot
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.dashboard_expertises_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END
  ORDER BY unique_visitors DESC NULLS LAST LIMIT max_rows;
$$;
CREATE OR REPLACE FUNCTION public.dashboard_expertises_trend(period_kind text DEFAULT 'rolling_90')
 RETURNS TABLE(visitors_daily numeric[], pageviews_daily numeric[], contacts_daily numeric[], gsc_clicks_daily numeric[], gsc_impressions_daily numeric[])
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily
  FROM public.dashboard_expertises_trend_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$$;
GRANT EXECUTE ON FUNCTION public.dashboard_expertises_kpis(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_expertises_overview(text,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_expertises_trend(text) TO service_role;

-- ============ 3. Refresh dédié (même conventions T-16 que l'articles) ============
CREATE OR REPLACE FUNCTION public.refresh_dashboard_expertises_snapshots(p_window text DEFAULT NULL)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int; cpi_day date; v_shift int;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_expertises_snapshot       WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_kpis_snapshot  WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_trend_snapshot WHERE window_kind = ANY(windows);

  DROP TABLE IF EXISTS _xp;
  CREATE TEMP TABLE _xp ON COMMIT DROP AS
    SELECT DISTINCT e.path FROM events e
    WHERE e.name='pageview' AND e.occurred_at > now() - interval '100 days'
      AND public.cooked_page_type(e.path)='expertise' AND e.path ~ '^(/[a-z0-9-]+)+$';

  FOREACH w IN ARRAY windows LOOP
    SELECT label_fr,n_start,n_end,prev_start,prev_end,paris_today,day_count
      INTO lbl,lns,lne,lps,lpe,lpt,ld FROM cooked_period_bounds(w,'live');
    SELECT n_start,n_end,prev_start,prev_end,gsc_last_day,lag_days
      INTO gns,gne,gps,gpe,glast,glag FROM cooked_period_bounds(w,'gsc');
    v_shift := lne - (public.paris_today() - 1);
    IF v_shift > 0 THEN lns:=lns-v_shift; lne:=lne-v_shift; lps:=lps-v_shift; lpe:=lpe-v_shift; END IF;
    ld := (lne - lns + 1)::int;

    -- events expertise (bot/noise filtrés)
    DROP TABLE IF EXISTS _evx;
    CREATE TEMP TABLE _evx ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        (e.occurred_at AT TIME ZONE 'Europe/Paris')::date AS d
      FROM events e JOIN _xp ON _xp.path=e.path
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
        AND e.occurred_at >= (lps::timestamp AT TIME ZONE 'Europe/Paris')
        AND e.occurred_at <  ((lne+1)::timestamp AT TIME ZONE 'Europe/Paris')
        AND NOT EXISTS (SELECT 1 FROM bot_fingerprints bf WHERE bf.anonymous_id=e.anonymous_id)
        AND NOT EXISTS (SELECT 1 FROM noise_sessions ns WHERE ns.session_id=e.session_id);
    ANALYZE _evx;

    -- canal d'entrée = 1er pageview GLOBAL de chaque session ayant touché une expertise
    DROP TABLE IF EXISTS _entry;
    CREATE TEMP TABLE _entry ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
        public.classify_channel(e.referrer_hostname,e.utm_source,e.utm_medium,'www.jplouton-avocat.fr') AS chan
      FROM events e
      WHERE e.name='pageview'
        AND e.session_id IN (SELECT DISTINCT session_id FROM _evx)
        AND e.occurred_at >= (lps::timestamp AT TIME ZONE 'Europe/Paris')
        AND e.occurred_at <  ((lne+1)::timestamp AT TIME ZONE 'Europe/Paris')
      ORDER BY e.session_id, e.occurred_at;

    INSERT INTO public.dashboard_expertises_snapshot (
      window_kind, path, theme, unique_visitors, pageviews, dwell_median_s, scroll_median,
      gsc_clicks, gsc_impressions, gsc_position_avg, gsc_ctr_pct,
      best_query, best_query_clicks, best_query_volume_fr, best_query_cpc,
      contacts, booking_intent, first_impression_day, first_tracker_day, days_live,
      confidence, cooked_start, cooked_end, gsc_start, gsc_end, refreshed_at,
      unique_visitors_prev, gsc_clicks_prev, cpi, cpi_grade, momentum, potentiel, convertit,
      ctr_expected, paid_share_pct)
    WITH
    reads AS (  -- lecture ORGANIQUE par page (entrée globale organique = cette page), grain session×path max (T-14)
      SELECT en.entry_path AS path,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.dur)) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.scr)) AS scroll
      FROM _entry en
      JOIN (SELECT session_id, path, max(dur) dur, max(scr) scr FROM _evx WHERE name='page_exit' GROUP BY session_id, path) a
        ON a.session_id=en.session_id AND a.path=en.entry_path
      WHERE en.chan LIKE 'organic%' AND en.entry_path IN (SELECT path FROM _xp)
      GROUP BY en.entry_path
    ),
    vis AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv
      FROM _evx GROUP BY path
    ),
    entries AS (  -- part paid par page (base = session d'entrée sur cette page)
      SELECT entry_path AS path, COUNT(*) AS tot, COUNT(*) FILTER (WHERE chan='paid') AS paid
      FROM _entry WHERE entry_path IN (SELECT path FROM _xp) GROUP BY entry_path
    ),
    gsc AS (SELECT m.path,m.clicks_total,m.impressions_total,m.position_avg,m.ctr_pct
            FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
    gscp AS (SELECT m.path,m.clicks_total AS clicks_prev FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
    cpi_d AS (SELECT path,cpi,grade,momentum FROM cpi_daily WHERE day=cpi_day),
    gis AS (SELECT path,potentiel,convertit FROM cpi_gisement),
    bestq AS (
      SELECT DISTINCT ON (q.path) q.path,q.query,q.clicks FROM (
        SELECT qp.path,qp.query,SUM(qp.clicks) clicks,SUM(qp.impressions) impr
        FROM gsc_query_page_daily qp JOIN _xp ON _xp.path=qp.path
        WHERE qp.day BETWEEN gns AND gne AND qp.query NOT ILIKE '%plouton%'
        GROUP BY qp.path,qp.query) q
      ORDER BY q.path,q.clicks DESC,q.impr DESC
    ),
    contacts AS (SELECT mc.path,mc.contacts,mc.booking_intent FROM macro_contacts_by_path(lns,lne) mc JOIN _xp ON _xp.path=mc.path)
    SELECT w, x.path,
      (SELECT theme FROM page_taxonomy pt WHERE pt.path=x.path),
      COALESCE(v.uv,0), COALESCE(v.pv,0), r.dwell, r.scroll,
      COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
      bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
      COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
      NULL::date, NULL::date, NULL::int,
      CASE WHEN ld>0 AND COALESCE(v.uv,0)::numeric/ld >= 1.5 THEN 'A'
           WHEN ld>0 AND COALESCE(v.uv,0)::numeric/ld >= 0.5 THEN 'B' ELSE 'C' END,
      lns, lne, gns, gne, now(),
      COALESCE(v.uv_prev,0)::int, COALESCE(gp.clicks_prev,0)::int,
      cd.cpi, cd.grade, cd.momentum, gi.potentiel, gi.convertit,
      CASE WHEN g.position_avg IS NOT NULL THEN ROUND(ctr_for_position(g.position_avg)*100,2) END,
      CASE WHEN e.tot>0 THEN ROUND(100.0*e.paid/e.tot,1) END
    FROM _xp x
    LEFT JOIN vis v      ON v.path=x.path
    LEFT JOIN reads r    ON r.path=x.path
    LEFT JOIN entries e  ON e.path=x.path
    LEFT JOIN gsc g      ON g.path=x.path
    LEFT JOIN gscp gp    ON gp.path=x.path
    LEFT JOIN cpi_d cd   ON cd.path=x.path
    LEFT JOIN gis gi     ON gi.path=x.path
    LEFT JOIN bestq bq   ON bq.path=x.path
    LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=bq.query AND dfs.location_code=2250
    LEFT JOIN contacts ct ON ct.path=x.path;

    INSERT INTO public.dashboard_expertises_kpis_snapshot (
      window_kind, label_fr, cooked_start, cooked_end, gsc_start, gsc_end, gsc_last_day, lag_days,
      is_partial, visitors_n, visitors_prev, pageviews_n, pageviews_prev, contacts_n, contacts_prev,
      gsc_clicks_n, gsc_clicks_prev, gsc_impressions_n, gsc_impressions_prev, refreshed_at,
      current_day_partial, no_prev_baseline, paid_entries_n, organic_entries_n, total_entries_n)
    SELECT w, lbl, lns, lne, gns, gne, glast, glag,
      ((lne >= lpt) OR (tracker_first_seen_global() > lpe::timestamptz)),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lps AND lpe),
      (SELECT COUNT(*) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(*) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lps AND lpe),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lns,lne) mc JOIN _xp ON _xp.path=mc.path),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lps,lpe) mc JOIN _xp ON _xp.path=mc.path),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
      now(), (lne >= lpt), (tracker_first_seen_global() > lpe::timestamptz),
      (SELECT COUNT(*) FILTER (WHERE chan='paid')          FROM _entry WHERE entry_path IN (SELECT path FROM _xp)),
      (SELECT COUNT(*) FILTER (WHERE chan LIKE 'organic%') FROM _entry WHERE entry_path IN (SELECT path FROM _xp)),
      (SELECT COUNT(*)                                     FROM _entry WHERE entry_path IN (SELECT path FROM _xp));

    INSERT INTO public.dashboard_expertises_trend_snapshot (
      window_kind, visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily, refreshed_at)
    SELECT w,
      (SELECT array_agg(COALESCE(v.uv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT d,COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') uv FROM _evx WHERE d BETWEEN lns AND lne GROUP BY d) v ON v.d=ds.d),
      (SELECT array_agg(COALESCE(p.pv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT d,COUNT(*) pv FROM _evx WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) p ON p.d=ds.d),
      (SELECT array_agg(COALESCE(ct.ct,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (
           SELECT (e.occurred_at AT TIME ZONE 'Europe/Paris')::date d, COUNT(*) ct
           FROM events e JOIN _xp ON _xp.path=e.path
           WHERE e.name IN ('cta_phone_click','form_submit')
             AND (e.name='cta_phone_click' OR form_submit_counts_as_macro(e.props))
             AND NOT EXISTS (SELECT 1 FROM bot_fingerprints bf WHERE bf.anonymous_id=e.anonymous_id)
             AND NOT EXISTS (SELECT 1 FROM noise_sessions ns WHERE ns.session_id=e.session_id)
             AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date BETWEEN lns AND lne
           GROUP BY 1
         ) ct ON ct.d=ds.d),
      (SELECT array_agg(COALESCE(gd.clicks,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp,gne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT day,SUM(clicks) clicks FROM gsc_path_daily WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM _xp) GROUP BY day) gd ON gd.day=ds.d),
      (SELECT array_agg(COALESCE(gd.impr,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp,gne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT day,SUM(impressions) impr FROM gsc_path_daily WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM _xp) GROUP BY day) gd ON gd.day=ds.d),
      now();
  END LOOP;
END $function$;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_expertises_snapshots(text) TO service_role;

-- ============ 4. Cron sibling (5 min après le refresh articles à 15 8) ============
SELECT cron.schedule('refresh-dashboard-expertises','20 8 * * *',
  $j$ SELECT public.refresh_dashboard_expertises_snapshots(); $j$);
