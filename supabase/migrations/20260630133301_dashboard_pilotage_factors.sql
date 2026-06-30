-- Dashboard V1 — facteurs de pilotage (30/06/2026)
-- Enrichit le tableau Articles (tendance N-1, santé CPI, CTR attendu, gisement)
-- et le tableau SEO par requête (tendance + opportunité). Additif : la table
-- snapshot gagne des colonnes, dashboard_resources_overview (SETOF) les expose
-- sans changement ; dashboard_seo_by_query (RETURNS TABLE) est recréée.

-- 1) Colonnes additionnelles sur le snapshot articles
ALTER TABLE public.dashboard_resources_snapshot
  ADD COLUMN IF NOT EXISTS unique_visitors_prev integer,
  ADD COLUMN IF NOT EXISTS gsc_clicks_prev integer,
  ADD COLUMN IF NOT EXISTS cpi integer,
  ADD COLUMN IF NOT EXISTS cpi_grade text,
  ADD COLUMN IF NOT EXISTS momentum numeric,
  ADD COLUMN IF NOT EXISTS potentiel integer,
  ADD COLUMN IF NOT EXISTS convertit boolean,
  ADD COLUMN IF NOT EXISTS ctr_expected numeric;

-- 2) Refresh enrichi
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
  END LOOP;
END $function$;

-- 3) SEO par requête : tendance N-1 + CTR attendu + opportunité
DROP FUNCTION IF EXISTS public.dashboard_seo_by_query(text,text,integer,integer);
CREATE FUNCTION public.dashboard_seo_by_query(period_kind text DEFAULT 'rolling_90', scope text DEFAULT 'ressource', min_volume integer DEFAULT 0, max_rows integer DEFAULT 200)
 RETURNS TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, nb_pages integer, top_page text, top_page_clicks bigint, top_page_theme text, volume_fr integer, cpc numeric, competition_level text, capture_pct numeric, is_quick_win boolean, clicks_prev bigint, position_prev numeric, ctr_expected numeric, opportunity_clicks numeric, gsc_start date, gsc_end date)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
WITH gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
qp AS (
  SELECT d.query, d.path, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
    AND d.query NOT ILIKE '%plouton%'
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query, d.path),
agg AS (SELECT query, SUM(clicks) clicks, SUM(impr) impr, SUM(pos_w) pos_w, COUNT(*) nb_pages FROM qp GROUP BY query),
top AS (SELECT DISTINCT ON (query) query, path top_page, clicks top_clicks FROM qp ORDER BY query, clicks DESC, impr DESC),
qprev AS (
  SELECT d.query, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT prev_start FROM gb) AND (SELECT prev_end FROM gb)
    AND d.query NOT ILIKE '%plouton%'
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query)
SELECT a.query, a.clicks, a.impr,
  ROUND(a.pos_w/NULLIF(a.impr,0),1),
  ROUND(100.0*a.clicks/NULLIF(a.impr,0),2),
  a.nb_pages::int, t.top_page, t.top_clicks, pt.theme,
  dfs.search_volume, dfs.cpc, dfs.competition_level,
  CASE WHEN dfs.search_volume>0 THEN ROUND(100.0*a.clicks/(dfs.search_volume*(SELECT day_count FROM gb)/30.0),1) END,
  (ROUND(a.pos_w/NULLIF(a.impr,0),1) BETWEEN 5 AND 15 AND COALESCE(dfs.search_volume,0)>=100),
  COALESCE(p.clicks,0),
  ROUND(p.pos_w/NULLIF(p.impr,0),1),
  ROUND(ctr_for_position(a.pos_w/NULLIF(a.impr,0))*100,2),
  CASE WHEN COALESCE(dfs.search_volume,0)>0
    THEN GREATEST(0, ROUND(dfs.search_volume*ctr_for_position(3) - a.clicks*30.0/NULLIF((SELECT day_count FROM gb),0)))
  END,
  (SELECT n_start FROM gb), (SELECT n_end FROM gb)
FROM agg a
LEFT JOIN top t ON t.query=a.query
LEFT JOIN page_taxonomy pt ON pt.path=t.top_page
LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=a.query AND dfs.location_code=2250
LEFT JOIN qprev p ON p.query=a.query
WHERE COALESCE(dfs.search_volume,0) >= min_volume
ORDER BY a.clicks DESC, a.impr DESC
LIMIT max_rows;
$function$;
