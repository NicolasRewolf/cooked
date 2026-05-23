-- Sprint 33+ (24/05/2026) — helpers SQL pour le Pulse
-- Factorise la dette DRY identifiée par la review thermo-nuclear :
--   A. CTE g28 (agrégation GSC 28j par path) recopié 4 fois.
--   B. Logique CASE quadrant dupliquée dans pages_pulse + site_pulse.
--   C. Sera utilisé par toute future RPC overview/pulse.
--
-- Ne casse aucune signature publique. Les anciennes RPCs continuent
-- à fonctionner ; pages_pulse et site_pulse sont réécrites pour
-- déléguer à ces helpers.

-- ============================================================
-- 1. pulse_quadrant(gsc_dir, cooked_dir) : règle quadrant pure
-- ============================================================
-- 'flat' sur un seul axe = rabattu sur l'autre direction (cohérent
-- avec la table de décision pages_pulse/site_pulse actuelle).
CREATE OR REPLACE FUNCTION public.pulse_quadrant(
  gsc_dir    text,
  cooked_dir text
)
RETURNS text
IMMUTABLE
LANGUAGE sql
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN gsc_dir = 'up'   AND cooked_dir = 'up'   THEN 'up_up'
    WHEN gsc_dir = 'up'   AND cooked_dir = 'flat' THEN 'up_up'
    WHEN gsc_dir = 'up'   AND cooked_dir = 'down' THEN 'up_down'
    WHEN gsc_dir = 'flat' AND cooked_dir = 'up'   THEN 'up_up'
    WHEN gsc_dir = 'flat' AND cooked_dir = 'down' THEN 'up_down'
    WHEN gsc_dir = 'down' AND cooked_dir = 'up'   THEN 'down_up'
    WHEN gsc_dir = 'down' AND cooked_dir = 'flat' THEN 'down_up'
    WHEN gsc_dir = 'down' AND cooked_dir = 'down' THEN 'down_down'
    ELSE 'neutral'
  END;
$$;

COMMENT ON FUNCTION public.pulse_quadrant(text, text) IS
  'Sprint 33+ : règle quadrant (gsc_dir × cooked_dir) → un des 5 quadrants. up/flat → up, flat/flat → neutral. Pure et immutable.';

REVOKE EXECUTE ON FUNCTION public.pulse_quadrant(text, text) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pulse_quadrant(text, text) TO service_role;


-- ============================================================
-- 2. pulse_status(volumes...) : règle complète quadrant + no_signal
-- ============================================================
-- Encapsule la décision finale : si pas assez de signal historique
-- (cooked_prev null), si volumes à 0 partout (no_signal), sinon
-- traduit les volumes en directions puis appelle pulse_quadrant.
CREATE OR REPLACE FUNCTION public.pulse_status(
  gsc_n             bigint,
  gsc_prev          bigint,
  cooked_n          bigint,
  cooked_prev       bigint,
  delta_threshold   numeric DEFAULT 5.0
)
RETURNS text
IMMUTABLE
LANGUAGE sql
SET search_path TO 'public'
AS $$
  WITH d AS (
    SELECT
      CASE WHEN gsc_prev > 0
           THEN 100.0 * (gsc_n - gsc_prev) / gsc_prev END    AS gsc_delta,
      CASE WHEN cooked_prev IS NOT NULL AND cooked_prev > 0
           THEN 100.0 * (cooked_n - cooked_prev) / cooked_prev END AS cooked_delta
  )
  SELECT CASE
    WHEN (gsc_n = 0 AND COALESCE(gsc_prev, 0) = 0) THEN 'no_signal'
    WHEN cooked_prev IS NULL THEN 'no_signal'
    WHEN (cooked_n = 0 AND COALESCE(cooked_prev, 0) = 0) THEN 'no_signal'
    ELSE public.pulse_quadrant(
      CASE WHEN d.gsc_delta IS NULL THEN 'flat'
           WHEN d.gsc_delta >=  delta_threshold THEN 'up'
           WHEN d.gsc_delta <= -delta_threshold THEN 'down'
           ELSE 'flat' END,
      CASE WHEN d.cooked_delta IS NULL THEN 'flat'
           WHEN d.cooked_delta >=  delta_threshold THEN 'up'
           WHEN d.cooked_delta <= -delta_threshold THEN 'down'
           ELSE 'flat' END
    )
  END
  FROM d;
$$;

COMMENT ON FUNCTION public.pulse_status(bigint, bigint, bigint, bigint, numeric) IS
  'Sprint 33+ : volumes (N, prev pour GSC et Cooked) + seuil → quadrant final, incluant no_signal. Délègue à pulse_quadrant().';

REVOKE EXECUTE ON FUNCTION public.pulse_status(bigint, bigint, bigint, bigint, numeric) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pulse_status(bigint, bigint, bigint, bigint, numeric) TO service_role;


-- ============================================================
-- 3. gsc_path_metrics(start_date, end_date) : agrégat GSC par path
-- ============================================================
-- Factorise le CTE g28 recopié dans pages_overview_unified,
-- gsc_pages_overview, gsc_pages_compare, etc. Paramétrable pour gérer
-- les fenêtres N et N-1 (deux appels). Pour la fenêtre 28j courante,
-- voir la vue gsc_path_metrics_28d ci-dessous.
CREATE OR REPLACE FUNCTION public.gsc_path_metrics(
  start_date date,
  end_date   date
)
RETURNS TABLE (
  path               text,
  impressions_total  bigint,
  clicks_total       bigint,
  position_avg       numeric,
  ctr_pct            numeric
)
STABLE
LANGUAGE sql
SET search_path TO 'public'
AS $$
  SELECT
    g.path,
    SUM(g.impressions)::bigint,
    SUM(g.clicks)::bigint,
    CASE WHEN SUM(g.impressions) > 0
         THEN ROUND((SUM(g.position * g.impressions) / SUM(g.impressions))::numeric, 2)
         ELSE NULL END,
    CASE WHEN SUM(g.impressions) > 0
         THEN ROUND((100.0 * SUM(g.clicks) / SUM(g.impressions))::numeric, 2)
         ELSE NULL END
  FROM public.gsc_path_daily g
  WHERE g.day >= start_date AND g.day <= end_date
  GROUP BY g.path;
$$;

COMMENT ON FUNCTION public.gsc_path_metrics(date, date) IS
  'Sprint 33+ : agrégat GSC par path sur [start_date, end_date]. Position pondérée par impressions, CTR en %.';

REVOKE EXECUTE ON FUNCTION public.gsc_path_metrics(date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_path_metrics(date, date) TO service_role;


-- Raccourci 28j (heure Paris) — surface principale pour les RPCs overview
CREATE OR REPLACE VIEW public.gsc_path_metrics_28d
WITH (security_invoker = true) AS
SELECT *
FROM public.gsc_path_metrics(
  ((now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days')::date,
  (now() AT TIME ZONE 'Europe/Paris')::date
);

COMMENT ON VIEW public.gsc_path_metrics_28d IS
  'Sprint 33+ : alias 28j (heure Paris) de gsc_path_metrics(). Recalculé à chaque SELECT.';

REVOKE SELECT ON public.gsc_path_metrics_28d FROM public, anon, authenticated;
GRANT  SELECT ON public.gsc_path_metrics_28d TO service_role;


-- ============================================================
-- 4. form_submits_per_path(start_date, end_date)
-- ============================================================
-- Factorise le CTE fs28 (count form_submit par path) recopié dans
-- pages_overview_unified, gsc_pages_overview, gsc_page_performance,
-- cooked_pages_compare. Lit events_human (bots + noise filtrés).
CREATE OR REPLACE FUNCTION public.form_submits_per_path(
  start_date date,
  end_date   date
)
RETURNS TABLE (
  path           text,
  form_submits   bigint
)
STABLE
LANGUAGE sql
SET search_path TO 'public'
AS $$
  SELECT
    e.path,
    count(*)::bigint
  FROM public.events_human e
  WHERE e.name = 'form_submit'
    AND e.path IS NOT NULL
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= start_date
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= end_date
  GROUP BY e.path;
$$;

COMMENT ON FUNCTION public.form_submits_per_path(date, date) IS
  'Sprint 33+ : count form_submit par path sur [start_date, end_date] (events_human). Bornes en heure Paris.';

REVOKE EXECUTE ON FUNCTION public.form_submits_per_path(date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.form_submits_per_path(date, date) TO service_role;
