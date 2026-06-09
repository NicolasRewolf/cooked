-- Sprint 37 (09/06/2026) — attribution conversion → parcours
--
-- Problème : 100 % des form_submit ont une identité synthétique (webhook-…),
-- la conversion est orpheline de sa session. Audit 09/06 : stitching temporel
-- a posteriori plafonne à 56 % (35/63 sur 28j).
--
-- Solution en 2 temps :
--   1. (ce fichier) resolve : props.cooked_aid si présent (déposé par le
--      tracker sprint37 dans un champ caché Wix → renvoyé par le webhook),
--      sinon stitching temporel à candidat UNIQUE (fenêtre -20min/+3min sur
--      la page du formulaire). Méthode tracée dans chaque ligne.
--   2. (tracker sprint37 + webhook v10) alimentation de cooked_aid → ~95 %.
--
-- ⚠️ L'identité des LIGNES events reste synthétique (invariants Sprint 24/29
-- préservés : form_submit jamais bot/noise). L'attribution vit en lecture.

create or replace function public.form_submits_attributed(days_back int default 28)
returns table (
  event_id uuid,
  occurred_at timestamptz,
  form_path text,
  objet text,
  counts_as_macro boolean,
  resolved_anonymous_id text,
  resolved_session_id text,
  attribution_method text
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  with forms as (
    select e.id, e.occurred_at, e.path,
      e.props->>'objet_de_ma_demande' as objet,
      coalesce((e.props->>'counts_as_macro')::boolean, true) as counts_as_macro,
      nullif(e.props->>'cooked_aid','') as hf_aid,
      nullif(e.props->>'cooked_sid','') as hf_sid
    from public.events e
    where e.name = 'form_submit'
      and e.occurred_at > now() - make_interval(days => days_back)
  ),
  temporal as (
    select f.id as form_id,
      (array_agg(distinct e.anonymous_id)) as aids,
      (array_agg(distinct e.session_id)) as sids
    from forms f
    join public.events_human e
      on e.path = coalesce(f.path, '/honoraires-rendez-vous')
     and e.device_type is distinct from 'server'
     and e.anonymous_id not like 'webhook-%'
     and e.occurred_at between f.occurred_at - interval '20 min'
                           and f.occurred_at + interval '3 min'
    where f.hf_aid is null
    group by f.id
    having count(distinct e.anonymous_id) = 1
  )
  select f.id, f.occurred_at, f.path, f.objet, f.counts_as_macro,
    coalesce(f.hf_aid, t.aids[1]),
    coalesce(f.hf_sid, t.sids[1]),
    case
      when f.hf_aid is not null then 'hidden_field'
      when t.aids[1] is not null then 'temporal_unique'
      else 'unresolved'
    end
  from forms f
  left join temporal t on t.form_id = f.id;
$$;
revoke execute on function public.form_submits_attributed(int) from public, anon, authenticated;
grant execute on function public.form_submits_attributed(int) to service_role;

create or replace function public.conversion_journeys(days_back int default 28)
returns table (
  contact_kind text,
  occurred_at timestamptz,
  contact_path text,
  objet text,
  anonymous_id text,
  attribution_method text,
  entry_path text,
  entry_channel text,
  pages_count int,
  journey text[],
  device_type text
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
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
  sess as (
    select c.kind, c.occurred_at, c.contact_path, c.objet, c.anonymous_id,
      c.method, c.session_id,
      (select array_agg(p.path order by p.first_seen)
       from (select e2.path, min(e2.occurred_at) as first_seen
             from public.events_human e2
             where e2.session_id = c.session_id and e2.name = 'pageview'
               and e2.occurred_at <= c.occurred_at + interval '3 min'
             group by e2.path) p) as journey,
      (select e3.referrer_hostname from public.events_human e3
       where e3.session_id = c.session_id and e3.name='pageview'
       order by e3.occurred_at limit 1) as first_ref,
      (select e4.utm_source from public.events_human e4
       where e4.session_id = c.session_id and e4.name='pageview'
       order by e4.occurred_at limit 1) as first_utm_source,
      (select e5.utm_medium from public.events_human e5
       where e5.session_id = c.session_id and e5.name='pageview'
       order by e5.occurred_at limit 1) as first_utm_medium,
      (select e6.device_type from public.events_human e6
       where e6.session_id = c.session_id and e6.device_type is distinct from 'server'
       limit 1) as dev
    from contacts c
  )
  select s.kind, s.occurred_at, s.contact_path, s.objet, s.anonymous_id, s.method,
    s.journey[1],
    public.classify_channel(s.first_ref, s.first_utm_source, s.first_utm_medium, 'www.jplouton-avocat.fr'),
    coalesce(array_length(s.journey,1),0),
    s.journey,
    s.dev
  from sess s
  order by s.occurred_at desc;
$$;
revoke execute on function public.conversion_journeys(int) from public, anon, authenticated;
grant execute on function public.conversion_journeys(int) to service_role;

create or replace function public.content_performance(days_back int default 28)
returns table (
  page_type text,
  theme text,
  pages int,
  sessions bigint,
  dwell_median numeric,
  scroll_median numeric,
  booking_intents bigint,
  contacts_assisted bigint,
  contact_rate_pct numeric
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  with base as (
    select e.path,
      public.cooked_page_type(e.path) as ptype,
      t.theme,
      e.session_id, e.name, e.props
    from public.events_human e
    left join public.page_taxonomy t on t.path = e.path
    where e.occurred_at > now() - make_interval(days => days_back)
      and e.path is not null
  ),
  grp as (
    select ptype, theme,
      count(distinct path) as pages,
      count(distinct session_id) filter (where name='pageview') as sessions,
      percentile_cont(0.5) within group (order by (props->>'duration_seconds')::numeric)
        filter (where name='page_exit') as dwell_median,
      percentile_cont(0.5) within group (order by (props->>'max_scroll')::numeric)
        filter (where name='page_exit') as scroll_median,
      count(*) filter (where name='cta_booking_click') as booking_intents
    from base
    group by ptype, theme
  ),
  assists as (
    select public.cooked_page_type(jp.path) as ptype, t.theme,
      count(distinct (j.anonymous_id, j.occurred_at)) as contacts_assisted
    from public.conversion_journeys(days_back) j
    cross join lateral unnest(j.journey) as jp(path)
    left join public.page_taxonomy t on t.path = jp.path
    group by 1, 2
  )
  select g.ptype, g.theme, g.pages::int, g.sessions,
    round(g.dwell_median::numeric,1), round(g.scroll_median::numeric,1),
    g.booking_intents,
    coalesce(a.contacts_assisted, 0),
    round(100.0 * coalesce(a.contacts_assisted,0) / nullif(g.sessions,0), 2)
  from grp g
  left join assists a on a.ptype = g.ptype and a.theme is not distinct from g.theme
  order by g.sessions desc;
$$;
revoke execute on function public.content_performance(int) from public, anon, authenticated;
grant execute on function public.content_performance(int) to service_role;
