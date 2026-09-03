-- T-17 (mission 02/09/2026, #118) — détection d'un contact macro sans amont (a-08, a-04 plancher).
-- Le garde d'origine du proxy Velo est forgeable par en-tête et il n'y a pas de rate-limit : un
-- injecteur pourrait poser des cta_phone_click. Un verrou (HMAC par event) attend le loader tracker
-- (décision §7.1) ; d'ici là, une DÉTECTION : un contact sans pageview antérieure dans la même
-- session est anormal pour un vrai visiteur.
--
-- Mesure avant (04/09/2026 01:10 Paris, events_human 28 j, hors server) :
--   cta_phone_click 128 → 0 sans amont ; cta_booking_click 331 → 4 sans amont (1,2 %).
-- Seuils : ≥ 3 contacts sans amont sur 24 h → warn ; ≥ 10 → critical (push ntfy).

CREATE OR REPLACE FUNCTION public.alert_rule_contact_sans_amont()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_n     bigint;
  v_tot   bigint;
  v_paths text;
BEGIN
  WITH c AS (
    SELECT e.session_id, e.occurred_at, e.name, e.path
    FROM public.events_human e
    WHERE e.name IN ('cta_phone_click', 'cta_booking_click')
      AND e.occurred_at > now() - interval '24 hours'
      AND e.device_type IS DISTINCT FROM 'server'
  ), j AS (
    SELECT c.*,
           EXISTS (SELECT 1 FROM public.events_human p
                   WHERE p.session_id = c.session_id AND p.name = 'pageview'
                     AND p.occurred_at <= c.occurred_at) AS amont
    FROM c
  )
  SELECT count(*), count(*) FILTER (WHERE NOT amont),
         string_agg(DISTINCT name || ' ' || coalesce(path, '?'), ', ') FILTER (WHERE NOT amont)
    INTO v_tot, v_n, v_paths
  FROM j;

  IF v_n >= 3 THEN
    kind := 'contact_sans_amont';
    severity := CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END;
    detail := format('%s contact(s) macro sur %s en 24 h sans pageview antérieure dans la même session (28 j : 0/128 phone, 4/331 booking). Injection possible via /_functions/track (garde d''origine forgeable, T-17) ou tracker cassé (pageview non émise) : vérifier user_agent / referrer des sessions concernées avant de livrer un chiffre de contacts. Concernés : %s',
                     v_n, v_tot, left(coalesce(v_paths, ''), 300));
    RETURN NEXT;
  END IF;
END $function$;

REVOKE ALL ON FUNCTION public.alert_rule_contact_sans_amont() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_contact_sans_amont() TO service_role;
