# Documentation Cooked — index du dossier `docs/`

Carte de la documentation. **Racine du repo** (standard mainteneur) :
[README.md](../README.md) · [AGENTS.md](../AGENTS.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) ·
[CHANGELOG.md](../CHANGELOG.md) · [CLAUDE.md](../CLAUDE.md) (règles agent, lu à chaque session) ·
[SECURITY.md](../SECURITY.md) (PII, secrets, surface d'attaque) · [CONTEXT.md](../CONTEXT.md) (glossaire de domaine et invariants).

## Docs vivants (font foi)

### Opérer & analyser
- [`OPERATIONS.md`](OPERATIONS.md) — architecture, events captés, RPCs publiées, crons, déploiement, dépannage.
- [`PLAYBOOK-analyse-seo.md`](PLAYBOOK-analyse-seo.md) — recettes d'analyse SEO × GSC et les pièges déjà payés.
- [`../supabase/rpcs.sql`](../supabase/rpcs.sql) — miroir lecture des **136 corps de RPC** (régénéré depuis la prod par le workflow `rpcs-regenerate`, gate CI Arch #5 + prod-drift T-12).
- [`rgpd-pont-secib.md`](rgpd-pont-secib.md) — RGPD du pont SECIB : textes à publier, registre, arbitrages ouverts.
- [`adr/`](adr/) — décisions d'architecture (ADR-0001 source unique de la profondeur de lecture, ADR-0002 registre des contrats de fraîcheur).
- [`mission-2026-09-02/`](mission-2026-09-02/) — mission précision/fiabilité/hygiène : [`00-baseline.md`](mission-2026-09-02/00-baseline.md), [`01-audit.md`](mission-2026-09-02/01-audit.md) (86 constats, 7 causes racines, 13 invariants), [`02-plan.md`](mission-2026-09-02/02-plan.md) (22 tickets), [`journal.md`](mission-2026-09-02/journal.md), [`03-passation.md`](mission-2026-09-02/03-passation.md).
- [`../dashboard/README.md`](../dashboard/README.md) — sous-app de lecture (articles ressources), Next 16 + Supabase, live sur data.rewolf.studio depuis le 29/06/2026.

### CPI — Cooked Page Index (score de priorisation par page)
- [`cpi-cooked-page-index.md`](cpi-cooked-page-index.md) — spec, usage & grille de lecture (**v2.2**).
- [`cpi-modele-mathematique.md`](cpi-modele-mathematique.md) — formules détaillées (support de relecture experte).

### Mémoire & suivi
- [`HISTORY-sprints.md`](HISTORY-sprints.md) — chronologie (à jour **03/09/2026**, mission précision/fiabilité).
- [`../CHANGELOG.md`](../CHANGELOG.md) — jalons par date (Keep a Changelog).
- [`ROADMAP.md`](ROADMAP.md) — **reste à faire courant** (état des lieux du 03/09/2026 au soir).
- [`JOURNAL-actions-contenu.md`](JOURNAL-actions-contenu.md) — archive des vagues contenu 1-2 (source canonique depuis le 11/06/2026 : table `annotations`).

## Archives datées (contexte historique, ne font plus foi)

### Audits fiabilité — le plus récent : **02/09/2026** (`mission-2026-09-02/01-audit.md`, docs vivants ci-dessus)
- [`audit-architecture-2026-07-25.md`](audit-architecture-2026-07-25.md) — revue d'architecture n°2 du **25/07/2026** (48 constats — lire l'avertissement de fiabilité en tête).
- [`audit-fable5-2026-07-02.md`](audit-fable5-2026-07-02.md) — audit complet multi-agents du **02/07/2026** (référence fiabilité la plus récente ; plan de correction exécuté à 100 % le 03/07/2026).
- [`plan-correction-audit-2026-07-02.md`](plan-correction-audit-2026-07-02.md) — plan T-01→T-19 issu de l'audit, exécuté à 100 %.
- [`data-quality-audit-2026-06-10.md`](data-quality-audit-2026-06-10.md) — audit fiabilité Sprint 37 + addendum Sprint 39 (superseded par l'audit du 02/07/2026).
- [`data-quality-audit-2026-05-24.md`](data-quality-audit-2026-05-24.md) — audit antérieur (superseded).
- [`audit-vitesse-avocat-divorce-bordeaux.md`](audit-vitesse-avocat-divorce-bordeaux.md) — audit perf d'une page expertise (mesures du 03/06/2026).

### CPI — revue experte (close le 18/06/2026)
- [`cpi-prompt-revue-expert.md`](cpi-prompt-revue-expert.md) — prompt de challenge soumis aux experts.
- [`cpi-revue-expert-reponse.md`](cpi-revue-expert-reponse.md) — revue reçue + trace de la décision « garder l'essentiel, ne pas complexifier » (confirmée par la validation J+28 du 11/07/2026).

### Passations & baselines
- [`ROADMAP-sprint38-handoff.md`](ROADMAP-sprint38-handoff.md) — handoff historique 09/06→03/07/2026 (remplacé par [`ROADMAP.md`](ROADMAP.md)).
- [`BASELINE-demandes-historiques.md`](BASELINE-demandes-historiques.md) — baseline des demandes entrantes, figée au 10/06/2026 (a servi la validation CPI du 11/07/2026).

## Skills d'ingénierie (agent)
- [`agents/`](agents/) — [`issue-tracker.md`](agents/issue-tracker.md), [`triage-labels.md`](agents/triage-labels.md), [`domain.md`](agents/domain.md).
- [`analyse-mathematique-avancee-2026-07-29.md`](analyse-mathematique-avancee-2026-07-29.md) — framework d'analyse mathématique (Markov, Shapley, causal) et ses limites de conclusion.
