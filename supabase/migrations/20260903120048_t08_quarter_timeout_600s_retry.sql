-- T-08 : le trimestre (01/07→02/09) dépasse 180 s.
-- One-shot 11:55 UTC failed 57014 (exactly 180 s) dans CREATE TEMP _pvk.
-- I4 28 j = 73 s ; trimestre ≈ 2,3× → ~170 s, trop juste.
-- 600 s = même ordre que les autres refresh dashboard (assisted 590 s, snapshots 600 s).
ALTER FUNCTION public.refresh_dashboard_assisted_quarter() SET statement_timeout = '600s';
ALTER FUNCTION public.assisted_contacts_by_entry_path(date, date) SET statement_timeout = '300s';

SELECT cron.unschedule('t08-snapshot-quarter');

SELECT cron.schedule('t08-snapshot-quarter-retry', '06 12 * * *', $job$
SET statement_timeout = '600s';
DO $$
BEGIN
  PERFORM public.refresh_dashboard_assisted_quarter();
  PERFORM cron.unschedule('t08-snapshot-quarter-retry');
END $$;
$job$);
