# Changelog

## [2026-11-04] — Hygiène du dépôt

- Retrait des 65 archives de documentation et de trois guides agents redondants ; leur contenu reste disponible dans l’historique Git. Index, décisions communes et guides du socle actualisés.
- Contrôle documentaire complété dans le script existant : guides requis, versions canoniques obligatoires, liens locaux et chemins d’index réels. Tests de liens cassés, documents absents et versions manquantes.
- Conventions Python et liens des modèles GitHub corrigés.
- Exceptions CPI retirées des alertes par la migration `20261104100422_remove_retired_alert_exceptions` : trois corps modifiés, les 57 autres identiques, droits inchangés.
- Edge track v32 / Supabase 43 et formulaire v17 / Supabase 27 livrés à 11:05 Paris ; douze fichiers distants conformes aux sources. Vingt événements réels sprint43 reçus après livraison ; gardes GET à 405.
- Tracker sprint44 livré dans Wix à 11:06 Paris (révision 35), paramètres inchangés ; HTML public sans cache identique au minifié de 14 480 caractères. Le cache racine servait encore sprint43 à 11:07 ; 37 événements réels sprint44 ont été reçus entre 11:06:55 et 11:08:52 Paris.

## [2026-11-04] — Inventaire Wix complet uniquement

- Retrait du format historique de catégories, de ses deux convertisseurs Python et de sa fixture. `--from-file` et la RPC existante conservent uniquement l’objet complet `{pages, observed_at, counts}`.
- Contrôles de complétude, transactions, conservation des anciennes pages, dry-run et rejeu sans réécriture conservés. Tests d’arrivée d’un article sans trafic, pagination au-delà de 100 articles et lecture des sous-sitemaps.
- Rapprochement réel à 10:43 Paris : 491 pages publiées dans Cooked concordent avec Wix (445 articles, 19 catégories, 27 pages statiques) ; les 489 URL du sitemap et les cinq articles les plus récents sont présents. Deux pages hors sitemap sont vérifiées sur le site.
- L’import quotidien avec sitemap remplace depuis ce matin l’ancien passage hebdomadaire limité au blog ; aucune nouvelle planification n’est ajoutée ici.
- Migration `20261104094735_complete_wix_inventory_only` appliquée ; données du référentiel, autres routines et droits inchangés par cette migration. Miroir régénéré depuis la production.

## [2026-11-04] — Règles de fraîcheur réutilisées

- Le résumé du pipeline lit les seuils Google dans `freshness_contract` et réutilise la règle de lot GSC incomplet ; les valeurs et règles de comptage sont conservées.
- Aucun nouvel objet SQL : mêmes cinq contrats et 60 routines. La portée du résumé, ses colonnes, ses arrondis et ses délais propres restent inchangés. Un contrat GSC absent ou désactivé est explicitement signalé.
- Consignes de reprise GSC et formulaires mises à jour pour les flux conservés. Tests SQL des seuils, limites, arrondis et périmètres.
- Migration `20261104092851_reuse_freshness_rules` appliquée ; registre inchangé hors consignes, autres routines identiques et état du pipeline sain avant/après. Miroir régénéré depuis la production.

## [2026-11-04] — Réception tracker regroupée

- `track/index.ts` se limite au branchement de l’environnement et de Supabase ; `_shared/track_delivery.ts` rassemble le traitement HTTP jusqu’au résultat de l’écriture.
- Règles de collecte et comptages inchangés : mêmes événements, identifiants, dates, filtrage, rejets agrégés et réponses. Suppression du branchement CORS redondant.
- 17 tests de requêtes complètes, intégrés à `make check` et à la CI ; vérification des types du point d’entrée.
- Edge v32 déployée en version Supabase 42 le 04/11/2026 ; bundle distant conforme aux sept fichiers locaux.

## [2026-11-04] — Simplification du socle éditorial

- Comptage commun des visites, entrées et actions, avec rattachements inconnus conservés.
- Inventaire des pages publiées indépendant du trafic dans le référentiel existant. Écriture vérifiée via l’API et GitHub ; seules les observations modifiées sont réécrites.
- Arrêt des recalculs automatiques des anciens indicateurs et retrait de leurs procédures inutilisées.
- Ménage final appliqué : 24 tables, huit vues et 62 routines retirées ; restent 13 tables, trois vues et 60 routines. Les index attachés disparaissent avec les tables : 62 → 27.
- Webhook v17 : une seule écriture analytique, dédoublonnage par soumission et reprise sur échec conservés. CRM/SECIB, CPI, DataForSEO, fiche Google, copies dashboard et modèles avancés retirés du fonctionnement actif.
- Import GSC réduit aux pages et aux requêtes par page ; manifestes historiques conservés. Six crons et cinq sources de fraîcheur utiles.
- Les anciennes pages dashboard sont retirées au profit d’une transition avec authentification, en attendant la refonte séparée.
- Contrôles du socle et rapport avant/après. Détails et sémantique dans [SIMPLIFICATION.md](docs/SIMPLIFICATION.md).

Les jalons antérieurs et les fonctions retirées restent dans [le changelog historique](https://github.com/NicolasRewolf/cooked/blob/b6aa6370b9041763814bc0b1253182ece2694772/CHANGELOG.md).
