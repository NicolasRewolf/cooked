@AGENTS.md
@README.md

## Périmètre courant

1. Cette application affiche uniquement une page de transition authentifiée.
   La nouvelle interface est une étape séparée ; ne pas ajouter de métriques.
2. Aucune table ni RPC métier n’est lue. Aucun client admin ni clé service n’est
   nécessaire. Supabase reste utilisé uniquement pour Auth.
3. Conserver magic-link, logout, allowlist fermée par défaut, validation serveur
   de la session et garde contre les redirections externes.
4. Les anciennes routes redirigent vers la transition. Ne pas restaurer les
   écrans, contrats ou bibliothèques de métriques retirés.
5. Les couleurs sont des tokens de `src/app/globals.css`. Conserver IBM Plex,
   orange rewolf, angles vifs et thème clair.
