-- T-11 correctif (mission 02/09/2026, #112) — alert_rule_gsc_ingest_missed : faux positif entre 22:00 et
-- 24:00 UTC. La garde horaire est en UTC (« ne juger qu'à partir de 12:00 UTC ») mais la comparaison de jour
-- se faisait en jour PARIS : à 22:15 UTC le 03/09 (00:15 Paris le 04/09), paris_today() valait déjà le 04/09
-- et l'ingestion du 03/09 12:35 Paris était déclarée « absente » (alerte #140, 04/09/2026 00:15 Paris).
-- Le cron GitHub est en UTC : le jour de référence de cette règle est le jour UTC, comme sa garde.
CREATE OR REPLACE FUNCTION public.alert_rule_gsc_ingest_missed()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last_ingest timestamptz;
BEGIN
  -- Le cron GitHub est planifié 06:00 UTC et dérive de +4 à +12 h (constat e-02) :
  -- on ne juge qu'à partir de 12:00 UTC, heure du cron (UTC), pas heure Paris.
  IF (now() AT TIME ZONE 'UTC')::time < time '12:00' THEN
    RETURN;
  END IF;
  SELECT max(g.ingested_at) INTO v_last_ingest FROM public.gsc_path_daily g;
  -- Jour UTC des deux côtés (le cron vit en UTC) — un jour Paris ici sonnait à tort de 22:00 à 24:00 UTC.
  IF (v_last_ingest AT TIME ZONE 'UTC')::date IS DISTINCT FROM (now() AT TIME ZONE 'UTC')::date THEN
    kind := 'gsc_ingest_missed'; severity := 'warn';
    detail := format(
      'Ingestion GSC en retard : attendue à 06:00 UTC, toujours absente à %s UTC (dernière : %s). '
      'Si rien à 18:00 UTC : gh workflow run gsc-daily-ingest.yml. '
      'L''aval (cooked-refresh-after-gsc) repartira seul à l''heure suivante, jusqu''à 21:00 UTC.',
      to_char(now() AT TIME ZONE 'UTC', 'HH24:MI'),
      coalesce(to_char(v_last_ingest AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI'), 'jamais'));
    RETURN NEXT;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.alert_rule_gsc_ingest_missed() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_gsc_ingest_missed() TO service_role;

-- Le faux positif du 03/09 22:15 UTC est acquitté (l'ingestion du 03/09 a bien eu lieu à 10:35 UTC).
UPDATE public.alerts SET acked = true
WHERE kind = 'gsc_ingest_missed' AND NOT acked
  AND created_at >= timestamptz '2026-09-03 22:00:00+00' AND created_at < timestamptz '2026-09-04 00:00:00+00';
