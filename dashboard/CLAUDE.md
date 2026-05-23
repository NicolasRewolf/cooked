@AGENTS.md

# CLAUDE.md — cooked-dashboard

> Lu automatiquement au démarrage de chaque session Claude Code dans ce repo.

---

## Identité du projet

**cooked-dashboard** est l'interface de lecture du système d'analytics
Cooked × GSC. C'est un projet **séparé** du repo `cooked` (data layer).

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
  page.tsx                Home : site_kpis_compare + pages_overview_unified (alertes/contributeurs)
  pages/page.tsx          Tableau /pages : pages_overview_unified (univers exhaustif, ~490 paths)
  p/[...slug]/page.tsx    Fiche page : gsc_page_performance + gsc_top_queries_for_path
  health/page.tsx         Pipeline : refresh_pipeline_health
  globals.css             Design tokens REWOLF (canvas, surface, signals, shadows)

lib/
  cooked.ts               ⚠️ Server-only. Wrappers RPCs. Single point of contact.
  format.ts               Helpers FR (JJ/MM/AAAA, Europe/Paris, espaces fines)
  page-category.ts        Catégorisation pages (home / cabinet / expertise / resource / article)
  resource-slugs.ts       Liste des 51 articles "Ressources et notions juridiques"
  utils.ts                shadcn cn()

components/
  nav.tsx                 Nav minimaliste top
  date-banner.tsx         Bandeau dates + GSC freshness sous Nav
  status-pill.tsx         Pill healthy/degraded/critical
  kpi-card.tsx            KPI card avec valeur + delta % + sub
  category-badge.tsx      Badge catégorie de page
  info-label.tsx          Label + tooltip ℹ️
  pages-table.tsx         Tableau client avec filtres / tri / pagination
  ui/                     shadcn (button, card, table, badge, separator, skeleton, tooltip)
```

Toutes les pages sont des **Server Components** (`export const dynamic =
"force-dynamic"`). Pas de fetch client-side, pas de cache.

---

## RPCs disponibles (signature des wrappers `lib/cooked.ts`)

| Wrapper TS | RPC Postgres | Sortie |
|---|---|---|
| `pagesOverviewUnified(maxRows=1000)` | `pages_overview_unified(max_rows)` | univers exhaustif (snapshot Cooked 365j ∪ GSC 90j) avec contacts macro + booking_intent micro séparés |
| `gscPagePerformance(path)` | `gsc_page_performance(target_path)` | fiche complète d'une page (contacts + intent séparés) |
| `gscTopQueriesForPath(path, daysBack=28, maxRows=20)` | `gsc_top_queries_for_path(target_path, days_back, max_rows)` | top requêtes Google sur une page |
| `pipelineHealth()` | `refresh_pipeline_health()` | self-diag 4 axes (snapshot, cron, ingestion, GSC) |
| `siteKpisCompare(periodDays=28)` | `site_kpis_compare(period_days)` | KPIs business N vs N-1 (sessions, pageviews, phone, form_submit, macro) |
| `siteContext()` | `site_context_export()` | contexte site-wide 28j |

## 🚨 RÈGLE DURE — Définition « Contacts » (CLAUDE.md cooked)

Le terme **Contacts** dans le dashboard correspond UNIQUEMENT à la macro-conversion :

  contacts = phone_clicks (cta_phone_click) + form_submits (form_submit)

Ne **jamais** y additionner `booking_cta_click` — c'est une **micro-conversion** (intent
déclaré, pas matérialisé). Le champ correspondant est `cooked_booking_intent_28d`,
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
