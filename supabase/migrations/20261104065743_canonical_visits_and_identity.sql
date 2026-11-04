CREATE OR REPLACE FUNCTION public.url_decode(input text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  result        text  := '';
  i             int   := 1;
  len           int   := length(input);
  pending       bytea := ''::bytea;
  hex_pair      text;
begin
  if input is null then
    return null;
  end if;
  -- Le chemin déjà décodé est le cas courant ; le résultat de la boucle serait identique.
  if strpos(input, '%') = 0 then
    return input;
  end if;
  while i <= len loop
    if substring(input from i for 1) = '%'
       and i + 2 <= len
       and substring(input from i+1 for 2) ~ '^[0-9A-Fa-f]{2}$'
    then
      hex_pair := substring(input from i+1 for 2);
      pending  := pending || decode(hex_pair, 'hex');
      i := i + 3;
    else
      if length(pending) > 0 then
        result  := result || convert_from(pending, 'UTF8');
        pending := ''::bytea;
      end if;
      result := result || substring(input from i for 1);
      i := i + 1;
    end if;
  end loop;
  if length(pending) > 0 then
    result := result || convert_from(pending, 'UTF8');
  end if;
  return result;
exception
  when others then
    return input;
end;
$function$;

-- Même périmètre que cooked_site_scope(...)=main, exprimé directement pour
-- que le planificateur n'estime pas à tort une sélectivité de 0,5 %.
CREATE OR REPLACE FUNCTION public.cooked_is_main_site(hostname text,props jsonb DEFAULT '{}'::jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT hostname IS DISTINCT FROM 'outremer.jplouton-avocat.fr'
  AND (props->>'cooked_site') IS DISTINCT FROM 'outremer' $$;

-- Une seule couture historique, sans table ni pipeline supplémentaire.
-- p_days reste accepté pour les appels existants ; la rétention des événements
-- conservés est désormais le périmètre, même pour refresh_identity_stitch(90).
CREATE OR REPLACE FUNCTION public.refresh_identity_stitch(p_days integer DEFAULT 400)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO public, pg_catalog SET statement_timeout TO '420s'
AS $$
DECLARE changed bigint;
BEGIN
  IF p_days IS NULL OR p_days<1 THEN
    RAISE EXCEPTION 'p_days must be positive' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(782028);
  DROP TABLE IF EXISTS pg_temp._st_pairs;
  DROP TABLE IF EXISTS pg_temp._st_labels;
  CREATE TEMP TABLE _st_pairs ON COMMIT DROP AS
    SELECT DISTINCT anonymous_id AS a,session_id AS s FROM public.events
    WHERE nullif(anonymous_id,'') IS NOT NULL AND nullif(session_id,'') IS NOT NULL
      AND anonymous_id NOT LIKE 'webhook-%' AND session_id NOT LIKE 'webhook-%'
      AND anonymous_id !~ '^[0-9a-f]{32}$';
  CREATE TEMP TABLE _st_labels ON COMMIT DROP AS
    SELECT s,min(a) AS label FROM pg_temp._st_pairs GROUP BY s;
  CREATE UNIQUE INDEX ON _st_labels(s);
  ANALYZE pg_temp._st_pairs;
  ANALYZE pg_temp._st_labels;
  -- Converger réellement plutôt que supposer qu'exactement trois passes suffisent.
  LOOP
    WITH aid_labels AS MATERIALIZED (
      SELECT p.a,min(l.label) AS label FROM pg_temp._st_pairs p
      JOIN pg_temp._st_labels l USING(s) GROUP BY p.a
    ), sid_labels AS (
      SELECT p.s,min(a.label) AS label FROM pg_temp._st_pairs p
      JOIN aid_labels a USING(a) GROUP BY p.s
    )
    UPDATE pg_temp._st_labels l SET label=n.label FROM sid_labels n
    WHERE l.s=n.s AND l.label IS DISTINCT FROM n.label;
    GET DIAGNOSTICS changed=ROW_COUNT;
    EXIT WHEN changed=0;
  END LOOP;
  DELETE FROM public.identity_stitch;
  INSERT INTO public.identity_stitch(kind,key,visitor_key)
    SELECT 'sid',s,label FROM pg_temp._st_labels
    UNION ALL
    SELECT 'aid',p.a,min(l.label) FROM pg_temp._st_pairs p JOIN pg_temp._st_labels l USING(s) GROUP BY p.a;
  INSERT INTO public.cooked_config(key,value,updated_at)
    VALUES ('identity_stitch_refreshed_at',now()::text,now()),
      ('identity_stitch_rows',(SELECT count(*)::text FROM public.identity_stitch),now())
  ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=EXCLUDED.updated_at;
END $$;
REVOKE ALL ON FUNCTION public.refresh_identity_stitch(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_identity_stitch(integer) TO service_role;

-- Primitive unique. Les pageviews, activités et contacts précèdent la coupe
-- calendaire afin de conserver l'entrée réelle d'une visite commencée avant.
-- Aucun événement futur, aucune attribution par proximité temporelle.
-- journey décrit uniquement le parcours avant un contact ; NULL sur les pageviews.
CREATE OR REPLACE FUNCTION public.cooked_visit_events(p_start date,p_end date)
RETURNS TABLE(event_id uuid,event_name text,occurred_at timestamptz,path text,
  anonymous_id text,objet text,counts_as_macro boolean,attribution_method text,
  visit_id uuid,entry_at timestamptz,entry_path text,entry_channel text,
  journey text[],device_type text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog SET jit TO off
AS $$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end>=public.paris_today() THEN
    RAISE EXCEPTION 'Expected completed Paris days with start <= end' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
  WITH raw AS MATERIALIZED (
    SELECT e.id,e.name,e.occurred_at AS t,CASE WHEN e.name IN ('pageview','cta_phone_click','form_submit') AND nullif(e.path,'') IS NOT NULL THEN public.canonical_path(e.path) END AS path,
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
END $$;
REVOKE ALL ON FUNCTION public.cooked_visit_events(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_visit_events(date,date) TO service_role;

CREATE OR REPLACE FUNCTION public.form_submits_attributed(days_back integer DEFAULT 28,p_end date DEFAULT NULL)
RETURNS TABLE(event_id uuid,occurred_at timestamptz,form_path text,objet text,counts_as_macro boolean,
  resolved_anonymous_id text,resolved_session_id text,attribution_method text,window_start date,window_end date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog
AS $$
  WITH w AS (
    SELECT coalesce(p_end,b.n_end) AS last_day,coalesce(p_end,b.n_end)-days_back+1 AS first_day
    FROM public.cooked_period_bounds('rolling_28','live_j1') b
  )
  SELECT v.event_id,v.occurred_at,v.path,v.objet,v.counts_as_macro,
    CASE WHEN v.attribution_method='hidden_field' THEN v.anonymous_id END,
    CASE WHEN v.attribution_method='hidden_field' THEN nullif(e.props->>'cooked_sid','') END,
    v.attribution_method,w.first_day,w.last_day
  FROM w CROSS JOIN LATERAL public.cooked_visit_events(w.first_day,w.last_day) v
  JOIN public.events e ON e.id=v.event_id
  WHERE v.event_name='form_submit';
$$;
REVOKE ALL ON FUNCTION public.form_submits_attributed(integer,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.form_submits_attributed(integer,date) TO service_role;

CREATE OR REPLACE FUNCTION public.conversion_journeys(days_back integer DEFAULT 28,p_end date DEFAULT NULL)
RETURNS TABLE(contact_kind text,occurred_at timestamptz,contact_path text,objet text,anonymous_id text,
  attribution_method text,entry_path text,entry_channel text,pages_count integer,journey text[],
  device_type text,window_start date,window_end date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog
AS $$
  WITH w AS (
    SELECT coalesce(p_end,b.n_end) AS last_day,coalesce(p_end,b.n_end)-days_back+1 AS first_day
    FROM public.cooked_period_bounds('rolling_28','live_j1') b
  )
  SELECT CASE e.event_name WHEN 'cta_phone_click' THEN 'phone' ELSE 'form' END,
    e.occurred_at,e.path,e.objet,e.anonymous_id,e.attribution_method,e.entry_path,e.entry_channel,
    cardinality(e.journey),e.journey,e.device_type,w.first_day,w.last_day
  FROM w CROSS JOIN LATERAL public.cooked_visit_events(w.first_day,w.last_day) e
  WHERE e.counts_as_macro;
$$;
REVOKE ALL ON FUNCTION public.conversion_journeys(integer,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.conversion_journeys(integer,date) TO service_role;

CREATE OR REPLACE FUNCTION public.assisted_contacts_by_entry_path(p_start date,p_end date)
RETURNS TABLE(entry_path text,contacts bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog
SET statement_timeout TO '300s'
AS $$
  SELECT coalesce(e.entry_path,'(non attribuable)'),count(*)
  FROM public.cooked_visit_events(p_start,p_end) e
  WHERE e.counts_as_macro GROUP BY 1;
$$;
REVOKE ALL ON FUNCTION public.assisted_contacts_by_entry_path(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.assisted_contacts_by_entry_path(date,date) TO service_role;

-- Une ligne par page observée, puis une ligne kind=coverage/path=NULL.
-- Visites consultantes : dédoublonnées par visite et page dans la période.
-- Numérateurs : visites entrées et ayant réalisé l'action dans la même période.
-- Les contacts survenus après sa clôture ne sont pas anticipés.
CREATE OR REPLACE FUNCTION public.page_visits(p_start date,p_end date)
RETURNS TABLE(row_kind text,path text,visits bigint,entries bigint,phone_visits bigint,
  form_visits bigint,contact_visits bigint,contact_rate_pct numeric,observed_days integer,
  unattributed_phone_events bigint,unattributed_form_events bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog
AS $$
  WITH e AS MATERIALIZED (SELECT * FROM public.cooked_visit_events(p_start,p_end)),
  per_page AS (
    SELECT e.path,count(DISTINCT e.visit_id) AS visits,
      count(DISTINCT e.visit_id) FILTER(WHERE e.event_id=e.visit_id) AS entries
    FROM e WHERE e.event_name='pageview' GROUP BY e.path
  ), contacts AS (
    SELECT e.entry_path,
      count(DISTINCT e.visit_id) FILTER(WHERE e.event_name='cta_phone_click') AS phone,
      count(DISTINCT e.visit_id) FILTER(WHERE e.event_name='form_submit') AS form,
      count(DISTINCT e.visit_id) AS union_count
    FROM e WHERE e.counts_as_macro AND e.entry_at>=public.cooked_paris_ts_start(p_start)
    GROUP BY e.entry_path
  )
  SELECT 'page',p.path,p.visits,p.entries,coalesce(c.phone,0),coalesce(c.form,0),coalesce(c.union_count,0),
    round(100.0*coalesce(c.union_count,0)/nullif(p.entries,0),2),NULL::integer,NULL::bigint,NULL::bigint
  FROM per_page p LEFT JOIN contacts c ON c.entry_path=p.path
  UNION ALL
  SELECT 'coverage',NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    count(DISTINCT public.paris_date(e.occurred_at)) FILTER(WHERE e.event_name='pageview')::integer,
    count(*) FILTER(WHERE e.event_name='cta_phone_click' AND e.visit_id IS NULL),
    count(*) FILTER(WHERE e.event_name='form_submit' AND e.counts_as_macro AND e.visit_id IS NULL)
  FROM e;
$$;
REVOKE ALL ON FUNCTION public.page_visits(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.page_visits(date,date) TO service_role;

CREATE OR REPLACE FUNCTION public.seo_to_contact_funnel(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(entry_path text, page_type text, theme text, gsc_impressions bigint, gsc_clicks bigint, top_queries text[], organic_entries bigint, contacts bigint, contacts_phone bigint, contacts_form bigint, contact_rate_pct numeric, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- Comptes rectifiés au grain visite. Les actions sont observées avant la
  -- clôture et seules les visites entrées dans cette fenêtre alimentent le taux.
  -- Signature conservée ; contacts/phone/form désignent désormais les visites.
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'cross') b
  ),
  e as materialized (
    select v.* from w cross join lateral public.cooked_visit_events(w.d_start,w.d_end) v
  ),
  organic as (
    select e.entry_path,count(*) as organic_entries
    from e where e.event_name='pageview' and e.event_id=e.visit_id
      and e.entry_channel like 'organic%'
    group by e.entry_path
  ),
  conv as (
    select e.entry_path,count(distinct e.visit_id) as contacts,
      count(distinct e.visit_id) filter(where e.event_name='cta_phone_click') as contacts_phone,
      count(distinct e.visit_id) filter(where e.event_name='form_submit') as contacts_form
    from e where e.counts_as_macro and e.entry_channel like 'organic%'
      and e.entry_at>=public.cooked_paris_ts_start((select d_start from w))
    group by e.entry_path
  ),
  gsc as (
    select g.path, sum(g.impressions) as impressions, sum(g.clicks) as clicks
    from public.gsc_path_daily g
    where g.day between (select d_start from w) and (select d_end from w)
    group by g.path
  ),
  topq as (
    select path, array_agg(query order by clicks desc) as top_queries
    from (
      select q.path, q.query, sum(q.clicks) as clicks,
        row_number() over (partition by q.path order by sum(q.clicks) desc) as rn
      from public.gsc_query_page_daily q
      where q.day between (select d_start from w) and (select d_end from w)
      group by q.path, q.query
    ) r where rn <= 3
    group by path
  ),
  pages as (
    select coalesce(o.entry_path, c.entry_path) as entry_path,
           coalesce(o.organic_entries, 0) as organic_entries,
           coalesce(c.contacts, 0) as contacts,
           coalesce(c.contacts_phone, 0) as contacts_phone,
           coalesce(c.contacts_form, 0) as contacts_form
    from organic o
    full join conv c on c.entry_path = o.entry_path
  )
  select
    p.entry_path, public.cooked_page_type(p.entry_path), t.theme,
    coalesce(g.impressions, 0), coalesce(g.clicks, 0), tq.top_queries,
    p.organic_entries, p.contacts, p.contacts_phone, p.contacts_form,
    round(100.0 * p.contacts / nullif(p.organic_entries, 0), 2),
    w.d_start, w.d_end
  from pages p
  cross join w
  left join gsc g   on g.path = p.entry_path
  left join topq tq on tq.path = p.entry_path
  left join public.page_taxonomy t on t.path = p.entry_path
  order by p.contacts desc, coalesce(g.clicks, 0) desc;
$function$;
REVOKE ALL ON FUNCTION public.seo_to_contact_funnel(integer,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.seo_to_contact_funnel(integer,date) TO service_role;
