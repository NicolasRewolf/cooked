-- Arch #2 — cooked_snapshot_window : bornes live_j1+gsc + cooked_events_window (driver unique dashboard)

CREATE OR REPLACE PROCEDURE public.cooked_snapshot_window(
  IN  p_window text,
  IN  p_grain  text,
  OUT o_label_fr       text,
  OUT o_lns            date,
  OUT o_lne            date,
  OUT o_lps            date,
  OUT o_lpe            date,
  OUT o_lpt            date,
  OUT o_ld             int,
  OUT o_gns            date,
  OUT o_gne            date,
  OUT o_gps            date,
  OUT o_gpe            date,
  OUT o_glast          date,
  OUT o_glag           int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $procedure$
BEGIN
  IF p_window NOT IN ('rolling_28', 'rolling_90') THEN
    RAISE EXCEPTION 'cooked_snapshot_window: unsupported window %', p_window;
  END IF;
  IF p_grain NOT IN ('clean', 'human') THEN
    RAISE EXCEPTION 'cooked_snapshot_window: grain must be clean|human, got %', p_grain;
  END IF;

  SELECT b.label_fr, b.n_start, b.n_end, b.prev_start, b.prev_end, b.paris_today, b.day_count
    INTO o_label_fr, o_lns, o_lne, o_lps, o_lpe, o_lpt, o_ld
  FROM public.cooked_period_bounds(p_window, 'live_j1') b;

  SELECT b.n_start, b.n_end, b.prev_start, b.prev_end, b.gsc_last_day, b.lag_days
    INTO o_gns, o_gne, o_gps, o_gpe, o_glast, o_glag
  FROM public.cooked_period_bounds(p_window, 'gsc') b;

  o_ld := (o_lne - o_lns + 1)::int;

  CALL public.cooked_events_window(
    public.cooked_paris_ts_start(o_lps),
    public.cooked_paris_ts_end_exclusive(o_lne),
    p_grain,
    'main'
  );
END;
$procedure$;

COMMENT ON PROCEDURE public.cooked_snapshot_window(text, text) IS
  'Driver dashboard : bornes Cooked live_j1 + GSC, puis matérialise _cooked_ev (grain clean|human).';

REVOKE ALL ON PROCEDURE public.cooked_snapshot_window(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.cooked_snapshot_window(text, text) TO service_role;

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
    CALL public.cooked_snapshot_window(w, 'clean', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);
    DROP TABLE IF EXISTS _ev;
    CREATE TEMP TABLE _ev ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.referrer_hostname AS ref,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        e.d
      FROM _cooked_ev e
      JOIN page_taxonomy pt ON pt.path = e.path AND pt.category='ressource'
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com';
    DROP TABLE IF EXISTS _evc;
    CREATE TEMP TABLE _evc ON COMMIT DROP AS SELECT * FROM _ev;
    ANALYZE _evc;
    INSERT INTO public.dashboard_resources_snapshot
    WITH res AS (SELECT pt.path, pt.theme FROM page_taxonomy pt WHERE pt.category='ressource'),
    dwx AS (
      SELECT path,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY dur)) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY scr)) AS scroll
      FROM (
        SELECT path, session_id, max(dur) AS dur, max(scr) AS scr
        FROM _evc
        WHERE name='page_exit' AND d BETWEEN lns AND lne
          AND ref NOT ILIKE '%linkedin%' AND ref NOT ILIKE '%facebook%'
        GROUP BY path, session_id
      ) a GROUP BY path
    ),
    cooked AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv
      FROM _evc GROUP BY path
    ),
    gsc AS (SELECT m.path, m.clicks_total, m.impressions_total, m.position_avg, m.ctr_pct
            FROM gsc_path_metrics(gns,gne) m JOIN res ON res.path=m.path),
    gscp AS (SELECT m.path, m.clicks_total AS clicks_prev FROM gsc_path_metrics(gps,gpe) m JOIN res ON res.path=m.path),
    cpi_d AS (SELECT path, cpi, grade, momentum FROM cpi_daily WHERE day = cpi_day),
    gis AS (SELECT path, potentiel, convertit FROM cpi_gisement),
    bestq AS (
      SELECT DISTINCT ON (q.path) q.path, q.query, q.clicks FROM (
        SELECT qp.path, qp.query, SUM(qp.clicks) clicks, SUM(qp.impressions) impr
        FROM gsc_query_page_daily qp JOIN res ON res.path=qp.path
        WHERE qp.day BETWEEN gns AND gne AND NOT public.gsc_is_branded(qp.query)
        GROUP BY qp.path, qp.query) q
      ORDER BY q.path, q.clicks DESC, q.impr DESC
    ),
    contacts AS (SELECT mc.path, mc.contacts, mc.booking_intent FROM macro_contacts_by_path(lns,lne) mc JOIN res ON res.path=mc.path),
    fi AS (SELECT g.path, MIN(g.day) first_impr FROM gsc_path_daily g
           WHERE g.impressions>0 AND g.path IN (SELECT path FROM res) GROUP BY g.path),
    fv AS (SELECT e.path, MIN(public.paris_date(e.occurred_at)) first_view
           FROM events_human e
           WHERE e.name='pageview' AND e.path IN (SELECT path FROM res)
           GROUP BY e.path)
    SELECT w, res.path, res.theme,
      COALESCE(c.uv,0), COALESCE(c.pv,0), dw.dwell, dw.scroll,
      COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
      bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
      COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
      fi.first_impr, fv.first_view,
      (lpt - LEAST(COALESCE(fi.first_impr,fv.first_view), COALESCE(fv.first_view,fi.first_impr)))::int,
      CASE WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 1.5 THEN 'A'
           WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 0.5 THEN 'B' ELSE 'C' END,
      lns, lne, gns, gne, now(),
      COALESCE(c.uv_prev,0)::int, COALESCE(gp.clicks_prev,0)::int,
      cd.cpi, cd.grade, cd.momentum, gi.potentiel, gi.convertit,
      CASE WHEN g.position_avg IS NOT NULL THEN ROUND(ctr_for_position(g.position_avg)*100, 2) END
    FROM res
    LEFT JOIN cooked c ON c.path=res.path
    LEFT JOIN dwx dw ON dw.path=res.path
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
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evc WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evc WHERE d BETWEEN lps AND lpe),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lps AND lpe),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lns,lne) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lps,lpe) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      now(), (lne >= lpt), (tracker_first_seen_global() > lpe::timestamptz);
    INSERT INTO public.dashboard_trend_snapshot
      (window_kind, visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily, refreshed_at)
    SELECT w,
      (SELECT array_agg(COALESCE(v.uv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') uv FROM _evc WHERE d BETWEEN lns AND lne GROUP BY d) v ON v.d = ds.d),
      (SELECT array_agg(COALESCE(p.pv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(*) pv FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) p ON p.d = ds.d),
      (SELECT array_agg(COALESCE(ct.ct,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (
           SELECT public.paris_date(e.occurred_at) d, COUNT(*) ct
           FROM events_human e JOIN page_taxonomy pt ON pt.path=e.path AND pt.category='ressource'
           WHERE e.name IN ('cta_phone_click','form_submit')
             AND (e.name='cta_phone_click' OR form_submit_counts_as_macro(e.props))
             AND public.paris_date(e.occurred_at) BETWEEN lns AND lne
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

CREATE OR REPLACE FUNCTION public.refresh_dashboard_expertises_snapshots(p_window text DEFAULT NULL)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int; cpi_day date;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_expertises_snapshot       WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_kpis_snapshot  WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_trend_snapshot WHERE window_kind = ANY(windows);

  DROP TABLE IF EXISTS _xp;
  -- T-20fix (03/07/2026) : scope = la liste OFFICIELLE des 14 pages expertise,
  -- validee par Nicolas. L'enumeration via page_taxonomy etait fausse : la table
  -- (heuristique par theme) ignorait droit-penal et proces-criminel (slugs sans
  -- mot-cle de theme) et incluait detention-provisoire + garde-a-vue, des pages
  -- RETIREES du site (301 verifies le 03/07 vers droit-penal / l'article GAV).
  -- Une nouvelle page expertise = l'ajouter ICI (decision business, pas heuristique).
  CREATE TEMP TABLE _xp ON COMMIT DROP AS
    SELECT * FROM (VALUES
      ('/defense-penale/droit-penal'),
      ('/defense-penale/droit-penal-des-affaires'),
      ('/defense-penale/proces-criminel'),
      ('/defense-penale/trafic-de-stupefiant'),
      ('/defense-penale/violences-conjugales-et-feminicides'),
      ('/indemnisation-des-victimes/accidents-de-la-route'),
      ('/indemnisation-des-victimes/accidents-de-la-vie-courante'),
      ('/indemnisation-des-victimes/accidents-et-erreurs-medicales'),
      ('/indemnisation-des-victimes/droit-et-accidents-du-travail'),
      ('/indemnisation-des-victimes/victimes-de-delits-ou-crimes'),
      ('/droit-des-contrats-et-des-personnes/droit-de-la-famille'),
      ('/droit-des-contrats-et-des-personnes/droit-de-la-famille/avocat-divorce-bordeaux'),
      ('/droit-des-contrats-et-des-personnes/defense-des-consommateurs'),
      ('/droit-des-contrats-et-des-personnes/droit-assurances-particuliers-professionnels')
    ) v(path);
  ANALYZE _xp;

  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'clean', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);
    DROP TABLE IF EXISTS _evx;
    CREATE TEMP TABLE _evx ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.occurred_at,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        e.d
      FROM _cooked_ev e JOIN _xp ON _xp.path=e.path
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com';
    ANALYZE _evx;

    -- canal GLOBAL d'acquisition (1er pageview de la session) pour les sessions
    -- expertise de la FENÊTRE COURANTE uniquement
    DROP TABLE IF EXISTS _fp;
    CREATE TEMP TABLE _fp ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
        public.classify_channel(e.referrer_hostname,e.utm_source,e.utm_medium,'www.jplouton-avocat.fr') AS chan
      FROM _cooked_ev e
      WHERE e.name='pageview'
        AND e.session_id IN (SELECT DISTINCT session_id FROM _evx WHERE name='pageview' AND d BETWEEN lns AND lne)
        AND e.d BETWEEN lns AND lne
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
        WHERE qp.day BETWEEN gns AND gne AND NOT public.gsc_is_branded(qp.query)
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
           SELECT public.paris_date(e.occurred_at) d, COUNT(*) ct
           FROM events_human e JOIN _xp ON _xp.path=e.path
           WHERE e.name IN ('cta_phone_click','form_submit')
             AND (e.name='cta_phone_click' OR form_submit_counts_as_macro(e.props))
             AND public.paris_date(e.occurred_at) BETWEEN lns AND lne
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

CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lbl text; lns date; lne date; lps date; lpe date; lpt date; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int;
BEGIN
  DELETE FROM public.dashboard_resources_assisted_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'human', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);


    -- 1er pageview GLOBAL de chaque session sur le span [lps..lne] (hors Baidu)
    DROP TABLE IF EXISTS _fpv;
    CREATE TEMP TABLE _fpv ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path, e.d AS entry_d
      FROM _cooked_ev e
      WHERE e.name='pageview'
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
      ORDER BY e.session_id, e.occurred_at;
    CREATE INDEX ON _fpv(session_id);
    ANALYZE _fpv;

    -- contacts macro datés (appels par session ; formulaires par cooked_sid)
    DROP TABLE IF EXISTS _ct;
    CREATE TEMP TABLE _ct ON COMMIT DROP AS
      SELECT e.session_id AS sid, e.d
      FROM _cooked_ev e
      WHERE e.name='cta_phone_click'
      UNION ALL
      SELECT e.props->>'cooked_sid', e.d
      FROM _cooked_ev e
      WHERE e.name='form_submit' AND form_submit_counts_as_macro(e.props)
        AND e.props->>'cooked_sid' IS NOT NULL;
    ANALYZE _ct;

    INSERT INTO public.dashboard_resources_assisted_snapshot (window_kind, path, assisted_contacts, assisted_prev, refreshed_at)
    SELECT w, pt.path,
      COALESCE(cur.n,0), COALESCE(prv.n,0), now()
    FROM page_taxonomy pt
    LEFT JOIN (
      SELECT f.entry_path, count(*) AS n
      FROM _ct c JOIN _fpv f ON f.session_id=c.sid
      WHERE c.d BETWEEN lns AND lne
      GROUP BY f.entry_path
    ) cur ON cur.entry_path=pt.path
    LEFT JOIN (
      SELECT f.entry_path, count(*) AS n
      FROM _ct c JOIN _fpv f ON f.session_id=c.sid
      WHERE c.d BETWEEN lps AND lpe
      GROUP BY f.entry_path
    ) prv ON prv.entry_path=pt.path
    WHERE pt.category='ressource';
  END LOOP;
END $function$;

REVOKE ALL ON FUNCTION public.refresh_dashboard_snapshots(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_snapshots(text) TO service_role;
REVOKE ALL ON FUNCTION public.refresh_dashboard_expertises_snapshots(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_expertises_snapshots(text) TO service_role;
REVOKE ALL ON FUNCTION public.refresh_dashboard_resources_assisted(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_resources_assisted(text) TO service_role;
