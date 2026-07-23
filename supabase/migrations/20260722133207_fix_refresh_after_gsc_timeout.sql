-- Le SET LOCAL à l'intérieur de cooked_refresh_after_gsc() ne rallonge PAS
-- le timer du statement cron déjà lancé (piège documenté OPERATIONS.md).
-- Séquence complète ≈ 13 min moy. / ~27 min max → budget 40 min.
-- Sans ce SET, le job timeout avant même la fin du 1er refresh (~3 min)
-- → dashboard figé depuis le 20/07 soir, CPI depuis le 19/07.

SELECT cron.unschedule('cooked-refresh-after-gsc');

SELECT cron.schedule(
  'cooked-refresh-after-gsc',
  '0 8-20 * * *',
  $cmd$SET statement_timeout='2400s'; SELECT public.cooked_refresh_after_gsc();$cmd$
);
