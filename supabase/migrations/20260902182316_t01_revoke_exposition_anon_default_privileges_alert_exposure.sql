-- T-01 (mission 02/09/2026, issue #102) — constats h-01 / o-02 / o-03 de docs/mission-2026-09-02/01-audit.md
-- 1. Révocation des trois objets exposés au rôle anon / authenticated via PostgREST.
REVOKE ALL ON FUNCTION public.rpc_contract_check(text, text, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.page_reads(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.page_reads(integer) FROM PUBLIC, anon, authenticated;

ALTER VIEW public.cpi_capture_perdue SET (security_invoker = true);
REVOKE ALL ON public.cpi_capture_perdue FROM PUBLIC, anon, authenticated;
-- Uniformisation : les deux autres vues sans security_invoker (aucun grant anon aujourd'hui).
ALTER VIEW public.cpi_movers SET (security_invoker = true);
REVOKE ALL ON public.cpi_movers FROM PUBLIC, anon, authenticated;
ALTER VIEW public.events_no_bots SET (security_invoker = true);
REVOKE ALL ON public.events_no_bots FROM PUBLIC, anon, authenticated;

-- 2. Cause racine (S1) : toute NOUVELLE fonction de public recevait EXECUTE pour PUBLIC (acldefault) ET pour
--    anon/authenticated (pg_default_acl posé par Supabase, rôles postgres et supabase_admin). service_role conserve le sien.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
DO $$
BEGIN
  BEGIN
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'default privileges de supabase_admin non modifiables par postgres : % — compensé par alert_rule_exposure()', SQLERRM;
  END;
END $$;

-- 3. Invariant I1 : règle d'alerte découverte par cooked_alerts_refresh() (LIKE 'alert\_rule\_%', 0 argument).
--    Liste toute fonction SECURITY DEFINER exécutable par anon/authenticated et toute vue sans security_invoker
--    lisible par anon/authenticated. critical → push ntfy.
CREATE OR REPLACE FUNCTION public.alert_rule_exposure()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_fn text;
  v_vw text;
BEGIN
  SELECT string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ' ORDER BY p.proname)
    INTO v_fn
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND (has_function_privilege('anon', p.oid, 'EXECUTE')
         OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname)
    INTO v_vw
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'v'
    AND NOT coalesce((SELECT bool_or(opt = 'security_invoker=true') FROM unnest(c.reloptions) AS opt), false)
    AND (has_table_privilege('anon', c.oid, 'SELECT')
         OR has_table_privilege('authenticated', c.oid, 'SELECT'));

  IF v_fn IS NOT NULL THEN
    kind := 'exposure_function'; severity := 'critical';
    detail := 'Fonction(s) SECURITY DEFINER exécutable(s) par anon/authenticated : ' || v_fn
              || ' — REVOKE ALL ON FUNCTION … FROM PUBLIC, anon, authenticated (règle I1, mission 02/09/2026).';
    RETURN NEXT;
  END IF;

  IF v_vw IS NOT NULL THEN
    kind := 'exposure_view'; severity := 'critical';
    detail := 'Vue(s) sans security_invoker lisible(s) par anon/authenticated : ' || v_vw
              || ' — ALTER VIEW … SET (security_invoker = true) + REVOKE (règle I1, mission 02/09/2026).';
    RETURN NEXT;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.alert_rule_exposure() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.alert_rule_exposure() IS
  'Invariant I1 (mission 02/09/2026) : aucune fonction SECURITY DEFINER exécutable par anon/authenticated, aucune vue sans security_invoker lisible par anon/authenticated. 0 ligne attendue.';
