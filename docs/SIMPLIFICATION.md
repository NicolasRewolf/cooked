# Socle éditorial — 4 novembre 2026

La mesure éditoriale repose sur les pages publiées, les visites observées, les clics sur le numéro, les formulaires et les requêtes Google. Le dashboard reste une seule page : URL publiées, vues, entrées, contacts observés et taux sur 30, 60 ou 90 jours Paris clos, avec comparaison à la période précédente. Les requêtes Google d’une page se chargent à la demande. Les lecteurs SQL de cette extension sont déployés ; les vérifications de l’implémentation figurent dans le [changelog](../CHANGELOG.md). Les filtres distinguent Expertises, Articles hors ressources et Ressources et notions juridiques.

## Comptage

Le tableau compte chaque événement humain `pageview` avec `page_view_counts`, y compris plusieurs affichages dans une même visite. Il complète les résultats depuis l’inventaire publié pour montrer aussi les pages à zéro vue mesurée. Le lecteur reprend les règles communes d’entrée et de contact pour deux périodes disjointes, avec un seul appel à la reconstruction des visites. Il ne crée ni table, ni cache, ni cron et conserve un calcul indépendant des vues.

La règle commune de visite regroupe l’activité observable d’un même navigateur tant que les écarts ne dépassent pas 30 minutes. Les performances Web tardives ne prolongent pas une visite. L’entrée est la première page vue de cette visite, même avant le début de la période demandée.

La couture utilise la table existante `identity_stitch` sur l’historique conservé. Les identifiants de repli 32-hex sont exclus du rapprochement. Les anciens consommateurs peuvent continuer à transmettre leur argument de durée, mais la reconstruction couvre au moins l’historique nécessaire à la comparaison.

Les formulaires à identifiants explicites peuvent être rattachés à une visite observable. Un simple voisinage dans le temps ne suffit plus à leur attribuer une page. Les contacts inconnus restent comptés dans le total du site. Un clic sur le numéro ne prouve pas un appel abouti.

Dans `page_visits`, les consultations comptent une fois la même visite pour chaque page. Les entrées comptent les visites commencées dans la fenêtre. Les numérateurs téléphone, formulaire et union comptent les visites distinctes de cette cohorte ayant réalisé l’action avant la clôture. Une visite avec deux formulaires et un clic compte une seule fois dans l’union. Une absence de dénominateur produit un taux inconnu. Ces mêmes règles alimentent l’extension du tableau, avec les événements non attribués séparés pour chaque fenêtre.

Les dates Cooked sont des jours Paris clos. Pour comparer 90 jours aux 90 précédents, utiliser des fenêtres de même durée avec la même définition. Les dates Google s’arrêtent au dernier jour observé commun aux deux grains, hors lots connus incomplets et peuvent différer. L’évolution de la couverture des identifiants reste une limite historique ; les données manquantes ne sont pas reconstituées par une supposition. Les petits volumes et les couvertures partielles accompagnent les nombres et les taux.

## Inventaire

`page_taxonomy` reste le seul référentiel. Le statut de publication et sa date de vérification proviennent d’un inventaire Wix complet, indépendant du trafic. Une ancienne URL reste conservée mais est identifiée comme absente de la publication courante. Les pages statiques et catégories sont incluses.

L’inventaire complet est validé avant un appel transactionnel. Une source inaccessible ou incomplète fait échouer la synchronisation sans dépublier les lignes précédemment connues. Le mode historique de mise à jour des catégories est retiré : Python et SQL acceptent uniquement l’inventaire complet, avec observation datée, pages et comptes des sources.

Depuis le 04/11/2026, l’import est quotidien et rapproche le sitemap, les articles, les catégories et les routes publiées. Il était auparavant hebdomadaire et limité au blog. La publication d’un article n’entraîne pas une mise à jour immédiate ; le même workflow permet une synchronisation manuelle.

## Retraits

Le retrait est appliqué en production : 24 tables, huit vues et 62 anciennes routines ont été supprimées. Le catalogue vérifié en production comporte 13 tables, trois vues et 61 routines, dont les quatre fonctions de l’extension `unaccent`. Le seul nouveau lecteur est `page_query_counts` ; `page_view_counts` est étendu. Le CPI, les copies dashboard, le rapprochement CRM/SECIB et les modèles de maillage n’ont plus de stockage ou de calcul actif.

Les intégrations DataForSEO et fiche Google sont retirées de Cooked. Google Search Console conserve deux sources : les totaux par page et les requêtes par page. Un lot doit terminer ces deux imports pour être complet. Les anciens manifestes à trois sources restent des preuves historiques, sans être réécrits.

Le webhook v17 écrit uniquement l’événement de formulaire. Son identifiant de soumission évite les doublons ; une erreur d’écriture demande une reprise. Le rapprochement quotidien avec les formulaires Wix et l’inventaire des pages publiées continuent. Le code Velo des identifiants cachés et le tracker ne changent pas pour ce retrait.

La surveillance garde les sources, les échecs et les contrôles du comptage commun. Les sondes lourdes tournent une fois par nuit ; les alertes horaires lisent leur résultat. Les anciennes sondes restent dans leur historique mais ne définissent plus la santé du socle.

## Livraison et preuves

Les migrations et leurs tests décrivent le changement déployable. Les corps SQL sont régénérés depuis la production après livraison. Les constantes du catalogue suivent `contracts/doc_constants.json`.

Les migrations `20261104080927_gsc_two_grain_batches.sql` et `20261104081230_retire_unused_data_surface.sql` portent ce retrait. Le rapport privé avant/après contient les fenêtres fixes de contre-vérification, les contrôles de production et le registre de chaque objet. Les événements bruts, les deux sources GSC utiles et l’inventaire publié sont conservés. L’extension éditoriale réutilise ces sources ; son périmètre et ses limites sont décrits dans [README.md](../README.md), sans nouveau score ni intégration.
