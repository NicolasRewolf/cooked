-- T-08 : premier remplissage du snapshot trimestre (one-shot).
SELECT cron.schedule('t08-snapshot-quarter', '55 11 * * *', $job$
SET statement_timeout = '180s';
DO $$
BEGIN
  PERFORM public.refresh_dashboard_assisted_quarter();
  PERFORM cron.unschedule('t08-snapshot-quarter');
END $$;
$job$);
