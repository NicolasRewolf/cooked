-- Cause racine : le cron `cooked-cpi-daily-snapshot` lançait `SELECT cooked_cpi_snapshot()` SANS
-- aucune protection de statement_timeout (contrairement à refresh_seo_url_snapshot qui a le SET dans
-- sa commande). Depuis CPI v2.2 (16/06) + croissance des données, le calcul a dépassé le timeout par
-- défaut et plantait EN SILENCE chaque nuit depuis le 21/06 — cpi_daily gelé 8 jours, les alertes
-- cpi_drop re-tirées à l'identique sur données figées.
-- Fix : pattern éprouvé = SET explicite dans la commande cron (essentiel — re-arme le timer du
-- statement suivant) + SET sur la fonction (couvre les appels manuels hors cron).
ALTER FUNCTION public.cooked_cpi_snapshot() SET statement_timeout = '600s';

SELECT cron.unschedule('cooked-cpi-daily-snapshot');
SELECT cron.schedule('cooked-cpi-daily-snapshot', '30 7 * * *',
  $$SET statement_timeout='600s'; SELECT public.cooked_cpi_snapshot();$$);
