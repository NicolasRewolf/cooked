-- Lecteurs éditoriaux : mêmes comptages, deux périodes closes et requêtes Google.
-- Aucun stockage dérivé ; une seule reconstruction des visites sur les deux périodes.
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
  v_previous_start date;
  v_start_ts timestamptz;
  v_previous_start_ts timestamptz;
  v_result jsonb;
BEGIN
  IF p_days IS NULL OR p_days NOT IN (30, 60, 90) THEN
    RAISE EXCEPTION 'Expected 30, 60 or 90 completed Paris days' USING ERRCODE = '22023';
  END IF;
  v_start := v_today - p_days;
  v_previous_start := v_start - p_days;
  v_start_ts := public.cooked_paris_ts_start(v_start);
  v_previous_start_ts := public.cooked_paris_ts_start(v_previous_start);

  WITH pageviews AS MATERIALIZED (
    -- Les vues restent indépendantes de la reconstruction des visites : les
    -- chemins absents contribuent à la couverture, jamais à une page inventée.
    SELECT e.path, public.paris_date(e.occurred_at) AS day
    FROM public.events_human e
    WHERE e.name = 'pageview'
      AND e.occurred_at >= v_previous_start_ts
      AND e.occurred_at < public.cooked_paris_ts_start(v_today)
  ), raw_counts AS (
    SELECT p.path, count(*) FILTER (WHERE p.day >= v_start) AS views,
      count(*) FILTER (WHERE p.day < v_start) AS previous_views
    FROM pageviews p WHERE nullif(p.path, '') IS NOT NULL
    GROUP BY p.path
  ), counts AS (
    SELECT public.canonical_path(r.path) AS path, sum(r.views)::bigint AS views,
      sum(r.previous_views)::bigint AS previous_views
    FROM raw_counts r
    GROUP BY public.canonical_path(r.path)
  ), visit_events AS MATERIALIZED (
    SELECT event_id, event_name, occurred_at, path, counts_as_macro, visit_id, entry_at, entry_path
    FROM public.cooked_visit_events(v_previous_start, v_today - 1)
  ), entries AS (
    SELECT e.path,
      count(DISTINCT e.visit_id) FILTER (WHERE e.occurred_at >= v_start_ts) AS entries,
      count(DISTINCT e.visit_id) FILTER (WHERE e.occurred_at < v_start_ts) AS previous_entries
    FROM visit_events e WHERE e.event_name = 'pageview' AND e.event_id = e.visit_id
    GROUP BY e.path
  ), cohort_contacts AS (
    SELECT e.entry_path, e.visit_id, e.event_name, e.entry_at >= v_start_ts AS current_period
    FROM visit_events e
    WHERE e.counts_as_macro AND e.entry_at >= v_previous_start_ts
      -- Entrée et action doivent appartenir à la même période. Une entrée
      -- précédente suivie d'un contact actuel ne convertit aucune des deux cohortes.
      AND (e.entry_at >= v_start_ts) = (e.occurred_at >= v_start_ts)
  ), contacts AS (
    SELECT e.entry_path AS path,
      count(DISTINCT e.visit_id) FILTER (WHERE e.current_period AND e.event_name = 'cta_phone_click') AS phone_visits,
      count(DISTINCT e.visit_id) FILTER (WHERE e.current_period AND e.event_name = 'form_submit') AS form_visits,
      count(DISTINCT e.visit_id) FILTER (WHERE e.current_period) AS contact_visits,
      count(DISTINCT e.visit_id) FILTER (WHERE NOT e.current_period AND e.event_name = 'cta_phone_click') AS previous_phone_visits,
      count(DISTINCT e.visit_id) FILTER (WHERE NOT e.current_period AND e.event_name = 'form_submit') AS previous_form_visits,
      count(DISTINCT e.visit_id) FILTER (WHERE NOT e.current_period) AS previous_contact_visits
    FROM cohort_contacts e GROUP BY e.entry_path
  ), coverage AS (
    SELECT count(*) FILTER (WHERE e.event_name = 'cta_phone_click' AND e.occurred_at >= v_start_ts) AS phone,
      count(*) FILTER (WHERE e.event_name = 'form_submit' AND e.occurred_at >= v_start_ts) AS form,
      count(*) FILTER (WHERE e.event_name = 'cta_phone_click' AND e.occurred_at < v_start_ts) AS previous_phone,
      count(*) FILTER (WHERE e.event_name = 'form_submit' AND e.occurred_at < v_start_ts) AS previous_form
    FROM visit_events e WHERE e.visit_id IS NULL AND e.counts_as_macro
  )
  SELECT jsonb_build_object(
    'period_start', v_start,
    'period_end', v_today - 1,
    'expected_days', p_days,
    'observed_days', (SELECT count(DISTINCT p.day)::integer FROM pageviews p WHERE p.day >= v_start),
    'inventory_checked_at', min(t.publication_checked_at),
    'unattributed_phone_events', (SELECT c.phone FROM coverage c),
    'unattributed_form_events', (SELECT c.form FROM coverage c),
    'previous', jsonb_build_object(
      'period_start', v_previous_start,
      'period_end', v_start - 1,
      'observed_days', (SELECT count(DISTINCT p.day)::integer FROM pageviews p WHERE p.day < v_start),
      'unattributed_phone_events', (SELECT c.previous_phone FROM coverage c),
      'unattributed_form_events', (SELECT c.previous_form FROM coverage c)
    ),
    'pages', coalesce(jsonb_agg(jsonb_build_object(
      'path', t.path,
      'page_type', public.cooked_page_type(t.path),
      'category', t.category,
      'views', coalesce(c.views, 0),
      'entries', coalesce(e.entries, 0),
      'phone_visits', coalesce(k.phone_visits, 0),
      'form_visits', coalesce(k.form_visits, 0),
      'contact_visits', coalesce(k.contact_visits, 0),
      'contact_rate_pct', round(100.0 * coalesce(k.contact_visits, 0) / nullif(e.entries, 0), 2),
      'previous', jsonb_build_object(
        'views', coalesce(c.previous_views, 0),
        'entries', coalesce(e.previous_entries, 0),
        'phone_visits', coalesce(k.previous_phone_visits, 0),
        'form_visits', coalesce(k.previous_form_visits, 0),
        'contact_visits', coalesce(k.previous_contact_visits, 0),
        'contact_rate_pct', round(100.0 * coalesce(k.previous_contact_visits, 0) / nullif(e.previous_entries, 0), 2)
      )
    ) ORDER BY coalesce(c.views, 0) DESC, t.path), '[]'::jsonb)
  ) INTO v_result
  FROM public.page_taxonomy t
  LEFT JOIN counts c ON c.path = t.path
  LEFT JOIN entries e ON e.path = t.path
  LEFT JOIN contacts k ON k.path = t.path
  WHERE t.is_published IS TRUE;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.page_query_counts(p_path text, p_days integer DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
SET statement_timeout TO '30s'
AS $function$
DECLARE
  v_path text;
  v_end date;
  v_start date;
  v_previous_start date;
  v_complete_days date[];
  v_result jsonb;
BEGIN
  IF p_days IS NULL OR p_days NOT IN (30, 60, 90) THEN
    RAISE EXCEPTION 'Expected 30, 60 or 90 completed Google days' USING ERRCODE = '22023';
  END IF;
  IF p_path IS NULL OR btrim(p_path) = '' THEN
    RAISE EXCEPTION 'Expected a page path' USING ERRCODE = '22023';
  END IF;
  v_path := public.canonical_path(p_path);

  -- Couverture observée dans les deux grains, y compris avant le registre des lots.
  -- Lorsqu'un lot couvre le jour, son dernier état doit attester les deux grains :
  -- les imports écrivent en place et un lot incomplet peut avoir écrasé les données.
  SELECT array_agg(d.day ORDER BY d.day), max(d.day)
  INTO v_complete_days, v_end
  FROM (SELECT DISTINCT g.day FROM public.gsc_path_daily g
    WHERE g.day < public.paris_today()) d
  WHERE EXISTS (SELECT 1 FROM public.gsc_query_page_daily q WHERE q.day = d.day)
    AND coalesce((SELECT coalesce(b.status = 'completed'
      AND b.row_counts ?& ARRAY['gsc_path_daily', 'gsc_query_page_daily'], false)
      FROM public.gsc_ingest_batches b
      WHERE d.day BETWEEN b.day_start AND b.day_end
      ORDER BY b.batch_no DESC LIMIT 1), true);

  v_start := v_end - p_days + 1;
  v_previous_start := v_start - p_days;
  WITH queries AS (
    SELECT g.query,
      coalesce(sum(g.clicks) FILTER (WHERE g.day >= v_start), 0)::bigint AS clicks,
      coalesce(sum(g.clicks) FILTER (WHERE g.day < v_start), 0)::bigint AS previous_clicks,
      round(sum(g.position * g.impressions) FILTER (WHERE g.day >= v_start)
        / nullif(sum(g.impressions) FILTER (WHERE g.day >= v_start), 0), 2) AS position_avg,
      round(sum(g.position * g.impressions) FILTER (WHERE g.day < v_start)
        / nullif(sum(g.impressions) FILTER (WHERE g.day < v_start), 0), 2) AS previous_position_avg
    FROM public.gsc_query_page_daily g
    WHERE g.path = v_path AND g.day BETWEEN v_previous_start AND v_end
      AND g.day = ANY(v_complete_days)
    GROUP BY g.query
  )
  SELECT jsonb_build_object(
    'path', v_path,
    'period_start', v_start,
    'period_end', v_end,
    'expected_days', p_days,
    'observed_days', (SELECT count(*)::integer FROM unnest(v_complete_days) d(day)
      WHERE d.day BETWEEN v_start AND v_end),
    'previous', jsonb_build_object(
      'period_start', v_previous_start,
      'period_end', v_start - 1,
      'observed_days', (SELECT count(*)::integer FROM unnest(v_complete_days) d(day)
        WHERE d.day BETWEEN v_previous_start AND v_start - 1)
    ),
    'queries', coalesce(jsonb_agg(jsonb_build_object(
      'query', q.query, 'clicks', q.clicks, 'previous_clicks', q.previous_clicks,
      'position_avg', q.position_avg, 'previous_position_avg', q.previous_position_avg
    ) ORDER BY abs(q.clicks - q.previous_clicks) DESC, q.clicks DESC, q.query), '[]'::jsonb)
  ) INTO v_result FROM queries q;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.page_view_counts(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.page_query_counts(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.page_view_counts(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.page_query_counts(text, integer) TO service_role;
NOTIFY pgrst, 'reload schema';

COMMIT;
