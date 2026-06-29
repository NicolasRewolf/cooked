# Dashboard Cooked — articles ressources

Tableau de bord (lecture seule) qui synthétise le **comportement** (Cooked) et le **SEO par requête**
(volume DataForSEO en référence) des articles « Ressources et notions juridiques » de
jplouton-avocat.fr.

Sous-app **isolée** du repo : aucun import du pipeline (`/scripts`, `/wix`, `/supabase`). Le seul
contrat avec la base est l'ensemble des **RPC Postgres** (migration `20260629112816_dashboard_v1_rpcs`).

## Stack
Next.js 16 (App Router) · React 19 · TypeScript · Tailwind v4 · Recharts · `@supabase/supabase-js`
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
  lib/                   supabase-admin (clé service), types (contrat RPC), format fr-FR, periods, cn
  data/dashboard.ts      appels typés aux 3 RPC
  components/            KpiHeader, SortableTable, ResourcesTable, SeoTable, FreshnessBanner, …
  app/                   / (synthèse)  ·  /seo (requêtes)  ·  /login  ·  /auth/{callback,signout}
```

## Données (couche serveur, source de vérité)
3 RPC `service_role` (migration `20260629112816`) qui figent les leçons de mesure :
- `dashboard_resources_overview(period_kind, max_rows)` — 1 ligne / article ressource.
- `dashboard_resources_kpis(period_kind)` — KPI d'en-tête N vs N-1.
- `dashboard_seo_by_query(period_kind, scope, min_volume, max_rows)` — requêtes + volume DFS.

Garanties intégrées : visiteurs **uniques** (pas sessions), spam **Baidu exclu** (vue
`events_human_clean`), lecture sur **vrais lecteurs** (hors ré-ouvertures réseaux sociaux), totaux
Google depuis `gsc_path_daily`, requêtes **de marque exclues**, volume **DataForSEO** (France, 2250).

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
- Le dashboard type les 3 RPC à la main (`src/lib/types.ts`) ; si une signature RPC change, mettre à
  jour ce fichier.
- Le bandeau de fraîcheur affiche le décalage Google (lag J-2 normal) — le dashboard dit toujours à
  quel point il est à jour.
