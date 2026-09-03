-- T-06 (mission 02/09/2026, #107) — étape 1/3 : photo « avant » du momentum du CPI.
--
-- Le cpi_daily du 03/09/2026 vaut à cet instant l'« après » T-09 (recalculé 11:37 Paris, dernier jour GSC 30/08/2026) :
-- c'est exactement l'« avant » T-06. Copie synchrone dans la table d'audit du jour, phase 't06_avant' (même patron que
-- T-09). L'« après » T-06 sera recalculé le même jour, sur les mêmes données GSC, par cooked_cpi_snapshot() (étape 2bis/3).
-- Table à supprimer au ticket T-19.
INSERT INTO public.cpi_pre_restatement_20260903
  (day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit, phase)
SELECT day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit,
       't06_avant'
FROM public.cpi_daily
WHERE day = public.paris_today();

COMMENT ON TABLE public.cpi_pre_restatement_20260903 IS
  'Photos du CPI du 03/09/2026 avant restatement : phase t05_avant (10:22 Paris), t09_avant (= après T-05, 10:58), t06_avant (= après T-09, 11:37 ; momentum encore sur qpd non brandé). Table d audit temporaire — à supprimer (T-19).';
