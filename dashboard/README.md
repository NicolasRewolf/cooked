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

## Périodes (URL `?period=`)

Sélecteur global dans la barre de navigation. Valeurs :

| `period` | Libellé |
|---|---|
| `today` | Aujourd'hui (jour Paris) |
| `week` | Semaine en cours (lundi → aujourd'hui) |
| `month` | Mois en cours (1er → aujourd'hui) |
| `rolling_28` | 28 derniers jours (défaut) |
| `rolling_90` | 3 derniers mois (90 j) |

Bornes calculées côté Postgres par `cooked_period_bounds(period_kind)` — heure **Europe/Paris**.

## Pages

| Route | RPCs principales | Contenu |
|---|---|---|
| `/` | `site_kpis_compare`, `site_pulse`, `pages_pulse`, `site_seo_funnel`, `pages_overview_unified` | Pulse, funnel SEO, KPI Contacts, alertes Pulse |
| `/pages` | `pages_overview_unified(period_kind)` | Tableau pages GSC × Cooked sur la période choisie |
| `/queries` | `gsc_top_queries_global`, `gsc_x_dfs_opportunities` | Top requêtes + opportunités SEO (DFS) |
| `/p/[...slug]` | `gsc_page_performance`, `gsc_top_queries_for_path`, `pages_pulse` | Fiche page (hérite `?period=`) |
| `/health` | `refresh_pipeline_health` | Pipeline (sans filtre période) |

## Définition Contacts (alignée cooked/CLAUDE.md)

- **Macro** (vrai contact) = `cta_phone_click` + `form_submit` → colonnes `cooked_contacts_*`, KPI « Contacts générés »
- **Micro / intent RDV** = `cta_booking_click` → `cooked_booking_intent_*` (affiché à part)
- **Engagement** = sessions, dwell, scroll — colonnes neutres, pas des « conversions » business

## Wrappers `lib/cooked.ts`

| Wrapper TS | RPC Postgres |
|---|---|
| `siteKpisCompare(periodKind)` | `site_kpis_compare(period_kind)` |
| `sitePulse(periodKind, threshold)` | `site_pulse(period_kind, …)` |
| `pagesPulse(periodKind, …)` | `pages_pulse(period_kind, …)` |
| `siteSeoFunnel(periodKind)` | `site_seo_funnel(period_kind)` |
| `pagesOverviewUnified(periodKind, maxRows)` | `pages_overview_unified(period_kind, …)` |
| `gscPagePerformance(path, periodKind)` | `gsc_page_performance(path, period_kind)` |
| `gscTopQueriesForPath(path, periodKind, max)` | `gsc_top_queries_for_path` (fenêtre = `cooked_period_bounds`) |
| `gscTopQueriesGlobal(periodKind, max)` | `gsc_top_queries_global(period_kind, …)` |
| `gscXDfsOpportunities(periodKind, …)` | `gsc_x_dfs_opportunities(…, period_kind, …)` |
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
