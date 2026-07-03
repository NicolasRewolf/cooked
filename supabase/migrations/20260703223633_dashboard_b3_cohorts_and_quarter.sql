-- B3 — Cohortes du contrat + objectif trimestre. Deux RPCs live, service_role only.
-- Ne touche à AUCUN refresh/snapshot existant, ne touche pas au CPI.

-- 1) Cohortes mensuelles : clics GSC cumulés MOYENS PAR ARTICLE, alignés sur l'âge
--    (J0 = 1re impression GSC, jamais la date Wix). Cohorte = mois de naissance GSC.
--    Chaque ligne s'arrête à l'âge de son benjamin (min cap), plafond J+60. 6 dernières.
CREATE OR REPLACE FUNCTION public.dashboard_resources_cohorts()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
WITH
res AS (SELECT path FROM page_taxonomy WHERE category='ressource'),
j0 AS (SELECT g.path, min(g.day) AS j0
       FROM gsc_path_daily g JOIN res ON res.path=g.path
       WHERE g.impressions > 0 GROUP BY g.path),
art AS (SELECT path, j0, to_char(j0,'YYYY-MM') AS cohort,
               LEAST((public.gsc_last_data_day() - j0), 60) AS cap
        FROM j0 WHERE (public.gsc_last_data_day() - j0) >= 0),
lastc AS (SELECT cohort FROM (SELECT DISTINCT cohort FROM art) d ORDER BY cohort DESC LIMIT 6),
arts AS (SELECT a.* FROM art a JOIN lastc l ON l.cohort=a.cohort),
grid AS (SELECT path, cohort, cap, generate_series(0, cap)::int AS age FROM arts),
da AS (SELECT a.path, (g.day - a.j0)::int AS age, g.clicks
       FROM arts a JOIN gsc_path_daily g
         ON g.path=a.path AND g.day BETWEEN a.j0 AND a.j0 + a.cap),
ca AS (SELECT gr.path, gr.cohort, gr.age, COALESCE(da.clicks,0) AS clicks
       FROM grid gr LEFT JOIN da ON da.path=gr.path AND da.age=gr.age),
cumul AS (SELECT path, cohort, age,
                 sum(clicks) OVER (PARTITION BY path ORDER BY age) AS cumul
          FROM ca),
benj AS (SELECT cohort, count(*) AS n_art, min(cap) AS benjamin FROM arts GROUP BY cohort),
cs AS (SELECT c.cohort, c.age, sum(c.cumul)::numeric / b.n_art AS avg_cumul
       FROM cumul c JOIN benj b ON b.cohort=c.cohort
       WHERE c.age <= b.benjamin
       GROUP BY c.cohort, c.age, b.n_art),
series AS (SELECT cohort, array_agg(round(avg_cumul,1) ORDER BY age) AS ser FROM cs GROUP BY cohort)
SELECT jsonb_build_object('gsc_last', public.gsc_last_data_day(), 'cohorts',
  COALESCE(jsonb_agg(jsonb_build_object(
    'month', s.cohort,
    'n_articles', b.n_art,
    'benjamin_age', b.benjamin,
    'series', to_jsonb(s.ser)
  ) ORDER BY s.cohort), '[]'::jsonb))
FROM series s JOIN benj b ON b.cohort=s.cohort;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_resources_cohorts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_resources_cohorts() TO service_role;

-- 2) Objectif trimestre : contacts assistés (attribution page d'entrée) trimestre-à-date.
--    Réplique EXACTEMENT la logique du snapshot assisted (refresh_dashboard_resources_assisted)
--    mais sur [début du trimestre, aujourd'hui]. Cible lue dans cooked_config (jamais inventée).
CREATE OR REPLACE FUNCTION public.dashboard_assisted_quarter()
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  q_start date := date_trunc('quarter', public.paris_today())::date;
  q_end   date := public.paris_today();
  q_label text := 'T' || extract(quarter from q_start)::int || ' ' || extract(year from q_start)::int;
  v_value int; v_target int;
BEGIN
  WITH fpv AS (
    SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path
    FROM events_human e
    WHERE e.name='pageview'
      AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com' AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
      AND e.occurred_at >= (q_start::timestamp AT TIME ZONE 'Europe/Paris')
      AND e.occurred_at <  ((q_end + 1)::timestamp AT TIME ZONE 'Europe/Paris')
    ORDER BY e.session_id, e.occurred_at
  ),
  ct AS (
    SELECT e.session_id AS sid FROM events_human e
    WHERE e.name='cta_phone_click'
      AND e.occurred_at >= (q_start::timestamp AT TIME ZONE 'Europe/Paris')
      AND e.occurred_at <  ((q_end + 1)::timestamp AT TIME ZONE 'Europe/Paris')
    UNION ALL
    SELECT e.props->>'cooked_sid' FROM events_human e
    WHERE e.name='form_submit' AND form_submit_counts_as_macro(e.props) AND e.props->>'cooked_sid' IS NOT NULL
      AND e.occurred_at >= (q_start::timestamp AT TIME ZONE 'Europe/Paris')
      AND e.occurred_at <  ((q_end + 1)::timestamp AT TIME ZONE 'Europe/Paris')
  )
  SELECT count(*) INTO v_value
  FROM ct JOIN fpv ON fpv.session_id = ct.sid
  JOIN page_taxonomy pt ON pt.path = fpv.entry_path AND pt.category='ressource';

  SELECT NULLIF(btrim(value),'')::int INTO v_target FROM cooked_config WHERE key='objectif_assistes_trimestre';

  RETURN jsonb_build_object('quarter', q_label, 'quarter_start', q_start, 'value', COALESCE(v_value,0), 'target', v_target);
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_assisted_quarter() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_assisted_quarter() TO service_role;
