@AGENTS.md

# CLAUDE.md — cooked-dashboard

> Lu automatiquement au démarrage de chaque session Claude Code dans ce repo.

---

## Identité du projet

**cooked-dashboard** est l'interface de lecture du système d'analytics
Cooked × GSC. Code dans `dashboard/` du repo **cooked** (data layer à la racine).

Stack : Next.js 15 + App Router + React 19 + TypeScript + Tailwind v4 +
shadcn/ui + Geist + Recharts + Framer Motion.

Style : minimaliste, palette crème (canvas `#F7F6F3`), Geist Sans/Mono,
ombres alpha 0.04-0.10, signaux feutrés. Tokens dans `app/globals.css`.

---

## 🚨 RÈGLE ABSOLUE — Silo strict avec Supabase

Ce dashboard est **READ-ONLY**. Aucun changement de schéma, aucune
migration, aucune écriture en base ne doit jamais venir d'ici. Toute
modification du data layer passe par le repo `cooked` (cf.
`~/Desktop/Cooked/`).

**Garde-fous en place :**

1. `lib/cooked.ts` commence par `import "server-only"` — empêche tout
   import dans un Client Component ou bundle navigateur.
2. La clé `SUPABASE_SECRET_KEY` est en env server-only, jamais
   `NEXT_PUBLIC_*`.
3. Les seules méthodes exposées sont des wrappers nommés sur des RPCs
   Postgres déjà publiées côté Cooked. Aucun accès au client Supabase
   brut depuis le reste du code.
4. Pas d'`apply_migration`, pas d'`execute_sql` DDL, pas de
   `CREATE/ALTER/DROP` jamais depuis ce repo.

**Si on a besoin d'une nouvelle vue/donnée :** on ouvre une session
dans le repo `cooked`, on crée la RPC + migration nommée + commit, puis
on revient ici ajouter un wrapper.

---

## Architecture

```
app/
  layout.tsx              Geist + theme + nav + TooltipProvider
  page.tsx                Home : KPIs, site_pulse, site_seo_funnel, alertes pages_pulse
  pages/page.tsx          Tableau /pages : pages_overview_unified
  queries/page.tsx        Top requêtes : gsc_top_queries_global
  p/[...slug]/page.tsx    Fiche : perf + queries + pulse + sparklines
  health/page.tsx         Pipeline : refresh_pipeline_health
  globals.css             Design tokens REWOLF (canvas, surface, signals, shadows)

lib/
  cooked.ts               ⚠️ Server-only. Wrappers RPCs. Single point of contact.
  format.ts               Helpers FR (JJ/MM/AAAA, Europe/Paris, espaces fines)
  page-category.ts        Catégorisation pages (home / cabinet / expertise / resource / article)
  resource-slugs.ts       Liste des 51 articles "Ressources et notions juridiques"
  utils.ts                shadcn cn()

components/
  nav.tsx                 Nav (/, /pages, /queries, /health)
  date-banner.tsx         Bandeau dates + fraîcheur GSC
  site-pulse-card.tsx     Pulse site-wide (quadrant GSC × Cooked)
  seo-funnel.tsx          Funnel impressions → contacts macro
  quadrant-badge.tsx      Badge quadrant Pulse (up_up, up_down, …)
  page-trend-panel.tsx    Sparklines GSC + Cooked (fiche page)
  status-pill.tsx         Pill healthy/degraded/critical
  kpi-card.tsx            KPI + delta %
  category-badge.tsx      Badge catégorie page
  pages-table.tsx         Tableau /pages (filtres, tri, pagination)
  queries-table.tsx       Tableau /queries
  ui/                     shadcn
```

Toutes les pages sont des **Server Components** (`export const dynamic =
"force-dynamic"`). Pas de fetch client-side, pas de cache.

---

## RPCs disponibles (signature des wrappers `lib/cooked.ts`)

| Wrapper TS | RPC Postgres | Sortie |
|---|---|---|
| `siteKpisCompare(periodKind)` | `site_kpis_compare(p_period_kind)` | KPIs business N vs N-1 (sessions, pageviews, phone, form_submit, macro) |
| `pagesOverviewUnified(periodKind, maxRows)` | `pages_overview_unified(period_kind, max_rows)` | tableau pages GSC × Cooked sur la période |
| `topContactPages(periodKind, maxRows)` | `top_contact_pages(p_period_kind, max_rows)` | top pages avec contacts (home, léger) |
| `gscPagePerformance(path, periodKind)` | `gsc_page_performance(target_path, period_kind)` | fiche page |
| `gscTopQueriesForPath(path, periodKind, maxRows)` | `gsc_top_queries_for_path(target_path, p_period_kind, max_rows)` | top requêtes Google sur une landing |
| `sitePulse(periodKind, threshold)` | `site_pulse(p_period_kind, …)` | Pulse site (GSC × Cooked, même fenêtre) |
| `pagesPulse(periodKind, threshold)` | `pages_pulse(period_kind, …)` | Pulse par path |
| `siteSeoFunnel(periodKind)` | `site_seo_funnel(period_kind)` | funnel SEO site-wide |
| `gscTopQueriesGlobal(periodKind, max)` | `gsc_top_queries_global(period_kind, max_rows)` | top requêtes + DFS |
| `gscXDfsOpportunities(periodKind, …)` | `gsc_x_dfs_opportunities(…, period_kind, …)` | opportunités SEO |
| `pipelineHealth()` | `refresh_pipeline_health()` | self-diag (sans filtre période) |
| `siteContext()` | `site_context_export()` | contexte site-wide 28j (fixe) |
| `gscPageDailySeries(path, days)` | `gsc_page_daily_series(...)` | série clics GSC (sparkline) |
| `cookedPageDailySeries(path, days)` | `cooked_page_daily_series(...)` | série sessions Cooked (sparkline) |

### Données externes : DataForSEO (volumes France)

Sprint 33+ (25/05/2026) — la table `public.dfs_keyword_volume` est
alimentée hebdomadairement par `.github/workflows/dfs-weekly-sync.yml`
(lundi 07:00 UTC) qui lit les top 500 keywords par clics GSC 90j
(RPC `dfs_keywords_to_sync`), appelle l'API DataForSEO Google Ads
search_volume France entière (`location_code = 2250`) et upsert
search_volume mensuel + CPC + competition. Le wrapper
`gscTopQueriesGlobal` joint cette table pour exposer `volume_fr`,
`cpc`, `click_yield_pct` sur chaque requête. `gscXDfsOpportunities`
projette les "quick wins" (lost potential ordonné desc) consommé par
`<SeoOpportunities />` en haut de `/queries`. Coût ~$2/mois.

## 🚨 RÈGLE DURE — Définition « Contacts » (CLAUDE.md cooked)

Le terme **Contacts** dans le dashboard correspond UNIQUEMENT à la macro-conversion :

  contacts = phone_clicks (cta_phone_click) + form_submits (form_submit)

Ne **jamais** y additionner `booking_cta_click` — c'est une **micro-conversion** (intent
déclaré, pas matérialisé). Le champ correspondant est `cooked_booking_intent`,
affiché séparément.

Le bug du 24/05/2026 (review code) a été causé par ce mélange : `gsc_pages_overview`
et `pages_overview_unified` v1/v2 calculaient `phone + booking` au lieu de
`phone + form_submit`, gonflant artificiellement les pages comme `/honoraires-rendez-vous`.
La v3 (migration `20260524100000_contacts_macro_per_path.sql`) corrige en allant
chercher `form_submit` par path dans `events_human`.

**Pour ajouter une RPC :** créer le wrapper dans `lib/cooked.ts` avec
le type de retour explicite. Ne **jamais** taper `.rpc()` ailleurs.

---

## Règles d'affichage (héritées de cooked/CLAUDE.md)

1. **Timezone Europe/Paris partout dans l'UI.** Les valeurs DB sont en
   UTC, on convertit à l'affichage via `formatDateTimeFR()`.

2. **Dates en JJ/MM/AAAA.** Jamais d'ISO dans le texte affiché.

3. **Nombres en français.** Espace fine pour les milliers, virgule
   décimale. `formatInt`, `formatPct`, `formatNumber` utilisent
   `Intl.NumberFormat("fr-FR", ...)`.

4. **Une seule métrique business à la fois.** Macro-conversions =
   `phone_clicks + form_submits` (voir section « Définition Contacts »).
   Ne pas mélanger avec micro (`cta_booking_click`, `cta_anchor_click`)
   ni engagement (scroll/dwell).

---

## Variables d'env

`.env.local` (non commité, voir `.env.local.example`) :

```
SUPABASE_URL=https://mxycmjkeotrycyneacje.supabase.co
SUPABASE_SECRET_KEY=sb_secret_***
```

Récupérables sur Dashboard Supabase → Cooked → API Keys.

---

## Dev

```
npm install
cp .env.local.example .env.local   # puis remplir SUPABASE_SECRET_KEY
npm run dev                         # http://localhost:3000
```

Build : `npm run build` puis `npm run start`.
Typecheck : `npx tsc --noEmit`.
Lint : `npm run lint`.
