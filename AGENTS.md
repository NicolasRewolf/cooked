# Agents IA — point d'entrée

Ce fichier oriente **tout agent** (Claude Code, Cursor, autre) avant de toucher
au code ou à la prod.

## Lire en premier (ordre)

1. [CLAUDE.md](CLAUDE.md) — règles métier, réflexes session, périmètre d'autonomie
2. [CONTRIBUTING.md](CONTRIBUTING.md) — workflow Git, migrations, CI
3. [docs/OPERATIONS.md](docs/OPERATIONS.md) — architecture, déploiement, crons
4. [SECURITY.md](SECURITY.md) — secrets interdits dans le repo

## Réflexes prod (30 s)

```sql
SELECT * FROM alerts WHERE NOT acked;
SELECT * FROM refresh_pipeline_health();
SELECT gsc_last_data_day();
```

## Où trouver quoi

| Besoin | Fichier |
|---|---|
| Corps complets des RPC (137 routines `pg_proc` = 133 Cooked + 4 `unaccent`, régénéré depuis la prod en CI) | [supabase/rpcs.sql](supabase/rpcs.sql) |
| Glossaire de domaine (conversions, attribution, lecture, fraîcheur, invariants) | [CONTEXT.md](CONTEXT.md) |
| Décisions d'architecture (ADR) | [docs/adr/](docs/adr/) |
| Sécurité : PII, secrets, surface d'attaque, invariant I1 | [SECURITY.md](SECURITY.md) |
| Mission précision/fiabilité/hygiène (02/09/2026) : baseline, audit, plan, journal | [docs/mission-2026-09-02/](docs/mission-2026-09-02/) |
| Signatures + vues | [supabase/views.sql](supabase/views.sql) |
| DDL déploiement | [supabase/migrations/](supabase/migrations/) |
| Couture d'identité (`identity_stitch` : table, `refresh_identity_stitch(90)`, garde-fou aid 32-hex) | [docs/OPERATIONS.md](docs/OPERATIONS.md) |
| Edge row builders (D4) | `supabase/functions/_shared/track_row.ts`, `form_row.ts` |
| Tracker navigateur | [wix/tracker.html](wix/tracker.html) |
| Analyse SEO (pièges) | [docs/PLAYBOOK-analyse-seo.md](docs/PLAYBOOK-analyse-seo.md) |
| Score CPI | [docs/cpi-cooked-page-index.md](docs/cpi-cooked-page-index.md) |
| Dashboard UI | [dashboard/README.md](dashboard/README.md) |
| Historique | [docs/HISTORY-sprints.md](docs/HISTORY-sprints.md) |
| Changements récents | [CHANGELOG.md](CHANGELOG.md) |
| Index docs | [docs/README.md](docs/README.md) |

## Contrats testables (`contracts/`)

| Fichier | Vérifie |
|---|---|
| `canonical_path_vectors.json` | SQL / Edge / Python paths (C3) |
| `branded_query_vectors.json` | `gsc_is_branded(query)` (Arch #3) |
| `recruitment_objet_vectors.json` | Filtrage macro `form_submit` (D4) |
| `rpc_snapshot_meta.json` | Hash + count de `supabase/rpcs.sql` (Arch #5) |
| `dashboard_rpc_columns.json` | Contrat des 16 RPC dashboard **généré depuis la prod** (`scripts/generate_dashboard_contracts.py`) : colonnes, NOT NULL, appel d'échantillon ; confronté aux schémas Zod par `dashboard/src/data/rpc-contract.test.ts` (Arch #6 → T-13) |

## Versions canoniques (repo `main`)

| Composant | Version repo | Déploiement prod |
|---|---|---|
| Tracker | `sprint41` (ids auto-réparants) | Wix Custom Code (minify) — déployé 12/07/2026 |
| Edge `track` | v28 (T-04 : UA « pc » / SEBot droppés ; v27 = gate `x-cooked-key` ; v26 = filtre bots à l'ingestion) | `supabase functions deploy track` — v28 déployée le 03/09/2026 |
| Edge `form-webhook` | `v14` (T-07 : `form_submit_dropped` via `raise_cooked_alert`) | déployée le 03/09/2026 16:30 Paris (version Supabase 22) |
| RPC Postgres | 137 routines `pg_proc` (133 Cooked + 4 `unaccent` ; compte dans `contracts/doc_constants.json`, comparé à la prod chaque matin) | migrations Supabase |

**Repo et prod peuvent diverger** tant que Edge / tracker ne sont pas redéployés.
Toujours vérifier : `props->>'_v'` sur events récents + version commentée en tête
des fichiers Edge.

## Périmètre

Mono-site `jplouton-avocat.fr` — ne pas généraliser multi-tenant sans décision
Nicolas explicite.
