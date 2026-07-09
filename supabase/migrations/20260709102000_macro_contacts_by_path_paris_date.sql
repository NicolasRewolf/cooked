-- C6 vague 2 — P2 macro_contacts_by_path : paris_date / paris_today
-- Source unique du chiffre « contacts » (23 consommateurs).

CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(
  start_date date,
  end_date   date
)
RETURNS TABLE (
  path             text,
  phone_clicks     bigint,
  form_submits     bigint,
  contacts         bigint,
  booking_intent   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    e.path,
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint,
    count(*) FILTER (
      WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
    )::bigint,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (
          WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
        )
    )::bigint,
    count(*) FILTER (
      WHERE e.name = 'cta_booking_click' AND e.device_type != 'server'
    )::bigint
  FROM public.events_human e
  WHERE e.path IS NOT NULL
    AND (
      e.name = 'cta_phone_click'
      OR (e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props))
      OR (e.name = 'cta_booking_click' AND e.device_type != 'server')
    )
    AND public.paris_date(e.occurred_at) >= start_date
    AND public.paris_date(e.occurred_at) <= end_date
  GROUP BY e.path;
$$;

CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(days_back integer)
RETURNS TABLE (
  path             text,
  phone_clicks     bigint,
  form_submits     bigint,
  contacts         bigint,
  booking_intent   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT m.*
  FROM public.macro_contacts_by_path(
    public.paris_today() - (days_back - 1),
    public.paris_today()
  ) m;
$$;

REVOKE EXECUTE ON FUNCTION public.macro_contacts_by_path(date, date) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.macro_contacts_by_path(date, date) TO service_role;
REVOKE EXECUTE ON FUNCTION public.macro_contacts_by_path(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.macro_contacts_by_path(integer) TO service_role;
