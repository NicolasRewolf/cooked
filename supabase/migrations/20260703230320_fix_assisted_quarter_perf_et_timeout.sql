-- Fix (04/07/2026) — dashboard_assisted_quarter : perf + timeout propre
-- ============================================================================
-- Incident : 2 timeouts en prod le 03/07 ~22:57 UTC (RpcError → la HOME
-- plantait). Causes : (1) la CTE fpv calculait le 1er pageview de TOUTES les
-- sessions du trimestre avant de filtrer sur celles ayant un contact ;
-- (2) pas de statement_timeout propre → héritait du timeout court du rôle API.
-- Fix : contacts D'ABORD (quelques dizaines/centaines de sessions), puis
-- lookup du 1er pageview restreint à CES sessions (index session_id) ;
-- + SET statement_timeout '30s' niveau fonction (effectif via PostgREST).
-- Le front devient aussi résilient (ligne masquée si erreur) — même PR.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.dashboard_assisted_quarter()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '30s'
AS $function$
DECLARE
  q_start date := date_trunc('quarter', public.paris_today())::date;
  q_end   date := public.paris_today();
  q_label text := 'T' || extract(quarter from q_start)::int || ' ' || extract(year from q_start)::int;
  v_value int; v_target int;
BEGIN
  WITH ct AS (  -- contacts macro du trimestre (petit ensemble) — D'ABORD
    SELECT e.session_id AS sid FROM events_human e
    WHERE e.name='cta_phone_click'
      AND e.occurred_at >= (q_start::timestamp AT TIME ZONE 'Europe/Paris')
      AND e.occurred_at <  ((q_end + 1)::timestamp AT TIME ZONE 'Europe/Paris')
    UNION ALL
    SELECT e.props->>'cooked_sid' FROM events_human e
    WHERE e.name='form_submit' AND form_submit_counts_as_macro(e.props) AND e.props->>'cooked_sid' IS NOT NULL
      AND e.occurred_at >= (q_start::timestamp AT TIME ZONE 'Europe/Paris')
      AND e.occurred_at <  ((q_end + 1)::timestamp AT TIME ZONE 'Europe/Paris')
  ),
  fpv AS (  -- 1er pageview UNIQUEMENT pour les sessions à contact
    SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path
    FROM events_human e
    WHERE e.name='pageview'
      AND e.session_id IN (SELECT sid FROM ct)
      AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com' AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
      AND e.occurred_at >= (q_start::timestamp AT TIME ZONE 'Europe/Paris')
      AND e.occurred_at <  ((q_end + 1)::timestamp AT TIME ZONE 'Europe/Paris')
    ORDER BY e.session_id, e.occurred_at
  )
  SELECT count(*) INTO v_value
  FROM ct JOIN fpv ON fpv.session_id = ct.sid
  JOIN page_taxonomy pt ON pt.path = fpv.entry_path AND pt.category='ressource';

  SELECT NULLIF(btrim(value),'')::int INTO v_target FROM cooked_config WHERE key='objectif_assistes_trimestre';

  RETURN jsonb_build_object('quarter', q_label, 'quarter_start', q_start, 'value', COALESCE(v_value,0), 'target', v_target);
END;
$function$;
