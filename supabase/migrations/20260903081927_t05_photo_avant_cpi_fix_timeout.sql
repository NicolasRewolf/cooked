-- T-05 (#106) — étape 1bis/3 : le job de photo « avant » a échoué à 10:18 Paris (« canceling statement due to statement
-- timeout », 2 min = défaut serveur). Cause : un `SET LOCAL statement_timeout` posé DANS le bloc DO ne réarme pas le
-- minuteur de la commande déjà en cours. Correctif = même patron que `cooked-refresh-after-gsc` : le SET est une commande
-- séparée, AVANT le DO, dans la chaîne envoyée par pg_cron. Un seul passage à 08:22 UTC (10:22 Paris), auto-désarmé.
SELECT cron.unschedule('t05-photo-avant-cpi');

SELECT cron.schedule('t05-photo-avant-cpi', '22 8 * * *', $job$
SET statement_timeout = '900s';
DO $$
BEGIN
  INSERT INTO public.cpi_pre_restatement_20260903
    (day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit)
  SELECT public.paris_today(),
    path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit
  FROM public.cooked_page_index(28);
  PERFORM cron.unschedule('t05-photo-avant-cpi');
END $$;
$job$);
