# Régressions SQL du 20/10/2026

`audit-integrity.test.mjs` exécute les véritables fonctions SQL dans PostgreSQL
embarqué (PGlite), en mémoire, avec des événements et volumes **synthétiques**.
Il ne se connecte jamais à Supabase et ne contient aucune clé.

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

Le scénario charge le miroir des fonctions du dépôt, puis la migration dont le
nom se termine par `_audit_data_integrity_and_ingest_completion.sql`.
Le timestamp peut donc être aligné sur celui effectivement appliqué.

Les assertions couvrent :

- lot GSC partiel, concurrent, échoué, reprise et manifestes invalides ;
- progression exacte du lot après une chaîne de refresh partielle ou complète ;
- positions pondérées, médianes sans referrer, trois identifiants Ads ;
- conservation des clics intentionnels dans le filtre prefetch ;
- dernière révision CWV par document dans les quatre consommateurs ;
- badge macro, contribution de booking au score préservée et versions CPI ;
- exclusion des bookings avant et après la fenêtre canonique, même si leur
  session possède une pageview dans cette fenêtre ;
- comptages de formulaires par jour Paris, recrutement inclus ;
- dépréciation du funnel ancien, ACL et maintien de l’inlining.

`fixtures/catalog-20261020.json` contient uniquement les **noms et types de
colonnes** du catalogue contrôlé le 20/10/2026, sans contenu de table. Les relations
y sont reconstituées avec les contraintes nécessaires au scénario. Ce n’est pas
un substitut à une restauration intégrale des migrations, aux extensions
Supabase, à un EXPLAIN sur les volumes de production ou à un test de contention
entre plusieurs connexions.

`fixtures/cpi-before-20261020.sql` conserve le calcul audité pour prouver que la
réparation du badge seule ne change aucun composant numérique du score, et pour
reproduire la fuite des bookings hors fenêtre avant sa correction.

La compatibilité avec un miroir déjà régénéré peut être vérifiée sans modifier
`supabase/rpcs.sql` : lancer une première fois avec
`SQL_RPC_EXPORT=/tmp/cooked-post-audit-mirror.sql`, puis relancer avec
`SQL_RPC_MIRROR=/tmp/cooked-post-audit-mirror.sql`. La seconde passe reconstruit
une base vide, charge les fonctions du miroir futur, puis applique la migration.
