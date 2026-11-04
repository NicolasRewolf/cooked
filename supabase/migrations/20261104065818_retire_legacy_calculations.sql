-- Les anciennes lectures restent disponibles avec leurs dernières dates.
-- Données, versions et historiques conservés. Seuls producteurs et contrôles
-- retirés sont supprimés ; chaque DROP est RESTRICT, jamais CASCADE.
SELECT cron.alter_job(jobid, active := false) FROM cron.job WHERE jobname IN (
  'cooked-refresh-after-gsc','cpi-calibration-monthly','math-refresh-snapshots-weekly','refresh_seo_url_snapshot');

UPDATE public.freshness_contract SET enabled=false WHERE source IN (
  'cpi_daily','cpi_calibration_checks','dashboard_resources_snapshot','dfs_keyword_volume','math_visit_sequences_snapshot','seo_url_snapshot');

-- Les alertes de ces calculs cessent d’avoir une échéance attendue.
-- Acquittement limité aux familles retirées, sans toucher aux alertes sources.
UPDATE public.alerts SET acked=true
WHERE NOT acked AND (
  kind IN ('cpi_drop','cpi_calibration','refresh_budget','refresh_after_gsc_stale')
  OR kind IN ('cpi_daily_stale','cpi_daily_gap','cpi_daily_contract_failed',
    'cpi_calibration_checks_stale','cpi_calibration_checks_gap','cpi_calibration_checks_contract_failed',
    'dashboard_resources_snapshot_stale','dashboard_resources_snapshot_gap','dashboard_resources_snapshot_contract_failed',
    'dfs_keyword_volume_stale','dfs_keyword_volume_gap','dfs_keyword_volume_contract_failed',
    'math_visit_sequences_snapshot_stale','math_visit_sequences_snapshot_gap','math_visit_sequences_snapshot_contract_failed',
    'seo_url_snapshot_stale','seo_url_snapshot_gap','seo_url_snapshot_contract_failed')
  OR kind IN ('refresh_step_failed_cooked_cpi_snapshot',
    'refresh_step_failed_refresh_dashboard_snapshots',
    'refresh_step_failed_refresh_dashboard_expertises_snapshots',
    'refresh_step_failed_refresh_dashboard_resources_assisted',
    'refresh_step_failed_refresh_dashboard_assisted_quarter')
);

CREATE OR REPLACE FUNCTION public.alert_rule_gsc_ingest_missed()
RETURNS TABLE(kind text,severity text,detail text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog
AS $function$
DECLARE b public.gsc_ingest_batches%ROWTYPE; last_complete timestamptz;
BEGIN
  SELECT * INTO b FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF b.status IN ('running','failed') AND b.started_at < now()-interval '3 hours' THEN
    kind:='gsc_ingest_incomplete'; severity:='critical';
    detail:='Le dernier lot GSC est incomplet depuis plus de trois heures. Reprendre les trois tables avant lecture.';
    RETURN NEXT;
  END IF;
  SELECT max(completed_at) INTO last_complete FROM public.gsc_ingest_batches WHERE status='completed';
  IF (now() AT TIME ZONE 'UTC')::time >= time '12:00'
     AND (last_complete AT TIME ZONE 'UTC')::date IS DISTINCT FROM (now() AT TIME ZONE 'UTC')::date THEN
    kind:='gsc_ingest_missed'; severity:='warn';
    detail:='Aucun lot GSC complet du jour UTC après midi. Vérifier le workflow gsc-daily-ingest et sa reprise.';
    RETURN NEXT;
  END IF;
END;
$function$;

-- La santé porte sur les sources actives. Les colonnes historiques restent
-- informatives pour les appelants existants ; elles ne créent plus de panne.
CREATE OR REPLACE FUNCTION public.refresh_pipeline_health()
RETURNS TABLE(status text,snapshot_refreshed_at timestamptz,snapshot_age_hours numeric,
  cron_last_status text,cron_last_run timestamptz,cron_age_hours numeric,
  last_event_at timestamptz,last_event_age_minutes numeric,events_last_60min bigint,
  gsc_last_day date,gsc_data_age_days numeric,gsc_last_ingest timestamptz,
  gsc_ingest_age_hours numeric,dfs_last_synced_at timestamptz,dfs_row_count bigint,
  dfs_sync_age_hours numeric,issues text[])
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO public,cron,pg_catalog
AS $function$
DECLARE b public.gsc_ingest_batches%ROWTYPE;
BEGIN
  status:='healthy'; issues:=ARRAY[]::text[];
  SELECT max(s.refreshed_at) INTO snapshot_refreshed_at FROM public.seo_url_snapshot s;
  snapshot_age_hours:=round(extract(epoch FROM now()-snapshot_refreshed_at)/3600,2);
  cron_last_status:='suspended';
  SELECT d.start_time INTO cron_last_run FROM cron.job j
    JOIN cron.job_run_details d ON d.jobid=j.jobid
    WHERE j.jobname='refresh_seo_url_snapshot' ORDER BY d.start_time DESC LIMIT 1;
  cron_age_hours:=round(extract(epoch FROM now()-cron_last_run)/3600,2);
  SELECT max(e.received_at) INTO last_event_at FROM public.events e;
  last_event_age_minutes:=round(extract(epoch FROM now()-last_event_at)/60,1);
  SELECT count(*) INTO events_last_60min FROM public.events e
    WHERE e.received_at >= now()-interval '60 minutes';
  IF last_event_at IS NULL OR last_event_age_minutes>360 THEN
    issues:=issues||'ingestion_stopped'::text; status:='critical';
  END IF;
  SELECT max(g.day) INTO gsc_last_day FROM public.gsc_path_daily g;
  gsc_data_age_days:=(public.paris_today()-gsc_last_day)::numeric;
  SELECT max(g.completed_at) INTO gsc_last_ingest FROM public.gsc_ingest_batches g WHERE g.status='completed';
  gsc_ingest_age_hours:=round(extract(epoch FROM now()-gsc_last_ingest)/3600,2);
  SELECT * INTO b FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF gsc_last_day IS NULL OR gsc_data_age_days>10
     OR gsc_last_ingest IS NULL OR gsc_ingest_age_hours>72 THEN
    issues:=issues||'gsc_source_stale'::text; status:='critical';
  ELSIF gsc_data_age_days>6 OR gsc_ingest_age_hours>30 THEN
    issues:=issues||'gsc_source_delayed'::text;
    IF status='healthy' THEN status:='degraded'; END IF;
  END IF;
  IF b.status IN ('running','failed') AND b.started_at<now()-interval '3 hours' THEN
    issues:=issues||'gsc_ingest_incomplete'::text; status:='critical';
  END IF;
  SELECT max(d.last_synced_at),count(*) INTO dfs_last_synced_at,dfs_row_count FROM public.dfs_keyword_volume d;
  dfs_sync_age_hours:=round(extract(epoch FROM now()-dfs_last_synced_at)/3600,2);
  RETURN NEXT;
END;
$function$;

-- Le catalogue contient l’historique des anciens contrôles. La lecture de santé
-- ne présente que le jeu actif, y compris une absence totale d’exécution.
CREATE OR REPLACE FUNCTION public.latest_rpc_health()
RETURNS TABLE(rpc_name text,status text,detail text,rows_returned bigint,
  duration_ms numeric,checked_at timestamptz,age_minutes numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog
AS $function$
  SELECT expected.name,
    CASE WHEN h.checked_at IS NULL THEN 'missing'
         WHEN h.checked_at<now()-interval '48 hours' THEN 'stale' ELSE h.status END,
    CASE WHEN h.checked_at IS NULL THEN 'Contrôle du socle jamais exécuté'
         WHEN h.checked_at<now()-interval '48 hours' THEN 'Contrôle du socle à relancer'
         ELSE h.detail END,
    h.rows_returned,h.duration_ms,h.checked_at,
    round(extract(epoch FROM now()-h.checked_at)/60,1)
  FROM (VALUES('core_visit_counts'),('core_unattributed_contacts'),('core_canonical_path'),
    ('core_gsc_batch'),('core_identity_fresh'),('core_private_surface')) expected(name)
  LEFT JOIN LATERAL (
    SELECT r.* FROM public.rpc_health r WHERE r.rpc_name=expected.name
    ORDER BY r.checked_at DESC LIMIT 1
  ) h ON true;
$function$;

-- Les sondes lourdes passent dans l’exécution nocturne ; l’alerte horaire lit
-- leurs résultats et conserve les échecs réels ainsi que l’absence de contrôle.
CREATE OR REPLACE FUNCTION public.alert_rule_rpc_health()
RETURNS TABLE(kind text,severity text,detail text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public,pg_catalog
AS $function$
  SELECT 'rpc_failed_'||h.rpc_name,'critical'::text,
    'Contrôle '||h.rpc_name||' : '||h.status
  FROM public.latest_rpc_health() h WHERE h.status IS DISTINCT FROM 'ok';
$function$;

CREATE OR REPLACE FUNCTION public.run_rpc_contract_tests()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO public,pg_catalog SET statement_timeout TO '120s'
AS $function$
DECLARE t record;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('core_visit_counts',
      $q$SELECT count(*) FROM public.page_visits(public.paris_today()-2,public.paris_today()-1)
        WHERE row_kind='page' AND (phone_visits>contact_visits OR form_visits>contact_visits
          OR contact_visits>entries OR entries>visits OR contact_visits>phone_visits+form_visits
          OR contact_visits<0 OR entries<0 OR visits<0)$q$,0),
    ('core_unattributed_contacts',
      $q$WITH visit_events AS MATERIALIZED (
           SELECT * FROM public.cooked_visit_events(public.paris_today()-2,public.paris_today()-1)),
         sources AS (
           SELECT count(*) AS n FROM public.events_human e
           WHERE e.occurred_at>=public.cooked_paris_ts_start(public.paris_today()-2)
             AND e.occurred_at<public.cooked_paris_ts_start(public.paris_today())
             AND (e.name='cta_phone_click'
               OR (e.name='form_submit' AND public.form_submit_counts_as_macro(e.props))))
         SELECT abs((SELECT count(*) FROM visit_events WHERE counts_as_macro)-(SELECT n FROM sources))$q$,0),
    ('core_canonical_path',
      $q$SELECT count(*) FROM (VALUES('/post/%C3%A9cole/','/post/école'),('/','/')) v(input,expected)
         WHERE public.canonical_path(v.input) IS DISTINCT FROM v.expected$q$,0),
    ('core_gsc_batch',
      $q$SELECT CASE WHEN EXISTS(
          SELECT 1 FROM public.gsc_ingest_batches WHERE status='completed'
            AND completed_at>now()-interval '48 hours') THEN 0 ELSE 1 END$q$,0),
    ('core_identity_fresh',
      $q$SELECT CASE WHEN EXISTS(
          SELECT 1 FROM public.cooked_config WHERE key='identity_stitch_refreshed_at'
            AND value::timestamptz>now()-interval '30 hours') THEN 0 ELSE 1 END$q$,0),
    ('core_private_surface',
      $q$SELECT count(*) FROM public.alert_rule_exposure()$q$,0)
  ) tests(name,sql,expected) LOOP
    PERFORM public.rpc_contract_check(t.name,t.sql,NULL,t.expected);
  END LOOP;
  DELETE FROM public.rpc_health WHERE checked_at<now()-interval '90 days';
END;
$function$;

-- Exécution après la couture quotidienne.
SELECT cron.alter_job(jobid, schedule := '50 3 * * *') FROM cron.job WHERE jobname='run_rpc_contract_tests';

REVOKE ALL ON FUNCTION public.alert_rule_gsc_ingest_missed() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.refresh_pipeline_health() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.latest_rpc_health() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_rpc_health() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.run_rpc_contract_tests() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_gsc_ingest_missed() TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_pipeline_health() TO service_role;
GRANT EXECUTE ON FUNCTION public.latest_rpc_health() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_rpc_health() TO service_role;
GRANT EXECUTE ON FUNCTION public.run_rpc_contract_tests() TO service_role;

-- Les signatures de lecture du dashboard et les vues de l’historique restent.
DROP FUNCTION IF EXISTS public.alert_rule_cpi_calibration();
DROP FUNCTION IF EXISTS public.alert_rule_cpi_drop();
DROP FUNCTION IF EXISTS public.alert_rule_refresh_after_gsc_stale();
DROP FUNCTION IF EXISTS public.alert_rule_refresh_budget();
DROP FUNCTION IF EXISTS public.conversions_leaderboard(p_since date);
DROP FUNCTION IF EXISTS public.cooked_cpi_snapshot();
DROP FUNCTION IF EXISTS public.cooked_page_index(p_days integer);
DROP FUNCTION IF EXISTS public.cooked_refresh_after_gsc();
DROP FUNCTION IF EXISTS public.cooked_refresh_after_gsc_pending();
DROP FUNCTION IF EXISTS public.cooked_weekly_conversions_snapshot(p_week_start date);
DROP FUNCTION IF EXISTS public.cpi_calibration_check();
DROP FUNCTION IF EXISTS public.math_internal_edges(days_back integer);
DROP FUNCTION IF EXISTS public.math_refresh_snapshots(p_window_days integer);
DROP FUNCTION IF EXISTS public.math_visit_sequences(days_back integer);
DROP FUNCTION IF EXISTS public.refresh_dashboard_assisted_quarter();
DROP FUNCTION IF EXISTS public.refresh_dashboard_expertises_snapshots(p_window text);
DROP FUNCTION IF EXISTS public.refresh_dashboard_resources_assisted(p_window text);
DROP FUNCTION IF EXISTS public.refresh_dashboard_snapshots(p_window text);
DROP FUNCTION IF EXISTS public.refresh_seo_url_snapshot();
DROP FUNCTION IF EXISTS public.site_seo_funnel(period_kind text);
DROP FUNCTION IF EXISTS public.weekly_conversions_report(p_week_start date);
DROP FUNCTION IF EXISTS public.gsc_top_queries_for_path(target_path text, days_back integer, max_rows integer);
DROP FUNCTION IF EXISTS public.macro_contacts_by_path(days_back integer);
