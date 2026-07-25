-- Récidive du défaut fermé par 20260725062716 (PR #77) : les deux fonctions
-- SECURITY DEFINER créées le matin même par la PR #78 ont été livrées sans
-- REVOKE — relevé par les advisors Supabase le 25/07/2026 (lints
-- anon_security_definer_function_executable). anon pouvait déclencher
-- alert_rule_cron_failed / alert_rule_cpi_stale via /rest/v1/rpc/ (lecture de
-- cron.job_run_details + INSERT dans alerts). Même remède, même motif :
-- seuls les crons (rôle postgres) et service_role sont des appelants
-- légitimes. SECURITY.md:36.

REVOKE ALL ON FUNCTION public.alert_rule_cron_failed() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_cpi_stale()   FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.alert_rule_cron_failed() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_cpi_stale()   TO service_role;
