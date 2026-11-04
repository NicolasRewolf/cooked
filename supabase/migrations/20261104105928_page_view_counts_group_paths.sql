-- Compter les chemins bruts avant de les normaliser : une normalisation par
-- chemin distinct, sans changer les vues, la couverture ou le contrat JSON.
BEGIN;

CREATE OR REPLACE FUNCTION public.page_view_counts(p_days integer DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
SET statement_timeout TO '30s'
AS $function$
DECLARE
  v_today date := public.paris_today();
  v_start date;
  v_result jsonb;
BEGIN
  IF p_days IS NULL OR p_days NOT IN (30, 60, 90) THEN
    RAISE EXCEPTION 'Expected 30, 60 or 90 completed Paris days' USING ERRCODE = '22023';
  END IF;
  v_start := v_today - p_days;

  WITH pageviews AS MATERIALIZED (
    SELECT e.path, public.paris_date(e.occurred_at) AS day
    FROM public.events_human e
    WHERE e.name = 'pageview'
      AND e.occurred_at >= public.cooked_paris_ts_start(v_start)
      AND e.occurred_at < public.cooked_paris_ts_start(v_today)
  ), raw_counts AS (
    SELECT p.path, count(*) AS views
    FROM pageviews p WHERE nullif(p.path, '') IS NOT NULL
    GROUP BY p.path
  ), counts AS (
    SELECT public.canonical_path(r.path) AS path, sum(r.views)::bigint AS views
    FROM raw_counts r
    GROUP BY public.canonical_path(r.path)
  )
  SELECT jsonb_build_object(
    'period_start', v_start,
    'period_end', v_today - 1,
    'expected_days', p_days,
    'observed_days', (SELECT count(DISTINCT p.day)::integer FROM pageviews p),
    'inventory_checked_at', min(t.publication_checked_at),
    'pages', coalesce(jsonb_agg(jsonb_build_object(
      'path', t.path,
      'page_type', public.cooked_page_type(t.path),
      'category', t.category,
      'views', coalesce(c.views, 0)
    ) ORDER BY coalesce(c.views, 0) DESC, t.path), '[]'::jsonb)
  ) INTO v_result
  FROM public.page_taxonomy t LEFT JOIN counts c ON c.path = t.path
  WHERE t.is_published IS TRUE;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.page_view_counts(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.page_view_counts(integer) TO service_role;

COMMIT;
