# Régressions SQL

Ces scénarios exécutent les fonctions SQL dans PostgreSQL embarqué (PGlite),
en mémoire, avec des événements et volumes synthétiques. Ils ne se connectent
jamais à Supabase et ne contiennent aucune donnée de visiteurs ni clé.

```sh
cd tests/sql
npm ci
npm test
```

Les suites couvrent le socle conservé :

- `gsc-batch.test.mjs` : deux grains GSC, lots partiels, concurrence, échecs,
  reprise et conservation des anciens manifestes ;
- `audit-integrity.test.mjs` : positions pondérées, couverture des requêtes,
  filtres réels site/bots/bruit, rapprochement des formulaires par jour Paris ;
- `analytics-windows.test.mjs` : jours Paris clos, heure d’hiver, visites et
  contacts par page, priorité des identifiants publicitaires ;
- `canonical-visits.test.mjs` : identité, inactivité, entrées, contacts sans
  amont, parcours bornés et taux cohérents ;
- `published-inventory.test.mjs` : pages sans trafic, mises à jour atomiques,
  refus des inventaires incomplets/périmés, rejeu sans réécriture ;
- `source-health.test.mjs` : sources actives, six contrôles du socle,
  lots GSC interrompus et interruption de réception ;
- `alert-clock.test.mjs` : règles d’alerte aux deux changements d’heure ;
- `click-dedup-index.test.mjs` : déduplication des clics, valeurs absentes,
  chrome/bruit et seconde UTC répétée lors du changement d’heure.

`helpers.mjs` charge le schéma synthétique cible de **13 tables et 3 vues**,
puis les fonctions de `supabase/rpcs.sql`. Les vues sont leurs vraies définitions,
pas des substituts simplifiés. La fixture conserve les types, contraintes et
RLS relevés dans le catalogue du 04/11/2026 ; ses valeurs par défaut sont limitées
aux scénarios testés. Les droits effectifs des rôles client/service sont repris
pour les routines présentes.

Pour valider un miroir candidat sans changer celui du dépôt :

```sh
SQL_RPC_MIRROR=/chemin/miroir-candidat.sql npm test
```

La CI utilise uniquement le schéma cible et le miroir du dépôt ; elle ne dépend
pas de `/tmp`. Le test ponctuel de migration et son ancien schéma synthétique
sont conservés dans les preuves privées du ménage, hors du code à maintenir.

Ces tests ne remplacent pas une vérification des extensions Supabase,
des plans sur les volumes réels ni de la contention entre plusieurs connexions.
