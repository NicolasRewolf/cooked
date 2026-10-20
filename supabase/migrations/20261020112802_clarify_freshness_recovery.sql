-- 20/10/2026 : les conseils de reprise distinguent accès API et OAuth.
-- Aucun seuil, comptage, acquittement d'alerte ou événement modifié.
UPDATE public.freshness_contract
SET repair_hint =
  'Lire le diagnostic du workflow gbp-daily-ingest : GBP_QUOTA_ZERO (HTTP 429, quota 0) demande une approbation d''accès API de base du projet Google Cloud ; GBP_AUTH demande un renouvellement ADC puis du secret GBP_CREDENTIALS_B64. Ne pas confondre les deux. Après résolution, relancer une fenêtre couvrant tout le retard et vérifier les jours effectivement reçus.'
WHERE source = 'gbp_daily';

UPDATE public.freshness_contract
SET repair_hint =
  'Vérifier le workflow gsc-daily-ingest et le dernier lot gsc_ingest_batches. Relancer scripts/gsc_ingest.py all --daily après arrêt confirmé de tout ancien processus. Seul un lot complet des trois tables autorise le refresh ; vérifier ensuite cooked_refresh_after_gsc_pending().'
WHERE source IN ('gsc_path_daily','gsc_query_daily','gsc_query_page_daily');
