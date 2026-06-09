-- Sprint 37 (09/06/2026) — seo_to_contact_funnel : la boucle SEO complète
-- Requête Google → landing → sessions organiques → contacts macro.
-- LA vue qui répond à « quoi écrire / optimiser ensuite ».
-- NB historique : appliquée en prod en deux temps (sprint37_seo_to_contact_funnel
-- puis sprint37_seo_funnel_organic_channels — le filtre initial 'organic' ne
-- matchait pas les valeurs granulaires organic_google/organic_other/organic_ai
-- de classify_channel). Ce fichier consolide la version finale rejouable.
-- GSC est à J-2 : fenêtre identique, 2 derniers jours GSC vides.
-- Premiers résultats (28j, 09/06/2026) : home 6,1 % via branded ; expertise
-- droit-de-la-famille 13,3 % ; post DDSE 328 entrées mais 0,3 % (info intent).

create or replace function public.seo_to_contact_funnel(days_back int default 28)
returns table (
  entry_path text, page_type text, theme text,
  gsc_impressions bigint, gsc_clicks bigint, top_queries text[],
  organic_entries bigint, contacts bigint,
  contacts_phone bigint, contacts_form bigint, contact_rate_pct numeric
)
language sql stable security definer
set search_path = public, pg_catalog
as $$
  with entries as (
    select distinct on (e.session_id)
      e.session_id, e.path,
      public.classify_channel(e.referrer_hostname, e.utm_source, e.utm_medium,
                              'www.jplouton-avocat.fr') as channel
    from public.events_human e
    where e.name = 'pageview'
      and e.occurred_at > now() - make_interval(days => days_back)
    order by e.session_id, e.occurred_at
  ),
  organic as (
    select path as entry_path, count(*) as organic_entries
    from entries where channel like 'organic%'
    group by path
  ),
  conv as (
    select j.entry_path,
      count(*) as contacts,
      count(*) filter (where j.contact_kind = 'phone') as contacts_phone,
      count(*) filter (where j.contact_kind = 'form')  as contacts_form
    from public.conversion_journeys(days_back) j
    where j.entry_channel like 'organic%' and j.entry_path is not null
    group by j.entry_path
  ),
  gsc as (
    select g.path, sum(g.impressions) as impressions, sum(g.clicks) as clicks
    from public.gsc_path_daily g
    where g.day > current_date - days_back
    group by g.path
  ),
  topq as (
    select path, array_agg(query order by clicks desc) as top_queries
    from (
      select q.path, q.query, sum(q.clicks) as clicks,
        row_number() over (partition by q.path order by sum(q.clicks) desc) as rn
      from public.gsc_query_page_daily q
      where q.day > current_date - days_back
      group by q.path, q.query
    ) r where rn <= 3
    group by path
  )
  select
    o.entry_path, public.cooked_page_type(o.entry_path), t.theme,
    coalesce(g.impressions, 0), coalesce(g.clicks, 0), tq.top_queries,
    o.organic_entries, coalesce(c.contacts, 0),
    coalesce(c.contacts_phone, 0), coalesce(c.contacts_form, 0),
    round(100.0 * coalesce(c.contacts, 0) / nullif(o.organic_entries, 0), 2)
  from organic o
  left join conv c  on c.entry_path = o.entry_path
  left join gsc g   on g.path = o.entry_path
  left join topq tq on tq.path = o.entry_path
  left join public.page_taxonomy t on t.path = o.entry_path
  order by coalesce(c.contacts, 0) desc, coalesce(g.clicks, 0) desc;
$$;
revoke execute on function public.seo_to_contact_funnel(int) from public, anon, authenticated;
grant execute on function public.seo_to_contact_funnel(int) to service_role;
