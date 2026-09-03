-- T-08 (mission 02/09/2026, #109) — assisted_contacts + snapshot trimestre + lecture.
-- 1. assisted_contacts_by_entry_path : plus aucun contact macro perdu.
CREATE OR REPLACE FUNCTION public.assisted_contacts_by_entry_path(p_start date, p_end date)
 RETURNS TABLE(entry_path text, contacts bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  t0 timestamptz := public.cooked_paris_ts_start(p_start);
  t1 timestamptz := public.cooked_paris_ts_end_exclusive(p_end);
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
    -- T-08 (c-03) : les forms sans cooked_sid/aid entraient jamais dans _ct (12/28 j le 03/09).
    -- On les garde avec une clé unresolved qui ne matchera aucune visite → (non attribuable).
    SELECT e.occurred_at,
           COALESCE(sts.visitor_key, sta.visitor_key,
             CASE
               WHEN nullif(e.props->>'cooked_sid', '') IS NOT NULL THEN 'sid:' || (e.props->>'cooked_sid')
               WHEN nullif(e.props->>'cooked_aid', '') IS NOT NULL THEN 'aid:' || (e.props->>'cooked_aid')
               ELSE 'unresolved:' || e.session_id
             END)
    FROM public.events_human e
    LEFT JOIN public.identity_stitch sts ON sts.kind = 'sid' AND sts.key = e.props->>'cooked_sid'
    LEFT JOIN public.identity_stitch sta ON sta.kind = 'aid' AND sta.key = e.props->>'cooked_aid'
    WHERE e.name = 'form_submit'
      AND public.form_submit_counts_as_macro(e.props)
      AND e.occurred_at >= t0 AND e.occurred_at < t1;
  ANALYZE _ct;

  DROP TABLE IF EXISTS _ce;
  CREATE TEMP TABLE _ce ON COMMIT DROP AS
    SELECT COALESCE(v.entry_path, '(non attribuable)') AS entry_path
    FROM _ct c
    LEFT JOIN LATERAL (
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

COMMENT ON FUNCTION public.assisted_contacts_by_entry_path(date, date) IS
  'Contacts macro (phone+form) par page d''entrée de visite (visiteur recousu, segmentation 30 min, ≤6 h). Forms sans identifiant et contacts sans visite → ligne (non attribuable). Σ = site_macro_counts sur la même fenêtre (I4, T-08).';


-- 2. Snapshot trimestre + lecture < 1 s.
CREATE TABLE IF NOT EXISTS public.dashboard_assisted_quarter_snapshot (
  quarter text PRIMARY KEY,
  quarter_start date NOT NULL,
  quarter_end date NOT NULL,
  value integer NOT NULL,
  target integer,
  refreshed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dashboard_assisted_quarter_snapshot ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dashboard_assisted_quarter_snapshot FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dashboard_assisted_quarter_snapshot TO service_role;

COMMENT ON TABLE public.dashboard_assisted_quarter_snapshot IS
  'Contacts assistés ressources du trimestre calendaire, fenêtre close à J-1 (live_j1). Rafraîchi par refresh_dashboard_assisted_quarter via cooked_refresh_after_gsc. T-08.';

CREATE OR REPLACE FUNCTION public.refresh_dashboard_assisted_quarter()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '180s'
AS $function$
DECLARE
  q_start date := date_trunc('quarter', public.paris_today())::date;
  q_end   date := public.paris_today() - 1;
  q_label text := 'T' || extract(quarter FROM q_start)::int || ' ' || extract(year FROM q_start)::int;
  v_value int;
  v_target int;
BEGIN
  -- T-08 (c-04) : J-1, le jour en cours n'est pas cousu avant 05:40 UTC.
  IF q_end < q_start THEN
    v_value := 0;
  ELSE
    SELECT coalesce(sum(a.contacts), 0)::int INTO v_value
    FROM public.assisted_contacts_by_entry_path(q_start, q_end) a
    JOIN public.page_taxonomy pt ON pt.path = a.entry_path AND pt.category = 'ressource';
  END IF;

  SELECT NULLIF(btrim(value), '')::int INTO v_target
  FROM public.cooked_config WHERE key = 'objectif_assistes_trimestre';

  INSERT INTO public.dashboard_assisted_quarter_snapshot
    (quarter, quarter_start, quarter_end, value, target, refreshed_at)
  VALUES (q_label, q_start, q_end, v_value, v_target, now())
  ON CONFLICT (quarter) DO UPDATE SET
    quarter_start = excluded.quarter_start,
    quarter_end   = excluded.quarter_end,
    value         = excluded.value,
    target        = excluded.target,
    refreshed_at  = excluded.refreshed_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.refresh_dashboard_assisted_quarter() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_assisted_quarter() TO service_role;

CREATE OR REPLACE FUNCTION public.dashboard_assisted_quarter()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '5s'
AS $function$
  SELECT jsonb_build_object(
    'quarter', coalesce(s.quarter,
      'T' || extract(quarter FROM public.paris_today())::int || ' ' || extract(year FROM public.paris_today())::int),
    'quarter_start', coalesce(s.quarter_start, date_trunc('quarter', public.paris_today())::date),
    'value', coalesce(s.value, 0),
    'target', s.target
  )
  FROM (SELECT 1) dummy
  LEFT JOIN public.dashboard_assisted_quarter_snapshot s
    ON s.quarter = 'T' || extract(quarter FROM public.paris_today())::int
                 || ' ' || extract(year FROM public.paris_today())::int;
$function$;

COMMENT ON FUNCTION public.dashboard_assisted_quarter() IS
  'Lit dashboard_assisted_quarter_snapshot (T-08). Ne recalcule plus le trimestre à l''affichage.';


