-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Rafraichissement hebdomadaire des snapshots d'analyse mathematique.
-- Dimanche 05:10 UTC : apres la purge du bruit (04:30) et le refresh du
-- snapshot SEO (03:00), pour travailler sur des donnees deja nettoyees.
-- Seule la fenetre 28 j est automatisee (~65 s) ; la fenetre 84 j (~200 s)
-- reste a la demande :
--     SET statement_timeout='600s'; SELECT math_refresh_snapshots(84);
SELECT cron.schedule(
  'math-refresh-snapshots-weekly',
  '10 5 * * 0',
  $$SET statement_timeout='600s'; SELECT public.math_refresh_snapshots(28);$$
);
