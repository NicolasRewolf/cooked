-- Contrat C6 : alert_rule_cpi_stale() passe par le foyer paris_today().
--
-- La version posée par 20260725070537 calculait le retard avec un cast Paris
-- brut :
--     v_lag := (now() AT TIME ZONE 'Europe/Paris')::date - v_last;
--
-- C'est précisément ce que le garde CI `scripts/check_migration_paris_date.py`
-- (contrat C6) interdit dans les migrations nouvelles : la règle « fenêtre
-- Paris » doit vivre à UN seul endroit, sinon elle ne tient que par la
-- discipline et un oubli devient un bug silencieux (« perte de 2 h chaque
-- matin », survenu le 18/05/2026).
--
-- Le garde a attrapé la faute avant le commit. Correction à l'identique
-- sémantique : paris_today() renvoie exactement la même valeur.

CREATE OR REPLACE FUNCTION public.alert_rule_cpi_stale()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last date;
  v_lag  int;
BEGIN
  SELECT max(day) INTO v_last FROM public.cpi_daily;

  IF v_last IS NULL THEN
    RETURN QUERY SELECT 'cpi_stale'::text, 'critical'::text,
      'cpi_daily est vide — le snapshot CPI n a jamais tourné.'::text;
    RETURN;
  END IF;

  v_lag := public.paris_today() - v_last;  -- foyer unique, cf. contrat C6

  IF v_lag >= 2 THEN
    RETURN QUERY SELECT
      'cpi_stale'::text,
      'critical'::text,
      ('cpi_daily s arrête au ' || to_char(v_last, 'DD/MM/YYYY') || ' (' || v_lag
       || ' jours de retard) — un jour de CPI non calculé est perdu définitivement.')::text;
  END IF;
END;
$function$;
