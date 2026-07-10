# Dashboard Cooked — articles ressources

Tableau de bord (lecture seule) qui synthétise le **comportement** (Cooked) et le **SEO par requête**
(volume DataForSEO en référence) des articles « Ressources et notions juridiques » de
jplouton-avocat.fr.

Sous-app **isolée** du pipeline (`/scripts`, `/wix`, `/supabase/migrations`). Le contrat
avec la base = RPC Postgres `dashboard_*` (corps lisibles dans `../supabase/rpcs.sql`).

## Stack
Next.js 16 (App Router) · React 19 · TypeScript · Tailwind v4 · `@supabase/supabase-js`
(lecture, clé service, serveur uniquement) · `@supabase/ssr` (auth) · zod. Déploiement Vercel.

## Architecture (pourquoi)
Tous les RPC sont `service_role` et les tables en RLS deny-all → **un navigateur avec la clé anon ne
lit rien**. Donc toutes les lectures passent **côté serveur** avec `SUPABASE_SECRET_KEY` (jamais
exposée : `src/lib/supabase-admin.ts` est marqué `import "server-only"`). La clé anon ne sert qu'à
l'authentification (magic-link), qui ne lit aucune donnée métier.

```
src/
  env.ts                 validation zod (serveur)
  proxy.ts               gate auth (ex-middleware Next 16) : session + allowlist d'emails
  lib/                   supabase-admin, types RPC, format fr-FR, dates, chart-geometry (D8), momentum, trend-math
  data/                  dashboard.ts (appels RPC), view-models.ts (D7 — pages → props UI)
  components/            KpiHeader, ResourcesTable, ExpertisesTable, SeoTable, metric-columns (D6), …
  app/                   / · /expertises · /seo · /article/[slug] · /login · /auth/{callback,signout}
```

**Tests** : `npm test` — 85 tests vitest (view-models, chart-geometry, metric-columns, RPC schemas…).

## Données (couche serveur, source de vérité)
RPC `service_role` (migrations `20260629112816` v1 + `20260629135836` v2 + `20260630133301`
facteurs de pilotage) qui figent les leçons de mesure :
- `dashboard_resources_overview(period_kind, max_rows)` — 1 ligne / article ressource.
- `dashboard_resources_kpis(period_kind)` — KPI d'en-tête N vs N-1.
- `dashboard_seo_by_query(period_kind, scope, min_volume, max_rows)` — requêtes + volume DFS.
- `dashboard_seo_kpis(period_kind, scope)` — totaux SEO calculés SQL (quick wins, 2 niveaux de clics) indépendants du cap du tableau.

Les RPC lisent des **snapshots quotidiens** (tables `dashboard_*_snapshot`, refresh
`refresh_dashboard_snapshots(p_window)` en cron — driver `cooked_snapshot_window`, lens
`live_j1` = fin J-1 Paris) — l'agrégation live des events était trop lente
(~106 s). Garanties intégrées : visiteurs **uniques** (pas sessions), spam **Baidu exclu** (filtrage
inline dans les RPC `dashboard_*` ; la vue `events_human_clean` d'origine a été dropée), lecture sur
**vrais lecteurs** (hors ré-ouvertures réseaux sociaux), totaux Google depuis `gsc_path_daily`,
requêtes **de marque exclues**, volume **DataForSEO** (France, 2250).

### Facteurs de pilotage (migration `20260630133301_dashboard_pilotage_factors`, 30/06/2026)
Pour répondre à « est-ce que ça va ou pas ? » au niveau de chaque ligne (et pas juste des KPI
d'en-tête), les tableaux croisent les sources existantes. Ajout **additif** : la table snapshot
gagne des colonnes, `dashboard_resources_overview` (SETOF) les expose sans changement de signature.

- **Tableau Articles** — colonnes snapshot ajoutées : `unique_visitors_prev`, `gsc_clicks_prev`
  (tendance N-1, déjà chargée par le refresh) ; `cpi`, `cpi_grade`, `momentum`, `potentiel`,
  `convertit` (croisés depuis `cpi_daily` / `cpi_gisement` par `path`) ; `ctr_expected`
  (= `ctr_for_position(position) × 100`, la courbe CTR du site). Rendu UI :
  - **Santé** = verdict momentum relatif au site (monte / stable / ralentit) + ⭐ *gisement*
    (grade A/B mais sans contact). On affiche le **potentiel hors-conversion**, pas le CPI brut —
    le CPI complet est tiré vers le bas par la conversion, rare sur des articles éducatifs, et
    ferait passer une page saine pour malade (le score CPI reste en infobulle).
  - **Tendance ▲▼** inline sur Visiteurs et Clics Google.
  - **CTR / attendu** : rouge si le CTR réel passe sous la courbe du site (titre/méta à retravailler).
  - **Source** : part du trafic venant de Google vs réseaux/IA/direct (clics GSC ÷ visiteurs Cooked).
- **Tableau SEO** — `dashboard_seo_by_query` recréée (RETURNS TABLE) avec `clicks_prev`,
  `position_prev`, `ctr_expected`, `opportunity_clicks` (clics/mois estimés si la requête passait
  en top 3 au CTR du site). Rendu UI : tendances ▲▼ (clics, places gagnées) + colonne **Gain pot.
  / mois** qui trie les quick wins par enjeu réel plutôt que par volume brut.

Composant `Trend` partagé dans `components/ui.tsx`. Le contrat typé de ces colonnes vit dans
`lib/types.ts` (`ResourceRow`, `SeoQueryRow`).

## Développement local
```bash
cp .env.local.example .env.local   # puis remplir les clés
npm install
npm run dev                        # http://localhost:3000
```

### Variables (`.env.local`)
| Var | Rôle | Exposée navigateur ? |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL projet | oui (sûr) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | flux auth uniquement | oui (sûr, RLS deny-all) |
| `SUPABASE_SECRET_KEY` | lecture des données (`sb_secret_…`) | **NON — serveur only** |
| `DASHBOARD_ALLOWED_EMAILS` | allowlist (séparée par virgules) | non |

## Authentification (Supabase Auth — magic-link + allowlist) — réglages OBLIGATOIRES
Le gate `proxy.ts` est **fail-closed** : allowlist vide ⇒ personne ne passe. `DASHBOARD_ALLOWED_EMAILS`
est donc requis (le build échoue s'il manque). Défense en profondeur : chaque page serveur
re-vérifie via `requireUser()` (`src/lib/auth.ts`). Côté Supabase (projet `mxycmjkeotrycyneacje`) :
1. **Auth → URL Configuration** : Site URL = l'URL du dashboard ; **Redirect URLs** = ajouter
   `http://localhost:3000/auth/callback` et `https://data.rewolf.studio/auth/callback`.
2. **OBLIGATOIRE — Auth → Sign In / Providers → Email** : désactiver « Allow new users to sign up »
   (sinon n'importe qui peut se créer un compte ; seule l'allowlist le bloquerait). Activer le
   rate-limit OTP.
3. Renseigner les emails autorisés dans `DASHBOARD_ALLOWED_EMAILS` (obligatoire).

## Déploiement (Vercel)
1. Nouveau projet Vercel pointant sur ce repo, **Root Directory = `dashboard`** (framework Next.js
   auto-détecté).
2. Environment Variables : les 4 ci-dessus (scope **Production + Preview** ; `SUPABASE_SECRET_KEY`
   sans préfixe `NEXT_PUBLIC_`).
3. Domaine : pointer le sous-domaine rewolf.
4. Ajouter l'URL de prod aux Redirect URLs Supabase (étape Auth ci-dessus).

## À savoir
- `params`/`searchParams` sont **async** (Next 16) ; pages `/` et `/seo` en `force-dynamic` (toujours
  frais, pas de cache — adapté à un usage interne 1-3 utilisateurs).
- Le dashboard type les 4 RPC à la main (`src/lib/types.ts`) ; si une signature RPC change, mettre à
  jour ce fichier.
- Le bandeau de fraîcheur affiche le décalage Google (lag J-2 normal) — le dashboard dit toujours à
  quel point il est à jour.
