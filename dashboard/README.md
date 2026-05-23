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
| `/` | `site_kpis_compare` + `pages_overview_unified` | KPIs business 28j vs 28j-1 (contacts macro = phone + form_submit) + top contributeurs + alertes |
| `/pages` | `pages_overview_unified` | Univers exhaustif (~490 paths : snapshot Cooked 365j ∪ GSC 90j) avec filtres / tri / pagination |
| `/p/[...slug]` | `gsc_page_performance` + `gsc_top_queries_for_path` | Fiche complète d'une page (contacts macro + intent micro séparés) |
| `/health` | `refresh_pipeline_health` | Self-diag pipeline 4 axes |

## Définition Contacts (CLAUDE.md cooked)

- **Macro** (vrai contact établi) = `cta_phone_click` + `form_submit`. C'est le chiffre "Contacts" affiché dans le dashboard. Ne pas y mélanger les micro-conversions.
- **Micro / Intent RDV** = `cta_booking_click` (clic « Prendre RDV » qui mène vers `/honoraires-rendez-vous`). Affiché séparément dans la fiche page.
- **Engagement** = scroll / dwell / sessions. Affiché en colonnes neutres.

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
