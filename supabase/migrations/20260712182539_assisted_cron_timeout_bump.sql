-- Le refresher contacts assistés v2 (couture + segmentation de visites)
-- traite 2 fenêtres × build _cooked_ev : ~250 s mesurés le 12/07/2026.
-- 300 s devenait juste → aligné sur le cron expertises (590 s).
SELECT cron.schedule(
  'refresh-dashboard-assisted',
  '16 4 * * *',
  $$SET statement_timeout='590s'; SELECT public.refresh_dashboard_resources_assisted();$$
);
