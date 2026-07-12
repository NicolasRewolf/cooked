# Changelog

Format basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Versions datées (pas de semver strict) — jalons opérationnels du système Cooked.

## [2026-07-12] — Couture d'identité : sessions coupées recollées, attribution réparée

### Corrigé — Bug d'identité tracker (cause racine)
- **Tracker `sprint41`** : ids auto-réparants. Un wipe/transition de storage en
  cours de page (typ. décision du bandeau de consentement ~10 s après l'arrivée)
  faisait tourner le `sid` (relu à chaque event, re-minté sur miss) puis l'`aid`
  (caché en closure, jamais ré-écrit → tournait à la navigation suivante).
  Mesuré : ~22 % des sessions coupées en deux, ~95 % des `cta_phone_click` sans
  amont visible, stable ≥6 semaines (antérieur à sprint40). Quatre gestes,
  iso-comportement si le storage est sain : cache mémoire `_cachedSid` ré-écrit
  au lieu de re-minter ; `healAid()` opportuniste (adossé au debounce 5 s) ;
  lecture sessionStorage sur MISS (plus seulement sur exception) avec
  rapatriement ; `exposeIds()` rejoué au flush si la paire (aid,sid) a tourné.
  **À déployer via minify + Wix Custom Code.**

### Ajouté — SQL (migrations `20260712*`, appliquées en prod le 12/07)
- Table **`identity_stitch`** + `refresh_identity_stitch(90)` : composantes
  connexes du graphe biparti aid↔sid (label propagation, convergence 2 iter.,
  aids 32-hex fallback serveur exclus comme clé). Recolle rétroactivement les
  visites coupées. Cron nocturne `40 3 * * *` (avant les refreshers dashboard).
- **`refresh_dashboard_resources_assisted` v2** : entrée d'un contact = première
  pageview de la **visite recousue** (segmentation à trous >30 min, rattachement
  à la dernière pageview ≤6 h avant le contact), fallback session brute.
  Contrat de sortie inchangé. Validation prod 12/07 : contacts assistés
  « ressource » 28 j **16 → 37**, entrée connue des phone clicks 54 % → 99 %,
  0 composante multi-device (garde-fou faux recollages), cas d'école du
  11/07 18:52 attribué à son article d'entrée réel.
- Cron `refresh-dashboard-assisted` : timeout 300 s → 590 s (v2 plus lourde).

### Connu — reste à faire (session du 12/07)
- `conversion_journeys` / `seo_to_contact_funnel` / `content_performance`
  joignent encore par session brute (journey tronqué, `entry_channel` NULL
  possible) — à brancher sur `identity_stitch`.
- Dashboard UI : harmoniser les deux compteurs (« contacts sur la page » du
  tableau vs « contacts assistés » de la fiche) — afficher les deux, étiquetés.

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
