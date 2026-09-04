-- Décision Nicolas 04/09/2026 : rétention events = 13 mois (CNIL audience exemptée), plus 400 jours.
-- Plus ancien event 06/05/2026 → première purge utile ≈ 06/2027. Aucune ligne à supprimer aujourd'hui.

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

  if v_deleted > 1000 then
    perform pg_advisory_lock(hashtext('purge_old_events_vacuum'));
    perform pg_advisory_unlock(hashtext('purge_old_events_vacuum'));
  end if;

  v_after := pg_size_pretty(pg_total_relation_size('public.events'));

  return query select
    v_deleted,
    v_before,
    v_after,
    extract(epoch from (clock_timestamp() - v_start)) * 1000;
end;
$function$;

COMMENT ON FUNCTION public.purge_old_events() IS
  'Rétention CNIL 13 mois (décision Nicolas 04/09/2026). Supprime events.occurred_at < now() - 13 months. Premier run utile ≈ 06/2027.';

REVOKE ALL ON FUNCTION public.purge_old_events() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_events() TO postgres, service_role;
