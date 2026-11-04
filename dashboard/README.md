# Cooked — pages et contacts observés

Une page liste toutes les URL actuellement publiées sur `jplouton-avocat.fr`,
y compris celles sans mesure. Elle réunit les vues, les entrées, les visites avec
contact et leur taux ; chaque mesure garde la valeur de la période précédente.

## Lecture

- Périodes de 30, 60 ou 90 jours clos Paris ; 90 jours par défaut. Les bornes des
  deux périodes consécutives sont affichées.
- Toutes les pages ; expertises (hubs et pages d’expertise) ; articles hors ressources ;
  articles « Ressources et notions juridiques ». Articles et ressources sont disjoints.
- Vues décroissantes puis chemin pour départager les égalités.
- Une vue est un affichage après filtrage des bots, pas une visite unique. Les entrées
  sont les visites commencées sur la page pendant la période. Les contacts et le taux
  portent sur ces entrées, avec les actions observées avant la clôture de la période.
- Le détail téléphone/formulaires compte des visites et peut se recouvrir : on ne
  les additionne pas pour obtenir les visites avec contact. Un clic téléphone ne
  prouve pas un appel abouti. Sans entrée, le taux reste inconnu (`—`).

L’inventaire et les comptes viennent de `page_view_counts(p_days)`, lu côté serveur
à l’ouverture et au changement de période. Le type de page filtre immédiatement
les données déjà reçues, sans nouvelle lecture. Les filtres restent dans l’URL
partageable ; précédent et suivant rétablissent le filtre.
Pendant une navigation de période, un message de chargement apparaît et les
autres liens de période attendent sa fin, pour éviter les calculs concurrents.

Les écarts sont absolus, ou en points pour les taux : aucune division par une
base nulle. Si une période est partielle, les nombres observés restent visibles
avec la couverture, et les écarts ne sont pas affichés. Un inventaire absent ou
confirmé il y a plus de deux jours calendaires Paris produit une indication courte.
Les contacts non attribués sont contextualisés séparément au grain événement,
sur tout le site ; ils ne s’ajoutent pas aux visites du tableau. Un échec de lecture
ne devient jamais une liste vide ou des zéros.

Le bouton « Requêtes Google » ouvre une seule page à la fois et charge
`page_query_counts(p_path, p_days)` à la demande. Les clics et positions sont comparés
sur deux périodes aux dates de la source Google, affichées séparément des dates
Cooked. Une position plus basse est meilleure ; une position absente reste inconnue.
Google masque certaines requêtes : zéro signifie aucun clic rapporté, et aucun
lien individuel requête → contact n’est déduit. Le changement de page, de filtre
ou de période annule la lecture navigateur devenue inutile ; cette annulation
ne prouve pas l’arrêt du calcul SQL déjà commencé.

Aucun score, graphique, recherche ou pagination n’est ajouté. Les anciennes adresses
`/expertises`, `/seo`, `/lab` et `/article/*` redirigent temporairement vers `/`.

## Accès

Supabase Auth reste utilisé pour le magic-link et les cookies de session.
`proxy.ts` vérifie l’adresse dans l’allowlist ; les deux lecteurs serveur appellent
`requireUser()` avant toute lecture métier. Une allowlist vide refuse l’accès.
La demande de magic-link conserve `shouldCreateUser: false` ; le callback limite
la destination à une URL interne. La déconnexion utilise POST, puis redirection
303 vers la connexion.

La clé publique ne lit aucune donnée métier. La clé technique est chargée
uniquement par le module `server-only`, après authentification. Elle n’est
nécessaire ni au navigateur ni au chargement de la configuration Auth.
`GET /api/page-queries?path=…&days=…` valide les paramètres, réutilise ce lecteur
et renvoie des agrégats sans cache. Une erreur de source produit un message
générique, jamais un message DB brut ni un faux zéro.
Un échec RPC laisse uniquement son nom, le SQLSTATE valide éventuel et le statut
HTTP dans le diagnostic serveur, sans paramètres, contenu de réponse ni erreur brute.

| Variable | Usage |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Projet Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clé publique du flux Auth |
| `DASHBOARD_ALLOWED_EMAILS` | Adresses autorisées, séparées par des virgules |
| `SUPABASE_SECRET_KEY` | Lecture agrégée, serveur uniquement |

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

Les tests vérifient Auth, les filtres locaux, les zéros, le tri, la cohérence des
contacts/taux, les deux périodes, les couvertures et les contrats Google.
Ils exercent la route protégée, l’ouverture à la demande, les annulations et
réponses tardives, les erreurs et les reprises. L’intégration de l’API History avec
Next est simulée en test DOM et se vérifie aussi dans le navigateur.
Les tests ne déclenchent aucun courriel ni accès à la production.

Vercel conserve `dashboard` comme Root Directory. L’indexation reste interdite
et les en-têtes existants restent en place. Les anciens lecteurs et contrats
RPC dashboard restent retirés.
