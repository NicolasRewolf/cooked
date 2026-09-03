# Contribuer à Cooked

Cooked est un système **mono-tenant** (jplouton-avocat.fr), maintenu par Nicolas
Rewolf avec assistance IA. Ce guide sert aux humains et aux agents qui reprennent
le repo.

## Avant de coder

1. Lire [README.md](README.md) (vue d'ensemble) et [CLAUDE.md](CLAUDE.md) (règles
   métier et réflexes SQL).
2. En session d'analyse prod : `SELECT * FROM alerts WHERE NOT acked` puis
   `SELECT * FROM refresh_pipeline_health()`.
3. Ne jamais committer de secrets (voir [SECURITY.md](SECURITY.md)).

## Workflow Git

```
main                          — prod stable
claude/<sujet> ou chore/…     — branche de travail
  → commit(s)
  → git push -u origin HEAD
  → gh pr create
  → CI verte → gh pr merge --merge --delete-branch
```

Règles :

- **Une migration appliquée en prod** = son miroir exact dans
  `supabase/migrations/` (timestamp réel) dans la **même PR**.
- Si une **RPC** change : régénérer `supabase/rpcs.sql` +
  `contracts/rpc_snapshot_meta.json` (`python3 scripts/generate_rpcs_sql.py`
  avec `DATABASE_URL`, ou dump prod — gate CI Arch #5).
- Pas de contenu placeholder ; pas de `UPDATE` manuel non tracé en prod.
- Après migration : `latest_rpc_health()` + advisors Supabase OK.

## Conventions de commit

Format libre, en français ou anglais, **impératif court + contexte** :

```
fix(C6): cooked_period_bounds utilise paris_today()
Arch #5: rpcs.sql miroir des 104 RPC + gate CI fraîcheur
Docs : synchro arch 10/07 + rpcs.sql
```

## Structure du repo

| Zone | Rôle |
|---|---|
| `supabase/migrations/` | **Source de vérité DDL** (déploiement) |
| `supabase/rpcs.sql` | Miroir lecture des corps RPC (généré) |
| `supabase/functions/` | Edge Functions Deno (`track`, `form-webhook`) |
| `wix/` | Tracker + proxy Velo (collé manuellement dans Wix) |
| `scripts/` | Ingest GSC/DFS/SECIB, import forms Wix, contrats CI, outillage |
| `dashboard/` | Sous-app Next.js isolée (Vercel) |
| `contracts/` | Vecteurs de test partagés (voir tableau ci-dessous) |
| `docs/` | Documentation approfondie |
| `tests/` | Tests tracker (jsdom) + Python ingest |

### Contrats (`contracts/`)

| Fichier | Rôle |
|---|---|
| `canonical_path_vectors.json` | C3 — paths SQL / Edge / Python |
| `branded_query_vectors.json` | Arch #3 — `gsc_is_branded` |
| `recruitment_objet_vectors.json` | D4 — filtrage macro `form_submit` |
| `rpc_snapshot_meta.json` | Arch #5 — hash de `supabase/rpcs.sql` |
| `dashboard_rpc_columns.json` | T-13 (ex-Arch #6) — contrat des 16 RPC dashboard généré DEPUIS LA PROD (`scripts/generate_dashboard_contracts.py`, `--check` en CI prod-drift) ↔ Zod (`rpc-contract.test.ts`) |

## Contrats CI (ne pas casser)

| Workflow | Rôle |
|---|---|
| `sql-contracts` | C6 pas de cast Paris brut ; C6c pas de `current_date` / `now() - make_interval` (migrations ≥ 20260903093320) ; Arch #5 rpcs.sql à jour |
| `canonical-path-contract` | SQL / Edge / Python alignés |
| `python-ingest-contract` | Tests GSC/DFS |
| `dashboard-contract` | Vitest dashboard (85 tests) |
| `tracker-test` | Suite jsdom tracker |
| `edge-shared-helpers` | Deno tests `_shared/` (events_row, track_row, form_row) |
| `gsc-daily-ingest` / `dfs-weekly-sync` / `gbp-daily-ingest` | Crons ingestion (GitHub Actions) |

## Issues

GitHub Issues : `gh issue create` — labels de triage dans
[docs/agents/triage-labels.md](docs/agents/triage-labels.md).

## Documentation à mettre à jour

Quand le comportement change :

- [CHANGELOG.md](CHANGELOG.md) — version / date du changement notable
- [docs/HISTORY-sprints.md](docs/HISTORY-sprints.md) — jalon sprint si significatif
- [README.md](README.md) ou [docs/OPERATIONS.md](docs/OPERATIONS.md) si impact opérationnel

## Décisions qui demandent validation explicite (Nicolas)

- Décision business / produit (multi-tenancy, UI client final)
- Suppression irréversible de données (`DROP`, `DELETE` massif)
- Coût significatif (plan Supabase supérieur, API tierce facturée)
- Backup externe (décliné 02/07/2026 — ne pas re-proposer avant ~06/2027)
