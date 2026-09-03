-- T-09 (mission 02/09/2026, #110) — étape 2bis/3 : « après » du CPI, calculé le MÊME jour et sur les MÊMES données GSC
-- (dernier jour 30/08/2026) que la photo « avant » (cpi_pre_restatement_20260903, phase t09_avant, copie de cpi_daily 11:0x Paris).
--
-- cooked_cpi_snapshot() réécrit cpi_daily du jour (ON CONFLICT (day, path) DO UPDATE) avec la définition T-09 de
-- cooked_page_index : seul le terme conversion zv change (conversion_journeys(p_days, gsc_last_data_day()) au lieu de
-- now()-28 j). cooked_refresh_after_gsc() repassera après l'ingestion GSC (~13:00 Paris) et remettra la ligne à jour avec la
-- donnée fraîche — comportement quotidien normal. Un seul passage à 09:37 UTC (11:37 Paris), auto-désarmé ; SET séparé du DO
-- (patron cooked-refresh-after-gsc).
SELECT cron.schedule('t09-photo-apres-cpi', '37 9 * * *', $job$
SET statement_timeout = '900s';
DO $$
BEGIN
  PERFORM public.cooked_cpi_snapshot();
  PERFORM cron.unschedule('t09-photo-apres-cpi');
END $$;
$job$);
