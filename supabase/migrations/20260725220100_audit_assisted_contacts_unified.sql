-- Audit 25/07/2026 — tâche #7 : une seule définition des contacts assistés.

CREATE OR REPLACE FUNCTION public.assisted_contacts_by_entry_path(p_start date, p_end date)
 RETURNS TABLE(entry_path text, contacts bigint)
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  t0 timestamptz := (p_start::timestamp AT TIME ZONE 'Europe/Paris');
  t1 timestamptz := ((p_end + 1)::timestamp AT TIME ZONE 'Europe/Paris');
BEGIN
  DROP TABLE IF EXISTS _pvk;
  CREATE TEMP TABLE _pvk ON COMMIT DROP AS
    SELECT COALESCE(st.visitor_key, 'sid:' || e.session_id) AS vk,
           e.occurred_at AS t, e.path
    FROM public.events_human e
    LEFT JOIN public.identity_stitch st ON st.kind = 'sid' AND st.key = e.session_id
    WHERE e.name = 'pageview'
      AND e.occurred_at >= t0 AND e.occurred_at < t1
      AND NOT public.cooked_is_spam_referrer(e.referrer_hostname);

  DROP TABLE IF EXISTS _pvseg;
  CREATE TEMP TABLE _pvseg ON COMMIT DROP AS
    SELECT vk, t, path,
           sum(brk) OVER (PARTITION BY vk ORDER BY t) AS visit_n
    FROM (
      SELECT vk, t, path,
             CASE WHEN lag(t) OVER (PARTITION BY vk ORDER BY t) IS NULL
                    OR t - lag(t) OVER (PARTITION BY vk ORDER BY t) > interval '30 minutes'
                  THEN 1 ELSE 0 END AS brk
      FROM _pvk
    ) x;
  CREATE INDEX ON _pvseg (vk, t);
  ANALYZE _pvseg;

  DROP TABLE IF EXISTS _ventry;
  CREATE TEMP TABLE _ventry ON COMMIT DROP AS
    SELECT vk, visit_n, (array_agg(path ORDER BY t))[1] AS entry_path
    FROM _pvseg GROUP BY vk, visit_n;
  ANALYZE _ventry;

  DROP TABLE IF EXISTS _ct;
  CREATE TEMP TABLE _ct ON COMMIT DROP AS
    SELECT e.occurred_at AS t,
           COALESCE(st.visitor_key, 'sid:' || e.session_id) AS vk
    FROM public.events_human e
    LEFT JOIN public.identity_stitch st ON st.kind = 'sid' AND st.key = e.session_id
    WHERE e.name = 'cta_phone_click'
      AND e.occurred_at >= t0 AND e.occurred_at < t1
    UNION ALL
    SELECT e.occurred_at,
           COALESCE(sts.visitor_key, sta.visitor_key, 'sid:' || (e.props->>'cooked_sid'))
    FROM public.events_human e
    LEFT JOIN public.identity_stitch sts ON sts.kind = 'sid' AND sts.key = e.props->>'cooked_sid'
    LEFT JOIN public.identity_stitch sta ON sta.kind = 'aid' AND sta.key = e.props->>'cooked_aid'
    WHERE e.name = 'form_submit'
      AND public.form_submit_counts_as_macro(e.props)
      AND e.occurred_at >= t0 AND e.occurred_at < t1
      AND COALESCE(e.props->>'cooked_sid', e.props->>'cooked_aid') IS NOT NULL;
  ANALYZE _ct;

  DROP TABLE IF EXISTS _ce;
  CREATE TEMP TABLE _ce ON COMMIT DROP AS
    SELECT COALESCE(v.entry_path, '(non rattaché)') AS entry_path
    FROM _ct c
    JOIN LATERAL (
      SELECT s.vk, s.visit_n
      FROM _pvseg s
      WHERE s.vk = c.vk AND s.t <= c.t AND c.t - s.t <= interval '6 hours'
      ORDER BY s.t DESC LIMIT 1
    ) lp ON true
    LEFT JOIN _ventry v ON v.vk = lp.vk AND v.visit_n = lp.visit_n;

  RETURN QUERY
  SELECT ce.entry_path, count(*)::bigint
  FROM _ce ce
  GROUP BY ce.entry_path;
END;
$function$;

REVOKE ALL ON FUNCTION public.assisted_contacts_by_entry_path(date, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.assisted_contacts_by_entry_path(date, date) TO service_role;

COMMENT ON FUNCTION public.assisted_contacts_by_entry_path(date, date) IS
  'Contacts macro (phone+form) par page d''entrée de visite (visiteur recousu, segmentation 30 min, ≤6 h). Source unique snapshot + objectif trimestre.';

CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lbl text; lns date; lne date; lps date; lpe date; lpt date; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int;
BEGIN
  DELETE FROM public.dashboard_resources_assisted_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'human', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);

    INSERT INTO public.dashboard_resources_assisted_snapshot
      (window_kind, path, assisted_contacts, assisted_prev, refreshed_at)
    SELECT w, pt.path, COALESCE(cur.n, 0), COALESCE(prv.n, 0), now()
    FROM public.page_taxonomy pt
    LEFT JOIN (
      SELECT entry_path, contacts AS n
      FROM public.assisted_contacts_by_entry_path(lns, lne)
    ) cur ON cur.entry_path = pt.path
    LEFT JOIN (
      SELECT entry_path, contacts AS n
      FROM public.assisted_contacts_by_entry_path(lps, lpe)
    ) prv ON prv.entry_path = pt.path
    WHERE pt.category = 'ressource';
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dashboard_assisted_quarter()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '30s'
AS $function$
DECLARE
  q_start date := date_trunc('quarter', public.paris_today())::date;
  q_end   date := public.paris_today();
  q_label text := 'T' || extract(quarter FROM q_start)::int || ' ' || extract(year FROM q_start)::int;
  v_value int;
  v_target int;
BEGIN
  SELECT coalesce(sum(a.contacts), 0)::int INTO v_value
  FROM public.assisted_contacts_by_entry_path(q_start, q_end) a
  JOIN public.page_taxonomy pt ON pt.path = a.entry_path AND pt.category = 'ressource';

  SELECT NULLIF(btrim(value), '')::int INTO v_target
  FROM public.cooked_config WHERE key = 'objectif_assistes_trimestre';

  RETURN jsonb_build_object(
    'quarter', q_label,
    'quarter_start', q_start,
    'value', COALESCE(v_value, 0),
    'target', v_target
  );
END;
$function$;
