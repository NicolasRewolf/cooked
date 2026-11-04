# Analyser les pages et les requêtes

Socle du 4 novembre 2026. Les décisions éditoriales restent celles du cabinet ; Cooked fournit les observations. Les anciennes recettes CPI et maillage sont dans l'historique Git. Voir [SIMPLIFICATION.md](SIMPLIFICATION.md) pour la définition des visites et des contacts.

## Lire les données disponibles

```sql
SELECT * FROM refresh_pipeline_health();
SELECT * FROM latest_rpc_health();
SELECT gsc_last_data_day();
```

Une alerte ancienne non acquittée ne prouve pas une panne actuelle. Vérifier sa date et la source concernée. Un trou de collecte signifie une mesure incomplète, pas zéro visite.

## Pages publiées, visites et contacts

Le référentiel est `page_taxonomy WHERE is_published`. Son horodatage `publication_checked_at` atteste la publication au dernier contrôle, pas la date initiale de publication. Il contient aussi les pages sans trafic et conserve les anciennes pages avec `is_published=false`.

```sql
-- 90 jours Paris clos, indépendants de l'heure d'exécution.
SELECT * FROM page_visits(paris_today()-90, paris_today()-1);
-- Les 90 jours précédents, avec exactement la même définition.
SELECT * FROM page_visits(paris_today()-180, paris_today()-91);
```

Les lignes `row_kind='page'` sont les statistiques observées. Faire une jointure gauche du référentiel publié vers ces lignes pour afficher toutes les pages. La ligne `coverage` précise le nombre de jours avec au moins une page vue et les contacts non attribuables. Une absence de ligne ne devient zéro que lorsque la couverture de la période est établie ; cette couverture journalière ne prouve pas une disponibilité à chaque minute.

`visits` compte les visites ayant consulté la page ; `entries` celles commencées dessus. `phone_visits`, `form_visits` et `contact_visits` concernent ces mêmes entrées et les actions observées avant la clôture. L'union déduplique une visite ayant réalisé plusieurs actions. Présenter le nombre avec le taux. Un clic téléphone ne prouve pas un appel abouti ; une soumission ne prouve pas un prospect unique.

`cooked_visit_events` fournit le détail nécessaire aux contrôles. `conversion_journeys` et `form_submits_attributed` gardent un grain événement : ne pas les additionner comme s'il s'agissait de visites distinctes. Les anciennes lectures du dashboard et `content_performance` conservent leurs contrats historiques ; elles ne définissent pas le nouveau tableau.

## Requêtes Google d'une page

Les clics et impressions complets par page viennent de `gsc_path_daily`. Les requêtes révélées viennent de `gsc_query_page_daily`. Google masque une partie des requêtes : leur somme n'est donc pas le total de la page et ne permet pas d'attribuer individuellement une soumission à une requête.

Pour chaque requête, comparer deux fenêtres de même durée se terminant au dernier jour GSC complet. Additionner les clics et impressions ; calculer la position moyenne en pondérant par les impressions. Ne pas faire la moyenne simple des moyennes quotidiennes. Une requête absente d'une fenêtre peut être masquée ou sans observation ; ne pas en déduire une disparition certaine.

La date limite Google peut précéder celle du tracker. Pour une lecture croisée, borner les deux sources au même dernier jour complet. Pour une lecture séparée, conserver leurs dates affichées.

Une baisse de clics avec une position stable invite à regarder la demande et la page de résultats. Une baisse de position invite à examiner le contenu et ses concurrents. Ces constats orientent l'examen de l'article sans établir automatiquement la cause ni décider de sa suppression.

## Limites de comparaison

- La même définition de visite s'applique à tout l'historique conservé, avec une coupure après plus de 30 minutes sans activité observable.
- La disponibilité des identifiants de formulaire a évolué. Comparer les taux avec la part attribuable de chaque période ; les liaisons manquantes ne sont pas inventées.
- Les faibles volumes rendent les taux instables. Garder les nombres visibles et examiner l'intérêt du sujet pour le cabinet.
- Les filtres bots/bruit peuvent reclasser des événements historiques. Conserver la date d'extraction lors d'une comparaison avant/après.
- Les scores CPI, snapshots SEO/dashboard et modèles de maillage sont figés depuis le 4 novembre. DataForSEO est manuel. Leurs anciennes valeurs ne décrivent pas la période courante.
