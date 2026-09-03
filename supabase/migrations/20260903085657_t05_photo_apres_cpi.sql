-- T-05 (mission 02/09/2026, #106) — étape 2bis/3 : « après » du CPI, calculé le MÊME jour et sur les MÊMES données GSC
-- (dernier jour 30/08/2026) que la photo « avant » (cpi_pre_restatement_20260903, 10:22 Paris).
--
-- cooked_cpi_snapshot() écrit cpi_daily du jour (ON CONFLICT (day, path) DO UPDATE) avec la définition T-05 de
-- cooked_page_index. En temps normal c'est cooked_refresh_after_gsc() qui l'appelle après l'ingestion GSC (~13:00 Paris) ;
-- il repassera aujourd'hui et remettra à jour la ligne avec la donnée fraîche — comportement quotidien normal.
-- Un seul passage à 08:58 UTC (10:58 Paris), auto-désarmé ; SET séparé du DO (patron cooked-refresh-after-gsc).
SELECT cron.schedule('t05-photo-apres-cpi', '58 8 * * *', $job$
SET statement_timeout = '900s';
DO $$
BEGIN
  PERFORM public.cooked_cpi_snapshot();
  PERFORM cron.unschedule('t05-photo-apres-cpi');
END $$;
$job$);
