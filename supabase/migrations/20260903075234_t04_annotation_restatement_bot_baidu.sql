-- T-04 (mission 02/09/2026, issue #105) — annotation du restatement (règle §2.10 de la mission).
-- Appliquée en prod le 03/09/2026 à 09:55 Paris, après vérification de la migration 20260903075011.
INSERT INTO public.annotations (day, kind, label, paths)
VALUES (
  DATE '2026-09-03',
  'autre',
  'Restatement T-04 (03/09/2026) : retrait d''un robot (user_agent « pc », referrer m.baidu.com, présent depuis le 07/05/2026) et de SEBot-WA d''events_human — 7 338 sessions masquées via noise_sessions, Edge track v28 les refuse à l''ingestion. Sur 28 j : pageviews 13 823 → 11 914 (−13,8 %), sessions 11 110 → 9 201 (−17,2 %), canal referral 1 995 → 120 pageviews ; classify_channel renvoie désormais ''spam'' pour ces referrers. Couverture page_exit 75,6 % → 89,1 % (desktop 94,6 %, mobile 86,5 %). Correction de mesure (retrait d''un robot), pas une baisse de trafic. RPC publiées, dashboard et CPI inchangés (déjà filtrés).',
  NULL
);
