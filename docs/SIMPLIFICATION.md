# Socle éditorial — 4 novembre 2026

La mesure éditoriale repose sur les pages publiées, les visites observées, les clics sur le numéro, les formulaires et les requêtes Google. Le tableau de bord sera repris séparément.

## Comptage

La règle commune de visite regroupe l’activité observable d’un même navigateur tant que les écarts ne dépassent pas 30 minutes. Les performances Web tardives ne prolongent pas une visite. L’entrée est la première page vue de cette visite, même avant le début de la période demandée.

La couture utilise la table existante `identity_stitch` sur l’historique conservé. Les identifiants de repli 32-hex sont exclus du rapprochement. Les anciens consommateurs peuvent continuer à transmettre leur argument de durée, mais la reconstruction couvre au moins l’historique nécessaire à la comparaison.

Les formulaires à identifiants explicites peuvent être rattachés à une visite observable. Un simple voisinage dans le temps ne suffit plus à leur attribuer une page. Les contacts inconnus restent comptés dans le total du site. Un clic sur le numéro ne prouve pas un appel abouti.

Pour chaque page, les consultations comptent une fois la même visite. Les entrées comptent les visites commencées dans la fenêtre. Les numérateurs téléphone, formulaire et union comptent les visites distinctes de cette cohorte ayant réalisé l’action avant la clôture. Une visite avec deux formulaires et un clic compte une seule fois dans l’union. Une absence de dénominateur produit un taux inconnu.

Les dates sont des jours Paris clos. Pour comparer 90 jours aux 90 précédents, utiliser des fenêtres de même durée avec la même définition. L’évolution de la couverture des identifiants reste une limite historique ; les données manquantes ne sont pas reconstituées par une supposition.

## Inventaire

`page_taxonomy` reste le seul référentiel. Le statut de publication et sa date de vérification proviennent d’un inventaire Wix complet, indépendant du trafic. Une ancienne URL reste conservée mais est identifiée comme absente de la publication courante. Les pages statiques et catégories sont incluses.

L’inventaire complet est validé avant un appel transactionnel. Une source inaccessible ou incomplète fait échouer la synchronisation sans dépublier les lignes précédemment connues. Le mode historique de mise à jour des catégories n’est pas une preuve de publication.

## Retraits

Les recalculs périodiques du CPI, des anciennes pages dashboard, du snapshot SEO et des modèles de maillage sont arrêtés. Leurs tables historiques restent disponibles avec leurs dates. Les procédures de production et les alertes exclusivement associées sont retirées lorsque leurs lecteurs actifs n’en dépendent plus. Les lectures du dashboard gardent leur contrat pendant la transition, avec un avis global de suspension des anciens indicateurs.

DataForSEO reste interrogeable à la demande. Sa synchronisation périodique cesse ; ses anciennes valeurs ne deviennent pas des zéros. Google Search Console, la fiche Google, le rapprochement de formulaires et l’inventaire Wix continuent à être alimentés.

La surveillance garde les sources, les échecs et les contrôles du comptage commun. Les sondes lourdes tournent une fois par nuit ; les alertes horaires lisent leur résultat. Les anciennes sondes restent dans leur historique mais ne définissent plus la santé du socle.

## Livraison et preuves

Les migrations et leurs tests décrivent le changement déployable. Les corps SQL sont régénérés depuis la production après livraison. Les constantes du catalogue suivent `contracts/doc_constants.json`.

Le rapport privé avant/après contient les fenêtres fixes de contre-vérification, les contrôles de production et le registre de chaque objet. Les sources d’origine et les tables historiques ne sont pas supprimées. La refonte fonctionnelle du dashboard reste une étape ultérieure.
