# Baseline historique des demandes entrantes — formulaire « Prise de contact site-web »

> Source : export Wix du 11/06/2026 (672 soumissions, 22/03/2025 → 10/06/2026),
> agrégé localement SANS lire les colonnes nominatives (PII jamais entrée dans
> Cooked ni dans ce repo — règle Sprint 30). Sert de référence pour
> contextualiser les comptes Cooked (« 25 contacts/28j » : bon ou mauvais ?),
> pour le mix par domaine, et pour la validation CPI du 08/07/2026.
> ⚠️ Périmètre : CE formulaire uniquement (pas les appels téléphone, pas le
> Formulaire Divorce créé en 06/2026). Le flux est co-porté par Adwords (39 %)
> — ne pas lire ces volumes comme du SEO pur.

## Volume mensuel (tendance : ×2,5-3 en un an)

| Mois | Demandes | | Mois | Demandes |
|---|---|---|---|---|
| 2025-03 | 6 (mois partiel) | | 2025-11 | 49 |
| 2025-04 | 25 | | 2025-12 | 56 |
| 2025-05 | 20 | | 2026-01 | **74** (pic) |
| 2025-06 | 25 | | 2026-02 | 64 |
| 2025-07 | 32 | | 2026-03 | 69 |
| 2025-08 | 31 | | 2026-04 | 61 |
| 2025-09 | 34 | | 2026-05 | 58 |
| 2025-10 | 44 | | 2026-06 | 24 au 10/06 (rythme ≈ 72/mois) |

**Baseline 2026 : ~65 demandes/mois via ce formulaire** (≈ 60 hors
candidatures). Pas de creux estival marqué en 2025 (juil-août ≈ 31-32, dans la
tendance de l'époque) → ne pas excuser un mauvais été 2026 par la saison.

## Mix par objet (672, dont 50 candidatures et 52 sans objet)

| Objet | n | % (hors candidatures/vides) |
|---|---|---|
| Droit Pénal | 137 | 24 % |
| **Droit de la famille** | **113** | **20 %** |
| Assurances particuliers/pros | 56 | 10 % |
| Accidents du travail | 46 | 8 % |
| Droit du consommateur | 35 | 6 % |
| Accidents et erreurs médicales | 34 | 6 % |
| Violences conjugales et féminicides | 29 | 5 % |
| Droit pénal des affaires | 27 | 5 % |
| Accidents de la route | 26 | 5 % |
| Procès criminel | 18 | 3 % |
| Trafic de stupéfiants | 17 | 3 % |
| Indemnisation victime (pénal) | 15 | 3 % |
| Accidents de la vie courante | 9 | 2 % |

**Enseignement stratégique : le droit de la famille est le 2ᵉ flux entrant du
cabinet (1 demande sur 5)** alors que le site n'a quasi pas de contenu
organique famille (1 hub + 1 page, faible capture GSC — cf. diagnostic
avocat-divorce-bordeaux). La demande existe ; le contenu n'existe pas encore.

## Canaux (utm_source au moment de la soumission)

| Canal | n | % |
|---|---|---|
| (aucun UTM — organique/direct) | 320 | 48 % |
| adwords | 264 | 39 % |
| gmb (fiche Google Business) | 75 | 11 % |
| chatgpt.com | 11 | 1,6 % |
| perplexity | 1 | — |

Les assistants IA réfèrent déjà 12 demandes (classify_channel les classe
`organic_ai`). À surveiller — c'est plus que certaines pages expertise.

## Notes de cohérence Cooked

- `page_source` vide sur 605/672 : le champ n'existe que depuis ~05/2026
  (faq-system.js) — normal.
- `cooked_aid` absent des 24 soumissions de juin (export arrêté au 10/06,
  veille du fix sprint38) — cohérent. Première attribution : 11/06 08:53.
- Mai 2026 : 58 demandes côté Wix — à rapprocher des comptes `form_submit`
  Cooked sur la même fenêtre lors du prochain audit de cohérence.
- v2.2 « pondération par thème » : ce mix DEBLOQUE l'estimation du volume
  relatif par domaine, mais la VALEUR par domaine reste une décision
  business (Nicolas/Me Plouton), pas une statistique.
