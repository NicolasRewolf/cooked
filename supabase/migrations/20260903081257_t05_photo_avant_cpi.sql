-- T-05 (mission 02/09/2026, #106) — étape 1/3 : photo « avant » du CPI, calculée le MÊME jour que l'« après ».
--
-- cooked_page_index(28) dure plusieurs minutes (le refresh complet prend ~26 min) : impossible en synchrone via MCP.
-- On la calcule donc en tâche de fond (pg_cron, un seul passage à 08:16 UTC = 10:16 Paris, le job se désarme lui-même)
-- avec la définition ACTUELLE (fenêtres GSC `current_date - 28` = 24 jours de données, fenêtres Cooked `now() - 28 j`),
-- dans une table d'audit temporaire — même dispositif que cpi_pre_restatement_20260712 / _20260727 (supprimées le
-- 10/08/2026). À supprimer au ticket T-19 (DROP = validation citée) une fois l'annotation posée.

CREATE TABLE IF NOT EXISTS public.cpi_pre_restatement_20260903 (LIKE public.cpi_daily INCLUDING DEFAULTS);
ALTER TABLE public.cpi_pre_restatement_20260903 ENABLE ROW LEVEL SECURITY;  -- aucune policy : service_role seul
REVOKE ALL ON TABLE public.cpi_pre_restatement_20260903 FROM public, anon, authenticated;

COMMENT ON TABLE public.cpi_pre_restatement_20260903 IS
  'Photo du CPI du 03/09/2026 calculée AVANT le restatement T-05 (fenêtres GSC 24 j / Cooked now()-28 j). Table d audit temporaire — à supprimer (T-19).';

SELECT cron.schedule('t05-photo-avant-cpi', '16 8 * * *', $job$
DO $$
BEGIN
  SET LOCAL statement_timeout = '900s';
  INSERT INTO public.cpi_pre_restatement_20260903
    (day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit)
  SELECT public.paris_today(),
    path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit
  FROM public.cooked_page_index(28);
  PERFORM cron.unschedule('t05-photo-avant-cpi');
END $$;
$job$);
