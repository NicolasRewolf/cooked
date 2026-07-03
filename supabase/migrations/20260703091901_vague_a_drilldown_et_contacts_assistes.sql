-- Vague A (03/07/2026) — dashboard : drill-down article + contacts assistés
-- ============================================================================
-- 1. Snapshot « contacts assistés » par article ressource : contacts macro
--    (appel n'importe où dans la session, ou formulaire relié par cooked_sid)
--    dont la session est ENTRÉE par l'article (1er pageview GLOBAL = l'article).
--    C'est l'attribution « page d'entrée » demandée par Nicolas le 02/07 —
--    complémentaire de la colonne contacts (= actions SUR la page).
--    Pattern sibling (fonction + cron dédiés), refresh articles intact.
-- 2. RPC live dashboard_article_detail(path, period) → jsonb : la fiche
--    drill-down (séries quotidiennes, top requêtes + volumes, composantes CPI,
--    trajectoire CPI, assistés). Une seule page = calcul live acceptable.
-- Conventions T-16 : fenêtres ancrées J-1 Paris (v_shift) ; Baidu exclu par
-- anti-join explicite (events_human ne le filtre pas), comme les autres
-- fonctions dashboard.
-- ============================================================================

-- ── 1a. Table snapshot ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dashboard_resources_assisted_snapshot (
  window_kind text NOT NULL,
  path text NOT NULL,
  assisted_contacts int NOT NULL DEFAULT 0,
  assisted_prev int NOT NULL DEFAULT 0,
  refreshed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (window_kind, path)
);
ALTER TABLE public.dashboard_resources_assisted_snapshot ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dashboard_resources_assisted_snapshot FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dashboard_resources_assisted_snapshot TO service_role;

-- ── 1b. Refresh (sibling — ne touche PAS refresh_dashboard_snapshots) ───────
CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '300s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date; v_shift int;
BEGIN
  DELETE FROM public.dashboard_resources_assisted_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    SELECT n_start,n_end,prev_start,prev_end INTO lns,lne,lps,lpe FROM cooked_period_bounds(w,'live');
    v_shift := lne - (public.paris_today() - 1);
    IF v_shift > 0 THEN lns:=lns-v_shift; lne:=lne-v_shift; lps:=lps-v_shift; lpe:=lpe-v_shift; END IF;

    -- 1er pageview GLOBAL de chaque session sur le span [lps..lne] (hors Baidu)
    DROP TABLE IF EXISTS _fpv;
    CREATE TEMP TABLE _fpv ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
             (e.occurred_at AT TIME ZONE 'Europe/Paris')::date AS entry_d
      FROM events_human e
      WHERE e.name='pageview'
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
        AND e.occurred_at >= (lps::timestamp AT TIME ZONE 'Europe/Paris')
        AND e.occurred_at <  ((lne+1)::timestamp AT TIME ZONE 'Europe/Paris')
      ORDER BY e.session_id, e.occurred_at;
    CREATE INDEX ON _fpv(session_id);
    ANALYZE _fpv;

    -- contacts macro datés (appels par session ; formulaires par cooked_sid)
    DROP TABLE IF EXISTS _ct;
    CREATE TEMP TABLE _ct ON COMMIT DROP AS
      SELECT e.session_id AS sid, (e.occurred_at AT TIME ZONE 'Europe/Paris')::date AS d
      FROM events_human e
      WHERE e.name='cta_phone_click'
        AND e.occurred_at >= (lps::timestamp AT TIME ZONE 'Europe/Paris')
        AND e.occurred_at <  ((lne+1)::timestamp AT TIME ZONE 'Europe/Paris')
      UNION ALL
      SELECT e.props->>'cooked_sid', (e.occurred_at AT TIME ZONE 'Europe/Paris')::date
      FROM events_human e
      WHERE e.name='form_submit' AND form_submit_counts_as_macro(e.props)
        AND e.props->>'cooked_sid' IS NOT NULL
        AND e.occurred_at >= (lps::timestamp AT TIME ZONE 'Europe/Paris')
        AND e.occurred_at <  ((lne+1)::timestamp AT TIME ZONE 'Europe/Paris');
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
REVOKE ALL ON FUNCTION public.refresh_dashboard_resources_assisted(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_resources_assisted(text) TO service_role;

-- ── 1c. Lecture ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dashboard_resources_assisted(period_kind text DEFAULT 'rolling_90')
 RETURNS TABLE(path text, assisted_contacts int, assisted_prev int)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT s.path, s.assisted_contacts, s.assisted_prev
      FROM dashboard_resources_assisted_snapshot s WHERE s.window_kind = period_kind $$;
REVOKE ALL ON FUNCTION public.dashboard_resources_assisted(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_resources_assisted(text) TO service_role;

-- ── 1d. Cron sibling (08:25 UTC, après articles 08:15 et expertises 08:20) ──
SELECT cron.schedule('refresh-dashboard-assisted', '25 8 * * *',
  $$SET statement_timeout='300s'; SELECT public.refresh_dashboard_resources_assisted();$$);

-- ── 2. Fiche article (drill-down) — calcul live pour UNE page ───────────────
CREATE OR REPLACE FUNCTION public.dashboard_article_detail(p_path text, period_kind text DEFAULT 'rolling_28')
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '45s'
AS $function$
DECLARE
  lns date; lne date; lps date; lpe date; v_shift int;
  gns date; gne date; gps date; gpe date;
  result jsonb;
BEGIN
  SELECT b.n_start,b.n_end,b.prev_start,b.prev_end INTO lns,lne,lps,lpe FROM cooked_period_bounds(period_kind,'live') b;
  v_shift := lne - (public.paris_today() - 1);
  IF v_shift > 0 THEN lns:=lns-v_shift; lne:=lne-v_shift; lps:=lps-v_shift; lpe:=lpe-v_shift; END IF;
  SELECT b.n_start,b.n_end,b.prev_start,b.prev_end INTO gns,gne,gps,gpe FROM cooked_period_bounds(period_kind,'gsc') b;

  SELECT jsonb_build_object(
    'path', p_path,
    'meta', (SELECT jsonb_build_object(
        'theme', pt.theme, 'category', pt.category,
        'naissance_google', (SELECT min(day) FROM gsc_path_daily g WHERE g.path=p_path AND g.impressions>0),
        'first_tracker_day', (SELECT min((occurred_at AT TIME ZONE 'Europe/Paris')::date) FROM events_human e WHERE e.path=p_path AND e.name='pageview'),
        'age_jours', (public.paris_today() - (SELECT min(day) FROM gsc_path_daily g WHERE g.path=p_path AND g.impressions>0))::int
      ) FROM page_taxonomy pt WHERE pt.path=p_path),
    'gsc', (SELECT jsonb_build_object(
        'clicks', COALESCE(sum(clicks),0), 'impressions', COALESCE(sum(impressions),0),
        'position', round(avg(position)::numeric,1),
        'ctr_pct', CASE WHEN COALESCE(sum(impressions),0)>0 THEN round(100.0*sum(clicks)/sum(impressions),2) END,
        'ctr_expected', CASE WHEN avg(position) IS NOT NULL THEN round(ctr_for_position(avg(position))*100,2) END,
        'clicks_prev', (SELECT COALESCE(sum(clicks),0) FROM gsc_path_daily g2 WHERE g2.path=p_path AND g2.day BETWEEN gps AND gpe)
      ) FROM gsc_path_daily g WHERE g.path=p_path AND g.day BETWEEN gns AND gne),
    'gsc_daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', ds.d, 'clicks', COALESCE(g.clicks,0), 'impressions', COALESCE(g.impressions,0)) ORDER BY ds.d), '[]'::jsonb)
      FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
      LEFT JOIN (SELECT day, sum(clicks) clicks, sum(impressions) impressions FROM gsc_path_daily WHERE path=p_path AND day BETWEEN gns AND gne GROUP BY day) g ON g.day=ds.d),
    'visitors_daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', ds.d, 'v', COALESCE(v.n,0)) ORDER BY ds.d), '[]'::jsonb)
      FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
      LEFT JOIN (SELECT (occurred_at AT TIME ZONE 'Europe/Paris')::date d, count(DISTINCT anonymous_id) n
                 FROM events_human WHERE path=p_path AND name='pageview'
                   AND referrer_hostname IS DISTINCT FROM 'm.baidu.com' AND referrer_hostname IS DISTINCT FROM 'baidu.com'
                   AND occurred_at >= (lns::timestamp AT TIME ZONE 'Europe/Paris')
                   AND occurred_at <  ((lne+1)::timestamp AT TIME ZONE 'Europe/Paris')
                 GROUP BY 1) v ON v.d=ds.d),
    'top_queries', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'query', q.query, 'clicks', q.clicks, 'impressions', q.impressions, 'position', q.pos,
        'volume_fr', dfs.search_volume, 'cpc', dfs.cpc) ORDER BY q.impressions DESC), '[]'::jsonb)
      FROM (SELECT query, sum(clicks) clicks, sum(impressions) impressions, round(avg(position)::numeric,1) pos
            FROM gsc_query_page_daily WHERE path=p_path AND day BETWEEN gns AND gne AND query NOT ILIKE '%plouton%'
            GROUP BY query ORDER BY sum(impressions) DESC LIMIT 10) q
      LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=q.query AND dfs.location_code=2250),
    'cpi', (SELECT to_jsonb(c) - 'created_at' FROM cpi_daily c WHERE c.path=p_path AND c.day=(SELECT max(day) FROM cpi_daily) ),
    'cpi_series', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', day, 'cpi', cpi) ORDER BY day), '[]'::jsonb)
      FROM cpi_daily WHERE path=p_path),
    'assisted', (SELECT jsonb_build_object('n', s.assisted_contacts, 'prev', s.assisted_prev)
      FROM dashboard_resources_assisted_snapshot s WHERE s.path=p_path AND s.window_kind=period_kind),
    'bounds', jsonb_build_object('cooked_start', lns, 'cooked_end', lne, 'gsc_start', gns, 'gsc_end', gne)
  ) INTO result;
  RETURN result;
END $function$;
REVOKE ALL ON FUNCTION public.dashboard_article_detail(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_article_detail(text, text) TO service_role;
