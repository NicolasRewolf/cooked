-- T-09 (mission 02/09/2026, #110) — étape 1/3 : photo « avant » du terme conversion (zv) du CPI.
--
-- Le cpi_daily du 03/09/2026 vaut aujourd'hui l'« après » T-05 (calculé 10:58 Paris, dernier jour GSC 30/08/2026) : c'est
-- exactement l'« avant » T-09. Copie synchrone dans la table d'audit de T-05, distinguée par une colonne `phase`
-- (les lignes T-05 déjà présentes reçoivent 't05_avant'). L'« après » T-09 sera recalculé le même jour, sur les mêmes
-- données GSC, par cooked_cpi_snapshot() (étape 2bis/3). Table à supprimer au ticket T-19 (DROP = validation citée).
ALTER TABLE public.cpi_pre_restatement_20260903 ADD COLUMN IF NOT EXISTS phase text NOT NULL DEFAULT 't05_avant';

INSERT INTO public.cpi_pre_restatement_20260903
  (day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit, phase)
SELECT day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit,
       't09_avant'
FROM public.cpi_daily
WHERE day = public.paris_today();

COMMENT ON TABLE public.cpi_pre_restatement_20260903 IS
  'Photos du CPI du 03/09/2026 avant restatement : phase t05_avant (fenêtres GSC 24 j / Cooked now()-28 j, 10:22 Paris) et t09_avant (= après T-05, zv encore sur now(), 10:58 Paris). Table d audit temporaire — à supprimer (T-19).';
