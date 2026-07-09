-- C2 (09/07/2026) — alertes modulaires : 1 règle = 1 fonction + driver mince.
-- Comportement identique au monolithe 20260702172248 ; test : scripts/c2_alerts_contract.sql

-- ── Règles (retournent 0..n lignes kind/severity/detail) ─────────────────────

CREATE OR REPLACE FUNCTION public.alert_rule_pipeline_dead()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n bigint;
BEGIN
  SELECT count(*) INTO v_n
  FROM public.events
  WHERE received_at > now() - interval '60 minutes';
  IF v_n = 0 THEN
    RETURN QUERY SELECT
      'pipeline_dead'::text,
      'critical'::text,
      'Aucun event reçu depuis 60 min — tracker ou Edge track en panne ?'::text;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_double_embed_suspect()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n bigint;
BEGIN
  SELECT count(distinct session_id) INTO v_n
  FROM (
    SELECT session_id
    FROM public.events
    WHERE occurred_at > now() - interval '24 hours'
      AND name IN ('pageview', 'web_vitals')
    GROUP BY session_id, name, path, date_trunc('second', occurred_at), props::text
    HAVING count(*) > 1
  ) d;
  IF v_n >= 30 THEN
    RETURN QUERY SELECT
      'double_embed_suspect'::text,
      'warn'::text,
      format(
        '%s sessions avec pageview/web_vitals dupliqués même-seconde sur 24h (fond normal ~8) — snippet tracker probablement en double dans Wix Custom Code',
        v_n
      );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_rpc_health()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_fn text;
  v_n bigint;
  v_start timestamptz;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['form_submits_attributed', 'conversion_journeys', 'content_performance']
  LOOP
    v_start := clock_timestamp();
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I(7)', v_fn) INTO v_n;
      INSERT INTO public.rpc_health (rpc_name, status, rows_returned, duration_ms)
      VALUES (v_fn, 'ok', v_n, extract(epoch FROM (clock_timestamp() - v_start)) * 1000);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.rpc_health (rpc_name, status, detail, duration_ms)
      VALUES (v_fn, 'failed', SQLERRM, extract(epoch FROM (clock_timestamp() - v_start)) * 1000);
      RETURN QUERY SELECT
        ('rpc_failed_' || v_fn)::text,
        'critical'::text,
        SQLERRM;
    END;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_form_attribution_degraded()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n bigint; v_tot bigint; v_pct numeric;
BEGIN
  SELECT count(*) FILTER (WHERE props->>'cooked_aid' IS NULL), count(*)
    INTO v_n, v_tot
  FROM public.events
  WHERE name = 'form_submit'
    AND occurred_at > now() - interval '7 days';
  IF v_tot >= 5 THEN
    v_pct := round(100.0 * v_n / v_tot, 0);
    IF v_pct > 30 THEN
      RETURN QUERY SELECT
        'form_attribution_degraded'::text,
        'warn'::text,
        format(
          '%s %% des form_submit sans cooked_aid sur 7j (%s/%s) — champs cachés Wix manquants ou tracker pas à jour ?',
          v_pct, v_n, v_tot
        );
    END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_gsc_lag()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_lag int;
BEGIN
  SELECT (current_date - public.gsc_last_data_day()) INTO v_lag;
  IF v_lag > 3 THEN
    RETURN QUERY SELECT
      'gsc_lag'::text,
      'warn'::text,
      format('Dernière donnée GSC : J-%s — ingestion en panne ?', v_lag);
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_gsc_gap()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n bigint; v_detail text;
BEGIN
  BEGIN
    SELECT count(*), string_agg(to_char(d, 'DD/MM/YYYY'), ', ' ORDER BY d)
      INTO v_n, v_detail
    FROM (
      SELECT generate_series(
               public.gsc_last_data_day() - 90,
               public.gsc_last_data_day(),
               interval '1 day'
             )::date AS d
      EXCEPT
      SELECT DISTINCT day
      FROM public.gsc_path_daily
      WHERE day >= public.gsc_last_data_day() - 90
    ) miss;
    IF v_n >= 1 THEN
      RETURN QUERY SELECT
        'gsc_gap'::text,
        'warn'::text,
        format(
          '%s jour(s) GSC manquant(s) sur 90j couverts : %s — backfill via scripts/gsc_ingest.py',
          v_n, v_detail
        );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT
      'gsc_gap_check_failed'::text,
      'critical'::text,
      SQLERRM;
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_cpi_drop()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n bigint; v_detail text;
BEGIN
  BEGIN
    SELECT count(*),
           string_agg(
             path || ' (' || cpi_ref || '→' || cpi_now
               || ', zvΔ' || round(coalesce(delta_zv, 0)::numeric, 1)
               || ' momΔ' || round(coalesce(delta_momentum, 0)::numeric, 2) || ')',
             ', ' ORDER BY rn
           ) FILTER (WHERE rn <= 3)
      INTO v_n, v_detail
    FROM (
      SELECT path, cpi_ref, cpi_now, delta_zv, delta_momentum,
             row_number() OVER (ORDER BY delta_cpi ASC) AS rn
      FROM public.cpi_movers
      WHERE statut = 'present'
        AND fiable
        AND delta_cpi <= -15
        AND coalesce(ecart_jours, 99) <= 8
        AND (coalesce(delta_momentum, 0) <= -0.10 OR coalesce(delta_zc, 0) <= -0.5)
    ) m;
    IF v_n >= 1 THEN
      RETURN QUERY SELECT
        'cpi_drop'::text,
        'warn'::text,
        format(
          '%s page(s) fiable(s) en vrai decay sur ~7j (fenêtre ≤8j, volatilité conversion exclue) : %s%s — diagnostiquer via cpi_movers (delta_zc/zr/zl/zv)',
          v_n,
          v_detail,
          CASE WHEN v_n > 3 THEN format(' … et %s autre(s)', v_n - 3) ELSE '' END
        );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT
      'cpi_movers_failed'::text,
      'critical'::text,
      SQLERRM;
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_dfs_stale()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_ts timestamptz;
BEGIN
  SELECT max(last_synced_at) INTO v_ts FROM public.dfs_keyword_volume;
  IF v_ts IS NULL OR v_ts < now() - interval '10 days' THEN
    RETURN QUERY SELECT
      'dfs_stale'::text,
      'warn'::text,
      format(
        'DataForSEO pas syncé depuis %s — cron dfs-weekly-sync en panne ?',
        coalesce(to_char(v_ts AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'), 'jamais')
      );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_tracker_drift()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_expected text;
  v_expected_since timestamptz;
  v_majv text;
BEGIN
  SELECT value, updated_at
    INTO v_expected, v_expected_since
  FROM public.cooked_config
  WHERE key = 'expected_tracker_version';
  IF v_expected IS NOT NULL THEN
    SELECT props->>'_v'
      INTO v_majv
    FROM public.events
    WHERE name = 'pageview'
      AND occurred_at > now() - interval '24 hours'
      AND props->>'_v' IS NOT NULL
    GROUP BY props->>'_v'
    ORDER BY count(*) DESC
    LIMIT 1;
    IF v_majv IS NOT NULL
       AND v_majv IS DISTINCT FROM v_expected
       AND (now() - v_expected_since) > interval '48 hours' THEN
      RETURN QUERY SELECT
        'tracker_drift'::text,
        'warn'::text,
        format(
          'Version tracker majoritaire 24h = %s, attendu %s — collage Wix Custom Code pas à jour ?',
          v_majv, v_expected
        );
    END IF;
  END IF;
END;
$function$;

-- ── Driver mince ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cooked_alerts_refresh()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  r record;
  v_added int := 0;
BEGIN
  FOR r IN
    SELECT * FROM public.alert_rule_pipeline_dead()
    UNION ALL SELECT * FROM public.alert_rule_double_embed_suspect()
    UNION ALL SELECT * FROM public.alert_rule_rpc_health()
    UNION ALL SELECT * FROM public.alert_rule_form_attribution_degraded()
    UNION ALL SELECT * FROM public.alert_rule_gsc_lag()
    UNION ALL SELECT * FROM public.alert_rule_gsc_gap()
    UNION ALL SELECT * FROM public.alert_rule_cpi_drop()
    UNION ALL SELECT * FROM public.alert_rule_dfs_stale()
    UNION ALL SELECT * FROM public.alert_rule_tracker_drift()
  LOOP
    v_added := v_added + public.raise_cooked_alert(r.kind, r.severity, r.detail);
  END LOOP;
  RETURN v_added;
END;
$function$;

-- Permissions : règles internes, testables par service_role
REVOKE ALL ON FUNCTION public.alert_rule_pipeline_dead() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_double_embed_suspect() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_rpc_health() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_form_attribution_degraded() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_gsc_lag() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_gsc_gap() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_cpi_drop() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_dfs_stale() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.alert_rule_tracker_drift() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_pipeline_dead() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_double_embed_suspect() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_rpc_health() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_form_attribution_degraded() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_gsc_lag() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_gsc_gap() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_cpi_drop() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_dfs_stale() TO service_role;
GRANT EXECUTE ON FUNCTION public.alert_rule_tracker_drift() TO service_role;

COMMENT ON FUNCTION public.cooked_alerts_refresh() IS
  'C2 — Driver alertes : délègue aux alert_rule_*() puis raise_cooked_alert (dédup 24h).';
