-- Conserver le filtre d’activité après la lecture source, pour éviter un accès aléatoire coûteux sur presque toute la table.
CREATE OR REPLACE FUNCTION public.cooked_visit_events(p_start date, p_end date)
 RETURNS TABLE(event_id uuid, event_name text, occurred_at timestamp with time zone, path text, anonymous_id text, objet text, counts_as_macro boolean, attribution_method text, visit_id uuid, entry_at timestamp with time zone, entry_path text, entry_channel text, journey text[], device_type text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET jit TO 'off'
AS $function$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end>=public.paris_today() THEN
    RAISE EXCEPTION 'Expected completed Paris days with start <= end' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
  WITH raw_paths AS MATERIALIZED (
    SELECT e.id,e.name,e.occurred_at AS t,CASE WHEN e.name IN ('pageview','cta_phone_click','form_submit') AND nullif(e.path,'') IS NOT NULL THEN e.path END AS raw_path,
      e.anonymous_id,CASE WHEN e.name='pageview' THEN e.device_type END AS device_type,CASE WHEN e.name='form_submit' THEN e.props->>'objet_de_ma_demande' END AS objet,
      e.name='cta_phone_click' OR (e.name='form_submit' AND public.form_submit_counts_as_macro(e.props)) AS macro,
      CASE WHEN e.name='pageview' THEN e.referrer_hostname END AS referrer_hostname,
      CASE WHEN e.name='pageview' THEN e.utm_source END AS utm_source,
      CASE WHEN e.name='pageview' THEN e.utm_medium END AS utm_medium,
      CASE WHEN e.name='pageview' THEN e.url END AS url,
      CASE WHEN e.name='form_submit' THEN nullif(e.props->>'cooked_sid','') ELSE nullif(e.session_id,'') END AS sid,
      CASE WHEN e.name='form_submit' THEN nullif(e.props->>'cooked_aid','') ELSE nullif(e.anonymous_id,'') END AS aid
    FROM public.events_human e
    WHERE e.occurred_at<public.cooked_paris_ts_end_exclusive(p_end)
  ), paths AS MATERIALIZED (
    -- Même normalisation ; une seule évaluation par chemin distinct.
    SELECT p.raw_path,public.canonical_path(p.raw_path) AS path
    FROM (SELECT DISTINCT r.raw_path FROM raw_paths r WHERE r.raw_path IS NOT NULL) p
  ), raw AS (
    SELECT r.*,p.path FROM raw_paths r LEFT JOIN paths p ON p.raw_path=r.raw_path
  ), keyed AS (
    SELECT r.*,CASE WHEN r.name='form_submit' AND s.visitor_key IS NOT NULL AND a.visitor_key IS NOT NULL
      AND s.visitor_key<>a.visitor_key THEN 'event:'||r.id ELSE coalesce(s.visitor_key,a.visitor_key,
      CASE WHEN r.sid NOT LIKE 'webhook-%' THEN 'sid:'||r.sid END,
      CASE WHEN r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%' THEN 'aid:'||r.aid END,'event:'||r.id) END AS vk
    FROM raw r
    LEFT JOIN public.identity_stitch s ON s.kind='sid' AND s.key=r.sid AND r.sid NOT LIKE 'webhook-%'
    LEFT JOIN public.identity_stitch a ON a.kind='aid' AND a.key=r.aid
      AND r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%'
    WHERE r.name IN ('pageview','engagement_tick','page_exit','scroll_depth','click_internal',
      'click_outbound','cta_anchor_click','cta_booking_click','cta_phone_click','form_submit')
  ), wanted AS (
    SELECT DISTINCT k.vk FROM keyed k WHERE k.t>=public.cooked_paris_ts_start(p_start)
  ), scoped AS (
    -- On conserve tout l'amont des navigateurs concernés, pas une marge arbitraire.
    SELECT k.* FROM keyed k JOIN wanted w ON w.vk=k.vk
  ), gaps AS (
    SELECT k.*,k.t-lag(k.t) OVER(PARTITION BY k.vk ORDER BY k.t,(k.name='pageview') DESC,k.id) AS gap FROM scoped k
  ), segmented AS (
    SELECT g.*,sum((g.gap IS NULL OR g.gap>interval '30 minutes')::int)
      OVER(PARTITION BY g.vk ORDER BY g.t,(g.name='pageview') DESC,g.id) AS seq FROM gaps g
  ), relevant AS (
    SELECT s.* FROM segmented s WHERE (s.name='pageview' AND s.path IS NOT NULL) OR s.name IN ('cta_phone_click','form_submit')
  ), enriched AS (
    SELECT r.*,
      first_value(r.id) OVER entry AS first_id,
      first_value(r.t) OVER entry AS first_time,
      first_value(r.name) OVER entry AS first_name,
      first_value(r.path) OVER entry AS first_path,
      first_value(r.referrer_hostname) OVER entry AS first_ref,
      first_value(r.utm_source) OVER entry AS first_source,
      first_value(r.utm_medium) OVER entry AS first_medium,
      first_value(r.url) OVER entry AS first_url,
      first_value(r.device_type) OVER entry AS first_device,
      array_agg(r.path) FILTER(WHERE r.name='pageview' AND r.path IS NOT NULL) OVER (
        PARTITION BY r.vk,r.seq ORDER BY r.t,(r.name='pageview') DESC,r.id) AS paths
    FROM relevant r WINDOW entry AS (PARTITION BY r.vk,r.seq
      ORDER BY (r.name='pageview') DESC,r.t,r.id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  )
  SELECT e.id,e.name,e.t,e.path,
    CASE WHEN e.name='form_submit' THEN e.aid ELSE e.anonymous_id END,
    e.objet,e.macro,
    CASE WHEN e.paths IS NULL THEN 'unresolved'
      WHEN e.name='form_submit' THEN 'hidden_field' ELSE 'direct' END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_id END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_time END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_path END,
    CASE WHEN e.paths IS NOT NULL THEN public.classify_channel(e.first_ref,e.first_source,e.first_medium,
      'www.jplouton-avocat.fr',e.first_url) END,
    CASE WHEN e.name<>'pageview' THEN
      ARRAY(SELECT x.p FROM unnest(e.paths) WITH ORDINALITY x(p,n) GROUP BY x.p ORDER BY min(x.n)) END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_device END
  FROM enriched e
  WHERE e.t>=public.cooked_paris_ts_start(p_start)
  ORDER BY e.t,e.id;
END $function$;

REVOKE ALL ON FUNCTION public.cooked_visit_events(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_visit_events(date,date) TO service_role;
