-- T-19 (audit + cartographie du 02/07/2026) — page_taxonomy : seed sitemap + purge poubelle
-- ============================================================================
-- Constat (cartographie sitemap × API Wix × prod, 02/07/2026) :
--   * page_taxonomy a été construite depuis le TRAFIC observé, jamais depuis
--     l'inventaire → 46 posts du sitemap (419 posts au 02/07) en étaient
--     absents (posts « affaires » à faible/zéro trafic). Toute analyse par
--     catégorie les ignorait silencieusement.
--   * 13 paths hors sitemap traînaient dans la table, entrés par l'heuristique
--     depuis des visites réelles : 9 sont de la poubelle pure (3 URLs de
--     preview Wix avec token, 1 mojibake « contrÃ´le… », 2 slugs tronqués,
--     2 URLs concaténées par erreur de collage, 1 variante avec parenthèse) ;
--     4 sont des ANCIENS SLUGS légitimes d'articles re-sluggés
--     (accident-médical-oniam, sarci-ou-civi, contrôle-coercitif sans î,
--     achat-de-vehicules sans accents) → CONSERVÉS : ils portent la
--     catégorisation du trafic historique. NOTE : sarci-ou-civi reste
--     category='classique' bien que son contenu soit la ressource
--     sarvi-ou-civi — volontaire, pour préserver l'invariant « 57 ressources
--     en base = 57 dans la catégorie API Wix » (contrôle de drift).
--   * Provenance des categories insérées : API Wix Blog vérifiée le
--     02/07/2026 — la catégorie « Ressources et notions juridiques »
--     (9477320f-…) totalise toujours 57 posts, tous déjà en base → les 46
--     manquants sont tous « classique ». Thème : mêmes regex que
--     refresh_page_taxonomy_heuristic (source='slug_heuristic').
--   * Sans garde-fou, refresh_page_taxonomy_heuristic() ré-insérerait la
--     poubelle au prochain run (scan de TOUT events_human, et le mojibake
--     matche la regex violences). → la fonction est amendée : borne 90 j
--     + exclusions structurelles (preview, http, mojibake, longueur).
--     Risque résiduel accepté : une variante courte re-visitée dans les 90 j
--     peut ré-entrer (rare, et re-purgeable).
-- ============================================================================

-- 1) Heuristique : borne 90 j + garde-fous anti-poubelle
create or replace function public.refresh_page_taxonomy_heuristic()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare v_count int;
begin
  with paths as (
    select distinct path from public.events_human
    where (path like '/post/%' or public.cooked_page_type(path) in ('expertise','hub'))
      -- T-19 : ne considérer que le trafic récent (évite de ressusciter de
      -- vieux paths morts) et exclure la poubelle structurelle
      and occurred_at > now() - interval '90 days'
      and path not like '%/preview/%'   -- previews Wix avec token
      and path !~ 'https?://'           -- URLs concaténées par erreur
      and path !~ '[ÃÂ]'                -- mojibake (double encodage)
      and length(path) <= 140           -- tokens/concaténations aberrantes
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
$function$;

-- 2) Purge des 9 paths poubelle (jamais dans le sitemap, artefacts de visites)
delete from public.page_taxonomy where path in (
    '/post/279fc8a2-a0f0-435d-855b-6912e006ac4a/preview/e9hsd5ajR1I1h8Oz4D0TzYxxkVyqXt_7AOHv3_0alkI.eyJpbnN0YW5jZUlkIjoiMDFjYzliNDEtYzE3NC00NzRiLTg5YmEtNGFlMjA5Yzc2ZGNiIiwiYXBwRGVmSWQiOiIxNGJjZGVkNy0wMDY2LTdjMzUtMTRkNy00NjZjYjNmMDkxMDMiLCJtZXRhU2l0ZUlkIjoiMDg3MDIzNWMtYjkyZC00YTY5LWEyZjQtMjVhOTc2YWU1ZjBjIiwic2lnbkRhdGUiOiIyMDI2LTA1LTIwVDIyOjM3OjM1LjMyNloiLCJ1aWQiOiJkMDVjOWVhNC1iMmZiLTQzZTctOWRlNC01MmZlODU3N2U1NGIiLCJwZXJtaXNzaW9ucyI6Ik9XTkVSIiwiZGVtb01vZGUiOmZhbHNlLCJiaVRva2VuIjoiMDliY2I4MWQtNzg1OS0wZDIyLTJiNGUtNmY0YjdmNjkzMmM3Iiwic2l0ZU93bmVySWQiOiIwNzQ1NGYxZi1jNTRhLTQzMDgtYjg5Ny0xOWJlNTU0ZGI4OGEiLCJzaXRlTWVtYmVySWQiOiIyMWI3ODU1MC01MjhlLTRhZDUtOWEzZC04OGQ4ZDQ0NjEwNDAiLCJleHBpcmF0aW9uRGF0ZSI6IjIwMjYtMDUtMjFUMDI6Mzc6MzUuMzI2WiIsImxvZ2luQWNjb3VudElkIjoiZDA1YzllYTQtYjJmYi00M2U3LTlkZTQtNTJmZTg1NzdlNTRiIiwiYW9yIjp0cnVlLCJzaWQiOiI0NThiMjM3Yi00ZGJmLTQxZTktYTI4Ny0wZTBhY2EzNzYwNWIiLCJzY2QiOiIyMDI0LTEyLTI0VDEyOjM2OjQzLjA2M1oiLCJhY2QiOiIyMDI1LTAxLTIzVDEyOjEyOjM5WiIsInNzIjp0cnVlfQ',
    '/post/9ee4af32-5eca-4630-a9e5-0c3bcf0b4e04/preview/r_I-nxHFBJemfhIdFVk4q-OYPk-9JTQ9TGBVRmhLD6o.eyJpbnN0YW5jZUlkIjoiMDFjYzliNDEtYzE3NC00NzRiLTg5YmEtNGFlMjA5Yzc2ZGNiIiwiYXBwRGVmSWQiOiIxNGJjZGVkNy0wMDY2LTdjMzUtMTRkNy00NjZjYjNmMDkxMDMiLCJtZXRhU2l0ZUlkIjoiMDg3MDIzNWMtYjkyZC00YTY5LWEyZjQtMjVhOTc2YWU1ZjBjIiwic2lnbkRhdGUiOiIyMDI2LTA1LTExVDE0OjEwOjQxLjMyN1oiLCJ1aWQiOiJkMDVjOWVhNC1iMmZiLTQzZTctOWRlNC01MmZlODU3N2U1NGIiLCJwZXJtaXNzaW9ucyI6Ik9XTkVSIiwiZGVtb01vZGUiOmZhbHNlLCJiaVRva2VuIjoiMDliY2I4MWQtNzg1OS0wZDIyLTJiNGUtNmY0YjdmNjkzMmM3Iiwic2l0ZU93bmVySWQiOiIwNzQ1NGYxZi1jNTRhLTQzMDgtYjg5Ny0xOWJlNTU0ZGI4OGEiLCJzaXRlTWVtYmVySWQiOiIyMWI3ODU1MC01MjhlLTRhZDUtOWEzZC04OGQ4ZDQ0NjEwNDAiLCJleHBpcmF0aW9uRGF0ZSI6IjIwMjYtMDUtMTFUMTg6MTA6NDEuMzI3WiIsImxvZ2luQWNjb3VudElkIjoiZDA1YzllYTQtYjJmYi00M2U3LTlkZTQtNTJmZTg1NzdlNTRiIiwiYW9yIjp0cnVlLCJzaWQiOiI1NGFhOTU4Yy05MjgxLTRmOTYtYTU5MC02NTQwYzUyOGQyODIiLCJzY2QiOiIyMDI0LTEyLTI0VDEyOjM2OjQzLjA2M1oiLCJhY2QiOiIyMDI1LTAxLTIzVDEyOjEyOjM5WiIsInNzIjp0cnVlfQ',
    '/post/accident-de-la-route-à-moto-indemnisation-de-70-000-pour-le-motard)',
    '/post/annulation-d-un-contrat-de-pompe-à-chaleur-et-victoire-en-droit-de-la-consommationhttps://transferwise.atlassian.net/wiki/spaces/KYCKNOW/pages/2812426288/Troubleshooting',
    '/post/c3fbcc58-e204-4691-919d-dcf553b28469/preview/KOgW45BTWuVZxsDqUqNqtNajt5nNretbgnifyCzJCsU.eyJpbnN0YW5jZUlkIjoiMDFjYzliNDEtYzE3NC00NzRiLTg5YmEtNGFlMjA5Yzc2ZGNiIiwiYXBwRGVmSWQiOiIxNGJjZGVkNy0wMDY2LTdjMzUtMTRkNy00NjZjYjNmMDkxMDMiLCJtZXRhU2l0ZUlkIjoiMDg3MDIzNWMtYjkyZC00YTY5LWEyZjQtMjVhOTc2YWU1ZjBjIiwic2lnbkRhdGUiOiIyMDI2LTA2LTAxVDExOjE3OjEzLjIyNFoiLCJ1aWQiOiJkMDVjOWVhNC1iMmZiLTQzZTctOWRlNC01MmZlODU3N2U1NGIiLCJwZXJtaXNzaW9ucyI6Ik9XTkVSIiwiZGVtb01vZGUiOmZhbHNlLCJiaVRva2VuIjoiMDliY2I4MWQtNzg1OS0wZDIyLTJiNGUtNmY0YjdmNjkzMmM3Iiwic2l0ZU93bmVySWQiOiIwNzQ1NGYxZi1jNTRhLTQzMDgtYjg5Ny0xOWJlNTU0ZGI4OGEiLCJzaXRlTWVtYmVySWQiOiIyMWI3ODU1MC01MjhlLTRhZDUtOWEzZC04OGQ4ZDQ0NjEwNDAiLCJleHBpcmF0aW9uRGF0ZSI6IjIwMjYtMDYtMDFUMTU6MTc6MTMuMjI0WiIsImxvZ2luQWNjb3VudElkIjoiZDA1YzllYTQtYjJmYi00M2U3LTlkZTQtNTJmZTg1NzdlNTRiIiwiYW9yIjp0cnVlLCJzaWQiOiI0NThiMjM3Yi00ZGJmLTQxZTktYTI4Ny0wZTBhY2EzNzYwNWIiLCJzY2QiOiIyMDI0LTEyLTI0VDEyOjM2OjQzLjA2M1oiLCJhY2QiOiIyMDI1LTAxLTIzVDEyOjEyOjM5WiIsInNzIjp0cnVlfQ',
    '/post/contrÃ´le-coercitif-reconnaÃ®tre-agir',
    '/post/retour-sur-la-sa',
    '/post/tribunal-judiciaire-une-ordonnance-de-protection-d',
    '/post/victime-d-accident-de-la-circulation-et-tétraplégie-indemnisation-complémentaire-de-plus-de-500-00https://www.jplouton-avocat.fr/post/indemnisation-d-une-victime-d-un-accident-de-la-circulation-90-000-de-dommages-et-intérêts'
);

-- 3) Seed des 46 posts du sitemap absents de la taxonomie (tous « classique »,
--    API Wix vérifiée 02/07 : total ressources = 57, inchangé)
insert into public.page_taxonomy (path, category, theme, source)
select v.p, 'classique',
    case
      when v.p ~* 'garde-.?-vue|gav' then 'garde à vue'
      when v.p ~* 'violence|f.minicide|conjugal|harc.lement|contr.le-coercitif' then 'violences & harcèlement'
      when v.p ~* 'indemnis|victime|civi|sarvi|pr.judice|dommage' then 'indemnisation victimes'
      when v.p ~* 'accident|erreur-m.dicale|route|travail' then 'accidents & réparation'
      when v.p ~* 'stup.fiant|trafic|drogue' then 'stupéfiants'
      when v.p ~* 'd.tention|prison|peine|sursis|bracelet|ddse|suret.|am.nagement' then 'peines & détention'
      when v.p ~* 'affaires|fraude|abus-de|escroquerie|blanchiment|corruption|fiscal' then 'pénal des affaires'
      when v.p ~* 'famille|divorce|filiation|succession|contrat' then 'famille & contrats'
      when v.p ~* 'instruction|proc.dure|comparution|tribunal|cour-d|assises|appel|mise-en-examen|t.moin|pr.venu|accus|perquisition|audition' then 'procédure pénale'
      when v.p ~* 'diffamation|injure|r.putation|presse' then 'réputation & presse'
      else null
    end,
    'slug_heuristic'
from (values
    ('/post/abus-de-faiblesse-relaxe-et-restitution-d-une-caution-de-50-000-pour-notre-cliente'),
    ('/post/accident-de-la-circulation-perte-de-contrôle-d-un-véhicule'),
    ('/post/accusé-de-viol-il-avait-été-incarcéré-trois-ans-avant-d-être-acquitté-par-la-cour-d-assises'),
    ('/post/acquittement-devant-la-cour-d-assises-de-la-gironde-dans-l-affaire-du-braquage-de-la-bijouterie-la'),
    ('/post/affaire-de-commensacq-maitre-plouton-saisi-en-défense-dans-le-cadre-de-l-instruction-criminelle'),
    ('/post/affrontements-en-marge-d-un-match-de-football-à-la-beaujoire-un-procès-devant-la-cour-d-assises-de'),
    ('/post/agression-gratuite-dans-la-rue-indemnisation-de-près-de-25-000-euros-pour-notre-client'),
    ('/post/assassinats-et-tentative-d-assassinat-devant-la-cour-d-assises-de-la-gironde'),
    ('/post/assises-de-la-gironde-l-un-des-accusés-s-est-fait-la-belle-avant-le-verdict'),
    ('/post/blanchiment-d-argent-lié-à-un-trafic-de-stupéfiant'),
    ('/post/cannabidiol-le-cabinet-obtient-une-nouvelle-décision-de-relaxe-pour-un-commerçant-à-nîmes-les-aut'),
    ('/post/coups-mortels-à-bordeaux-lac'),
    ('/post/cour-d-assises-d-appel-de-la-charente-diminution-de-peine-pour-l-accusé'),
    ('/post/cour-d-assises-de-la-gironde-extorsion-avec-arme-séquestration-et-meurtre-maître-plouton-assist'),
    ('/post/cour-d-assises-des-mineurs-de-la-charente-intervention-en-défense'),
    ('/post/destruction-d-un-bien-d-autrui-par-moyen-dangereux'),
    ('/post/drame-passionnel-à-artigues-le-cabinet-saisi-en-défense'),
    ('/post/incendie-de-la-rue-erlanger-190-000-d-indemnisation-provisoire-pour-les-victimes-assistées-par-l'),
    ('/post/indemnisation-des-victimes-d-accidents-interview-dans-l-émission-les-experts-de-france-bleu-gironde'),
    ('/post/indemnisation-du-fils-de-la-victime-d-un-assassinat-par-incendie-criminel-à-aunay-sous-crécy'),
    ('/post/intervention-en-défense-dans-le-cadre-d-rsquo-une-affaire-de-coups-mortels'),
    ('/post/intervention-en-défense-dans-le-cadre-d-une-affaire-de-trafic-de-stupéfiant'),
    ('/post/interview-de-m-plouton-dans-l-émission-allo-ici-bouvard-du-03-novembre-2019'),
    ('/post/jugement-d-un-gang-de-braqueurs'),
    ('/post/le-cabinet-obtient-la-nullité-de-procédures-en-matière-de-contrôles-de-stupéfiants'),
    ('/post/le-cabinet-obtient-la-relaxe-et-une-peine-inférieure-aux-réquisitions-pour-deux-prévenus-jugés-pour'),
    ('/post/maître-plouton-intervient-pour-une-victime-d-usurpation-d-identité-et-d-abus-de-confiance-commis-par'),
    ('/post/nullité-de-la-procédure-et-relaxe-d-un-client-dans-un-dossier-de-traffic-de-stupéfiants'),
    ('/post/poursuites-pour-abus-de-biens-sociaux-à-papeete-la-citation-directe-de-cma-cgm-déclarée-irrecevabl'),
    ('/post/procès-devant-la-cour-d-assises-d-appel-de-la-charente-tentative-de-suicide-collectif-par-incendie'),
    ('/post/projet-immobilier-de-luxe-dans-la-creuse-le-cabinet-obtient-le-placement-sous-contrôle-judiciaire'),
    ('/post/relaxe-pour-le-gérant-d-un-garage-automobile-poursuivi-en-tant-que-siveur-dans-une-vaste-affaire-d-e'),
    ('/post/remise-en-liberté-après-une-condamnation-à-9-ans-d-emprisonnement-dans-l-attente-du-procès-en-appel'),
    ('/post/rixe-mortelle-entre-bikers-à-tarbes-maitre-julien-plouton-interviendra-en-défense-devant-la-cour-d'),
    ('/post/règlement-de-comptes-entre-2-familles-issues-de-la-communauté-des-gens-du-voyage-le-jour-de-noël-r'),
    ('/post/soustraction-de-mineurs-abandon-moral-et-matériel-de-mineurs-en-relation-avec-une-entreprise-terro'),
    ('/post/trafic-d-1-7-tonnes-de-cocaïne-le-cabinet-obtient-la-remise-en-liberté-de-son-client'),
    ('/post/trafic-de-stupéfiants-à-bordeaux-alors-que-le-parquet-demandait-une-peine-de-6-ans-de-prison-ferme'),
    ('/post/trafic-de-stupéfiants-à-la-cité-maurice-thorez-à-bègles-le-cabinet-saisi-en-défense-par-l-un-des-m'),
    ('/post/trafic-international-de-cocaïne'),
    ('/post/trafic-international-de-stupéfiants-le-cabinet-intervient-en-défense-de-l-un-des-principaux-mis-en'),
    ('/post/vins-de-bordeaux-vols-de-grands-crus-classés-en-bande-organisée-notre-client-remis-en-liberté-à'),
    ('/post/violences-entre-supporters-lors-du-match-nantes-nice-du-2-décembre-2023'),
    ('/post/violences-volontaires-avec-arme-en-réunion-au-bar-les-cascades-à-lormont'),
    ('/post/vol-de-grands-crus-classés-et-recel-dans-le-bordelais-épisode-2-de-l-importance-de-l-étude-de-la'),
    ('/post/vol-à-main-armée-de-la-poste-de-périgueux-maître-plouton-assiste-les-victimes')
) v(p)
on conflict (path) do nothing;
