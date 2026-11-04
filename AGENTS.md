# Agents IA — point d’entrée

**État du 04/11/2026 : socle éditorial simplifié.** Les anciens écrans, scores CPI, snapshots et intégrations annexes sont retirés. La nouvelle interface sera traitée séparément. Lire [SIMPLIFICATION.md](docs/SIMPLIFICATION.md) avant toute recette historique.

## Lire en premier

1. [CLAUDE.md](CLAUDE.md) — métier, autonomie et règles d’analyse.
2. [CONTRIBUTING.md](CONTRIBUTING.md) — Git, migrations et vérifications.
3. [docs/OPERATIONS.md](docs/OPERATIONS.md) — sources, crons et déploiement.
4. [SECURITY.md](SECURITY.md) — secrets, données et privilèges.

## Avant une analyse de production

```sql
SELECT * FROM alerts WHERE NOT acked;
SELECT * FROM refresh_pipeline_health();
SELECT * FROM latest_rpc_health();
SELECT gsc_last_data_day();
```

Lire les dates et le périmètre des résultats. Expliquer les incidents qui affectent l’analyse ; ne pas acquitter globalement les alertes. Une santé technique ponctuelle ne garantit pas la couverture de toute une période.

## Où trouver quoi

| Besoin | Source |
|---|---|
| Visites, entrées, contacts, couverture | [CONTEXT.md](CONTEXT.md), [playbook](docs/PLAYBOOK-analyse-seo.md) |
| Sources et exploitation | [OPERATIONS.md](docs/OPERATIONS.md) |
| Corps SQL courants | [supabase/rpcs.sql](supabase/rpcs.sql), miroir généré depuis la production |
| Signatures et vues | [supabase/views.sql](supabase/views.sql) |
| Historique DDL | [supabase/migrations/](supabase/migrations/) |
| Ingestion Python | [src/cooked/](src/cooked/) |
| Réception Edge | `supabase/functions/track/`, `form-webhook/` et `_shared/` |
| Tracker et attribution Forms | [wix/tracker.html](wix/tracker.html), [wix/masterpage-cooked.js](wix/masterpage-cooked.js) |
| Page de transition et authentification | [dashboard/README.md](dashboard/README.md) |
| Décisions, anciens audits et guides retirés | [docs/README.md](docs/README.md), [docs/adr/](docs/adr/) |

## Contrats conservés

`contracts/canonical_path_vectors.json` vérifie les chemins SQL/Edge/Python ; `recruitment_objet_vectors.json` l’exclusion des candidatures ; `rpc_snapshot_meta.json` le miroir SQL. `doc_constants.json` porte les compteurs du catalogue et les versions, confrontés aux sources et à la production par la CI.

Le socle compte **60 routines** publiques : 56 Cooked et quatre `unaccent`. Les anciens contrats des lecteurs dashboard ont été retirés avec leurs consommateurs.

## Versions canoniques

| Composant | Version source | Dernier déploiement vérifié |
|---|---|---|
| Tracker | `sprint43` | Custom Code du 20/10/2026, réception sprint43 vérifiée le même jour |
| Edge `track` | v32 | Supabase 42, 04/11/2026 ; réception regroupée et testée |
| Edge `form-webhook` | `v17` | Supabase 26, 04/11/2026 ; événement uniquement, réponse idempotente |

Un fichier modifié ne prouve jamais son déploiement. Vérifier le bundle Edge, le HTML public du tracker et, lorsque pertinent, les versions reçues dans les événements. Ne pas afficher de secrets ni injecter de faux contacts dans la production pour vérifier une livraison.

Cooked reste mono-site `jplouton-avocat.fr`. Le sous-site Outremer reste exclu des comptages du site principal. Ne pas généraliser le produit sans décision explicite de Nicolas.
