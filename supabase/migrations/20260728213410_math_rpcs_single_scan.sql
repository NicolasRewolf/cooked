-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Perf 2/3 — events_human coute ~12 s par evaluation sur 28 j (anti-join
-- nested loop sur bot_fingerprints : 77 lignes x 20 000 boucles). Les deux
-- RPC la scannaient 2 a 3 fois. Elle n'est desormais scannee QU'UNE fois,
-- via une CTE AS MATERIALIZED. La definition canonique d'events_human n'est
-- pas touchee (regle projet : source unique).
-- Etat final de math_internal_edges (math_visit_sequences : voir 20260728215013).

CREATE OR REPLACE FUNCTION public.math_internal_edges(days_back integer DEFAULT 28)
RETURNS TABLE(src text, dst text, kind text, placement text, weight bigint, dst_resolved boolean)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  with ev as materialized (
    select e.anonymous_id, e.session_id, e.name, e.path, e.occurred_at, e.props
    from public.events_human e
    where e.name in ('pageview', 'click_internal')
      and e.occurred_at > now() - make_interval(days => days_back)
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
