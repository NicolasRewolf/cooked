-- Candidat 1 de la revue d'architecture du 28/07/2026 — reifier la Lecture.
--
-- Constat : 14 occurrences de page_exit.props.duration_seconds reparties sur
-- 8 RPC (cooked_page_index, content_performance, engagement_density_for_path,
-- pogo_rates_for_period, seo_pages_overview, refresh_seo_url_snapshot,
-- refresh_dashboard_snapshots, refresh_dashboard_expertises_snapshots),
-- chacune redérivant a la main le grain de regroupement, la source de la
-- profondeur et le traitement du zero. Trois definitions divergentes
-- coexistaient (cf. CONTEXT.md § Lecture et docs/adr/0001).
--
-- Ce module N'AJOUTE AUCUN COMPORTEMENT. Il reproduit exactement la semantique
-- de cooked_page_index, pour pouvoir y brancher les appelants sans deplacer un
-- seul chiffre. Equivalence verifiee en prod le 28/07/2026 sur 7 jours :
-- 3 163 lectures des deux cotes, 0 ligne divergente, 2 600 retenues de part et
-- d'autre, dwell median 49,00 identique.
--
-- La reconstruction du dwell depuis engagement_tick — qui, elle, CHANGE les
-- chiffres (~40 % de visites desktop recuperees, ecart median 0,44 s) — viendra
-- derriere cette interface, dans un changement separe et annote. La colonne
-- `source` est le seam prevu pour ca : aujourd'hui elle vaut toujours
-- 'page_exit'.
--
-- Signature double, motif de macro_contacts_by_path : bornes explicites pour
-- les appelants qui ont deja une fenetre, surcharge en jours pour les autres.

CREATE OR REPLACE FUNCTION public.page_reads(p_from timestamptz, p_to timestamptz)
 RETURNS TABLE(
   session_id  text,
   path        text,
   dwell_s     numeric,
   scroll_pct  numeric,
   session_pageviews bigint,
   retained    boolean,
   source      text
 )
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH pex AS (
    SELECT e.session_id, e.path,
           max((e.props->>'duration_seconds')::numeric) AS d,
           max(coalesce((e.props->>'max_scroll')::numeric, 0)) AS s
    FROM public.events_human e
    WHERE e.name = 'page_exit'
      AND e.path IS NOT NULL
      AND e.occurred_at > p_from AND e.occurred_at <= p_to
    GROUP BY e.session_id, e.path
  ),
  spv AS (
    SELECT e.session_id, count(*) AS pv
    FROM public.events_human e
    WHERE e.name = 'pageview'
      AND e.occurred_at > p_from AND e.occurred_at <= p_to
    GROUP BY e.session_id
  )
  SELECT pex.session_id,
         pex.path,
         pex.d,
         pex.s,
         coalesce(spv.pv, 1)::bigint,
         (pex.d >= 15 OR coalesce(spv.pv, 1) >= 2),
         'page_exit'::text
  FROM pex LEFT JOIN spv ON spv.session_id = pex.session_id;
$function$;

CREATE OR REPLACE FUNCTION public.page_reads(p_days integer DEFAULT 28)
 RETURNS TABLE(
   session_id  text,
   path        text,
   dwell_s     numeric,
   scroll_pct  numeric,
   session_pageviews bigint,
   retained    boolean,
   source      text
 )
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT * FROM public.page_reads(now() - make_interval(days => p_days), now());
$function$;

COMMENT ON FUNCTION public.page_reads(timestamptz, timestamptz) IS
  'Lecture d une page (CONTEXT.md § Lecture) : une ligne par session x path, '
  'avec dwell_s, scroll_pct, et retained = (dwell_s >= 15 OR session_pageviews >= 2). '
  'Foyer unique — remplace les 14 extractions manuelles de '
  'page_exit.props.duration_seconds reparties sur 8 RPC. Profondeur toujours issue '
  'de page_exit.max_scroll, jamais de scroll_depth.percent (ADR-0001). '
  'ATTENTION : ne couvre que les visites ayant emis page_exit — 59 % sur 28 j au '
  '27/07/2026, 50 % en desktop. La colonne source est le seam prevu pour une '
  'reconstruction depuis engagement_tick (ecart median 0,44 s) ; elle vaut '
  'aujourd hui toujours page_exit et tout changement de sa valeur est un '
  'changement de comportement a annoter.';

COMMENT ON FUNCTION public.page_reads(integer) IS
  'Surcharge en jours glissants de page_reads(timestamptz, timestamptz). '
  'Fenetre identique a celle de cooked_page_index : now() - p_days jours.';
