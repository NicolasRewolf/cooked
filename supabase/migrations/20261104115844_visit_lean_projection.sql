-- Lecture des visites à projection réduite ; ni table, ni cache, ni nouveau lecteur.
-- Garde le filtre d'activité après le CTE source pour préserver le plan de scan.
CREATE OR REPLACE FUNCTION public.cooked_visit_events(p_start date, p_end date)
 RETURNS TABLE(event_id uuid, event_name text, occurred_at timestamp with time zone, path text, anonymous_id text, objet text, counts_as_macro boolean, attribution_method text, visit_id uuid, entry_at timestamp with time zone, entry_path text, entry_channel text, journey text[], device_type text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET jit TO 'off'
 SET work_mem TO '32MB'
AS $function$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end>=public.paris_today() THEN
    RAISE EXCEPTION 'Expected completed Paris days with start <= end' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
  WITH raw_paths AS MATERIALIZED (
    SELECT e.id,e.name,e.occurred_at AS t,
      CASE WHEN e.name IN ('pageview','cta_phone_click','form_submit') AND nullif(e.path,'') IS NOT NULL THEN e.path END AS raw_path,
      CASE WHEN e.name IN ('pageview','cta_phone_click') THEN e.anonymous_id END AS anonymous_id,
      CASE WHEN e.name='pageview' THEN e.device_type END AS device_type,
      CASE WHEN e.name='form_submit' THEN e.props->>'objet_de_ma_demande' END AS objet,
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
    SELECT p.raw_path,public.canonical_path(p.raw_path) AS path
    FROM (SELECT DISTINCT r.raw_path FROM raw_paths r WHERE r.raw_path IS NOT NULL) p
  ), keyed AS (
    -- Les tris de segmentation n'emportent ni URL, ni campagne, ni formulaire.
    SELECT r.id,r.name,r.t,r.raw_path,
      CASE WHEN r.name='form_submit' AND s.visitor_key IS NOT NULL AND a.visitor_key IS NOT NULL
        AND s.visitor_key<>a.visitor_key THEN 'event:'||r.id ELSE coalesce(s.visitor_key,a.visitor_key,
        CASE WHEN r.sid NOT LIKE 'webhook-%' THEN 'sid:'||r.sid END,
        CASE WHEN r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%' THEN 'aid:'||r.aid END,'event:'||r.id) END AS vk
    FROM raw_paths r
    LEFT JOIN public.identity_stitch s ON s.kind='sid' AND s.key=r.sid AND r.sid NOT LIKE 'webhook-%'
    LEFT JOIN public.identity_stitch a ON a.kind='aid' AND a.key=r.aid
      AND r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%'
    WHERE r.name IN ('pageview','engagement_tick','page_exit','scroll_depth','click_internal',
      'click_outbound','cta_anchor_click','cta_booking_click','cta_phone_click','form_submit')
  ), gaps AS (
    SELECT k.*,k.t-lag(k.t) OVER(PARTITION BY k.vk ORDER BY k.t,(k.name='pageview') DESC,k.id) AS gap
    FROM keyed k
  ), segmented AS (
    SELECT g.id,g.name,g.t,g.raw_path,g.vk,
      sum((g.gap IS NULL OR g.gap>interval '30 minutes')::int)
        OVER(PARTITION BY g.vk ORDER BY g.t,(g.name='pageview') DESC,g.id) AS seq
    FROM gaps g
  ), relevant AS MATERIALIZED (
    SELECT s.id,s.name,s.t,s.vk,s.seq,p.path
    FROM segmented s LEFT JOIN paths p ON p.raw_path=s.raw_path
    WHERE (s.name='pageview' AND p.path IS NOT NULL) OR s.name IN ('cta_phone_click','form_submit')
  ), first_pages AS (
    SELECT DISTINCT ON (r.vk,r.seq) r.vk,r.seq,r.id,r.t,r.path
    FROM relevant r WHERE r.name='pageview'
    ORDER BY r.vk,r.seq,r.t,r.id
  ), entry_inputs AS MATERIALIZED (
    SELECT p.vk,p.seq,p.id,p.t,p.path,r.device_type,
      jsonb_build_array(r.referrer_hostname,r.utm_source,r.utm_medium,r.url) AS channel_key
    FROM first_pages p JOIN raw_paths r ON r.id=p.id
  ), channels AS MATERIALIZED (
    -- Plusieurs visites ont les mêmes sources : classifier chaque tuple une fois.
    -- Le tableau JSON garde les quatre positions et distingue NULL de la chaîne vide.
    SELECT c.channel_key,
      public.classify_channel(c.channel_key->>0,c.channel_key->>1,c.channel_key->>2,
        'www.jplouton-avocat.fr',c.channel_key->>3) AS channel
    FROM (SELECT DISTINCT i.channel_key FROM entry_inputs i) c
  ), entries AS MATERIALIZED (
    SELECT i.vk,i.seq,i.id,i.t,i.path,i.device_type,c.channel
    FROM entry_inputs i JOIN channels c ON c.channel_key=i.channel_key
  ), contact_paths AS (
    -- Jointure des seuls contacts rendus aux pages déjà vues de leur visite.
    -- Le premier passage conserve l'ordre exact des chemins dédupliqués.
    SELECT DISTINCT ON (c.id,p.path) c.id,p.path,p.t,p.id AS page_id
    FROM relevant c JOIN relevant p ON p.vk=c.vk AND p.seq=c.seq
      AND p.name='pageview' AND p.t<=c.t
    WHERE c.name IN ('cta_phone_click','form_submit')
      AND c.t>=public.cooked_paris_ts_start(p_start)
    ORDER BY c.id,p.path,p.t,p.id
  ), journeys AS MATERIALIZED (
    SELECT c.id,array_agg(c.path ORDER BY c.t,c.page_id) AS paths
    FROM contact_paths c GROUP BY c.id
  )
  SELECT e.id,e.name,e.t,e.path,
    CASE WHEN e.name='form_submit' THEN r.aid ELSE r.anonymous_id END,
    r.objet,r.macro,
    CASE WHEN entry.id IS NULL THEN 'unresolved'
      WHEN e.name='form_submit' THEN 'hidden_field' ELSE 'direct' END,
    entry.id,entry.t,entry.path,entry.channel,
    CASE WHEN e.name<>'pageview' THEN coalesce(j.paths,ARRAY[]::text[]) END,
    entry.device_type
  FROM relevant e
  JOIN raw_paths r ON r.id=e.id
  LEFT JOIN entries entry ON entry.vk=e.vk AND entry.seq=e.seq AND entry.t<=e.t
  LEFT JOIN journeys j ON j.id=e.id
  WHERE e.t>=public.cooked_paris_ts_start(p_start)
  ORDER BY e.t,e.id;
END $function$;

REVOKE ALL ON FUNCTION public.cooked_visit_events(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_visit_events(date,date) TO service_role;
