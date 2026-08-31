-- page_taxonomy : rattrapage des articles publiés jamais ingérés + détecteur de récidive.
--
-- PROBLÈME. La catégorie Wix Blog (« ressource » / « classique ») n'a pas de refresh
-- automatique : elle n'existe que si l'on rejoue la synchro API Wix. Dernière passe
-- 22/07/2026 (ressource) / 10/07/2026 (classique). Au 30/08/2026 l'API déclare
-- 433 posts publiés (62 ressource + 371 classique) ; page_taxonomy n'en connaissait
-- que 426, dont 58 ressource seulement.
--
-- CAUSE. Les mécanismes qui créent des lignes ne regardent que les paths DÉJÀ VUS dans
-- events_human — refresh_page_taxonomy_heuristic() filtre explicitement sur le trafic
-- 90 j, et les synchros Wix précédentes partaient de la même base. Un article publié
-- mais pas encore visité n'obtient donc aucune ligne, et n'est jamais rattrapé ensuite
-- puisque la synchro suivante repart du même filtre. Les 5 ressources manquantes ont
-- toutes reçu leur premier trafic APRÈS la synchro du 22/07 :
--   /post/soumission-chimique-victime-preuve-recours     publié 24/08/2026, 1re vue 24/08
--   /post/fraude-bancaire-remboursement-faux-conseiller  publié 28/06/2026, 1re vue 07/08
--   /post/faute-inexcusable-employeur-indemnisation      publié 22/06/2026, 1re vue 27/07
--   /post/pension-alimentaire-impayee-recours            publié 15/06/2026, 1re vue 29/07
--   /post/changer-d-avocat-en-cours-de-procedure         publié 14/06/2026, 1re vue 26/07
-- Ces articles étaient invisibles de toute lecture par catégorie (onglet Articles
-- Ressources du dashboard, content_performance, suivi du contrat éditorial), alors que
-- plusieurs sont au-dessus de la médiane en trafic (changer-d-avocat 74 vues/30 j,
-- faute-inexcusable 59, fraude-bancaire 51).
--
-- MÉTHODE. Liste faisant autorité obtenue via GET https://www.wixapis.com/blog/v3/posts
-- (site 0870235c-b92d-4a69-a2f4-25a976ae5f0c ; catégorie « Ressources et notions
-- juridiques » = 9477320f-5902-40e9-ace3-b0e3b6b8b51f), 433 posts sur 5 pages. Diff
-- contre page_taxonomy : 421 déjà corrects, 12 absents, 0 catégorie à corriger,
-- 5 paths en base qui ne sont plus publiés. Le même écart de 12 est retrouvé
-- indépendamment par la requête de détection ci-dessous — deux méthodes concordantes.
--
-- INVARIANTS.
--  * Lignes existantes : seule `category` bougerait. `theme` et `source` sont préservés,
--    sinon on casse le garde-fou `where source = 'slug_heuristic'` de
--    refresh_page_taxonomy_heuristic(). Ici aucune ligne existante n'est modifiée.
--  * Lignes créées : `theme` calculé par la MÊME heuristique de slug que cette fonction
--    (copiée à l'identique), source = 'slug_heuristic' pour rester maintenables par elle.
--  * Les 5 paths de page_taxonomy absents de la liste Wix ne sont PAS touchés : articles
--    dépubliés ou re-sluggés (ex. /post/mes-droits-en-garde-a-vue, supprimé et 301 le
--    13/07/2026) qui portent de l'historique de trafic.

insert into public.page_taxonomy (path, category, theme, source)
select
  p.path,
  p.category,
  case
    when p.path ~* 'garde-.?-vue|gav' then 'garde à vue'
    when p.path ~* 'violence|f.minicide|conjugal|harc.lement|contr.le-coercitif' then 'violences & harcèlement'
    when p.path ~* 'indemnis|victime|civi|sarvi|pr.judice|dommage' then 'indemnisation victimes'
    when p.path ~* 'accident|erreur-m.dicale|route|travail' then 'accidents & réparation'
    when p.path ~* 'stup.fiant|trafic|drogue' then 'stupéfiants'
    when p.path ~* 'd.tention|prison|peine|sursis|bracelet|ddse|suret.|am.nagement' then 'peines & détention'
    when p.path ~* 'affaires|fraude|abus-de|escroquerie|blanchiment|corruption|fiscal' then 'pénal des affaires'
    when p.path ~* 'famille|divorce|filiation|succession|contrat' then 'famille & contrats'
    when p.path ~* 'instruction|proc.dure|comparution|tribunal|cour-d|assises|appel|mise-en-examen|t.moin|pr.venu|accus|perquisition|audition' then 'procédure pénale'
    when p.path ~* 'diffamation|injure|r.putation|presse' then 'réputation & presse'
    else null
  end,
  'slug_heuristic'
from (values
    ('/post/soumission-chimique-victime-preuve-recours','ressource'),
    ('/post/fraude-bancaire-remboursement-faux-conseiller','ressource'),
    ('/post/faute-inexcusable-employeur-indemnisation','ressource'),
    ('/post/pension-alimentaire-impayee-recours','ressource'),
    ('/post/changer-d-avocat-en-cours-de-procedure','ressource'),
    ('/post/pression-assureurs-gironde-analyse-juridique-cabinet-plouton','classique'),
    ('/post/affaire-foulon-baude-partie-civile-menaces-bordeaux','classique'),
    ('/post/assistance-éducative-levée-de-la-mesure-de-placement-et-retour-des-enfants-auprès-de-leur-père','classique'),
    ('/post/rejet-d-une-ordonnance-de-protection-le-juge-estime-que-les-violences-n-étaient-pas-vraisemblables','classique'),
    ('/post/violences-commises-par-des-hooligans-contre-des-chauffeurs-vtc-à-nantes-notre-cabinet-obtient-l-ou','classique'),
    ('/post/escroquerie-au-permis-de-conduire-à-bordeaux-après-l-annulation-des-premières-poursuites-le-tribu','classique'),
    ('/post/homicide-involontaire-routier-landes-sursis-mont-de-marsan','classique')
) as p(path, category)
on conflict (path) do update
  set category   = excluded.category,
      updated_at = now()
  where page_taxonomy.category is distinct from excluded.category;


-- DÉTECTEUR DE RÉCIDIVE. Le trou ci-dessus est resté ouvert deux mois sans que rien ne
-- le signale. cooked_alerts_refresh() auto-découvre toute fonction alert_rule_*() à zéro
-- argument renvoyant (kind, severity, detail) : il suffit donc de créer la règle.
-- Elle se lit entièrement en SQL (aucun appel Wix) : un article qui reçoit du trafic
-- sans avoir de catégorie est, par construction, un article que la synchro a raté.
create or replace function public.alert_rule_page_taxonomy_gap()
returns table(kind text, severity text, detail text)
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
DECLARE
  v_n  bigint;
  v_ex text;
BEGIN
  WITH vus AS (
    SELECT e.path, count(*) FILTER (WHERE e.name = 'pageview') AS pv
    FROM public.events_human e
    WHERE e.path LIKE '/post/%'
      AND e.occurred_at > now() - interval '30 days'
      -- mêmes exclusions structurelles que refresh_page_taxonomy_heuristic (T-19)
      AND e.path NOT LIKE '%/preview/%'   -- previews Wix avec token
      AND e.path !~ 'https?://'           -- URLs concaténées par erreur
      AND e.path !~ '[ÃÂ]'                -- mojibake (double encodage)
      AND e.path !~ '%'                   -- restes d'URL-encoding
      AND length(e.path) <= 140
    GROUP BY e.path
    HAVING count(*) FILTER (WHERE e.name = 'pageview') >= 5
  )
  SELECT count(*), string_agg(v.path, ', ' ORDER BY v.pv DESC)
    INTO v_n, v_ex
  FROM vus v
  LEFT JOIN public.page_taxonomy t ON t.path = v.path
  WHERE t.path IS NULL OR t.category IS NULL;

  IF v_n >= 3 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j) sans catégorie Wix dans page_taxonomy — toute lecture par catégorie (dashboard Articles Ressources, content_performance, contrat éditorial) les ignore. Rejouer la synchro API Wix : GET /blog/v3/posts, site 0870235c-b92d-4a69-a2f4-25a976ae5f0c, catégorie ressource 9477320f-5902-40e9-ace3-b0e3b6b8b51f. Concernés : %s',
        v_n, left(coalesce(v_ex, ''), 400)
      );
  END IF;
END;
$function$;

revoke all on function public.alert_rule_page_taxonomy_gap() from public;

comment on function public.alert_rule_page_taxonomy_gap() is
  'Alerte page_taxonomy_gap : articles avec trafic mais sans catégorie Wix. Détecte que la synchro API Wix (manuelle, sans cron) a pris du retard. Ajoutée le 30/08/2026 après un trou de 2 mois passé inaperçu (12 articles, dont 5 ressources).';
