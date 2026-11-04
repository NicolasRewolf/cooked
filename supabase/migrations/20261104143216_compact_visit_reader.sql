BEGIN;
-- Ne calculer que les huit champs du moteur de visites encore consommés.
-- Aucun CASCADE, stockage dérivé, cache ni mode de lecture.
DROP FUNCTION public.cooked_visit_events(date,date);
CREATE FUNCTION public.cooked_visit_events(p_start date,p_end date)
RETURNS TABLE(event_id uuid,event_name text,occurred_at timestamptz,path text,
  counts_as_macro boolean,visit_id uuid,entry_at timestamptz,entry_path text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO public,pg_catalog SET jit TO off SET work_mem TO '32MB'
AS $function$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end>=public.paris_today() THEN
    RAISE EXCEPTION 'Expected completed Paris days with start <= end' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
  WITH raw AS MATERIALIZED (
    SELECT e.id,e.name,e.occurred_at AS t,
      CASE WHEN e.name IN ('pageview','cta_phone_click','form_submit') AND nullif(e.path,'') IS NOT NULL THEN e.path END AS raw_path,
      e.name='cta_phone_click' OR (e.name='form_submit' AND public.form_submit_counts_as_macro(e.props)) AS macro,
      CASE WHEN e.name='form_submit' THEN nullif(e.props->>'cooked_sid','') ELSE nullif(e.session_id,'') END AS sid,
      CASE WHEN e.name='form_submit' THEN nullif(e.props->>'cooked_aid','') ELSE nullif(e.anonymous_id,'') END AS aid
    FROM public.events_human e
    WHERE e.occurred_at<public.cooked_paris_ts_end_exclusive(p_end)
  ), paths AS MATERIALIZED (
    SELECT p.raw_path,public.canonical_path(p.raw_path) AS path
    FROM (SELECT DISTINCT r.raw_path FROM raw r WHERE r.raw_path IS NOT NULL) p
  ), keyed AS (
    SELECT r.id,r.name,r.t,r.raw_path,r.macro,
      CASE WHEN r.name='form_submit' AND s.visitor_key IS NOT NULL AND a.visitor_key IS NOT NULL
        AND s.visitor_key<>a.visitor_key THEN 'event:'||r.id ELSE coalesce(s.visitor_key,a.visitor_key,
        CASE WHEN r.sid NOT LIKE 'webhook-%' THEN 'sid:'||r.sid END,
        CASE WHEN r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%' THEN 'aid:'||r.aid END,'event:'||r.id) END AS vk
    FROM raw r
    LEFT JOIN public.identity_stitch s ON s.kind='sid' AND s.key=r.sid AND r.sid NOT LIKE 'webhook-%'
    LEFT JOIN public.identity_stitch a ON a.kind='aid' AND a.key=r.aid
      AND r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%'
    WHERE r.name IN ('pageview','engagement_tick','page_exit','scroll_depth','click_internal',
      'click_outbound','cta_anchor_click','cta_booking_click','cta_phone_click','form_submit')
  ), gaps AS (
    SELECT k.*,k.t-lag(k.t) OVER(PARTITION BY k.vk ORDER BY k.t,(k.name='pageview') DESC,k.id) AS gap
    FROM keyed k
  ), segmented AS (
    SELECT g.id,g.name,g.t,g.raw_path,g.macro,g.vk,
      sum((g.gap IS NULL OR g.gap>interval '30 minutes')::int)
        OVER(PARTITION BY g.vk ORDER BY g.t,(g.name='pageview') DESC,g.id) AS seq
    FROM gaps g
  ), relevant AS MATERIALIZED (
    SELECT s.id,s.name,s.t,s.vk,s.seq,s.macro,p.path
    FROM segmented s LEFT JOIN paths p ON p.raw_path=s.raw_path
    WHERE (s.name='pageview' AND p.path IS NOT NULL) OR s.name IN ('cta_phone_click','form_submit')
  ), first_pages AS MATERIALIZED (
    SELECT DISTINCT ON (r.vk,r.seq) r.vk,r.seq,r.id,r.t,r.path
    FROM relevant r WHERE r.name='pageview'
    ORDER BY r.vk,r.seq,r.t,r.id
  )
  SELECT e.id,e.name,e.t,e.path,e.macro,entry.id,entry.t,entry.path
  FROM relevant e
  LEFT JOIN first_pages entry ON entry.vk=e.vk AND entry.seq=e.seq AND entry.t<=e.t
  WHERE e.t>=public.cooked_paris_ts_start(p_start)
  ORDER BY e.t,e.id;
END $function$;
REVOKE ALL ON FUNCTION public.cooked_visit_events(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_visit_events(date,date) TO service_role;

-- La classification de canaux n’a plus de consommateur dans le produit courant.
DROP FUNCTION public.classify_channel(text,text,text,text,text);
NOTIFY pgrst, 'reload schema';
COMMIT;
