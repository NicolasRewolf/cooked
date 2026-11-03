-- Alignement des lectures analytics sur leurs bornes canoniques.
-- Les signatures et unités restent identiques ; aucun calcul CPI modifié.

CREATE OR REPLACE FUNCTION public.math_visit_sequences(days_back integer DEFAULT 28)
 RETURNS TABLE(journey text[], converted boolean, entry_channel text, n bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with w as (
    select b.n_end as d_end, b.n_end - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  ev as materialized (
    select e.anonymous_id, e.session_id, e.name, e.path, e.occurred_at,
           e.referrer_hostname, e.utm_source, e.utm_medium, e.url
    from public.events_human e
    where e.name in ('pageview', 'cta_phone_click')
      and e.occurred_at >= public.cooked_paris_ts_start((select d_start from w))
      and e.occurred_at < public.cooked_paris_ts_end_exclusive((select d_end from w))
  ),
  pv as materialized (
    select
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(e.session_id, e.anonymous_id, 'inconnu')) as vk,
      e.path, e.occurred_at as t,
      e.referrer_hostname, e.utm_source, e.utm_medium, e.url
    from ev e
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = e.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = e.anonymous_id
    where e.name = 'pageview' and e.path is not null
  ),
  contacts as materialized (
    select
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(c.session_id, c.anonymous_id, 'inconnu')) as vk,
      c.occurred_at as t
    from (
      select e.occurred_at, e.anonymous_id, e.session_id
      from ev e where e.name = 'cta_phone_click'
      union all
      select f.occurred_at, f.resolved_anonymous_id, f.resolved_session_id
      from public.form_submits_attributed(days_back, (select d_end from w)) f
      where f.counts_as_macro
    ) c
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = c.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = c.anonymous_id
  ),
  vis as materialized (
    select seg.*,
      sum(is_new) over (partition by vk order by t rows unbounded preceding) as visit_no
    from (
      select pv.*,
        case when pv.t - lag(pv.t) over (partition by pv.vk order by pv.t)
                  > interval '30 minutes'
               or lag(pv.t) over (partition by pv.vk order by pv.t) is null
             then 1 else 0 end as is_new
      from pv
    ) seg
  ),
  bounds as materialized (
    select vk, visit_no, min(t) as t_start, max(t) as t_end
    from vis group by vk, visit_no
  ),
  -- un contact = au plus une visite : la plus recente qui le precede,
  -- dans la limite de 6 h (fenetre de conversion_journeys v2)
  contact_visit as materialized (
    select distinct on (c.vk, c.t) c.vk, c.t as contact_at, b.visit_no
    from contacts c
    join bounds b
      on b.vk = c.vk
     and b.t_start <= c.t + interval '3 minutes'
     and c.t <= b.t_end + interval '6 hours'
    order by c.vk, c.t, b.t_start desc
  ),
  vc as materialized (
    select vk, visit_no, min(contact_at) as contact_at
    from contact_visit group by vk, visit_no
  ),
  kept as materialized (
    select v.vk, v.visit_no, v.path, v.t,
           v.referrer_hostname, v.utm_source, v.utm_medium, v.url,
           (vc.contact_at is not null) as converted
    from vis v
    left join vc on vc.vk = v.vk and vc.visit_no = v.visit_no
    where vc.contact_at is null
       or v.t <= vc.contact_at + interval '3 minutes'
  ),
  entry as materialized (
    select distinct on (k.vk, k.visit_no)
           k.vk, k.visit_no, k.referrer_hostname, k.utm_source, k.utm_medium, k.url
    from kept k
    order by k.vk, k.visit_no, k.t
  ),
  per_visit as materialized (
    select f.vk, f.visit_no,
      array_agg(f.path order by f.first_seen) as journey,
      bool_or(f.converted) as converted
    from (
      select vk, visit_no, path, min(t) as first_seen, bool_or(converted) as converted
      from kept group by vk, visit_no, path
    ) f
    group by f.vk, f.visit_no
  ),
  raw_grouped as (
    select p.journey, p.converted,
           e.referrer_hostname, e.utm_source, e.utm_medium, e.url,
           count(*)::bigint as n
    from per_visit p
    join entry e on e.vk = p.vk and e.visit_no = p.visit_no
    group by 1, 2, 3, 4, 5, 6
  )
  select g.journey, g.converted,
         public.classify_channel(g.referrer_hostname, g.utm_source, g.utm_medium,
                                 'www.jplouton-avocat.fr', g.url),
         sum(g.n)::bigint
  from raw_grouped g
  group by 1, 2, 3;
$function$;
REVOKE ALL ON FUNCTION public.math_visit_sequences(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.math_visit_sequences(integer) TO service_role;

CREATE OR REPLACE FUNCTION public.content_performance(days_back integer DEFAULT 28)
 RETURNS TABLE(page_type text, theme text, pages integer, sessions bigint, dwell_median numeric, scroll_median numeric, booking_intents bigint, contacts_assisted bigint, contact_rate_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with w as (
    select b.n_end as d_end, b.n_end - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  base as (
    select e.path, public.cooked_page_type(e.path) as ptype, t.theme, e.session_id, e.name, e.props
    from public.events_human e
    left join public.page_taxonomy t on t.path = e.path
    where e.occurred_at >= public.cooked_paris_ts_start((select d_start from w))
      and e.occurred_at < public.cooked_paris_ts_end_exclusive((select d_end from w))
      and e.path is not null
  ),
  grp as (
    select ptype, theme, count(distinct path) as pages,
      count(distinct session_id) filter (where name='pageview') as sessions,
      count(*) filter (where name='cta_booking_click') as booking_intents
    from base group by ptype, theme
  ),
  dwagg as (
    select ptype, theme, session_id, path,
      max((props->>'duration_seconds')::numeric) as dur,
      max((props->>'max_scroll')::numeric) as scr
    from base where name='page_exit' group by ptype, theme, session_id, path
  ),
  dwm as (
    select ptype, theme,
      percentile_cont(0.5) within group (order by dur) as dwell_median,
      percentile_cont(0.5) within group (order by scr) as scroll_median
    from dwagg group by ptype, theme
  ),
  assists as (
    select public.cooked_page_type(jp.path) as ptype, t.theme,
      count(distinct (j.anonymous_id, j.occurred_at)) as contacts_assisted
    from public.conversion_journeys(days_back, (select d_end from w)) j
    cross join lateral unnest(j.journey) as jp(path)
    left join public.page_taxonomy t on t.path = jp.path
    group by 1, 2
  )
  select g.ptype, g.theme, g.pages::int, g.sessions,
    round(d.dwell_median::numeric,1), round(d.scroll_median::numeric,1),
    g.booking_intents, coalesce(a.contacts_assisted, 0),
    round(100.0 * coalesce(a.contacts_assisted,0) / nullif(g.sessions,0), 2)
  from grp g
  left join dwm d on d.ptype = g.ptype and d.theme is not distinct from g.theme
  left join assists a on a.ptype = g.ptype and a.theme is not distinct from g.theme
  order by g.sessions desc;
$function$;
REVOKE ALL ON FUNCTION public.content_performance(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.content_performance(integer) TO service_role;

CREATE OR REPLACE FUNCTION public.math_internal_edges(days_back integer DEFAULT 28)
 RETURNS TABLE(src text, dst text, kind text, placement text, weight bigint, dst_resolved boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with w as (
    select b.n_end as d_end, b.n_end - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  ev as materialized (
    select e.anonymous_id, e.session_id, e.name, e.path, e.occurred_at, e.props
    from public.events_human e
    where e.name in ('pageview', 'click_internal')
      and e.occurred_at >= public.cooked_paris_ts_start((select d_start from w))
      and e.occurred_at < public.cooked_paris_ts_end_exclusive((select d_end from w))
      and e.path is not null
  ),
  seen as (
    select distinct e.path from ev e where e.name = 'pageview'
  ),
  clicks_raw as (
    select e.path as src,
           e.props->>'target_path' as dst_raw,
           coalesce(e.props->>'placement', 'inconnu') as placement,
           count(*)::bigint as weight
    from ev e
    where e.name = 'click_internal' and e.props->>'target_path' is not null
    group by 1, 2, 3
  ),
  clicks as (
    -- resolution ciblee des cibles orphelines : les liens du site pointent
    -- vers des URL accentuees qui redirigent (301) vers la forme desaccentuee
    -- ou atterrissent les pageviews. On ne desaccentue QUE si la cible brute
    -- n'existe pas et que la forme desaccentuee, elle, existe.
    select c.src,
      case when c.raw_exists then c.dst_raw
           when c.flat_exists then c.dst_flat
           else c.dst_raw end as dst,
      c.placement, c.weight,
      (not c.raw_exists and c.flat_exists) as dst_resolved
    from (
      select c0.*,
        translate(c0.dst_raw, 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ',
                              'aaaeeeeiioouuucAAAEEEEIIOOUUUC') as dst_flat,
        exists (select 1 from seen s where s.path = c0.dst_raw) as raw_exists,
        exists (select 1 from seen s where s.path =
                translate(c0.dst_raw, 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ',
                                      'aaaeeeeiioouuucAAAEEEEIIOOUUUC')) as flat_exists
      from clicks_raw c0
    ) c
  ),
  pv as (
    select
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(e.session_id, e.anonymous_id, 'inconnu')) as vk,
      e.path, e.occurred_at as t
    from ev e
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = e.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = e.anonymous_id
    where e.name = 'pageview'
  ),
  seg as (
    select pv.*,
      case when pv.t - lag(pv.t) over (partition by pv.vk order by pv.t)
                > interval '30 minutes'
             or lag(pv.t) over (partition by pv.vk order by pv.t) is null
           then 1 else 0 end as is_new
    from pv
  ),
  vis as (
    select seg.*,
      sum(is_new) over (partition by vk order by t rows unbounded preceding) as visit_no
    from seg
  ),
  flows as (
    select v.path as src,
           lead(v.path) over (partition by v.vk, v.visit_no order by v.t) as dst
    from vis v
  )
  select f.src, f.dst, 'flow'::text, null::text, count(*)::bigint, false
  from flows f
  where f.dst is not null and f.dst <> f.src
  group by f.src, f.dst
  union all
  select c.src, c.dst, 'click'::text, c.placement, c.weight, c.dst_resolved
  from clicks c
  where c.dst <> c.src;
$function$;
REVOKE ALL ON FUNCTION public.math_internal_edges(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.math_internal_edges(integer) TO service_role;

-- Les anciennes lignes gardent NULL : leur période glissante ne devient pas
-- rétrospectivement une fenêtre close. Seul un nouveau refresh prouve ses bornes.
ALTER TABLE public.math_visit_sequences_snapshot
  ADD COLUMN IF NOT EXISTS window_start date,
  ADD COLUMN IF NOT EXISTS window_end date,
  ADD COLUMN IF NOT EXISTS calculation_version text;
ALTER TABLE public.math_internal_edges_snapshot
  ADD COLUMN IF NOT EXISTS window_start date,
  ADD COLUMN IF NOT EXISTS window_end date,
  ADD COLUMN IF NOT EXISTS calculation_version text;

CREATE OR REPLACE FUNCTION public.math_refresh_snapshots(p_window_days integer DEFAULT 28)
 RETURNS TABLE(sequences bigint, edges bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_seq bigint;
  v_edg bigint;
  v_start date;
  v_end date;
  v_computed_at timestamptz := now();
BEGIN
  IF p_window_days IS NULL OR p_window_days < 1 THEN
    RAISE EXCEPTION 'window_days must be a positive integer' USING ERRCODE = '22023';
  END IF;
  SELECT b.n_end - (p_window_days - 1), b.n_end INTO v_start, v_end
  FROM public.cooked_period_bounds('rolling_28', 'live_j1') b;

  DELETE FROM public.math_visit_sequences_snapshot WHERE window_days = p_window_days;
  INSERT INTO public.math_visit_sequences_snapshot
    (computed_at, window_days, window_start, window_end, calculation_version, journey, converted, entry_channel, n)
  SELECT v_computed_at, p_window_days, v_start, v_end, 'paris_j1_v1', s.journey, s.converted, s.entry_channel, s.n
  FROM public.math_visit_sequences(p_window_days) s;
  GET DIAGNOSTICS v_seq = ROW_COUNT;

  DELETE FROM public.math_internal_edges_snapshot WHERE window_days = p_window_days;
  INSERT INTO public.math_internal_edges_snapshot
    (computed_at, window_days, window_start, window_end, calculation_version, src, dst, kind, placement, weight, dst_resolved)
  SELECT v_computed_at, p_window_days, v_start, v_end, 'paris_j1_v1', e.src, e.dst, e.kind, e.placement, e.weight, e.dst_resolved
  FROM public.math_internal_edges(p_window_days) e;
  GET DIAGNOSTICS v_edg = ROW_COUNT;

  RETURN QUERY SELECT v_seq, v_edg;
END;
$function$;
REVOKE ALL ON FUNCTION public.math_refresh_snapshots(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.math_refresh_snapshots(integer) TO service_role;
