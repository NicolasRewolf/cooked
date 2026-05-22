# cooked-dashboard

Interface de lecture pour le système d'analytics Cooked × GSC du cabinet
`jplouton-avocat.fr`.

Projet **séparé** du repo [`cooked`](https://github.com/NicolasRewolf/cooked)
qui contient le data layer (tracker Wix, Edge Functions Supabase,
ingestion GSC, RPCs Postgres). Ce dashboard est strictement READ-ONLY
sur la base.

## Stack

- Next.js 15 (App Router) + React 19 + TypeScript
- Tailwind v4 + shadcn/ui + Geist
- Recharts, Framer Motion
- `@supabase/supabase-js` server-only

## Pages

| Route | Source | Contenu |
|---|---|---|
| `/` | `gsc_pages_overview` | Top 30 pages 28j (GSC × Cooked) |
| `/p/[...slug]` | `gsc_page_performance` + `gsc_top_queries_for_path` | Fiche complète d'une page |
| `/health` | `refresh_pipeline_health` | Self-diag pipeline 4 axes |

## Dev

```bash
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

**Conséquence** : aucune modification de schéma, aucune migration, aucune
écriture ne peut venir d'ici. Pour toute évolution du data layer, ouvrir
une session dans le repo `cooked`.

## Variables d'env

| Var | Description |
|---|---|
| `SUPABASE_URL` | URL du projet Cooked (défaut hardcodé OK) |
| `SUPABASE_SECRET_KEY` | Clé `sb_secret_*` server-only |

⚠️ Jamais de préfixe `NEXT_PUBLIC_` pour ces vars — la clé secret serait
exposée au navigateur.
