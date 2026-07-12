-- conversion_journeys v2 (12/07/2026) — parcours sur le VISITEUR RECOUSU.
-- v1 joignait par session brute : dès que le tracker (≤ sprint40) avait
-- fait tourner ses ids en cours de visite (~22 % des sessions), le journey
-- était tronqué à la session du contact — entry_path faux (souvent la page
-- du contact elle-même), entry_channel NULL (referrer interne), et l'amont
-- réel (l'article lu) absent du journey. Consommateurs impactés :
-- cooked_page_index (composante conversion : direct + assists 1/L),
-- seo_to_contact_funnel (contacts organiques perdus), content_performance.
-- v2 : le contact est résolu vers son visitor_key (identity_stitch,
-- sid > aid > fallback session brute), le journey = pageviews de la VISITE
-- recousue (fenêtre [t-6h, t+3min], chaîne sans trou > 30 min — même
-- sémantique que la fenêtre de session du tracker et que le refresher
-- contacts assistés v2). Contrat de sortie STRICTEMENT inchangé.
-- Validation : cas d'école du 11/07 18:52 → entry_path = l'article
-- /post/arnaque-en-ligne-victime-escroquerie-recours, entry_channel
-- organic_google, journey [article, /honoraires-rendez-vous].
CREATE OR REPLACE FUNCTION public.conversion_journeys(days_back integer DEFAULT 28)
 RETURNS TABLE(contact_kind text, occurred_at timestamp with time zone, contact_path text, objet text, anonymous_id text, attribution_method text, entry_path text, entry_channel text, pages_count integer, journey text[], device_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with contacts as (
    select 'phone'::text as kind, e.occurred_at, e.path as contact_path,
      null::text as objet, e.anonymous_id, e.session_id, 'direct'::text as method
    from public.events_human e
    where e.name = 'cta_phone_click'
      and e.occurred_at > now() - make_interval(days => days_back)
    union all
    select 'form', f.occurred_at, f.form_path, f.objet,
      f.resolved_anonymous_id, f.resolved_session_id, f.attribution_method
    from public.form_submits_attributed(days_back) f
    where f.counts_as_macro
  ),
  ck as (
    select c.*,
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(c.session_id, c.anonymous_id, 'inconnu')) as vk
    from contacts c
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = c.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = c.anonymous_id
  ),
  -- sessions couvertes par chaque visiteur porteur de contact
  -- (fallback : la session brute du contact si la couture ne la connaît
  -- pas encore — sessions plus récentes que le dernier refresh du stitch)
  vsess as (
    select k.vk, st.key as sid
    from (select distinct vk from ck) k
    join public.identity_stitch st on st.kind = 'sid' and st.visitor_key = k.vk
    union
    select c.vk, c.session_id from ck c where c.session_id is not null
  )
  select s.kind, s.occurred_at, s.contact_path, s.objet, s.anonymous_id, s.method,
    s.journey[1],
    public.classify_channel(s.first_ref, s.first_utm_source, s.first_utm_medium, 'www.jplouton-avocat.fr'),
    coalesce(array_length(s.journey, 1), 0),
    s.journey,
    s.dev
  from (
    select c.kind, c.occurred_at, c.contact_path, c.objet, c.anonymous_id, c.method,
      j.journey, j.first_ref, j.first_utm_source, j.first_utm_medium,
      (select e6.device_type from public.events_human e6
        where e6.session_id in (select v2.sid from vsess v2 where v2.vk = c.vk)
          and e6.device_type is distinct from 'server'
        limit 1) as dev
    from ck c
    left join lateral (
      with pv as (
        select e2.path, e2.occurred_at as t,
               e2.referrer_hostname, e2.utm_source, e2.utm_medium
        from public.events_human e2
        where e2.name = 'pageview'
          and e2.session_id in (select v.sid from vsess v where v.vk = c.vk)
          and e2.occurred_at <= c.occurred_at + interval '3 min'
          and e2.occurred_at >= c.occurred_at - interval '6 hours'
      ),
      seg as (
        select pv.*,
          case when pv.t - lag(pv.t) over (order by pv.t) > interval '30 minutes'
               then pv.t end as brk
        from pv
      ),
      chain as (
        select * from seg
        where seg.t >= coalesce((select max(s2.brk) from seg s2), '-infinity'::timestamptz)
      )
      select
        (select array_agg(q.path order by q.first_seen)
           from (select ch.path, min(ch.t) as first_seen from chain ch group by ch.path) q) as journey,
        (select ch.referrer_hostname from chain ch order by ch.t limit 1) as first_ref,
        (select ch.utm_source from chain ch order by ch.t limit 1) as first_utm_source,
        (select ch.utm_medium from chain ch order by ch.t limit 1) as first_utm_medium
    ) j on true
  ) s
  order by s.occurred_at desc;
$function$;
