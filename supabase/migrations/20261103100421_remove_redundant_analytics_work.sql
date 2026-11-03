-- Retire trois travaux sans effet utile, sans changer les métriques.
-- Les contacts assistés gardent leurs fenêtres Paris J-1 et leur attribution.
-- DFS garde le classement par clics 90 jours (comptages non négatifs).
-- La rétention des événements reste strictement de 13 mois ; seule une prise
-- puis libération de verrou sans opération protégée est retirée.

CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date;
BEGIN
  IF p_window IS NOT NULL AND p_window NOT IN ('rolling_28','rolling_90') THEN
    RAISE EXCEPTION 'refresh_dashboard_resources_assisted: unsupported window %', p_window;
  END IF;
  DELETE FROM public.dashboard_resources_assisted_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    SELECT b.n_start, b.n_end, b.prev_start, b.prev_end
      INTO lns, lne, lps, lpe
    FROM public.cooked_period_bounds(w, 'live_j1') b;

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

CREATE OR REPLACE FUNCTION public.dfs_keywords_to_sync(limit_n integer DEFAULT 500)
RETURNS TABLE(keyword text, clicks_total bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT q.query AS keyword, SUM(q.clicks)::bigint AS clicks_total
  FROM public.gsc_query_daily q
  WHERE q.day BETWEEN public.paris_today()-89 AND public.paris_today()
    AND q.query IS NOT NULL AND q.query <> ''
  GROUP BY q.query
  ORDER BY SUM(q.clicks) DESC
  LIMIT limit_n;
$function$;

CREATE OR REPLACE FUNCTION public.purge_old_events()
 RETURNS TABLE(deleted_rows bigint, size_before text, size_after text, duration_ms numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_start   timestamptz := clock_timestamp();
  v_before  text;
  v_after   text;
  v_deleted bigint;
begin
  v_before := pg_size_pretty(pg_total_relation_size('public.events'));

  delete from public.events
  where occurred_at < now() - interval '13 months';

  get diagnostics v_deleted = row_count;

  v_after := pg_size_pretty(pg_total_relation_size('public.events'));

  return query select
    v_deleted,
    v_before,
    v_after,
    extract(epoch from (clock_timestamp() - v_start)) * 1000;
end;
$function$;

REVOKE ALL ON FUNCTION public.refresh_dashboard_resources_assisted(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_resources_assisted(text) TO service_role;
REVOKE ALL ON FUNCTION public.dfs_keywords_to_sync(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dfs_keywords_to_sync(integer) TO service_role;
REVOKE ALL ON FUNCTION public.purge_old_events() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_events() TO service_role;
