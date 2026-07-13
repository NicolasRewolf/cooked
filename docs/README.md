# Documentation Cooked — index du dossier `docs/`

Carte de la documentation. **Racine du repo** (standard mainteneur) :
[README.md](../README.md) · [AGENTS.md](../AGENTS.md) · [CONTRIBUTING.md](../CONTRIBUTING.md) ·
[CHANGELOG.md](../CHANGELOG.md) · [CLAUDE.md](../CLAUDE.md) (règles agent, lu à chaque session).

## Docs vivants (font foi)

### Opérer & analyser
- [`OPERATIONS.md`](OPERATIONS.md) — architecture, events captés, RPCs publiées, crons, déploiement, dépannage.
- [`PLAYBOOK-analyse-seo.md`](PLAYBOOK-analyse-seo.md) — recettes d'analyse SEO × GSC et les pièges déjà payés.
- [`../supabase/rpcs.sql`](../supabase/rpcs.sql) — miroir lecture des **105 corps de RPC** (régénéré le 12/07/2026, gate CI Arch #5).
- [`../dashboard/README.md`](../dashboard/README.md) — sous-app de lecture (articles ressources), Next 16 + Supabase, live sur data.rewolf.studio depuis le 29/06/2026.

### CPI — Cooked Page Index (score de priorisation par page)
- [`cpi-cooked-page-index.md`](cpi-cooked-page-index.md) — spec, usage & grille de lecture (**v2.2**).
- [`cpi-modele-mathematique.md`](cpi-modele-mathematique.md) — formules détaillées (support de relecture experte).

### Mémoire & suivi
- [`HISTORY-sprints.md`](HISTORY-sprints.md) — chronologie (à jour **12/07/2026**, couture d'identité + sprint41).
- [`../CHANGELOG.md`](../CHANGELOG.md) — jalons par date (Keep a Changelog).
- [`ROADMAP.md`](ROADMAP.md) — **reste à faire courant** (état des lieux du 12/07/2026 au soir).
- [`JOURNAL-actions-contenu.md`](JOURNAL-actions-contenu.md) — archive des vagues contenu 1-2 (source canonique depuis le 11/06/2026 : table `annotations`).

## Archives datées (contexte historique, ne font plus foi)

### Audits fiabilité — le plus récent : **02/07/2026**
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
- [`agents/`](agents/) — `issue-tracker`, `triage-labels`, `domain`.
