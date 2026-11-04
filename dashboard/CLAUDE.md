@AGENTS.md
@README.md

## Périmètre courant

1. Une page authentifiée liste toutes les URL publiées : vues, entrées, visites
   avec contact et taux, avec comparaison à la période précédente. Le détail
   téléphone/formulaires reste dépliable ; les deux nombres peuvent se recouvrir.
2. Les périodes sont 30, 60 ou 90 jours clos Paris, 90 par défaut. Filtres :
   toutes les pages ; expertises (hubs compris) ; articles hors ressources ;
   articles catégorisés « Ressources et notions juridiques ». Les deux derniers
   ensembles sont disjoints. Aucun score, graphique ou classement supplémentaire.
3. Le tableau lit `page_view_counts(p_days)` depuis un module `server-only`, après
   validation de session et allowlist. La clé serveur reste privée, sans cache.
   Les types filtrent localement et synchronisent l’URL par l’API History native ;
   seul un changement de période relit les métriques. Conserver les liens sans
   prefetch et l’historique précédent/suivant.
4. Google se déplie pour une seule page à la fois, via `/api/page-queries` et le
   lecteur protégé `page_query_counts(p_path, p_days)`. Aucun appel anticipé pour
   toutes les URL. Annuler les requêtes navigateur devenues inutiles et ignorer
   leurs réponses tardives. Conserver les dates source et les limites Google.
5. Sans entrée, le taux est inconnu. Les écarts sont absolus, ou en points pour le
   taux ; aucune évolution si l’une des couvertures est partielle. Les non-attribués
   restent hors tableau, au grain événement. Un échec reste une erreur.
6. Conserver magic-link, logout, allowlist fermée par défaut, validation serveur
   de la session et garde contre les redirections externes. Les anciennes routes
   continuent de rediriger vers `/`.
7. Les couleurs sont des tokens de `src/app/globals.css`. Conserver IBM Plex,
   orange rewolf, angles vifs, thème clair et tableau compact.
