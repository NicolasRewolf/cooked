# Cooked — pages et vues

Une seule page liste les URL actuellement publiées sur `jplouton-avocat.fr`,
y compris celles à zéro vue. Les vues sont les événements `pageview` après les
filtres communs du site et des bots. Plusieurs affichages d’une page comptent
plusieurs vues ; ce ne sont pas des visites uniques.

## Lecture

- Périodes de 30, 60 ou 90 jours clos Paris ; 90 jours par défaut. Les dates sont affichées.
- Toutes les pages ; expertises (hubs et pages d’expertise) ; articles hors ressources ;
  articles « Ressources et notions juridiques ». Articles et ressources sont disjoints.
- Vues décroissantes puis chemin pour départager les égalités.

L’inventaire et les comptes viennent de `page_view_counts(p_days)`, lu côté serveur
à l’ouverture et au changement de période. Le type de page filtre immédiatement
les données déjà reçues, sans nouvelle lecture. Les filtres restent dans l’URL
partageable ; précédent et suivant rétablissent le filtre. Une collecte partielle ou un
inventaire absent ou confirmé il y a plus de deux jours calendaires Paris produit une indication courte.
Un échec de lecture ne devient jamais une liste vide ou des zéros.

Aucun graphique, score, comparaison, conversion, recherche ou pagination n’est
ajouté. Les anciennes adresses `/expertises`, `/seo`, `/lab` et `/article/*`
redirigent temporairement vers `/`.

## Accès

Supabase Auth reste utilisé pour le magic-link et les cookies de session.
`proxy.ts` vérifie l’adresse dans l’allowlist ; le lecteur serveur appelle
`requireUser()` avant toute lecture métier. Une allowlist vide refuse l’accès.
La demande de magic-link conserve `shouldCreateUser: false` ; le callback limite
la destination à une URL interne. La déconnexion utilise POST, puis redirection
303 vers la connexion.

La clé publique ne lit aucune donnée métier. La clé technique est chargée
uniquement par le lecteur `server-only`, après authentification. Elle n’est
nécessaire ni au navigateur ni au chargement de la configuration Auth.

| Variable | Usage |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Projet Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clé publique du flux Auth |
| `DASHBOARD_ALLOWED_EMAILS` | Adresses autorisées, séparées par des virgules |
| `SUPABASE_SECRET_KEY` | Lecture agrégée des vues, serveur uniquement |

Copier `.env.local.example` vers `.env.local` pour le développement ; ne jamais
committer les valeurs réelles. Les réglages Supabase Auth existants restent
nécessaires : inscriptions désactivées et URL de callback autorisées, dont
`https://data.rewolf.studio/auth/callback`.

## Développement et vérification

Next.js 16, React 19, TypeScript et Tailwind ; IBM Plex et orange rewolf.
Les couleurs vivent dans `src/app/globals.css`. Aucune dépendance d’exécution
ajoutée pour ce tableau ; jsdom sert uniquement aux tests d’interaction.

```sh
npm ci
npm test
npm run lint
npm run build
npm run dev
```

Les tests vérifient Auth, les filtres, la séparation articles/ressources,
les zéros, le tri, le contrat de lecture et le refus avant appel métier.
Les tests DOM exercent les clics et l’historique sans requête métier ; l’intégration
de l’API History avec Next est simulée et se vérifie aussi dans le navigateur.
Ils ne déclenchent aucun courriel ni accès à la production.

Vercel conserve `dashboard` comme Root Directory. L’indexation reste interdite
et les en-têtes existants restent en place. Les anciens lecteurs et contrats
RPC dashboard restent retirés.
