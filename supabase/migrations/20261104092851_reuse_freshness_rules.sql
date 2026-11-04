-- Le résumé garde sa portée : réception, données GSC par page et lots GSC.
-- Les seuils de fraîcheur viennent du registre ; le lot interrompu de sa règle.
CREATE OR REPLACE FUNCTION public.refresh_pipeline_health()
 RETURNS TABLE(status text, last_event_at timestamp with time zone, last_event_age_minutes numeric, events_last_60min bigint, gsc_last_day date, gsc_data_age_days numeric, gsc_last_ingest timestamp with time zone, gsc_ingest_age_hours numeric, issues text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE c public.freshness_contract%ROWTYPE;
BEGIN
  status:='healthy'; issues:=ARRAY[]::text[];
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
  SELECT * INTO c FROM public.freshness_contract WHERE source='gsc_path_daily' AND enabled;
  IF c.source IS NULL THEN
    issues:=issues||'gsc_freshness_contract_unavailable'::text; status:='critical';
  END IF;
  IF gsc_last_day IS NULL OR gsc_data_age_days>c.critical_after_days
     OR gsc_last_ingest IS NULL OR gsc_ingest_age_hours>72 THEN
    issues:=issues||'gsc_source_stale'::text; status:='critical';
  ELSIF gsc_data_age_days>c.warn_after_days OR gsc_ingest_age_hours>30 THEN
    issues:=issues||'gsc_source_delayed'::text;
    IF status='healthy' THEN status:='degraded'; END IF;
  END IF;
  IF EXISTS (SELECT 1 FROM public.alert_rule_gsc_ingest_missed() WHERE kind='gsc_ingest_incomplete') THEN
    issues:=issues||'gsc_ingest_incomplete'::text; status:='critical';
  END IF;
  RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.refresh_pipeline_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_pipeline_health() TO service_role;

-- Les indications de réparation suivent les flux conservés le 04/11/2026.
-- Aucun seuil, source SQL ni fenêtre de contrôle ne change.
UPDATE public.freshness_contract SET repair_hint =
  'Vérifier le workflow gsc-daily-ingest et le dernier lot gsc_ingest_batches. Relancer python3 scripts/gsc_ingest.py all --daily après arrêt confirmé de tout ancien processus ; le lot doit terminer ses deux grains, pages et requêtes par page.'
WHERE source IN ('gsc_path_daily', 'gsc_query_page_daily');

UPDATE public.freshness_contract SET repair_hint =
  'Vérifier l’automatisation Wix vers form-webhook puis lancer le workflow wix-forms-reconcile. Le rapprochement signale les écarts sans réimporter de soumissions.'
WHERE source = 'form_submit';
