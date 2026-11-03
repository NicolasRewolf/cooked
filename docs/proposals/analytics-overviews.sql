-- PROPOSITION NON APPLIQUÉE — pas une migration.
-- Comparaisons par page sur les dates GSC exactes. Le résultat est testé sur
-- une base isolée ; le coût des lectures sur les volumes de production reste
-- trop élevé pour remplacer les lectures actuelles. Ne pas déployer tel quel.

CREATE OR REPLACE FUNCTION public.top_contact_pages(p_period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 10)
 RETURNS TABLE(path text, cooked_contacts bigint, cooked_phone_clicks bigint, cooked_form_submits bigint, gsc_clicks bigint, cooked_sessions bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1
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
  ),
  sessions AS (
    SELECT e.path, count(DISTINCT e.session_id)::bigint AS n
    FROM public.events_human e
    INNER JOIN mc ON mc.path = e.path
    WHERE e.name = 'pageview'
      AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)
      AND e.occurred_at >= public.cooked_paris_ts_start((SELECT n_start FROM b))
      AND e.occurred_at < public.cooked_paris_ts_end_exclusive((SELECT n_end FROM b))
    GROUP BY e.path
  )
  SELECT
    mc.path,
    mc.contacts,
    mc.phone_clicks,
    mc.form_submits,
    coalesce(gsc.clicks_total, 0),
    coalesce(s.n, 0)::bigint
  FROM mc
  LEFT JOIN gsc ON gsc.path = mc.path
  LEFT JOIN sessions s ON s.path = mc.path
  ORDER BY mc.contacts DESC, mc.path;
$function$;
REVOKE ALL ON FUNCTION public.top_contact_pages(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.top_contact_pages(text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.pages_overview_unified(period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 1000)
 RETURNS TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_dwell_avg_s numeric, cooked_bounce_rate numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, has_cooked_data boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT n_start,n_end FROM public.cooked_period_bounds(period_kind,'cross') LIMIT 1
  ),
  -- Déduplication par ensemble, équivalente à events_human pour des bornes
  -- à la seconde entière. Les candidats viennent de events_main AVANT les
  -- filtres bot/bruit/chrome, comme dans le NOT EXISTS de la vue canonique.
  -- Projection étroite : ne pas matérialiser les payloads JSON complets sur 90j.
  raw_window AS MATERIALIZED (
    SELECT e.id,e.anonymous_id,e.name,e.path,e.session_id,e.occurred_at,e.referrer_hostname,e.device_type,
      e.props->>'anchor' AS anchor_key,
      CASE WHEN e.name='page_exit' THEN e.props->>'duration_seconds' END AS dwell_text,
      CASE WHEN e.name='form_submit' THEN public.form_submit_counts_as_macro(e.props) ELSE false END AS form_macro,
      CASE WHEN e.name='cta_anchor_click' THEN public.cooked_is_chrome_anchor(e.props) ELSE false END AS chrome_anchor
    FROM public.events_main e
    WHERE e.occurred_at >= public.cooked_paris_ts_start((SELECT n_start FROM bounds))
      AND e.occurred_at < public.cooked_paris_ts_end_exclusive((SELECT n_end FROM bounds))
  ),
  first_click AS (
    SELECT DISTINCT ON (e.session_id,e.name,e.path,date_trunc('second',e.occurred_at),e.anchor_key) e.*
    FROM raw_window e
    WHERE e.name IN ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound')
      AND e.session_id IS NOT NULL
    ORDER BY e.session_id,e.name,e.path,date_trunc('second',e.occurred_at),e.anchor_key,e.id
  ),
  deduplicated AS (
    SELECT e.* FROM raw_window e
    WHERE e.name NOT IN ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound')
       OR e.session_id IS NULL
    UNION ALL SELECT * FROM first_click
  ),
  window_events AS MATERIALIZED (
    SELECT e.* FROM deduplicated e
    WHERE NOT EXISTS (SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id=e.anonymous_id)
      AND NOT EXISTS (SELECT 1 FROM public.noise_sessions n WHERE n.session_id=e.session_id)
      AND NOT e.chrome_anchor
  ),
  clean_events AS MATERIALIZED (
    SELECT * FROM window_events
    WHERE NOT public.cooked_is_spam_referrer(referrer_hostname)
  ),
  pv AS (
    SELECT path,count(DISTINCT session_id)::bigint AS sessions
    FROM clean_events WHERE name='pageview' AND path IS NOT NULL GROUP BY path
  ),
  session_summary AS (
    SELECT session_id,min(occurred_at) AS t_start,max(occurred_at) AS t_end,
      count(*) FILTER(WHERE name='pageview') AS pages,
      (array_agg(path ORDER BY occurred_at) FILTER(WHERE name='pageview'))[1] AS entry_path
    FROM clean_events GROUP BY session_id
  ),
  bounce AS (
    SELECT entry_path AS path,
      round(100.0*count(*) FILTER(WHERE pages=1 AND extract(epoch FROM(t_end-t_start))<10)
        /nullif(count(*),0),2) AS rate
    FROM session_summary WHERE entry_path IS NOT NULL GROUP BY entry_path
  ),
  page_dwell AS (
    SELECT session_id,path,max(dwell_text::numeric) AS dwell
    FROM clean_events WHERE name='page_exit' AND path IS NOT NULL GROUP BY session_id,path
  ),
  dwell AS (
    SELECT path,round(avg(dwell),1) AS average FROM page_dwell GROUP BY path
  ),
  google_entries AS (
    SELECT DISTINCT session_id,path FROM window_events
    WHERE name='pageview' AND referrer_hostname LIKE '%google%'
  ),
  pogo_sessions AS (
    SELECT session_id,count(*) AS pages FROM window_events WHERE name='pageview' GROUP BY session_id
  ),
  pogo_dwell AS (
    SELECT session_id,path,max(dwell_text::numeric) AS dwell
    FROM window_events WHERE name='page_exit' GROUP BY session_id,path
  ),
  pogo AS (
    SELECT g.path,round(100.0*count(*) FILTER(WHERE s.pages=1 AND (d.dwell<10 OR d.dwell IS NULL))
      /nullif(count(*),0),1) AS rate
    FROM google_entries g
    LEFT JOIN pogo_sessions s ON s.session_id=g.session_id
    LEFT JOIN pogo_dwell d ON d.session_id=g.session_id AND d.path=g.path
    GROUP BY g.path
  ),
  gsc AS MATERIALIZED (
    SELECT * FROM public.gsc_path_metrics((SELECT n_start FROM bounds),(SELECT n_end FROM bounds))
  ),
  ranked_paths AS (
    SELECT coalesce(p.path,g.path) AS path
    FROM pv p FULL JOIN gsc g ON g.path=p.path
    ORDER BY coalesce(p.sessions,0) DESC,coalesce(g.clicks_total,0) DESC,coalesce(p.path,g.path)
    LIMIT max_rows
  ),
  contacts AS (
    -- Même contrat que macro_contacts_by_path(date,date), sans rescanner la vue.
    SELECT coalesce(path,'(non rattaché)') AS path,
      count(*) FILTER(WHERE name='cta_phone_click')::bigint AS phone_clicks,
      count(*) FILTER(WHERE name='form_submit' AND form_macro)::bigint AS form_submits,
      (count(*) FILTER(WHERE name='cta_phone_click')
        +count(*) FILTER(WHERE name='form_submit' AND form_macro))::bigint AS contacts,
      count(*) FILTER(WHERE name='cta_booking_click' AND device_type!='server')::bigint AS booking_intent
    FROM window_events
    WHERE name='cta_phone_click' OR (name='form_submit' AND form_macro)
      OR (name='cta_booking_click' AND device_type!='server')
    GROUP BY 1
  )
  SELECT r.path,coalesce(g.clicks_total,0),coalesce(g.impressions_total,0),g.position_avg,g.ctr_pct,
    coalesce(p.sessions,0),
    CASE WHEN p.path IS NOT NULL THEN coalesce(d.average,0) END,
    CASE WHEN p.path IS NOT NULL THEN coalesce(b.rate,0) END,
    coalesce(c.phone_clicks,0),coalesce(c.form_submits,0),coalesce(c.contacts,0),coalesce(c.booking_intent,0),
    po.rate,p.path IS NOT NULL
  FROM ranked_paths r
  LEFT JOIN gsc g ON g.path=r.path
  LEFT JOIN pv p ON p.path=r.path
  LEFT JOIN dwell d ON d.path=r.path
  LEFT JOIN bounce b ON b.path=r.path
  LEFT JOIN pogo po ON po.path=r.path
  LEFT JOIN contacts c ON c.path=r.path
  ORDER BY coalesce(p.sessions,0) DESC,coalesce(g.clicks_total,0) DESC,r.path;
$function$;
REVOKE ALL ON FUNCTION public.pages_overview_unified(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pages_overview_unified(text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.gsc_pages_overview(max_rows integer DEFAULT 30)
 RETURNS TABLE(path text, gsc_clicks_28d bigint, gsc_impressions_28d bigint, gsc_position_avg_28d numeric, gsc_ctr_pct_28d numeric, cooked_sessions_28d bigint, cooked_dwell_avg_s_28d numeric, cooked_bounce_rate_28d numeric, cooked_phone_clicks_28d bigint, cooked_form_submits_28d bigint, cooked_contacts_28d bigint, cooked_booking_intent_28d bigint, cooked_pogo_rate_28d numeric, has_cooked_data boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- La projection commune calcule le comportement une seule fois sur les dates GSC.
  SELECT p.path,p.gsc_clicks,p.gsc_impressions,p.gsc_position_avg,p.gsc_ctr_pct,
    p.cooked_sessions,p.cooked_dwell_avg_s,p.cooked_bounce_rate,p.cooked_phone_clicks,
    p.cooked_form_submits,p.cooked_contacts,p.cooked_booking_intent,p.cooked_pogo_rate,p.has_cooked_data
  FROM public.pages_overview_unified('rolling_28',NULL) p
  WHERE EXISTS (
    SELECT 1 FROM public.gsc_path_daily g
    WHERE g.path=p.path AND g.day BETWEEN
      (SELECT n_start FROM public.cooked_period_bounds('rolling_28','gsc')) AND
      (SELECT n_end FROM public.cooked_period_bounds('rolling_28','gsc'))
  )
  ORDER BY p.gsc_clicks DESC,p.gsc_impressions DESC,p.path
  LIMIT max_rows;
$function$;
REVOKE ALL ON FUNCTION public.gsc_pages_overview(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gsc_pages_overview(integer) TO service_role;
