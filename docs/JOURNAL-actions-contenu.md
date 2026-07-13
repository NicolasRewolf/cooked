# Journal des actions contenu/SEO — jplouton-avocat.fr

> ⚠️ **Source canonique des actions contenu depuis le 11/06/2026 : table
> `annotations` (migration 20260611201942). Ce fichier = archive des
> vagues 1-2.**
>
> **Verdict de la vague du 11/06/2026 (constat revue stratégique des
> 10-11/07/2026) : VALIDÉE** — les CTA/maillage posés sur les posts ont
> fait passer les phone clicks des posts de ~2 à ~43 par période
> comparable.

> Chaque action déployée sur le site (title, meta, bloc de conversion,
> maillage) est consignée ici AVEC SA DATE de mise en ligne. C'est ce qui
> permet de lire l'avant/après dans `cpi_daily` / `cpi_movers` / GSC sans
> deviner. Règle de lecture : effet CTR visible à ~J+7-10 (lag GSC J-2),
> verdict propre à J+28. Le diagnostic d'origine est dans la conversation
> du 11/06/2026 et docs/PLAYBOOK-analyse-seo.md.

| # | Date déploiement | Page | Action | Métrique à suivre | Attendu |
|---|---|---|---|---|---|
| 1 | **11/06/2026** ✅ vérifié servi | `/` (home) | Title + meta réécrits (intent local d'abord, marque ensuite) | zc CPI + CTR GSC sur `avocat bordeaux`, `avocat pénal(iste) bordeaux` | CTR 0,58 % → ≥ 1,2 % sur `avocat bordeaux` (pos ~4,8) |
| 2 | **11/06/2026** ✅ vérifié servi | `/post/casier-judiciaire-comprendre-et-effacer` | Title + meta réécrits (intent effacement/délais + service avocat) | zc + momentum (page en ↘) ; CTR sur `avocat casier judiciaire` (0 % à pos 4,1 !) | inverser le ↘ ; premiers clics sur la requête avocat |
| 3 | CLOS — non suivi individuellement, englobé dans le verdict de vague (constat 10-11/07/2026) | `/post/itt-pénale-définition-en-2025` | Title + meta réécrits (seuil 8 jours / plainte / indemnisation) | zc ; CTR sur `jour itt et plainte` (647 imps, pos 6,8) et `itt supérieur à 8 jours` | récupérer une partie des 59 clics perdus/28j |
| 4 | **11/06/2026** ✅ vérifié servi | `/post/durée-de-la-garde-à-vue-24h-48h-96h…` | Bloc pont « proche en garde à vue » (urgence, tél) | zv CPI + cta_phone_click sur la page | premiers contacts depuis la page n°1 du site (1 726 entrées/28j, zv −3) |
| 5 | **11/06/2026** ✅ vérifié servi | `/post/itt-pénale-définition-en-2025` | Bloc pont « victime avec certificat ITT » | zv + assists `conversion_journeys` | — |
| 6 | **11/06/2026** ✅ vérifié servi (wording adapté par Nicolas) | `/post/indemnisation-civi-2025-guide-complet…` | Bloc pont « êtes-vous éligible CIVI » placé tôt. Bonus Nicolas : title réécrit « Indemnisation CIVI : montants et démarches 2026 » + meta orientée intent | zv + assists ; zc en bonus | — |

Hors plan initial, même jour : champs cachés `cooked_aid`/`cooked_sid`
ajoutés au Formulaire Divorce (11/06/2026, déclaré — vérification au
premier form_submit venant de ce formulaire).

## Vague 2 — maillage interne vers les étoiles montantes (11/06/2026)

7 liens éditoriaux posés **par l'agent via l'API Wix Blog** (autorisation
explicite Nicolas ; insertion auto-vérifiée : assert d'intégrité avant
chaque envoi, blocs identifiables `ckdmlg*` retirables en un appel,
publication vérifiée page par page en live). Métrique de suivi : momentum
+ zc des 3 cibles dans `cpi_daily` (effet attendu sous 2-4 semaines).

| Depuis | Vers | Détail |
|---|---|---|
| faute-lourde (188 v/mois) | **délai-déraisonnable** | après le § L.141-1 (même fondement) |
| guide CIVI (690) | **délai-déraisonnable** | fin de section recours |
| guide CIVI (690) | **ONIAM** | FAQ exclusions (accident médical ∉ CIVI) |
| mis-en-cause (457) | **délai-déraisonnable** | après la section évolutions de statuts |
| accident-travail (359) | **ONIAM** | section prise en charge des soins |
| GAV durée (1 738) | **nullité-dépistage** | section dépassement des délais/nullités |
| après-GAV (303) | **nullité-dépistage** | section rôle de l'avocat |

Non posé (hors API Blog — page Studio, action manuelle Nicolas) : lien
ONIAM depuis l'expertise `/indemnisation-des-victimes/accidents-et-erreurs-medicales`.

Reportés sciemment (archétype « dictionnaire » : des clics sans valeur
business directe — zl/zv au plancher) : `période-de-sûreté`,
`garde-à-vue-définition`, `mis-en-cause`. On ne dépense pas d'énergie
de réécriture dessus tant que les pages à intent ne sont pas traitées.
