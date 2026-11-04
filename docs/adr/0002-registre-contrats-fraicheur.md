# ADR-0002 — Un contrat de fraîcheur par source

- **Statut** : accepté le 23/08/2026 ; portée actualisée le 04/11/2026.
- **Concerne** : `freshness_contract`, règles d’alerte et résumé du pipeline.

## Décision

Les seuils de retard et consignes de reprise d’une source sont définis dans
`freshness_contract`. `alert_rule_freshness()` lit les contrats actifs avec
l’horloge `paris_today()` et signale retard, trous ou échec d’évaluation.
Les données événementielles sont surveillées même lorsqu’aucun contact récent
n’a été reçu ; leur silence ne prouve pas à lui seul une panne.

`cooked_alerts_refresh()` découvre les règles `alert_rule_*` sans argument dans
le catalogue et isole leurs erreurs. La déduplication par type et sévérité,
l’escalade et l’effet de l’acquittement restent des mécanismes communs. Ne pas
réécrire ces décisions dans chaque collecteur ni acquitter globalement les alertes.

## Pourquoi

Des seuils recopiés dans plusieurs fonctions avaient divergé. Le contrat rend
explicites les sources surveillées et leurs tolérances, sans ajouter un cadre
générique aux imports GSC et Wix qui ont des contraintes différentes.

Le registre contient du SQL exécuté avec des privilèges techniques : ses accès
restent restreints et ses changements sont tracés par migration.

## Application du 04/11/2026

`refresh_pipeline_health()` réutilise les seuils du contrat actif
`gsc_path_daily` et la détection de lot interrompu d’`alert_rule_gsc_ingest_missed()`.
Il conserve sa portée réception / pages GSC / lots, ses délais, arrondis et colonnes.
Il n’est pas une synthèse de toutes les sources ou des alertes ouvertes. Un contrat
GSC absent ou désactivé est critique, sans seuil de secours caché.

Les règles et seuils courants sont dans le [miroir SQL](../../supabase/rpcs.sql) ;
les sources et gestes de reprise sont décrits dans [OPERATIONS.md](../OPERATIONS.md).
Le contexte de création et les intégrations depuis retirées restent dans
[l’ADR historique](https://github.com/NicolasRewolf/cooked/blob/b6aa6370b9041763814bc0b1253182ece2694772/docs/adr/0002-registre-contrats-fraicheur.md).
