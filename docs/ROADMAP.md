# Roadmap Cooked — reste à faire courant

État des lieux au **12/07/2026 au soir** (post-couture d'identité, tracker
sprint41 déployé). Court par construction : une ligne de contexte par item.
Les décisions produit restent chez **Nicolas** — ce fichier liste, il ne
décide pas. Historique : [ROADMAP-sprint38-handoff.md](ROADMAP-sprint38-handoff.md)
(archive) et [HISTORY-sprints.md](HISTORY-sprints.md).

| # | Quoi | Échéance | Contexte (une ligne) |
|---|---|---|---|
| 1 | Harmonisation UI des deux compteurs contacts | — | Le tableau affiche les contacts « sur la page », la fiche les « assistés » — afficher les deux, étiquetés, pour lever l'ambiguïté. |
| 2 | Vérif J+1 tracker sprint41 | 13/07/2026 | Taux de sessions coupées attendu ≈ 0 (vs ~22 % avant les ids auto-réparants). |
| 3 | Drop de la table d'audit `cpi_pre_restatement_20260712` | ~19/07/2026 | Table de comparaison avant/après du restatement CPI du 12/07/2026, à supprimer une fois le recul pris. |
| 4 | Premiers `cpi_movers` post-restatement fiables | ~19/07/2026 | La dérivée ~7 j du CPI a besoin de 7 jours de snapshots post-restatement pour redevenir lisible. |
| 5 | Re-test diagnostic CPI 56 j | 05/08/2026 | Suite de la validation J+28 du 11/07/2026 (VALIDÉE — « score de priorisation ») sur fenêtre doublée. |
| 6 | Issue GitHub [#19](https://github.com/NicolasRewolf/cooked/issues/19) — biais de taille CPI | ouverte | Limite connue actée lors de la validation J+28 ; à traiter ou documenter, pas urgent. |
