-- Funnel intent RDV → formulaire (page /honoraires-rendez-vous).
CREATE OR REPLACE FUNCTION public.dashboard_honoraires_funnel(period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  booking_sessions bigint,
  honoraires_sessions bigint,
  booking_then_honoraires bigint,
  forms_after_booking_6h bigint,
  forms_on_honoraires bigint,
  forms_macro_total bigint,
  rate_booking_to_form numeric,
  cooked_start date,
  cooked_end date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  b record;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, 'live_j1');

  RETURN QUERY
  WITH ev AS (
    SELECT e.*
    FROM public.events_human e
    WHERE public.paris_date(e.occurred_at) BETWEEN b.n_start AND b.n_end
  ),
  book AS (
    SELECT DISTINCT e.session_id, min(e.occurred_at) AS t0
    FROM ev e
    WHERE e.name = 'cta_booking_click'
      AND e.device_type IS DISTINCT FROM 'server'
    GROUP BY e.session_id
  ),
  hon AS (
    SELECT DISTINCT e.session_id
    FROM ev e
    WHERE e.name = 'pageview'
      AND e.path = '/honoraires-rendez-vous'
  ),
  forms AS (
    SELECT
      e.occurred_at AS t,
      e.props->>'cooked_sid' AS sid,
      e.path,
      e.props->>'page_source' AS page_source
    FROM ev e
    WHERE e.name = 'form_submit'
      AND public.form_submit_counts_as_macro(e.props)
  ),
  agg AS (
    SELECT
      (SELECT count(*)::bigint FROM book) AS booking_sessions,
      (SELECT count(*)::bigint FROM hon) AS honoraires_sessions,
      (SELECT count(*)::bigint FROM book bk JOIN hon h ON h.session_id = bk.session_id)
        AS booking_then_honoraires,
      (SELECT count(DISTINCT f.sid)::bigint
         FROM forms f
         JOIN book bk ON bk.session_id = f.sid
        WHERE f.t BETWEEN bk.t0 AND bk.t0 + interval '6 hours')
        AS forms_after_booking_6h,
      (SELECT count(*)::bigint FROM forms f
        WHERE f.path = '/honoraires-rendez-vous'
           OR coalesce(f.page_source, '') ILIKE '%honoraires%')
        AS forms_on_honoraires,
      (SELECT count(*)::bigint FROM forms) AS forms_macro_total
  )
  SELECT
    a.booking_sessions,
    a.honoraires_sessions,
    a.booking_then_honoraires,
    a.forms_after_booking_6h,
    a.forms_on_honoraires,
    a.forms_macro_total,
    CASE WHEN a.booking_sessions > 0
      THEN round((100.0 * a.forms_after_booking_6h / a.booking_sessions)::numeric, 1)
      ELSE NULL END,
    b.n_start,
    b.n_end
  FROM agg a;
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_honoraires_funnel(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_honoraires_funnel(text) TO service_role;

COMMENT ON FUNCTION public.dashboard_honoraires_funnel(text) IS
  'Funnel intent RDV (cta_booking_click) → page /honoraires-rendez-vous → form_submit macro (même session, ≤6 h). Lens live_j1.';
