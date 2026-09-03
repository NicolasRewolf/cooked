-- T-05 (mission 02/09/2026, issue #106) — annotation du restatement (règle §2.10 de la mission).
-- Appliquée en prod le 03/09/2026 à 11:06 Paris, après la migration 20260903085351 et la comparaison photo « avant »
-- (cpi_pre_restatement_20260903, 10:22) / « après » (cpi_daily du 03/09, 10:58) sur les mêmes données GSC (dernier jour 30/08).
INSERT INTO public.annotations (day, kind, label, paths)
VALUES (
  DATE '2026-09-03',
  'autre',
  'Restatement T-05 (03/09/2026) : alignement des fenêtres « 28 jours » sur les données GSC réellement livrées (28 jours clos à gsc_last_data_day(), lag Google J-3/J-4). gsc_pages_overview : la fenêtre brute paris_today()-27 ne contenait que 24 jours de données → clics 28 j 4 474 → 5 358 (+19,8 % ce jour, +12 à +20 % selon le lag). CPI : capture, courbe CTR, momentum (c1 = c0 = 28 j) et côté Cooked (entrées, lectures, page_exit, LCP) sur les mêmes jours Paris, plus de borne sur l''heure du run ; conversion (conversion_journeys) encore sur l''horloge → T-09. Photo avant/après du même jour : 175 pages → 175 (169 communes, 6 entrées/6 sorties toutes grade C au seuil n_org 5), delta CPI moyen −1,3 pt (médiane |Δ| 3), 46 pages fiables S/A/B : delta moyen −1,3, médiane |Δ| 2, 1 seul mover ≥ 15 pts (assurance-perte-exploitation 21→41, conversion), 2 changements de grade (1 B→C, 1 C→B), clics perdus 1 138 → 1 284 (+13 %, 28 jours GSC au lieu de 24), CPI pondéré trafic 48,5 → 45,6. Les écarts de momentum entre 03/09 et les jours précédents reflètent la fenêtre, pas les pages. Correction de mesure (alignement des fenêtres), pas un changement de trafic ni de santé des pages. Un « avant/après 03/09 » dans cpi_daily n''est PAS un decay.',
  NULL
);
