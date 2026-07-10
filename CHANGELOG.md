# Changelog

Format basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Versions datées (pas de semver strict) — jalons opérationnels du système Cooked.

## [2026-07-10] — Revue architecture complète + repo standardisé

### Ajouté — SQL (Arch #1–#5, PRs #60–#61)
- Lens **`live_j1`** dans `cooked_period_bounds` (ancrage J-1 Paris dashboard).
- **`gsc_is_branded(query)`** + contrat `contracts/branded_query_vectors.json`.
- Procédure **`cooked_snapshot_window`** (driver des 3 refreshers dashboard).
- **`supabase/rpcs.sql`** — miroir lecture 104 RPC + gate CI `check_rpcs_sql_fresh.py`.

### Ajouté — Dashboard (D6–D8, PRs #58–#59, #64)
- **D7** `data/view-models.ts` — view-models purs (pages → props UI testables).
- **D8** `lib/chart-geometry.ts` — géométrie SVG partagée (TrendChart, Sparkline, CohortChart).
- **D6** `metric-columns.tsx` + `useTableViewState` — colonnes partagées Resources / Expertises / SEO.

### Ajouté — Edge & tracker (D4, D9, PRs #57, #65)
- **D4** `_shared/track_row.ts` + `_shared/form_row.ts` (builders testables Deno) ;
  Edge **track v25**, **form-webhook v12** dans le repo.
- **D9** refactor helpers tracker (`stripSlash`, `inStickyAncestor`, `labelOf`) —
  iso-comportement, `COOKED_VERSION` inchangé (`sprint40`).

### Ajouté — Maintenabilité repo (PR #63)
- LICENSE, CONTRIBUTING, SECURITY, AGENTS.md, CHANGELOG, `.env.example`,
  `.editorconfig`, templates GitHub Issues/PR.

### Modifié
- Fin des blocs `v_shift` copiés dans 11 callers dashboard.
- Documentation synchronisée sur l'ensemble du repo.
- **`main` unique** — branches et worktrees Claude obsolètes purgés (PRs #57–#65 mergées).

### Déploiement manuel (repo ≠ prod tant que non fait)
- Edge : `supabase functions deploy track` + `form-webhook` (v25 / v12).
- Tracker D9 : `python3 scripts/minify-tracker.py` → coller dans Wix Custom Code.

## [2026-07-04 — 2026-07-09] — Programme architecture C1–C9

### Ajouté
- `paris_date()` / `paris_today()` + garde CI C6.
- `cooked_events_window()` adopté par les refreshers nocturnes.
- Alertes modulaires (9 règles + driver C2).
- Contrat `canonical_path` unifié SQL / Edge / Python (C3).
- Tests Python GSC/DFS + `cooked_store.py` (C7).
- Dashboard : `lib/dates.ts`, Zod, vitest (C9).
- Modules Edge `_shared/events_row` (C5).

## [2026-07-01 — 2026-07-03] — Audit Fable 5 (T-01 → T-19)

### Ajouté
- Tracker **sprint40** (page_exit ré-armé) ; Edge **track v23** ; webhook **v11**.
- Alerte `gsc_gap` ; ingest GSC `--daily` (2 mois) ; backfill 31/05 & 30/06.
- `classify_channel` v2 (IA via utm_source).
- Purge hebdo bruit > 28 j ; filtres incrémentaux 48 h.
- Alertes critical → ntfy.
- Dashboard : onglet Expertises, fiches article, contacts assistés.

### Modifié
- Restatement CPI léger (±7 pts, grain session×path).
- 14 pages expertise = liste business explicite.

## [2026-06-29 — 2026-06-30] — Dashboard V1 + fiabilité pipeline

### Ajouté
- Sous-app **dashboard/** live sur data.rewolf.studio.
- RPC `dashboard_*` sur snapshots quotidiens.

### Corrigé
- Cron CPI gelé (timeout) ; snapshot SEO optimisé (671 s → 210 s).
- Filtres bruit : `TRUNCATE` → `DELETE` (fin deadlocks).

## [2026-06-15 — 2026-06-18] — Sprint 39

### Ajouté
- CPI v2.2 ; vue `cpi_gisement` ; alertes recalibrées.

### Corrigé
- `click_internal.target_path` URL-décodé (Edge v22 + backfill).

## Versions antérieures

Chronologie complète : [docs/HISTORY-sprints.md](docs/HISTORY-sprints.md).
