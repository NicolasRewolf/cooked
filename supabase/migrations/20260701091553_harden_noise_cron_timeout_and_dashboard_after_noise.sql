-- Fiabilise le filtre bruit/bots + ordonne le refresh dashboard APRÈS le bruit.
--
-- (1) jobid 4 `refresh_noise_filters_hourly` échouait par intermittence sur
--     `canceling statement due to statement timeout` à 120 s (statement_timeout
--     du rôle cron). La proconfig `SET statement_timeout TO '300s'` des fonctions
--     n'arme PAS le timer : PostgreSQL fige statement_timeout au DÉBUT du statement,
--     un SET en cours de statement ne le rallonge pas. Seul un `SET` posé comme
--     statement séparé AVANT l'appel fonctionne (cf. cron dashboard jobid 12,
--     migration 20260614233842). Conséquence de la panne : pendant un pic de
--     trafic (plus de lignes à agréger dans refresh_bot_fingerprints), le job
--     saute et le filtre bruit meurt pile quand on en a besoin — le 01/07/2026
--     les runs de 08:05 ET 09:05 ont échoué, laissant un swarm de bots non flaggé
--     au refresh dashboard de 10:00 (faux pic visiteurs).
--     -> `SET statement_timeout='600s'` en tête de commande (170 s typiques << 600).
--
-- (2) Le cron dashboard tournait à 08:00 UTC, AVANT le refresh bruit de 08:05 UTC,
--     donc lisait des filtres périmés d'une heure. Décalé à 08:15 UTC (10:15 Paris),
--     ~10 min après le refresh bruit de :05, pour construire le snapshot sur des
--     filtres frais. Combiné au comptage pageview-only (20260701084357), ferme la
--     race qui gelait un faux pic dans le point du jour.

SELECT cron.schedule(
  'refresh_noise_filters_hourly',
  '5 * * * *',
  $cmd$SET statement_timeout='600s';
    select public.refresh_bot_fingerprints();
    select public.refresh_noise_sessions();
  $cmd$
);

SELECT cron.schedule(
  'refresh-dashboard-snapshots',
  '15 8 * * *',
  $cmd$SET statement_timeout='600s'; SELECT public.refresh_dashboard_snapshots();$cmd$
);
