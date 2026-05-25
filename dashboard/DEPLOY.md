# Déployer le dashboard sur Vercel

## Cause du 404

Si le deploy dure **~2 secondes** et affiche **404 NOT_FOUND**, Vercel ne build **pas** Next.js : le **Root Directory** pointe encore sur la racine du repo (pas `dashboard/`).

Vérification : **Deployments** → durée **45–90 s** et logs avec `next build`.

## Réglage obligatoire (interface Vercel)

1. [vercel.com](https://vercel.com) → projet **cooked**
2. **Settings** → **General**
3. **Root Directory** → **Edit** → `dashboard` → **Save**
4. **Framework Preset** → **Next.js** (si proposé)
5. **Environment Variables** :
   - `SUPABASE_URL` = `https://mxycmjkeotrycyneacje.supabase.co`
   - `SUPABASE_SECRET_KEY` = clé `sb_secret_*`
6. **Deployments** → dernier deploy → **Redeploy** (sans cache)

## Variables d’env

Jamais de `NEXT_PUBLIC_` pour la clé Supabase.

## SQL Supabase (avant prod)

Voir `supabase/scripts/README.md` — 4 migrations dans l’ordre.

## Domaine `cooked.rewolf.studio`

**Settings → Domains** → ajouter le domaine → CNAME Squarespace `cooked` → `cname.vercel-dns.com`.

## Sécurité

**Settings → Deployment Protection** → mot de passe avant de partager l’URL.

## CLI (optionnel)

```bash
cd dashboard
vercel link --project=cooked
vercel deploy --prod
```

Toujours lancer les commandes depuis `dashboard/`, pas la racine du repo.
