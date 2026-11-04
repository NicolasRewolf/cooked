# Documentation Cooked

**Référence du 04/11/2026 : socle éditorial simplifié.** Les guides actifs décrivent le tableau des URL et vues, ainsi que les sources conservées : pages publiées, visites, contacts observés et requêtes Google. Les anciens modules ne sont plus des recettes de travail.

## Guides actifs

| Besoin | Document |
|---|---|
| Vue d’ensemble | [README.md](../README.md) |
| Entrée agents et versions | [AGENTS.md](../AGENTS.md) |
| Autonomie, sécurité d’analyse et invariants | [CLAUDE.md](../CLAUDE.md) |
| Vocabulaire des vues, visites, contacts et périodes | [CONTEXT.md](../CONTEXT.md) |
| Périmètre retenu et retraits | [SIMPLIFICATION.md](SIMPLIFICATION.md) |
| Git, migrations et CI | [CONTRIBUTING.md](../CONTRIBUTING.md) |
| Collecte, crons et exploitation | [OPERATIONS.md](OPERATIONS.md) |
| Lecture des pages et des requêtes | [PLAYBOOK-analyse-seo.md](PLAYBOOK-analyse-seo.md) |
| Secrets et droits d’accès | [SECURITY.md](../SECURITY.md) |
| Suite produit | [ROADMAP.md](ROADMAP.md) |
| Tableau des URL, vues et accès privé | [dashboard/README.md](../dashboard/README.md) |
| SQL exact courant | [rpcs.sql](../supabase/rpcs.sql), [views.sql](../supabase/views.sql) et [migrations](../supabase/migrations/) |

Les [constantes du catalogue](../contracts/doc_constants.json) portent les compteurs et versions contrôlés. [CHANGELOG.md](../CHANGELOG.md) suit les changements livrés du socle.

## Décisions communes

- [Source de la profondeur de lecture](adr/0001-source-unique-profondeur-lecture.md).
- [Contrat de fraîcheur des sources](adr/0002-registre-contrats-fraicheur.md).

Les anciens audits, missions, propositions et guides des modules retirés restent dans [l’historique Git](https://github.com/NicolasRewolf/cooked/tree/b6aa6370b9041763814bc0b1253182ece2694772/docs). Ils ne font plus partie des instructions du dépôt courant.
