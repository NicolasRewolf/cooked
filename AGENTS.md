# Agents IA — point d'entrée

Ce fichier oriente **tout agent** (Claude Code, Cursor, autre) avant de toucher
au code ou à la prod.

## Lire en premier (ordre)

1. [CLAUDE.md](CLAUDE.md) — règles métier, réflexes session, périmètre d'autonomie
2. [CONTRIBUTING.md](CONTRIBUTING.md) — workflow Git, migrations, CI (`make check`)
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
| Corps complets des RPC (143 routines `pg_proc` = 139 Cooked + 4 `unaccent`, régénéré depuis la prod en CI) | [supabase/rpcs.sql](supabase/rpcs.sql) |
| Bibliothèques d'ingest Python | [src/cooked/](src/cooked/) |
| Glossaire de domaine (conversions, attribution, lecture, fraîcheur, invariants) | [CONTEXT.md](CONTEXT.md) |
| Décisions d'architecture (ADR) | [docs/adr/](docs/adr/) |
| Sécurité : PII, secrets, surface d'attaque, invariant I1 | [SECURITY.md](SECURITY.md) |
| Correctifs du 20/10/2026 : état de livraison et limites | [docs/RELIABILITY.md](docs/RELIABILITY.md) |
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

## Versions canoniques (20/10/2026)

| Composant | Version repo | Déploiement prod |
|---|---|---|
| Tracker | `sprint43` — contexte SPA, CWV document révisables ; minifier avant collage | Custom Code mis à jour le 20/10/2026 à 11:50 Paris ; HTML public conforme au minifié vérifié, événements sprint43 encore à vérifier |
| Edge `track` | v31 — iPhone/iPad reconnus iOS avant le motif macOS | Déployé le 20/10/2026 à 11:49 Paris, version Supabase 41 ACTIVE |
| Edge `form-webhook` | `v16` — ID obligatoire, reprise idempotente des deux écritures, HTTP 503 si incomplètes | Déployé le 20/10/2026 à 11:49 Paris, version Supabase 25 ACTIVE ; succède au correctif T-19 `country` du 19/09/2026 (Supabase 24) |
| RPC Postgres | 143 routines `pg_proc` (139 Cooked + 4 `unaccent` ; compte dans `contracts/doc_constants.json`, comparé à la prod chaque matin) | migrations Supabase |

**Repo et prod peuvent diverger** tant que Edge / tracker ne sont pas redéployés.
Toujours vérifier : `props->>'_v'` sur events récents + version commentée en tête
des fichiers Edge.
La déduplication SQL `measurement_id` + métrique a été déployée **avant** le
tracker révisable. Mettre à jour les états seulement après vérification.

## Périmètre

Mono-site `jplouton-avocat.fr` — ne pas généraliser multi-tenant sans décision
Nicolas explicite.
