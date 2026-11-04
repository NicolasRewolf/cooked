# Documentation Cooked

**Référence du 04/11/2026 : socle éditorial simplifié.** Les guides actifs décrivent les pages publiées, les visites, les contacts observés et les requêtes Google. Les anciens modules ne sont plus des recettes de travail.

## Guides actifs

| Besoin | Document |
|---|---|
| Vue d’ensemble | [README.md](../README.md) |
| Entrée agents et versions | [AGENTS.md](../AGENTS.md) |
| Autonomie, sécurité d’analyse et invariants | [CLAUDE.md](../CLAUDE.md) |
| Vocabulaire des visites, contacts et périodes | [CONTEXT.md](../CONTEXT.md) |
| Périmètre retenu et retraits | [SIMPLIFICATION.md](SIMPLIFICATION.md) |
| Git, migrations et CI | [CONTRIBUTING.md](../CONTRIBUTING.md) |
| Collecte, crons et exploitation | [OPERATIONS.md](OPERATIONS.md) |
| Lecture des pages et des requêtes | [PLAYBOOK-analyse-seo.md](PLAYBOOK-analyse-seo.md) |
| Secrets et droits d’accès | [SECURITY.md](../SECURITY.md) |
| Suite produit | [ROADMAP.md](ROADMAP.md) |
| Authentification et page de transition | [dashboard/README.md](../dashboard/README.md) |
| SQL exact courant | [rpcs.sql](../supabase/rpcs.sql), [views.sql](../supabase/views.sql) et [migrations](../supabase/migrations/) |

Les [constantes du catalogue](../contracts/doc_constants.json) portent les compteurs vérifiés. Les [ADR](adr/) conservent les décisions communes. Pour les agents : [domain.md](agents/domain.md), [issue-tracker.md](agents/issue-tracker.md), [triage-labels.md](agents/triage-labels.md).

## Historique, à lire avec sa date

[CHANGELOG.md](../CHANGELOG.md) et [HISTORY-sprints.md](HISTORY-sprints.md) suivent les jalons. Les archives ci-dessous expliquent les choix et incidents anciens ; elles ne prouvent pas l’état courant et leurs commandes visant des objets retirés ne doivent pas être rejouées.

- [RELIABILITY.md](RELIABILITY.md) : correction et état de livraison du 20/10/2026.
- [ANALYTICS_WINDOWS.md](ANALYTICS_WINDOWS.md) : anciennes fenêtres et copies de calculs.
- [JOURNAL-actions-contenu.md](JOURNAL-actions-contenu.md) : interventions éditoriales historiques.
- [ROADMAP-sprint38-handoff.md](ROADMAP-sprint38-handoff.md) et [BASELINE-demandes-historiques.md](BASELINE-demandes-historiques.md) : anciennes passations et références.

### Modules retirés

- CPI : [spécification et lecture](cpi-cooked-page-index.md), [modèle mathématique](cpi-modele-mathematique.md), [prompt de revue](cpi-prompt-revue-expert.md), [réponse experte](cpi-revue-expert-reponse.md).
- CRM/SECIB : [ancien dossier de traitement et décisions](rgpd-pont-secib.md). Les contraintes de confidentialité des archives subsistent ; ce pont n’est plus une fonction active de Cooked.
- Maths : [analyse avancée du 29/07/2026](analyse-mathematique-avancee-2026-07-29.md).

### Audits datés

- Mission de septembre : [baseline](mission-2026-09-02/00-baseline.md), [audit](mission-2026-09-02/01-audit.md), [plan](mission-2026-09-02/02-plan.md), [journal](mission-2026-09-02/journal.md), [mesures après](mission-2026-09-02/02-apres.md), [passation](mission-2026-09-02/03-passation.md).
- [Architecture du 25/07/2026](audit-architecture-2026-07-25.md).
- [Fiabilité du 02/07/2026](audit-fable5-2026-07-02.md) et [plan de correction](plan-correction-audit-2026-07-02.md).
- [Qualité du 10/06/2026](data-quality-audit-2026-06-10.md) et [du 24/05/2026](data-quality-audit-2026-05-24.md).
- [Performance de la page divorce](audit-vitesse-avocat-divorce-bordeaux.md).
