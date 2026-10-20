# Roadmap Cooked — reste à faire courant

Mise à jour technique du **20/10/2026** : corrections et preuves de livraison
dans [RELIABILITY.md](RELIABILITY.md). Les tableaux de mission ci-dessous
conservent leur contexte de septembre ; une échéance passée n'atteste pas sa réalisation.

État de référence au **04/09/2026 matin** (mission précision/fiabilité/hygiène du 02/09/2026 :
**Phases 0-4 livrées** — 20 tickets agent faits ; bilan [mission-2026-09-02/02-apres.md](mission-2026-09-02/02-apres.md),
passation [03-passation.md](mission-2026-09-02/03-passation.md) ; restes Nicolas ci-dessous).
Court par construction : une ligne de contexte par item. Les décisions produit restent chez
**Nicolas** — ce fichier liste, il ne décide pas. Historique :
[ROADMAP-sprint38-handoff.md](ROADMAP-sprint38-handoff.md) (archive) et [HISTORY-sprints.md](HISTORY-sprints.md).

## Vérifications de livraison du 20/10/2026

- Appliquer et contrôler la migration SQL, régénérer les miroirs/contrats,
  obtenir un lot GSC complet puis les snapshots attendus.
- Déployer les Edge et le dashboard ; publier le tracker après le SQL,
  vérifier le code servi et les versions réellement reçues.
- Rétablir GBP par réauthentification et ingestion avec rattrapage ; exiger
  la fraîcheur et la continuité, pas seulement la réussite du login.
- Activer le rapprochement Wix quotidien avec permission Forms et vérifier
  un run réel. Un écart ne déclenche pas de réimport automatique.
- Conserver le garde-fou SECIB production jusqu'à validation d'une
  synchronisation complète des dossiers, modifications et facturation.
- Traiter la source du lien vers le chemin 404 signalé par la taxonomie ;
  ne pas inventer une catégorie pour acquitter l'alerte.
- Faire valider les conditions de traitement des identifiants pseudonymes,
  la couture CRM, les durées et les textes juridiques ; aucune publication
  n'est déduite de la mise à jour documentaire.

## Mission 02/09/2026 — tickets encore ouverts

| Ticket | Quoi | Qui | Contexte (une ligne) |
|---|---|---|---|
| [T-02](https://github.com/NicolasRewolf/cooked/issues/103) | Relecture des journaux + rotation de la clé publishable | **parké 04/09** — ne pas cliquer « Disable JWT-based API keys » | Vercel = `sb_publishable`, Wix = `sb_secret` ; le bouton tuerait aussi `service_role` JWT encore utilisé ailleurs. Exposition `anon` déjà fermée (T-01). |
| — | **Restes Nicolas des tickets livrés** (liste complète : `03-passation.md`) | **Nicolas** | ~~tracker / masterPage / http-functions / champs / WIX_API_KEY / CNIL / doublons / annotations / ntfy~~ ; T-02 parké ; lire la vérif CPI J+1 du 04/09 puis DROP `cpi_pre_restatement_20260903` ; overloads `days_back` après le 01/10 ; GBP ~10-15/09. |
| [T-15](https://github.com/NicolasRewolf/cooked/issues/116) | `page_taxonomy` : synchro Wix Blog automatisée | **fait le 04/09** — secret `WIX_API_KEY` posé (dry-run 33854781065 : 434 posts, 0 insert) | Script + RPC + cron hebdo livrés ; prochain run réel lundi 05:00 UTC. |
| [T-16](https://github.com/NicolasRewolf/cooked/issues/117) | Pont SECIB : garde-fous avant le premier chiffre | **fait le 04/09** — doublons `crm_prospects` nettoyés (décision Nicolas 04/09 : 2e envoi retiré) | `pont_couverture`, statuts `non_rapprochable`/`dossier_ulterieur`, env prod seul, rangs personne/dossier, vecteurs de normalisation partagés, tests des 3 scripts d'ingestion. |
| [T-17](https://github.com/NicolasRewolf/cooked/issues/118) | Tracker : filet CI, tests des correctifs, CLS explicite, debug off | **fait le 04/09** — sprint42 collé à 10:12 Paris, `expected_tracker_version` basculée (`20260904081320`) ; loader first-party = décision §7.1 (pas lancé) | 14 820 / 15 000 chars ; cliquet CI (aucun ajout net > 14 500) ; 6 assertions jsdom ajoutées (sprint41/40/35/42) ; alerte `contact_sans_amont`. |
| [T-18](https://github.com/NicolasRewolf/cooked/issues/119) | Edge / formulaires : `page_source` partout, alertes routées, gate fail-fast | **fait le 04/09** — Edge v29/v15 + collages Wix publiés (masterPage, http-functions, champs Divorce + dossier) | Alerte `form_fields_missing` reste jusqu'au prochain vrai envoi (historique 28 j sans `page_source`) ; `track` v29 fail-fast ; `form-webhook` v15. |
| [T-19](https://github.com/NicolasRewolf/cooked/issues/120) | Budget de complexité : dépréciations, bloat, vestiges, `country`, `url`/`title` | **fait le 04/09** — reste : DROP `cpi_pre_restatement_20260903` (après lecture de la vérif J+1 du 04/09), DROP des 2 overloads `days_back` après le 01/10/2026. **CNIL 13 mois posée** (`purge_old_events`, 04/09). | `country` amputée (5 vues recréées), supprimés : `page_reads` ×2 et la vue `gsc_path_metrics_28d`, `url`/`title` réduits à l'Edge (v30), `identity_stitch` réindexée 124 → 10 MB, autovacuum GSC resserré, drops agrégés. |
| [T-20](https://github.com/NicolasRewolf/cooked/issues/121) | Restatements passés : annotations manquantes + version du CPI dans `cpi_daily` | **fait le 04/09** — 3 libellés validés par Nicolas tels quels ; premier cron le 01/10/2026 | `cpi_daily.cpi_version` (2.2.0 → 2.2.5), `cooked_config.cpi_definition_version`, 3 annotations (02/07, 25/07, 31/08), check de calibration mensuel `cpi_calibration_check()` + alerte `cpi_calibration` (04/09 : R² 0,913). Invariant I10. |

## Chantiers hors mission

| # | Quoi | Échéance | Contexte (une ligne) |
|---|---|---|---|
| 1 | Harmonisation UI des deux compteurs contacts (fiche article) | — | L'issue #45 a été fermée le 30/08 sans action (constat g-05) : la fiche n'affiche que les « assistés », le tableau les « sur la page ». Commentaire posé sur #45 le 03/09 ; à rouvrir si Nicolas le décide. |
| 3 | Re-test diagnostic CPI sur une définition homogène | Replanifier selon la première série 2.2.6 vérifiée | L'ancienne échéance du 29/10 supposait 56 jours homogènes en 2.2.5 ; ne pas franchir la nouvelle rupture de définition dans le même diagnostic. |
| 4 | ~~Issue #19 — biais de taille CPI~~ | fermée le 30/08/2026 | Limite connue, documentée dans `cpi-cooked-page-index.md` ; pas de v2.3 (décision 18/06 et 11/07). |
| 5 | Cron GBP : réauthentifier, reprendre et vérifier la continuité | Reprise à confirmer | Le run contrôlé le 20/10 demande une réauthentification Google. L'ancienne attente d'approbation de septembre ne suffit plus à expliquer l'échec courant ; ne pas classer la panne comme normale. |
| 6 | Ingestion mensuelle `gbp_search_keywords` | go de Nicolas | Sonde du 05/08 : fiche quasi invisible sur l'indemnisation (≤75 impressions/12 mois vs ~2 100 pénal) ; lag ≈ 1 mois → cadence mensuelle. Conditionné au #5. |
| 7 | Renommage de la fiche Google Business | décision Julien/Nicolas | Seul signal encore 100 % pénal : le nom. Ne pas toucher la catégorie principale. Annotation à poser le jour J. |
| 8 | Boucle 3 — Google Ads | à lancer (hors mission) | MCP connecté (01/07) mais sans developer token en session : coût par campagne → coût par contact macro. ~71 % du trafic expertise est paid. |
| 9 | SECIB — passage en prod | Bloqué techniquement avant validation de la synchronisation complète | `--secib-env prod` refuse l'ingestion avant credentials/API. Une signature ou un changement de credentials ne suffit pas : couvrir les dossiers anciens modifiés et valider le périmètre financier. |
| 10 | RGPD du pont SECIB | **en retard** (annoncé « cette semaine » le 10/08) | `crm_prospects` = **858** lignes au 03/09 (796 le 10/08), dernier ajout 03/09 13:28. Textes prêts : [rgpd-pont-secib.md](rgpd-pont-secib.md) — relecture Julien, publication, 3 arbitrages (art. 28, durée de conservation, champ « objet »). |
| 11 | Pont téléphone (3CX ↔ SECIB ↔ Cooked) | chantier Easylia en cours | Le jour où le journal d'appels est accessible : matcher avec `secib_dossiers`, corréler avec `cta_phone_click` (les appels ≈ 50 % du contact que les formulaires ne voient pas). |
| 12 | Chute de ~40 % des clics GSC depuis fin juillet | à instruire | 2 155 → ~1 350 clics/semaine depuis le 27/07, portée par les ressources à impressions constantes (CTR 2,14 → 1,14 %) : la SERP bouge (AI Overview ?), pas le classement. Lecture du 03/09 dans l'onglet Lab. |
| 13 | Parité sémantique `views.sql` ↔ prod | petit | 11/11 noms mais fichier reformaté à la main, aucune gate ne le compare (zone i). Faire générer `views.sql` par le workflow `rpcs-regenerate`. |
| 14 | 3 copies littérales `m.baidu.com` dans des corps RPC | petit | `rpcs.sql:2426`, `:4640`, `:4846` filtrent la même chaîne que `cooked_is_spam_referrer()` — aucun chiffre faux aujourd'hui, aucune gate demain. |
| 15 | `CLAUDE.md` à 1 252 lignes | hygiène | +140 lignes pendant la mission (3 règles absolues). Déplacer les blocs « Sprint 37/38/39 » vers `HISTORY-sprints.md`. |
| 16 | Gate ACL tables (`has_table_privilege('anon', t, 'TRUNCATE') = false`) | petit | La re-mesure du 04/09 a trouvé 22 tables avec ALL pour `anon` (default privileges) que ni `alert_rule_exposure()` ni prod-drift ne voyaient — corrigé `20260904073237`, à garder sous gate. |
