-- dashboard_expertises_channel_fix
-- Correctif canal + fenêtre (vérif croisée 03/07) :
--   BUG 1 (fenêtre) : les compteurs d'entrées comptaient sur _evx (span courant+précédent
--     = 56/180j) au lieu de la seule fenêtre courante → total gonflé (2447 vs 1509 réels).
--   BUG 2 (canal) : le canal « 1er pageview EXPERTISE » surcomptait le paid (le paid
--     atterrit direct sur l'expertise) et cachait le referral (20 %) + l'organique arrivé
--     par navigation interne. Corrigé : canal = 1er pageview GLOBAL de la session
--     (acquisition réelle, convention CPT), scopé à la fenêtre courante.
-- Vérif croisée 28j (05/06→02/07) : paid 58,8 % · referral 20,4 % · organique 8,7 %.
-- Définitions finales :
--   * KPI paid/organic = sessions expertise (fenêtre courante) par canal GLOBAL ;
--   * paid_share_pct(page) = part des sessions VOYANT la page arrivées en paid (canal global) ;
--   * lecture (dwell/scroll) = atterrisseurs organiques directs sur la page (CPI).

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
    SELECT path FROM public.page_taxonomy
    WHERE public.cooked_page_type(path)='expertise' AND path ~ '^(/[a-z0-9-]+)+$';
  ANALYZE _xp;

  FOREACH w IN ARRAY windows LOOP
    SELECT label_fr,n_start,n_end,prev_start,prev_end,paris_today,day_count
      INTO lbl,lns,lne,lps,lpe,lpt,ld FROM cooked_period_bounds(w,'live');
    SELECT n_start,n_end,prev_start,prev_end,gsc_last_day,lag_days
      INTO gns,gne,gps,gpe,glast,glag FROM cooked_period_bounds(w,'gsc');
    v_shift := lne - (public.paris_today() - 1);
    IF v_shift > 0 THEN lns:=lns-v_shift; lne:=lne-v_shift; lps:=lps-v_shift; lpe:=lpe-v_shift; END IF;
    ld := (lne - lns + 1)::int;

    DROP TABLE IF EXISTS _evx;
    CREATE TEMP TABLE _evx ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.occurred_at,
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

    -- canal GLOBAL d'acquisition (1er pageview de la session) pour les sessions
    -- expertise de la FENÊTRE COURANTE uniquement
    DROP TABLE IF EXISTS _fp;
    CREATE TEMP TABLE _fp ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
        public.classify_channel(e.referrer_hostname,e.utm_source,e.utm_medium,'www.jplouton-avocat.fr') AS chan
      FROM events e
      WHERE e.name='pageview'
        AND e.session_id IN (SELECT DISTINCT session_id FROM _evx WHERE name='pageview' AND d BETWEEN lns AND lne)
        AND e.occurred_at >= (lns::timestamp AT TIME ZONE 'Europe/Paris')
        AND e.occurred_at <  ((lne+1)::timestamp AT TIME ZONE 'Europe/Paris')
        AND NOT EXISTS (SELECT 1 FROM bot_fingerprints bf WHERE bf.anonymous_id=e.anonymous_id)
        AND NOT EXISTS (SELECT 1 FROM noise_sessions ns WHERE ns.session_id=e.session_id)
      ORDER BY e.session_id, e.occurred_at;
    ANALYZE _fp;

    INSERT INTO public.dashboard_expertises_snapshot (
      window_kind, path, theme, unique_visitors, pageviews, dwell_median_s, scroll_median,
      gsc_clicks, gsc_impressions, gsc_position_avg, gsc_ctr_pct,
      best_query, best_query_clicks, best_query_volume_fr, best_query_cpc,
      contacts, booking_intent, first_impression_day, first_tracker_day, days_live,
      confidence, cooked_start, cooked_end, gsc_start, gsc_end, refreshed_at,
      unique_visitors_prev, gsc_clicks_prev, cpi, cpi_grade, momentum, potentiel, convertit,
      ctr_expected, paid_share_pct)
    WITH
    reads AS (  -- lecture organique = atterrisseurs organiques DIRECTS sur la page (CPI), grain session×path max
      SELECT fp.entry_path AS path,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.dur)) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.scr)) AS scroll
      FROM _fp fp
      JOIN (SELECT session_id, path, max(dur) dur, max(scr) scr FROM _evx WHERE name='page_exit' GROUP BY session_id, path) a
        ON a.session_id=fp.session_id AND a.path=fp.entry_path
      WHERE fp.chan LIKE 'organic%' AND fp.entry_path IN (SELECT path FROM _xp)
      GROUP BY fp.entry_path
    ),
    vis AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv
      FROM _evx GROUP BY path
    ),
    pgchan AS (  -- part paid de la page = sessions VOYANT la page (fenêtre courante) par canal global
      SELECT ev.path,
        COUNT(DISTINCT ev.session_id) AS tot,
        COUNT(DISTINCT ev.session_id) FILTER (WHERE fp.chan='paid') AS paid
      FROM _evx ev JOIN _fp fp ON fp.session_id=ev.session_id
      WHERE ev.name='pageview' AND ev.d BETWEEN lns AND lne
      GROUP BY ev.path
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
      CASE WHEN pc.tot>0 THEN ROUND(100.0*pc.paid/pc.tot,1) END
    FROM _xp x
    LEFT JOIN vis v      ON v.path=x.path
    LEFT JOIN reads r    ON r.path=x.path
    LEFT JOIN pgchan pc  ON pc.path=x.path
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
      (SELECT COUNT(*) FILTER (WHERE chan='paid')          FROM _fp),
      (SELECT COUNT(*) FILTER (WHERE chan LIKE 'organic%') FROM _fp),
      (SELECT COUNT(*)                                     FROM _fp);

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