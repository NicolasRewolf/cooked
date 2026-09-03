-- T-03 (mission 02/09/2026, issue #104) — annotation du restatement (règle §2.10 de la mission).
-- Appliquée en prod le 03/09/2026 à 07:43 Paris (version 20260903054331).
INSERT INTO public.annotations (day, kind, label, paths)
VALUES (
  DATE '2026-09-03',
  'autre',
  'Restatement T-03 (03/09/2026) : taux de rebond ×100 dans behavior_pages_for_period (÷100 de trop depuis le 26/07), cooked_bounce_rate unifié en pourcentage 0-100 (gsc_page_performance, pages_overview_unified chemin lent), sessions à referrer spam retirées du dénominateur du rebond dans seo_pages_overview (/honoraires-rendez-vous : 21,7 % → 32,1 %). Correction d''unité et de mesure, pas un changement de comportement des visiteurs. Les tableaux du dashboard (snapshot) ne bougent pas.',
  NULL
);
