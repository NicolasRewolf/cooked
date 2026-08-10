# Roadmap Cooked — reste à faire courant

État des lieux au **10/08/2026** (post-pivot SECIB : fondations du pont
prospects ↔ dossiers livrées, PII en clair confinée, rangement post-audit).
Court par construction : une ligne de contexte par item.
Les décisions produit restent chez **Nicolas** — ce fichier liste, il ne
décide pas. Historique : [ROADMAP-sprint38-handoff.md](ROADMAP-sprint38-handoff.md)
(archive) et [HISTORY-sprints.md](HISTORY-sprints.md).

| # | Quoi | Échéance | Contexte (une ligne) |
|---|---|---|---|
| 1 | Harmonisation UI des deux compteurs contacts | — | Le tableau affiche les contacts « sur la page », la fiche les « assistés » — afficher les deux, étiquetés, pour lever l'ambiguïté. |
| 2 | ~~Drop des tables d'audit `cpi_pre_restatement_*`~~ | **fait 10/08/2026** | Supprimées par la migration `rangement_post_pivot_secib` (qui désarme aussi le VACUUM FULL annuel du 26/07). |
| 3 | Re-test diagnostic CPI 56 j | 05/08/2026 | Suite de la validation J+28 du 11/07/2026 (VALIDÉE — « score de priorisation ») sur fenêtre doublée. Pas encore lancé. |
| 4 | Issue GitHub [#19](https://github.com/NicolasRewolf/cooked/issues/19) — biais de taille CPI | ouverte | Limite connue actée lors de la validation J+28 ; à traiter ou documenter, pas urgent. |
| 5 | Cron GBP : reauth ADC + client OAuth dédié | **action Nicolas** | L'alerte `gbp_gap` existe depuis le 10/08/2026 (warn > 7 j, critical > 14 j → ntfy). Mais le cron est RETOMBÉ en panne reauth du 06 au 10/08 (5 échecs) : re-login gcloud (les DEUX scopes) + re-pousser `GBP_CREDENTIALS_B64`. Parade durable : client OAuth dédié (voie 2 de `scripts/gbp_ingest.py`). |
| 6 | Ingestion mensuelle `gbp_search_keywords` | go de Nicolas | Sonde du 05/08/2026 : la fiche est quasi invisible sur l'indemnisation (≤75 impressions/12 mois vs ~2 100 pénal) alors que la demande locale existe ; lag de publication ≈ 1 mois → cadence mensuelle, pas quotidienne. |
| 7 | Renommage de la fiche Google Business | décision Julien/Nicolas | Catégories, services et description sont déjà bons (lecture API 05/08/2026) : le seul signal encore 100 % pénal est le **nom** (« Avocats en Droit Pénal à Bordeaux »). Ne pas toucher la catégorie principale. Annotation à poser le jour du changement. |
| 8 | Boucle 3 — Google Ads | à lancer | MCP connecté depuis le 01/07/2026 : coût par campagne → coût par contact macro, puis coût par dossier signé quand SECIB sera branché. ~71 % du trafic des pages expertise est paid. |
| 9 | SECIB — passage en prod | signature devis (~17/08) | Étape 0 **validée le 10/08/2026** sur le bac à sable (token, dossiers, matières, ExportFinancier) ; fondations du pont livrées (PR #93). Après signature du devis SECIB+ (120 €HT/mois) : swap credentials, `secib_ingest.py ingest --secib-env prod`, cron GitHub Actions (patron gsc/gbp), cartographie matières réelles → `page_taxonomy`. Question ouverte à Septeo : lecture API des `InfoComplementaire` (écriture seule dans le swagger 8.6.0) + demande d'accès d'évaluation temporaire envoyée le 10/08. |
| 10 | RGPD du pont SECIB | **cette semaine (Nicolas)** | La capture PII en clair est ACTIVE depuis le 10/08/2026. **Textes prêts à publier, registre et arbitrages : [rgpd-pont-secib.md](rgpd-pont-secib.md)** — reste à faire relire par Julien, publier, et trancher 3 points (contrat de sous-traitance REWOLF art. 28, durée de conservation, champ « objet de la demande »). |
| 11 | Pont téléphone (3CX ↔ SECIB ↔ Cooked) | chantier Easylia en cours | Easylia travaille sur l'API 3CX et son intégration SECIB (10/08/2026). Côté Cooked : le jour où le journal d'appels (numéro + horodatage) est accessible, matcher avec `secib_dossiers` et corréler avec `cta_phone_click` — les appels sont le ~50 % du contact que le pont formulaires ne voit pas. |
