-- C1/C6 vague 2 — P1 dashboard_article_detail : paris_date + cooked_paris_ts_*
-- Lit déjà events_human (filtre canonique) ; on retire les casts Paris bruts restants.

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
        'first_tracker_day', (SELECT min(public.paris_date(e.occurred_at)) FROM events_human e WHERE e.path=p_path AND e.name='pageview'),
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
      LEFT JOIN (SELECT public.paris_date(e.occurred_at) d, count(DISTINCT e.anonymous_id) n
                 FROM events_human e
                 WHERE e.path=p_path AND e.name='pageview'
                   AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
                   AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
                   AND e.occurred_at >= public.cooked_paris_ts_start(lns)
                   AND e.occurred_at <  public.cooked_paris_ts_end_exclusive(lne)
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
