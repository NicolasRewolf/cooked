-- REVERT de 20260728103000_content_performance_via_page_reads.
--
-- Le rebranchement etait fonctionnellement neutre (medianes identiques ligne
-- a ligne) mais coute trop cher : content_performance passait en ~27 s, elle
-- depasse 120 s apres.
--
-- CAUSE — page_reads(timestamptz, timestamptz) est SECURITY DEFINER et porte
-- un SET search_path : deux raisons pour lesquelles PostgreSQL ne peut PAS
-- l'inliner. L'ancien code reutilisait le CTE `base` deja materialise pour
-- grp ; l'appel de fonction impose deux scans supplementaires de events_human
-- (page_exit + pageview) que le planificateur ne peut ni partager ni fusionner.
--
-- Le coût ne vient pas des index : idx_events_name_occurred (name,
-- occurred_at DESC) couvre exactement le filtre. Il vient de events_human,
-- vue dont chaque ligne traverse une anti-jointure sur noise_sessions, le
-- filtre chrome-anchor et la sous-requete de dedup meme-seconde. Chaque
-- appelant la paie deja une fois ; page_reads en ajoute une seconde.
--
-- CONSEQUENCE — un concept destine a etre lu par 8 RPC ne peut pas etre une
-- barriere d'optimisation. page_reads doit etre MATERIALISE (comme
-- identity_stitch, seo_url_snapshot et cpi_daily le sont deja) avant que le
-- moindre appelant y soit rebranche. La couture et sa preuve d'equivalence
-- restent valides ; c'est sa forme d'execution qui est a revoir.
--
-- On restaure la definition d'avant, a l'identique. Verifie apres revert :
-- cabinet 19,0/23,0 · expertise famille 35,0/31,0 · post 49,0/44,0 ·
-- post garde a vue 72,0/39,0 — identiques a la photo de reference.

CREATE OR REPLACE FUNCTION public.content_performance(days_back integer DEFAULT 28)
 RETURNS TABLE(page_type text, theme text, pages integer, sessions bigint, dwell_median numeric, scroll_median numeric, booking_intents bigint, contacts_assisted bigint, contact_rate_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with base as (
    select e.path, public.cooked_page_type(e.path) as ptype, t.theme, e.session_id, e.name, e.props
    from public.events_human e
    left join public.page_taxonomy t on t.path = e.path
    where e.occurred_at > now() - make_interval(days => days_back) and e.path is not null
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
    from public.conversion_journeys(days_back) j
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
