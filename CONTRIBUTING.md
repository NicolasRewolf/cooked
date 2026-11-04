# Contribuer à Cooked

Cooked reste mono-site `jplouton-avocat.fr`. Lire [CLAUDE.md](CLAUDE.md), [CONTEXT.md](CONTEXT.md), [OPERATIONS.md](docs/OPERATIONS.md) et [SECURITY.md](SECURITY.md) avant de modifier le socle.

## Workflow

Branche `codex/<sujet>` depuis `main`, changements ciblés, vérifications locales, puis PR et CI. Les restrictions de la mission sur les commits, publications et déploiements priment. Préserver les changements des autres intervenants.

Toute modification SQL livrée a sa migration exacte, avec timestamp réel, dans `supabase/migrations/` et dans la même PR. Ne pas faire de correction de données manuelle non tracée. Régénérer les miroirs SQL et `contracts/rpc_snapshot_meta.json` depuis la production après livraison ; ne pas modifier le miroir pour faire passer une garde.

L’autonomie technique ne couvre pas une nouvelle décision produit, une suppression irrécupérable de données ou un coût significatif sans autorisation. Ne pas redemander une autorisation déjà donnée dans la session. Le backup externe reste décliné depuis le 02/07/2026 ; ne pas le reproposer avant juin 2027 sans demande nouvelle.

## Vérifier

```bash
make deps
make check
```

Python 3.12 en CI, Node 22 et Deno 2. `make deps` installe le paquet avec ses outils de développement ; le module maths n’est plus une dépendance. `make check` n’a pas besoin de secrets de production.

Les tests couvrent les imports GSC à deux grains, l’inventaire Wix, le rapprochement agrégé des formulaires, le stockage, les scénarios SQL PGlite, le tracker, les helpers Edge et le dashboard : authentification, lecteurs éditoriaux, filtres et détail Google à la demande. `page_view_counts` conserve les vues et ajoute les cohortes de contacts sur deux périodes, contre-vérifiées avec `page_visits` ; `page_query_counts` vérifie couverture commune, requêtes perdues et positions pondérées. Les anciens lecteurs et contrats abandonnés restent retirés.

```bash
# Réception tracker : HTTP, lots, filtrage, horodatage et résultat de l’écriture.
deno test supabase/functions/_shared/track_delivery_test.ts
# Réception formulaire : insertion, doublon, erreur, reprise et validation HTTP.
deno test supabase/functions/_shared/form_delivery_test.ts
# Écart dépôt/production, avec le rôle de lecture seule déjà configuré.
make check-prod
```

`make check-prod` s’arrête au premier échec. Il ne doit pas être lancé avec des identifiants imprimés dans la commande ou les logs. PGlite vérifie les régressions sur données synthétiques ; il ne prouve pas les plans, volumes, extensions ou privilèges de production.

Les gardes SQL comparent le diff à sa référence Git ; une référence absente doit être récupérée, jamais contournée. Les workflows dans `.github/workflows/` sont la source d’exécution CI ; le Makefile en reprend les suites locales.

## Zones du dépôt

| Zone | Rôle |
|---|---|
| `supabase/migrations/` | Historique de déploiement du schéma |
| `supabase/rpcs.sql`, `views.sql` | Miroirs SQL lisibles, générés depuis la production |
| `supabase/functions/` | Réception tracker et formulaires, helpers Deno |
| `wix/` | Tracker, proxy Velo et champs d’attribution Forms |
| `src/cooked/`, `scripts/` | GSC, inventaire Wix, rapprochement Forms et contrôles |
| `dashboard/` | Tableau privé des URL, vues, entrées, contacts, comparaison et requêtes Google à la demande |
| `tests/` | Régressions Python, tracker et PostgreSQL embarqué |
| `contracts/` | Vecteurs partagés et métadonnées contrôlées |
| `docs/` | Guides du socle et décisions communes (ADR) |

Les contrats actifs portent notamment sur les chemins canoniques (`canonical_path_vectors.json`), les candidatures (`recruitment_objet_vectors.json`), le miroir SQL (`rpc_snapshot_meta.json`) et les constantes du catalogue (`doc_constants.json`). Une suppression fonctionnelle retire aussi ses consommateurs, contrôles et dépendances devenus inutiles.

## CI utile

| Workflow | Vérification |
|---|---|
| `sql-contracts` | Scénarios SQL, bornes Paris, cohérence des migrations et miroir RPC |
| `canonical-path-contract` | Chemins identiques en SQL, Edge et Python |
| `python-ingest-contract` | GSC, stockage et contrôles Wix |
| `edge-shared-helpers` / `tracker-test` | Réception et événements navigateur |
| `dashboard-contract` | Session, allowlist, magic-link, redirections, lecteurs éditoriaux, filtres et détail Google |
| `prod-drift` / `rpcs-regenerate` | Catalogue, migrations, accès et miroir SQL |
| `docs-check` | Documents requis, versions, compteurs, liens locaux et index |

Les ingestions quotidiennes GSC/Wix et le rapprochement Forms sont détaillés dans [OPERATIONS.md](docs/OPERATIONS.md). Aucun import CPI, DFS, GBP, maths ou SECIB ne fait partie du workflow actif.

## Documentation

Un changement de comportement met à jour son guide actif et [CHANGELOG.md](CHANGELOG.md). Les constantes de catalogue suivent `contracts/doc_constants.json`. Les guides retirés et les anciens audits restent dans [l’historique Git](https://github.com/NicolasRewolf/cooked/tree/b6aa6370b9041763814bc0b1253182ece2694772/docs). Le dépôt courant ne conserve pas de recettes pour des fonctions abandonnées.

Les issues et PRD sont suivis sur GitHub dans ce dépôt. Lire le ticket et ses commentaires avant de le traiter (`gh issue view <numéro> --comments`). Les modèles utilisent `needs-triage` ; ne pas inventer de labels ni ouvrir une nouvelle issue sans nécessité liée à la tâche. Pour les descriptions et commentaires multilignes, écrire un fichier puis utiliser `--body-file`. Aucun secret ni contenu personnel dans les commits, PR ou captures.
