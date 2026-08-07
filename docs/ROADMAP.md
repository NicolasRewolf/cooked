# Roadmap Cooked — reste à faire courant

État des lieux au **05/08/2026** (post-réparation du cron GBP, sonde des
search keywords de la fiche, ticket API SECIB envoyé). Court par
construction : une ligne de contexte par item.
Les décisions produit restent chez **Nicolas** — ce fichier liste, il ne
décide pas. Historique : [ROADMAP-sprint38-handoff.md](ROADMAP-sprint38-handoff.md)
(archive) et [HISTORY-sprints.md](HISTORY-sprints.md).

| # | Quoi | Échéance | Contexte (une ligne) |
|---|---|---|---|
| 1 | Harmonisation UI des deux compteurs contacts | — | Le tableau affiche les contacts « sur la page », la fiche les « assistés » — afficher les deux, étiquetés, pour lever l'ambiguïté. |
| 2 | Drop des tables d'audit `cpi_pre_restatement_20260712` et `_20260727` | en retard | Photos avant/après des restatements CPI du 12/07 (couture d'identité) et du 27/07 (`classify_channel` v3 — GMB) ; échéances ~19/07 et ~03/08 dépassées, le recul est pris → vérifier leur présence en prod et les dropper par une migration nommée. |
| 3 | Re-test diagnostic CPI 56 j | 05/08/2026 | Suite de la validation J+28 du 11/07/2026 (VALIDÉE — « score de priorisation ») sur fenêtre doublée. Pas encore lancé. |
| 4 | Issue GitHub [#19](https://github.com/NicolasRewolf/cooked/issues/19) — biais de taille CPI | ouverte | Limite connue actée lors de la validation J+28 ; à traiter ou documenter, pas urgent. |
| 5 | Alerte de fraîcheur `gbp_gap` | dès que possible | Le cron GBP a échoué **en silence** du 30/07 au 04/08/2026 (reauth Google sur le credential ADC) — aucune alerte n'a sonné, contrairement à `gsc_gap`. Parade durable de la reauth : client OAuth dédié (voie 2 de `scripts/gbp_ingest.py`). |
| 6 | Ingestion mensuelle `gbp_search_keywords` | go de Nicolas | Sonde du 05/08/2026 : la fiche est quasi invisible sur l'indemnisation (≤75 impressions/12 mois vs ~2 100 pénal) alors que la demande locale existe ; lag de publication ≈ 1 mois → cadence mensuelle, pas quotidienne. |
| 7 | Renommage de la fiche Google Business | décision Julien/Nicolas | Catégories, services et description sont déjà bons (lecture API 05/08/2026) : le seul signal encore 100 % pénal est le **nom** (« Avocats en Droit Pénal à Bordeaux »). Ne pas toucher la catégorie principale. Annotation à poser le jour du changement. |
| 8 | Boucle 3 — Google Ads | à lancer | MCP connecté depuis le 01/07/2026 : coût par campagne → coût par contact macro, puis coût par dossier signé quand SECIB sera branché. ~71 % du trafic des pages expertise est paid. |
| 9 | SECIB — étape 0 | à réception du token | Ticket d'accès API envoyé à Septeo le 05/08/2026. Dès réception : un `GetDossierById` de test pour vérifier si les champs personnalisés (`InfoComplementaire`) remontent, et cartographier les libellés matière → thèmes `page_taxonomy`. |
