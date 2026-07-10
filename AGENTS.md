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
| Corps complets des RPC | [supabase/rpcs.sql](supabase/rpcs.sql) |
| Signatures + vues | [supabase/views.sql](supabase/views.sql) |
| DDL déploiement | [supabase/migrations/](supabase/migrations/) |
| Analyse SEO (pièges) | [docs/PLAYBOOK-analyse-seo.md](docs/PLAYBOOK-analyse-seo.md) |
| Score CPI | [docs/cpi-cooked-page-index.md](docs/cpi-cooked-page-index.md) |
| Dashboard UI | [dashboard/README.md](dashboard/README.md) + [dashboard/AGENTS.md](dashboard/AGENTS.md) |
| Historique | [docs/HISTORY-sprints.md](docs/HISTORY-sprints.md) |
| Changements récents | [CHANGELOG.md](CHANGELOG.md) |
| Index docs | [docs/README.md](docs/README.md) |

## Contrats testables

- `contracts/canonical_path_vectors.json`
- `contracts/branded_query_vectors.json`
- `contracts/rpc_snapshot_meta.json`

## Périmètre

Mono-site `jplouton-avocat.fr` — ne pas généraliser multi-tenant sans décision
Nicolas explicite.
