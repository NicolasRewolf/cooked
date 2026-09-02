-- T-12 : cooked_ci_ro a SELECT sur cron.job mais 0 ligne visible (propriétaire pg_cron).
-- Lecteur SECURITY DEFINER minimal, réservé au rôle CI + service_role.
CREATE OR REPLACE FUNCTION public.cooked_ci_cron_jobs()
RETURNS TABLE(jobname text, schedule text, active boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'cron', 'public', 'pg_catalog'
AS $function$
  SELECT j.jobname::text, j.schedule::text, j.active
  FROM cron.job j
  ORDER BY 1;
$function$;

REVOKE ALL ON FUNCTION public.cooked_ci_cron_jobs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_ci_cron_jobs() TO cooked_ci_ro, service_role;

COMMENT ON FUNCTION public.cooked_ci_cron_jobs() IS
  'T-12 mission 02/09/2026 : liste des jobs pg_cron pour la CI lecture seule (cooked_ci_ro).';
