-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Correction de rattachement contact -> visite. ETAT FINAL de la fonction.
--
-- La borne "contact <= fin de visite + 3 min" perdait 25 contacts sur 192
-- (dont 19 formulaires sur 43 : le temps de remplissage depasse largement
-- 3 min apres la derniere pageview). conversion_journeys v2 remonte jusqu'a
-- 6 h avant le contact ; on s'aligne, en rattachant chaque contact a la
-- visite la plus recente qui le precede.
--
-- Controle apres correction (28 j, 28/07/2026) : 161 visites converties et
-- 54 parcours multi-touch, contre 192 contacts et 63 parcours multi-touch
-- chez conversion_journeys(28). L'ecart est entierement explique par le
-- grain : cette RPC compte des VISITES, conversion_journeys des CONTACTS
-- (192 - 161 = 31 contacts surnumeraires, dont 9 sur des visites multi-touch).
CREATE OR REPLACE FUNCTION public.math_visit_sequences(days_back integer DEFAULT 28)
RETURNS TABLE(journey text[], converted boolean, entry_channel text, n bigint)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  with ev as materialized (
    select e.anonymous_id, e.session_id, e.name, e.path, e.occurred_at,
           e.referrer_hostname, e.utm_source, e.utm_medium
    from public.events_human e
    where e.name in ('pageview', 'cta_phone_click')
      and e.occurred_at > now() - make_interval(days => days_back)
  ),
  pv as materialized (
    select
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(e.session_id, e.anonymous_id, 'inconnu')) as vk,
      e.path, e.occurred_at as t,
      e.referrer_hostname, e.utm_source, e.utm_medium
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
      from public.form_submits_attributed(days_back) f
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
           v.referrer_hostname, v.utm_source, v.utm_medium,
           (vc.contact_at is not null) as converted
    from vis v
    left join vc on vc.vk = v.vk and vc.visit_no = v.visit_no
    where vc.contact_at is null
       or v.t <= vc.contact_at + interval '3 minutes'
  ),
  entry as materialized (
    select distinct on (k.vk, k.visit_no)
           k.vk, k.visit_no, k.referrer_hostname, k.utm_source, k.utm_medium
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
           e.referrer_hostname, e.utm_source, e.utm_medium,
           count(*)::bigint as n
    from per_visit p
    join entry e on e.vk = p.vk and e.visit_no = p.visit_no
    group by 1, 2, 3, 4, 5
  )
  select g.journey, g.converted,
         public.classify_channel(g.referrer_hostname, g.utm_source, g.utm_medium,
                                 'www.jplouton-avocat.fr'),
         sum(g.n)::bigint
  from raw_grouped g
  group by 1, 2, 3;
$function$;
