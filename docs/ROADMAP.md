# Roadmap Cooked — reste à faire courant

État des lieux au **03/09/2026 soir** (mission précision/fiabilité/hygiène du 02/09/2026 :
Phases 0-2 livrées le 02/09, Phase 3 en cours — T-01, T-03→T-13 faits ; suite dans
[mission-2026-09-02/02-plan.md](mission-2026-09-02/02-plan.md) et les issues `mission-2026-09-02`).
Court par construction : une ligne de contexte par item. Les décisions produit restent chez
**Nicolas** — ce fichier liste, il ne décide pas. Historique :
[ROADMAP-sprint38-handoff.md](ROADMAP-sprint38-handoff.md) (archive) et [HISTORY-sprints.md](HISTORY-sprints.md).

## Mission 02/09/2026 — tickets encore ouverts

| Ticket | Quoi | Qui | Contexte (une ligne) |
|---|---|---|---|
| [T-02](https://github.com/NicolasRewolf/cooked/issues/103) | Relecture des journaux + rotation de la clé publishable | **Nicolas** | Décision : l'exposition `anon` (h-01) a été fermée le 02/09 (T-01) ; la clé legacy `anon` reste à désactiver dans la console Supabase, les 24 h de logs ont été relues. |
| [T-15](https://github.com/NicolasRewolf/cooked/issues/116) | `page_taxonomy` : synchro Wix Blog automatisée | **fait le 04/09** — reste : secret `WIX_API_KEY` (**Nicolas**) | Script + RPC + cron hebdo livrés ; sans le secret, le workflow sort sans écrire et la synchro se rejoue à la main (`--dry-run` puis sans). |
| [T-16](https://github.com/NicolasRewolf/cooked/issues/117) | Pont SECIB : garde-fous avant le premier chiffre | **fait le 04/09** — reste : 2 doublons `crm_prospects` à nettoyer (**décision Nicolas**) | `pont_couverture`, statuts `non_rapprochable`/`dossier_ulterieur`, env prod seul, rangs personne/dossier, vecteurs de normalisation partagés, tests des 3 scripts d'ingestion. |
| [T-17](https://github.com/NicolasRewolf/cooked/issues/118) | Tracker : filet CI, tests des correctifs, CLS explicite, debug off | **code fait le 04/09** — reste : **collage Wix par Nicolas** (`tracker.min.html` sprint42 + `masterpage-cooked.js`), puis bump `expected_tracker_version` ; loader first-party = décision §7.1 | 14 820 / 15 000 chars ; cliquet CI (aucun ajout net > 14 500) ; 6 assertions jsdom ajoutées (sprint41/40/35/42) ; alerte `contact_sans_amont`. |
| [T-18](https://github.com/NicolasRewolf/cooked/issues/119) | Edge / formulaires : `page_source` partout, alertes routées, gate `x-cooked-key` fail-fast | agent + champs cachés Wix Nicolas | 8,7 % des `form_submit` (180 j) sans `page_source` → invisibles par page ; l'Edge est fail-open si `COOKED_INGEST_KEY` est vide. |
| [T-19](https://github.com/NicolasRewolf/cooked/issues/120) | Budget de complexité : dépréciations, bloat, vestiges, `country`, `url`/`title` | agent, **DROP = validation Nicolas** | Décisions déjà prises (tri du 03/09) : amputer `events.country` ; cesser `title`, tronquer `url` aux paramètres de campagne, rétention 400 j (CNIL 13 mois à confirmer). Photo `cpi_pre_restatement_20260903` à supprimer. |
| [T-20](https://github.com/NicolasRewolf/cooked/issues/121) | Restatements passés : annotations manquantes + version du CPI dans `cpi_daily` | agent | Les restatements du 02/07 et du 25/07 n'ont pas de ligne `annotations` ; ceux du 03/09 (T-05/06/08/09) en ont. |

## Chantiers hors mission

| # | Quoi | Échéance | Contexte (une ligne) |
|---|---|---|---|
| 1 | Harmonisation UI des deux compteurs contacts (fiche article) | — | L'issue #45 a été fermée le 30/08 sans action (constat g-05) : la fiche n'affiche que les « assistés », le tableau les « sur la page ». Commentaire posé sur #45 le 03/09 ; à rouvrir si Nicolas le décide. |
| 3 | Re-test diagnostic CPI 56 j | échéance **05/08/2026 dépassée** — à replanifier | Suite de la validation J+28 du 11/07 (VALIDÉE). Depuis, trois restatements CPI le 03/09 (fenêtres, momentum, contacts) : refaire la grille sur `cpi_daily` ≥ 04/09. |
| 4 | ~~Issue #19 — biais de taille CPI~~ | fermée le 30/08/2026 | Limite connue, documentée dans `cpi-cooked-page-index.md` ; pas de v2.3 (décision 18/06 et 11/07). |
| 5 | Cron GBP : accès API après la migration GCP + client OAuth dédié | **action Nicolas** — verdict Google ≈ 10-15/09 | `gbp_daily` s'arrête au **20/08/2026** (13 j au 03/09) : le projet Google a migré vers `rewolf-507310` le 01/09, l'approbation Business Profile est redemandée (n° 2-9425000042353). L'alerte `gbp_daily_stale` (registre : warn > 7 j, critical > 14 j) sonne depuis le 28/08 — échec attendu jusqu'au verdict, plan B « projet plouton » avant le 19/09. |
| 6 | Ingestion mensuelle `gbp_search_keywords` | go de Nicolas | Sonde du 05/08 : fiche quasi invisible sur l'indemnisation (≤75 impressions/12 mois vs ~2 100 pénal) ; lag ≈ 1 mois → cadence mensuelle. Conditionné au #5. |
| 7 | Renommage de la fiche Google Business | décision Julien/Nicolas | Seul signal encore 100 % pénal : le nom. Ne pas toucher la catégorie principale. Annotation à poser le jour J. |
| 8 | Boucle 3 — Google Ads | à lancer (hors mission) | MCP connecté (01/07) mais sans developer token en session : coût par campagne → coût par contact macro. ~71 % du trafic expertise est paid. |
| 9 | SECIB — passage en prod | **devis non signé au 03/09** (valable ~17/08, à renégocier) | 49 dossiers `env = 'test'`, dernière synchro 10/08 ; fondations livrées (PR #93). Après signature : T-16 d'abord, puis swap credentials, `secib_ingest.py ingest --secib-env prod`, cron GitHub Actions. |
| 10 | RGPD du pont SECIB | **en retard** (annoncé « cette semaine » le 10/08) | `crm_prospects` = **858** lignes au 03/09 (796 le 10/08), dernier ajout 03/09 13:28. Textes prêts : [rgpd-pont-secib.md](rgpd-pont-secib.md) — relecture Julien, publication, 3 arbitrages (art. 28, durée de conservation, champ « objet »). |
| 11 | Pont téléphone (3CX ↔ SECIB ↔ Cooked) | chantier Easylia en cours | Le jour où le journal d'appels est accessible : matcher avec `secib_dossiers`, corréler avec `cta_phone_click` (les appels ≈ 50 % du contact que les formulaires ne voient pas). |
| 12 | Chute de ~40 % des clics GSC depuis fin juillet | à instruire | 2 155 → ~1 350 clics/semaine depuis le 27/07, portée par les ressources à impressions constantes (CTR 2,14 → 1,14 %) : la SERP bouge (AI Overview ?), pas le classement. Lecture du 03/09 dans l'onglet Lab. |
