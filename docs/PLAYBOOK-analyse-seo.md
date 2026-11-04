# Analyser les pages et les requêtes

Référence du **04/11/2026**. Cooked fournit les observations ; Nicolas décide de l’intérêt du sujet et de l’action éditoriale. Lire [CONTEXT.md](../CONTEXT.md) pour les grains et [SIMPLIFICATION.md](SIMPLIFICATION.md) pour le périmètre.

## Vérifier la période disponible

```sql
SELECT * FROM alerts WHERE NOT acked;
SELECT * FROM refresh_pipeline_health();
SELECT * FROM latest_rpc_health();
SELECT gsc_last_data_day();
```

Lire les dates et l’état du dernier lot `gsc_ingest_batches`. Une alerte ancienne ne prouve pas une panne actuelle. Une santé correcte aujourd’hui ne démontre pas la couverture des mois précédents. Un trou de collecte signifie une mesure partielle, pas zéro visite.

## Pages publiées, visites et contacts

Le référentiel est `page_taxonomy WHERE is_published`. `publication_checked_at` date le dernier inventaire complet, pas la publication initiale. Les pages sans trafic y figurent aussi ; les anciennes URLs restent connues avec un statut non publié.

```sql
-- 90 jours Paris clos.
SELECT * FROM page_visits(paris_today()-90, paris_today()-1);
-- Les 90 jours précédents, même définition et durée.
SELECT * FROM page_visits(paris_today()-180, paris_today()-91);
```

Joindre à gauche le référentiel publié aux lignes `row_kind='page'`. La ligne `coverage` indique les jours avec au moins une page vue et les événements téléphone/formulaire non attribués. Cette couverture journalière ne prouve pas une disponibilité à chaque minute. N’afficher zéro que si la fenêtre permet cette lecture ; sinon indiquer inconnu ou partiel et éviter un delta trompeur.

`visits` compte les visites ayant consulté la page ; `entries` celles commencées dessus. `phone_visits`, `form_visits` et `contact_visits` portent sur ces mêmes entrées et les actions observées avant la clôture. L’union déduplique une visite qui a fait plusieurs actions. Présenter nombres et taux ensemble ; sans entrée, le taux est inconnu.

Un clic téléphone ne prouve pas un appel abouti ; une soumission ne prouve pas un prospect unique. Les candidatures sont exclues. Les contacts sans amont certain restent comptés séparément, sans entrée inventée. `cooked_visit_events` fournit le détail événementiel nécessaire à une contre-vérification ; ne pas additionner ses événements comme des visites distinctes.

## Requêtes Google d’une page

Les totaux de page viennent de `gsc_path_daily`, les requêtes révélées de `gsc_query_page_daily`. Google masque une partie des requêtes : leur somme ne reconstitue pas tous les clics et ne permet pas d’attribuer individuellement une soumission à une requête.

Comparer deux fenêtres de même durée, bornées au dernier jour Google complet. Additionner les clics et impressions ; calculer la position par `sum(position * impressions) / sum(impressions)`, avec dénominateur nul traité comme inconnu. Ne pas faire une moyenne simple des moyennes quotidiennes.

Une requête absente d’une fenêtre peut être masquée ou sans observation. Une baisse de clics à position stable invite à regarder la demande et la page de résultats ; une baisse de position invite à examiner la page et ses concurrents. Ces indices n’établissent pas seuls une cause.

Les dates Google conservent leur horloge source. Le dernier jour disponible peut précéder celui du tracker. Pour un recoupement, aligner les bornes calendaires et signaler la différence d’horloge ; pour deux lectures séparées, afficher les dates de chaque source. Il n’existe pas d’égalité attendue entre clics GSC et visites Cooked.

## Décider sans surinterpréter

Contre-vérifier tout chiffre soutenant une recommandation, par décomposition ou source comparable. Si cela n’a pas été possible, le dire. Garder les nombres à côté des taux : une niche avec peu de visites peut convertir fortement, tandis qu’un article large peut amener davantage de contacts en volume.

La disponibilité des identifiants Forms et les filtres ont évolué. Examiner la part attribuable et la couverture des deux périodes ; conserver la date d’extraction. Les liaisons historiques manquantes ne sont pas reconstituées par supposition. La décision de supprimer ou réécrire un article repose aussi sur son intérêt pour le cabinet, pas sur un score automatique.
