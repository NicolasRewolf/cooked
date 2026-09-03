-- Lab — dashboard_lab_gsc_weekly v2 : typage des chemins UNE fois (paths distincts), pas ligne par ligne.
-- v1 (20260903151638) appelait cooked_page_type() deux fois par ligne de gsc_path_daily sur 70 semaines
-- (~120 k lignes) → statement timeout dès le premier appel. Contrat de sortie inchangé.

CREATE OR REPLACE FUNCTION public.dashboard_lab_gsc_weekly(p_weeks integer DEFAULT 70)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
WITH g_end AS (
  SELECT public.gsc_last_data_day() AS d
),
-- Dernier dimanche ≤ gsc_last_data_day (semaine ISO close), puis p_weeks semaines en arrière.
w AS (
  SELECT (date_trunc('week', d)::date - 1) AS w_end,
         (date_trunc('week', d)::date - 1) - (7 * GREATEST(p_weeks, 1)) + 1 AS w_start
  FROM g_end
),
win AS (
  SELECT g.day, g.path, g.clicks, g.impressions
  FROM public.gsc_path_daily g
  WHERE g.day BETWEEN (SELECT w_start FROM w) AND (SELECT w_end FROM w)
),
-- Type par chemin distinct (≈ 500 chemins) : cooked_page_type() évaluée une fois par chemin.
ptype AS (
  SELECT p.path,
         CASE
           WHEN t.typ = 'post' AND pt.category = 'ressource' THEN 'ressource'
           WHEN t.typ = 'post' AND pt.category = 'classique' THEN 'classique'
           WHEN t.typ = 'expertise' THEN 'expertise'
           ELSE 'divers'
         END AS typ
  FROM (SELECT DISTINCT path FROM win) p
  CROSS JOIN LATERAL (SELECT public.cooked_page_type(p.path) AS typ) t
  LEFT JOIN public.page_taxonomy pt ON pt.path = p.path
),
typed AS (
  SELECT date_trunc('week', win.day)::date AS week_start, ptype.typ, win.clicks, win.impressions
  FROM win JOIN ptype USING (path)
),
weeks AS (
  SELECT week_start,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'ressource'), 0)::bigint AS c_ressource,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'classique'), 0)::bigint AS c_classique,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'expertise'), 0)::bigint AS c_expertise,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'divers'), 0)::bigint    AS c_divers,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'ressource'), 0)::bigint AS i_ressource,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'classique'), 0)::bigint AS i_classique,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'expertise'), 0)::bigint AS i_expertise,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'divers'), 0)::bigint    AS i_divers
  FROM typed
  GROUP BY week_start
),
ann AS (
  SELECT a.day, a.kind, a.label, a.paths
  FROM public.annotations a
  WHERE a.day BETWEEN (SELECT w_start FROM w) AND (SELECT w_end FROM w)
  ORDER BY a.day, a.id
)
SELECT jsonb_build_object(
  'gsc_end',      (SELECT d FROM g_end),
  'window_start', (SELECT w_start FROM w),
  'window_end',   (SELECT w_end FROM w),
  'weeks',        COALESCE((SELECT jsonb_agg(to_jsonb(weeks) ORDER BY week_start) FROM weeks), '[]'::jsonb),
  'annotations',  COALESCE((SELECT jsonb_agg(to_jsonb(ann)) FROM ann), '[]'::jsonb)
);
$function$;
