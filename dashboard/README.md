# cooked-dashboard

Interface de lecture pour le système d'analytics **Cooked × GSC** du cabinet
[jplouton-avocat.fr](https://www.jplouton-avocat.fr).

Le code vit dans le dossier `dashboard/` du repo **cooked** (même dépôt que le
data layer : tracker Wix, Edge Functions, ingestion GSC, RPCs Postgres). Ce
dashboard est strictement **READ-ONLY** sur Supabase.

## Stack

- Next.js 15 (App Router) + React 19 + TypeScript
- Tailwind v4 + shadcn/ui + Geist
- Recharts, Framer Motion
- `@supabase/supabase-js` server-only

## Pages

| Route | RPCs principales | Contenu |
|---|---|---|
| `/` | `site_kpis_compare`, `site_pulse`, `pages_pulse`, `site_seo_funnel`, `pages_overview_unified` | Pulse site-wide, funnel SEO (impressions → contacts), KPI **Contacts** macro, alertes Pulse `up_down`, top contributeurs |
| `/pages` | `pages_overview_unified` | Univers exhaustif (~490 paths : snapshot Cooked 365j ∪ GSC 90j), filtres / tri / pagination |
| `/queries` | `gsc_top_queries_global`, `gsc_x_dfs_opportunities` | Top requêtes Google du site (28j) avec page cible + volumes France DataForSEO (search_volume / CPC / click yield) + section "Opportunités SEO" (pos 5–15, lost potential) |
| `/p/[...slug]` | `gsc_page_performance`, `gsc_top_queries_for_path`, `pages_pulse`, `gsc_page_daily_series`, `cooked_page_daily_series` | Fiche page, requêtes, quadrant Pulse, sparklines GSC (56j) + Cooked (14j) |
| `/health` | `refresh_pipeline_health` | Self-diag pipeline (snapshot, cron, ingestion, GSC) |

## Définition Contacts (alignée cooked/CLAUDE.md)

- **Macro** (vrai contact) = `cta_phone_click` + `form_submit` → colonnes `cooked_contacts_*`, KPI « Contacts générés »
- **Micro / intent RDV** = `cta_booking_click` → `cooked_booking_intent_*` (affiché à part)
- **Engagement** = sessions, dwell, scroll — colonnes neutres, pas des « conversions » business

## Wrappers `lib/cooked.ts`

| Wrapper TS | RPC Postgres |
|---|---|
| `siteKpisCompare(periodDays)` | `site_kpis_compare` |
| `sitePulse(gscPeriod, cookedPeriod, threshold)` | `site_pulse` |
| `pagesPulse(...)` | `pages_pulse` |
| `siteSeoFunnel(periodDays)` | `site_seo_funnel` |
| `pagesOverviewUnified(maxRows)` | `pages_overview_unified` |
| `gscPagePerformance(path)` | `gsc_page_performance` |
| `gscTopQueriesForPath(path, days, max)` | `gsc_top_queries_for_path` |
| `gscTopQueriesGlobal(days, max)` | `gsc_top_queries_global` (v2 enrichi DFS) |
| `gscXDfsOpportunities(minVol, posMin, posMax, days, max)` | `gsc_x_dfs_opportunities` |
| `gscPageDailySeries(path, days)` | `gsc_page_daily_series` |
| `cookedPageDailySeries(path, days)` | `cooked_page_daily_series` |
| `pipelineHealth()` | `refresh_pipeline_health` |
| `siteContext()` | `site_context_export` |

Nouvelle donnée → migration + RPC dans le repo **cooked**, puis wrapper ici.

## Dev

```bash
cd dashboard
npm install
cp .env.local.example .env.local
# remplir SUPABASE_SECRET_KEY (sb_secret_*)
npm run dev
```

Ouvre [http://localhost:3000](http://localhost:3000).

## Principe silo

Toutes les requêtes Supabase passent par `lib/cooked.ts`, qui :

- est marqué `import "server-only"` (jamais bundlé navigateur)
- expose uniquement des wrappers READ-ONLY sur des RPCs Postgres
- ne donne pas accès au client Supabase brut

**Conséquence** : aucune migration ni écriture depuis ce dossier. Évolution schéma
→ session à la racine du repo `cooked` (`supabase/migrations/`).

## Variables d'env

| Var | Description |
|---|---|
| `SUPABASE_URL` | URL du projet Cooked (défaut hardcodé OK) |
| `SUPABASE_SECRET_KEY` | Clé `sb_secret_*` server-only |

⚠️ Jamais de préfixe `NEXT_PUBLIC_` pour ces vars.

Règles agent : [`CLAUDE.md`](./CLAUDE.md).
