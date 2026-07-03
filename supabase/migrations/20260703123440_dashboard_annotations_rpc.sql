-- B1 — dashboard_annotations : journal d'interventions visible sur les courbes.
-- Renvoie les annotations dont `day` tombe dans la fenêtre Cooked LIVE du
-- period_kind, MÊMES bornes ancrées J-1 que les snapshots (cooked_period_bounds +
-- v_shift T-16 : shift = max(n_end - (paris_today-1), 0), appliqué aux deux bornes).
-- Lecture LIVE d'une table minuscule — ne touche à aucun refresh/snapshot.
-- Le filtrage par path (fiche article) se fait côté front (la RPC renvoie paths[]).
CREATE OR REPLACE FUNCTION public.dashboard_annotations(period_kind text DEFAULT 'rolling_90')
 RETURNS TABLE(day date, kind text, label text, paths text[])
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  WITH b AS (
    SELECT n_start, n_end, paris_today
    FROM public.cooked_period_bounds(
      CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END, 'live')
  ),
  s AS (
    SELECT (n_start - GREATEST(n_end - (paris_today - 1), 0)) AS ns,
           (n_end   - GREATEST(n_end - (paris_today - 1), 0)) AS ne
    FROM b
  )
  SELECT a.day, a.kind, a.label, a.paths
  FROM public.annotations a, s
  WHERE a.day BETWEEN s.ns AND s.ne
  ORDER BY a.day, a.id;
$$;

REVOKE ALL ON FUNCTION public.dashboard_annotations(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_annotations(text) TO service_role;
