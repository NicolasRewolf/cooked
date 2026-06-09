-- Sprint 37 (09/06/2026) — taxonomie des pages
-- Débloque les analyses "quel TYPE de contenu / quel THÈME performe"
-- au lieu de page par page.
--
-- 2 axes :
--   • page_type : déterministe par pattern d'URL (taxonomie CLAUDE.md)
--   • theme     : table page_taxonomy, seed heuristique slug (source tracée,
--                 corrigeable à la main ou par enrichissement futur).
--                 ⚠️ La CATÉGORIE Wix (ressource/classique) n'est PAS déductible
--                 du slug (règle CLAUDE.md) → colonne category, NULL en attendant
--                 un enrichissement via le hub /comprendre-le-droit.

create or replace function public.cooked_page_type(p text)
returns text
language sql
immutable
parallel safe
set search_path = public, pg_catalog
as $$
  select case
    when p is null then 'autre'
    when p = '/' then 'cabinet'
    when p in ('/notre-cabinet','/honoraires-rendez-vous','/mentions-legales','/comprendre-le-droit') then 'cabinet'
    when p in ('/defense-penale','/indemnisation-des-victimes','/droit-des-contrats-et-des-personnes') then 'hub'
    when p like '/defense-penale/%'
      or p like '/indemnisation-des-victimes/%'
      or p like '/droit-des-contrats-et-des-personnes/%' then 'expertise'
    when p like '/post/%' then 'post'
    when p like '/blog%' then 'blog-nav'
    else 'autre'
  end;
$$;
grant execute on function public.cooked_page_type(text) to public;

create table if not exists public.page_taxonomy (
  path       text primary key,
  category   text,
  theme      text,
  source     text not null,
  updated_at timestamptz not null default now()
);
revoke all on public.page_taxonomy from anon, authenticated;
grant select, insert, update, delete on public.page_taxonomy to service_role;

create or replace function public.refresh_page_taxonomy_heuristic()
returns int
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare v_count int;
begin
  with paths as (
    select distinct path from public.events_human
    where path like '/post/%' or public.cooked_page_type(path) in ('expertise','hub')
  ), themed as (
    select path,
      case
        when path ~* 'garde-.?-vue|gav' then 'garde à vue'
        when path ~* 'violence|f.minicide|conjugal|harc.lement|contr.le-coercitif' then 'violences & harcèlement'
        when path ~* 'indemnis|victime|civi|sarvi|pr.judice|dommage' then 'indemnisation victimes'
        when path ~* 'accident|erreur-m.dicale|route|travail' then 'accidents & réparation'
        when path ~* 'stup.fiant|trafic|drogue' then 'stupéfiants'
        when path ~* 'd.tention|prison|peine|sursis|bracelet|ddse|suret.|am.nagement' then 'peines & détention'
        when path ~* 'affaires|fraude|abus-de|escroquerie|blanchiment|corruption|fiscal' then 'pénal des affaires'
        when path ~* 'famille|divorce|filiation|succession|contrat' then 'famille & contrats'
        when path ~* 'instruction|proc.dure|comparution|tribunal|cour-d|assises|appel|mise-en-examen|t.moin|pr.venu|accus|perquisition|audition' then 'procédure pénale'
        when path ~* 'diffamation|injure|r.putation|presse' then 'réputation & presse'
        else null
      end as theme
    from paths
  )
  insert into public.page_taxonomy (path, theme, source)
  select path, theme, 'slug_heuristic' from themed where theme is not null
  on conflict (path) do update
    set theme = excluded.theme, updated_at = now()
    where page_taxonomy.source = 'slug_heuristic';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function public.refresh_page_taxonomy_heuristic() from public, anon, authenticated;
grant execute on function public.refresh_page_taxonomy_heuristic() to service_role;

select public.refresh_page_taxonomy_heuristic();
