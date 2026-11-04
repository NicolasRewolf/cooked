# Cooked — page de transition

L’ancienne interface de métriques est retirée. Une page authentifiée explique
que les anciens indicateurs ont été retirés, que la nouvelle interface sera
traitée séparément et que les données sources sont conservées. Elle ne consulte
aucune table ni RPC métier et ne présente aucun état de santé en direct.

Les anciennes adresses `/expertises`, `/seo`, `/lab` et `/article/*` redirigent
vers `/`. Les redirections sont temporaires afin de ne pas figer les futures URL.

## Accès

Supabase Auth reste utilisé pour le magic-link et les cookies de session.
`proxy.ts` vérifie l’adresse dans l’allowlist ; `requireUser()` répète cette
vérification côté serveur avant d’afficher la page. Une allowlist vide refuse
l’accès. La demande de magic-link conserve `shouldCreateUser: false` et le
callback limite la destination à une URL interne. La déconnexion utilise POST,
puis une redirection 303 vers la connexion.

Le dashboard n’a plus besoin de clé service. Les variables nécessaires sont :

| Variable | Usage |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Projet d’authentification |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clé publique du flux Auth |
| `DASHBOARD_ALLOWED_EMAILS` | Adresses autorisées, séparées par des virgules |

Copier `.env.local.example` vers `.env.local` pour le développement ; ne jamais
committer les valeurs réelles. Les réglages Supabase Auth existants restent
nécessaires : inscriptions désactivées et URL de callback autorisées, dont
`https://data.rewolf.studio/auth/callback`.

## Développement et vérification

Next.js 16, React 19, TypeScript et Tailwind ; identité IBM Plex et orange rewolf
conservée. Les couleurs vivent dans `src/app/globals.css`.

```sh
npm ci
npm test
npm run lint
npm run build
npm run dev
```

Les tests vérifient les destinations du callback, le payload magic-link,
l’allowlist, le refus sans session, la déconnexion et l’absence de dépendance
à une clé service. Ils ne déclenchent aucun courriel ni accès à la production.

Vercel conserve `dashboard` comme Root Directory. L’indexation reste interdite,
et les en-têtes de sécurité existants restent en place. Le générateur de contrats
et les schémas des anciennes RPC dashboard ont été retirés avec leurs lecteurs.
