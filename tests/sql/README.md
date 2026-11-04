# Régressions SQL

Ces scénarios exécutent les fonctions SQL dans PostgreSQL embarqué (PGlite),
en mémoire, avec des événements et volumes synthétiques. Ils ne se connectent
jamais à Supabase et ne contiennent aucune clé.

```sh
cd tests/sql
npm ci
npm test
```

Pour utiliser une installation extérieure du même moteur :

```sh
PGLITE_MODULE=/chemin/node_modules/@electric-sql/pglite/dist/index.js \
  node tests/sql/audit-integrity.test.mjs
```

Les suites couvrent les garanties conservées après la simplification :

- `audit-integrity.test.mjs` : lots GSC partiels, concurrents, échoués et
  repris, manifestes, positions pondérées, versions CPI historiques en lecture,
  clics intentionnels hors prefetch, dernières révisions CWV, jours Paris et ACL ;
- `analytics-windows.test.mjs` : jours Paris clos, passage à l’heure d’hiver,
  lecture et contacts par page, priorité des identifiants publicitaires ;
- `analytics-cleanup.test.mjs` : sélection du volume DataForSEO disponible
  sur la fenêtre de référence ;
- `canonical-visits.test.mjs` : couture d’identité, séparation des visites,
  contacts sans amont conservés, absence de page future dans un parcours et
  cohérence des lecteurs de contacts ;
- `published-inventory.test.mjs` : pages sans trafic, inventaire complet ou
  partiel, absence de dépublication déduite d’un échec et préservation du manuel ;
- `simplification.test.mjs` : arrêt ciblé des calculs et de leur fraîcheur,
  historique intact, lecteurs dashboard conservés, santé des sources actives,
  contrôles minimaux, acquittements ciblés et migration rejouable ;
- `alert-clock.test.mjs` : règles d’alerte avec horloge synthétique aux deux
  changements d’heure ;
- `click-dedup-index.test.mjs` : filtre des clics répétés inchangé avec sa
  comparaison de secondes UTC indexable ;
- `proposed-overviews.test.mjs` : bornes et agrégations des récapitulatifs
  de `docs/proposals/analytics-overviews.sql`. Cette proposition reste distincte
  des migrations appliquées.

`helpers.mjs` prépare les relations synthétiques, le schéma de suivi des lots
GSC, puis charge le miroir actuel des fonctions. Il ne réapplique pas une
ancienne définition de RPC par-dessus ce miroir. Chaque scénario installe
ensuite uniquement les migrations nécessaires à sa vérification. Les vues de
base sont simplifiées ; les tests de déduplication chargent explicitement leur
définition réelle.

`fixtures/catalog-20261020.json` contient uniquement les noms et types de
colonnes du catalogue contrôlé le 20/10/2026. Ces tests ne remplacent pas une
restauration complète des migrations, les extensions Supabase, les plans sur
les volumes réels ou la contention entre plusieurs connexions.
Le scénario de simplification fournit un double de `cron.alter_job` : il
vérifie les états et horaires demandés, pas les privilèges de l’extension pg_cron.

Pour vérifier un miroir après simplification sans modifier `supabase/rpcs.sql` :

```sh
SQL_SIMPLIFIED_EXPORT=/tmp/cooked-simplified-rpcs.sql \
  node tests/sql/simplification.test.mjs
cd tests/sql
SQL_RPC_MIRROR=/tmp/cooked-simplified-rpcs.sql npm test
```

Le fichier temporaire sert uniquement à cette vérification. Les tests du
calcul CPI et des producteurs retirés ont été supprimés ; leur historique
reste accessible par les migrations Git.
