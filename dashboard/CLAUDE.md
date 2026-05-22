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
  layout.tsx              Geist + theme + nav
  page.tsx                Home : gsc_pages_overview(30)
  p/[...slug]/page.tsx    Fiche page : gsc_page_performance + gsc_top_queries_for_path
  health/page.tsx         Pipeline : refresh_pipeline_health
  globals.css             Design tokens REWOLF (canvas, surface, signals, shadows)

lib/
  cooked.ts               ⚠️ Server-only. Wrappers RPCs. Single point of contact.
  format.ts               Helpers FR (JJ/MM/AAAA, Europe/Paris, espaces fines)
  utils.ts                shadcn cn()

components/
  nav.tsx                 Nav minimaliste top
  status-pill.tsx         Pill healthy/degraded/critical
  ui/                     shadcn (button, card, table, badge, separator, skeleton)
```

Toutes les pages sont des **Server Components** (`export const dynamic =
"force-dynamic"`). Pas de fetch client-side, pas de cache.

---

## RPCs disponibles (signature des wrappers `lib/cooked.ts`)

| Wrapper TS | RPC Postgres | Sortie |
|---|---|---|
| `gscPagesOverview(maxRows=30)` | `gsc_pages_overview(max_rows)` | top pages 28j |
| `gscPagePerformance(path)` | `gsc_page_performance(target_path)` | fiche complète d'une page |
| `gscTopQueriesForPath(path, daysBack=28, maxRows=20)` | `gsc_top_queries_for_path(target_path, days_back, max_rows)` | top requêtes Google |
| `pipelineHealth()` | `refresh_pipeline_health()` | self-diag 4 axes |
| `siteContext()` | `site_context_export()` | contexte site-wide 28j |

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
   `phone_clicks + booking_clicks`. Ne pas mélanger avec micro
   (`anchor`) ou engagement (scroll/dwell).

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
