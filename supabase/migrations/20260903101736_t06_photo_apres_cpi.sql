-- T-06 (mission 02/09/2026, #107) — étape 2bis/3 : photo « après » du CPI, recalculée le même jour et sur les mêmes
-- données GSC (dernier jour 30/08/2026) que la photo « avant » (phase t06_avant, 12:12 Paris). Même patron que T-05/T-09 :
-- job cron one-shot (le recalcul dépasse le délai du MCP), qui se désarme lui-même.
SELECT cron.schedule('t06-photo-apres-cpi', '22 10 * * *', $job$
SET statement_timeout = '900s';
DO $$
BEGIN
  PERFORM public.cooked_cpi_snapshot();
  PERFORM cron.unschedule('t06-photo-apres-cpi');
END $$;
$job$);
