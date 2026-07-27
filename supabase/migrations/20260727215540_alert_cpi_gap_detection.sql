-- Bloc 0 / A2 — detecter les TROUS de cpi_daily, pas seulement son retard.
--
-- Constat du 27/07/2026 : cpi_daily n'a aucune ligne pour les 20, 21 et 24/07
-- alors que GSC a bien livre ces jours-la (297, 290 et 281 lignes dans
-- gsc_path_daily). Aucune alerte n'a ete levee, parce que alert_rule_cpi_stale
-- ne regarde que max(day) : des que le dernier jour est frais, un trou au
-- milieu de la serie est invisible.
--
-- Causes des trous, toutes deux deja corrigees :
--   * 20-21/07 : cooked-refresh-after-gsc (jobid 45) mourait a 120 s sur
--     "CREATE TEMP TABLE", et l'ancien job CPI (jobid 14) a 600 s sur
--     cooked_page_index. Regle par la migration 20260722133207.
--   * 24/07    : "No space left on device" toutes les heures de 11 h a 22 h.
--     Regle par le VACUUM FULL du 26/07 04:00.
--
-- Un jour de CPI non calcule est perdu definitivement (cooked_page_index lit
-- now()). Il faut donc le voir passer, meme si on ne peut pas le rattraper :
-- c'est le signal qu'un incident a eu lieu et que cpi_movers compare, ce
-- jour-la, contre un snapshot plus ancien qu'il ne le croit.
--
-- Fenetre volontairement courte (7 jours) : l'alerte est informative et non
-- corrigeable, elle doit donc s'eteindre d'elle-meme plutot que s'accumuler.

CREATE OR REPLACE FUNCTION public.alert_rule_cpi_stale()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last    date;
  v_lag     int;
  v_debut   date;
  v_fin     date;
  v_trous   date[];
  v_premier date;
BEGIN
  SELECT max(day), min(day) INTO v_last, v_premier FROM public.cpi_daily;

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

  -- Trous au milieu de la série : invisibles au test de retard ci-dessus.
  v_debut := greatest(v_premier, public.paris_today() - 7);
  v_fin   := public.paris_today() - 1;

  SELECT array_agg(s.d ORDER BY s.d) INTO v_trous
  FROM (
    SELECT (v_debut + i)::date AS d
    FROM generate_series(0, greatest(v_fin - v_debut, -1)) AS i
  ) s
  WHERE NOT EXISTS (SELECT 1 FROM public.cpi_daily c WHERE c.day = s.d);

  IF v_trous IS NOT NULL AND cardinality(v_trous) > 0 THEN
    RETURN QUERY SELECT
      'cpi_gap'::text,
      'warn'::text,
      ('cpi_daily : ' || cardinality(v_trous) || ' jour(s) manquant(s) sur les 7 derniers — '
       || (SELECT string_agg(to_char(d, 'DD/MM'), ', ') FROM unnest(v_trous) d)
       || '. Jours perdus définitivement ; cpi_movers compare contre un snapshot '
       || 'plus ancien que prévu sur ces dates. Vérifier cron.job_run_details.')::text;
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.alert_rule_cpi_stale() IS
  'Deux regles : cpi_stale (retard du dernier jour, critical) et cpi_gap '
  '(jours manquants au milieu des 7 derniers, warn). La seconde a ete ajoutee '
  'le 27/07/2026 apres que les trous des 20, 21 et 24/07 soient passes '
  'inapercus — max(day) etant frais, le retard ne les voyait pas.';
