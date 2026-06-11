# Journal des actions contenu/SEO — jplouton-avocat.fr

> Chaque action déployée sur le site (title, meta, bloc de conversion,
> maillage) est consignée ici AVEC SA DATE de mise en ligne. C'est ce qui
> permet de lire l'avant/après dans `cpi_daily` / `cpi_movers` / GSC sans
> deviner. Règle de lecture : effet CTR visible à ~J+7-10 (lag GSC J-2),
> verdict propre à J+28. Le diagnostic d'origine est dans la conversation
> du 11/06/2026 et docs/PLAYBOOK-analyse-seo.md.

| # | Date déploiement | Page | Action | Métrique à suivre | Attendu |
|---|---|---|---|---|---|
| 1 | ___ | `/` (home) | Title + meta réécrits (intent local d'abord, marque ensuite) | zc CPI + CTR GSC sur `avocat bordeaux`, `avocat pénal(iste) bordeaux` | CTR 0,58 % → ≥ 1,2 % sur `avocat bordeaux` (pos ~4,8) |
| 2 | ___ | `/post/casier-judiciaire-comprendre-et-effacer` | Title + meta réécrits (intent effacement/délais + service avocat) | zc + momentum (page en ↘) ; CTR sur `avocat casier judiciaire` (0 % à pos 4,1 !) | inverser le ↘ ; premiers clics sur la requête avocat |
| 3 | ___ | `/post/itt-pénale-définition-en-2025` | Title + meta réécrits (seuil 8 jours / plainte / indemnisation) | zc ; CTR sur `jour itt et plainte` (647 imps, pos 6,8) et `itt supérieur à 8 jours` | récupérer une partie des 59 clics perdus/28j |
| 4 | ___ | `/post/durée-de-la-garde-à-vue-24h-48h-96h…` | Bloc pont « proche en garde à vue » (urgence, tél) | zv CPI + cta_phone_click sur la page | premiers contacts depuis la page n°1 du site (1 726 entrées/28j, zv −3) |
| 5 | ___ | `/post/itt-pénale-définition-en-2025` | Bloc pont « victime avec certificat ITT » | zv + assists `conversion_journeys` | — |
| 6 | ___ | `/post/indemnisation-civi-2025-guide-complet…` | Bloc pont « êtes-vous éligible CIVI » placé tôt | zv + assists | — |

Reportés sciemment (archétype « dictionnaire » : des clics sans valeur
business directe — zl/zv au plancher) : `période-de-sûreté`,
`garde-à-vue-définition`, `mis-en-cause`. On ne dépense pas d'énergie
de réécriture dessus tant que les pages à intent ne sont pas traitées.
