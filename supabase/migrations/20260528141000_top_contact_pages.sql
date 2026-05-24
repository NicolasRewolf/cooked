-- Pages avec contacts sur la fenêtre — léger pour la home dashboard (évite pages_overview_unified).

CREATE OR REPLACE FUNCTION public.top_contact_pages(
  p_period_kind text DEFAULT 'rolling_28',
  max_rows        integer DEFAULT 10
)
RETURNS TABLE (
  path                  text,
  cooked_contacts       bigint,
  cooked_phone_clicks   bigint,
  cooked_form_submits   bigint,
  gsc_clicks            bigint,
  cooked_sessions       bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind) LIMIT 1
  ),
  mc AS (
    SELECT m.path, m.contacts, m.phone_clicks, m.form_submits
    FROM public.macro_contacts_by_path(
      (SELECT n_start FROM b),
      (SELECT n_end FROM b)
    ) m
    WHERE m.contacts > 0
    ORDER BY m.contacts DESC, m.path
    LIMIT max_rows
  ),
  gsc AS (
    SELECT g.path, sum(g.clicks)::bigint AS clicks_total
    FROM public.gsc_path_daily g
    INNER JOIN mc ON mc.path = g.path
    CROSS JOIN b
    WHERE g.day >= b.n_start AND g.day <= b.n_end
    GROUP BY g.path
  )
  SELECT
    mc.path,
    mc.contacts,
    mc.phone_clicks,
    mc.form_submits,
    coalesce(gsc.clicks_total, 0),
    coalesce(
      CASE
        WHEN lower(trim(coalesce(p_period_kind, 'rolling_28'))) = 'rolling_90'
          THEN s.sessions_90d
        ELSE s.sessions_28d
      END,
      0
    )::bigint
  FROM mc
  LEFT JOIN gsc ON gsc.path = mc.path
  LEFT JOIN public.seo_url_snapshot s ON s.path = mc.path;
$$;

COMMENT ON FUNCTION public.top_contact_pages(text, integer) IS
  'Top pages avec au moins 1 contact macro sur la période (home dashboard).';

REVOKE EXECUTE ON FUNCTION public.top_contact_pages(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.top_contact_pages(text, integer) TO service_role;
