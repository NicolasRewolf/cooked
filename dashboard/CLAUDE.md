@AGENTS.md
@README.md

## Périmètre courant

1. Une page authentifiée liste toutes les URL publiées, y compris celles à zéro vue.
   Une seule métrique : les affichages de page filtrés, pas les visites uniques.
2. Les périodes sont 30, 60 ou 90 jours clos Paris, 90 par défaut. Filtres :
   toutes les pages ; expertises (hubs compris) ; articles hors ressources ;
   articles catégorisés « Ressources et notions juridiques ». Les deux derniers
   ensembles sont disjoints ; aucun score, conversion, graphique ou détail ajouté.
3. La seule lecture métier appelle `page_view_counts(p_days)` depuis un module
   `server-only`, après validation de session et allowlist. La clé serveur n’est
   jamais transmise au navigateur. Pas d’API intermédiaire ni cache ajouté.
   Le tableau client filtre les types localement et synchronise l’URL par l’API
   History native ; seul un changement de période déclenche une nouvelle lecture.
   Conserver les liens de période sans prefetch et l’historique précédent/suivant.
4. Conserver magic-link, logout, allowlist fermée par défaut, validation serveur
   de la session et garde contre les redirections externes. Les anciennes routes
   continuent de rediriger vers `/`.
5. Les couleurs sont des tokens de `src/app/globals.css`. Conserver IBM Plex,
   orange rewolf, angles vifs, thème clair et tableau compact.
