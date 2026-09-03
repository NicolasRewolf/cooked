-- Lab (onglet « Lab » de data.rewolf.studio, 03/09/2026) — clics Google par semaine et par type de page.
--
-- Première brique du « Lab » : un graphe Stream Ribbon (Lieflat F16) des clics GSC du site, 16 mois,
-- décomposés par type de page (ressources / classiques / expertises / cabinet & divers). Sert à lire la
-- chute de ~40 % des clics de mi-juillet 2026 (constat CLAUDE.md, non instruit) : la décomposition montre
-- qu'elle est portée par les articles ressources, à impressions constantes.
--
-- Contrat : UNE fenêtre close — semaines ISO complètes (lundi → dimanche) dont le dimanche ≤ gsc_last_data_day().
-- Pas de borne d'horloge (règle C6c). Totaux = gsc_path_daily (tous clics, marque incluse — piège n°3 du
-- playbook : gsc_query_page_daily ne couvre qu'une fraction du trafic). Types : cooked_page_type(path) ;
-- les posts sont ventilés par page_taxonomy.category (ressource / classique) ; un post sans ligne de
-- taxonomie tombe dans « divers » (mode de défaillance connu : absence de ligne, cf. alerte page_taxonomy_gap).

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
typed AS (
  SELECT date_trunc('week', g.day)::date AS week_start,
         CASE
           WHEN public.cooked_page_type(g.path) = 'post' AND pt.category = 'ressource' THEN 'ressource'
           WHEN public.cooked_page_type(g.path) = 'post' AND pt.category = 'classique' THEN 'classique'
           WHEN public.cooked_page_type(g.path) = 'expertise' THEN 'expertise'
           ELSE 'divers'
         END AS typ,
         g.clicks, g.impressions
  FROM public.gsc_path_daily g
  LEFT JOIN public.page_taxonomy pt ON pt.path = g.path
  WHERE g.day BETWEEN (SELECT w_start FROM w) AND (SELECT w_end FROM w)
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

COMMENT ON FUNCTION public.dashboard_lab_gsc_weekly(integer) IS
  'Lab dashboard — clics et impressions GSC par semaine ISO close (≤ gsc_last_data_day) et par type de page (ressource/classique/expertise/divers), + annotations de la fenêtre. Totaux gsc_path_daily, marque incluse.';

REVOKE ALL ON FUNCTION public.dashboard_lab_gsc_weekly(integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_lab_gsc_weekly(integer) TO service_role;
