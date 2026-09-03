-- T-07 (mission 02/09/2026, #108) — alertes v4.
-- Mesure avant 03/09 14:27 Paris : 55 non acquittées (34 cpi_drop, 9 gbp_daily_stale,
-- 8 gbp_gap, 3 gsc_ingest_missed, 1 pipeline_dead du 22/08) ; 11 critical / 10 j.
-- Replay 40 j : 1 trou diurne 166 min (01/08 13:16→16:02) ; 3 trous nocturnes 61-69 min
-- (dont le faux positif 22/08 03:12). Seuil 90 min : 0 FP nuit, 1 détection jour.
-- cpi_drop du jour : 3 pages v3 (2 S/A à momentum 1,01 et 1,09 ; 1 B) → 0 en v4.

-- Heure Paris sans cast brut (C6).
CREATE OR REPLACE FUNCTION public.cooked_paris_hour(p_ts timestamptz)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_catalog'
AS $f$
  SELECT floor(extract(epoch FROM (
    p_ts - public.cooked_paris_ts_start(public.paris_date(p_ts))
  )) / 3600)::int;
$f$;
REVOKE ALL ON FUNCTION public.cooked_paris_hour(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_paris_hour(timestamptz) TO service_role;

-- 1. pipeline_dead : âge du dernier event, pas « zéro dans la fenêtre ».
CREATE OR REPLACE FUNCTION public.alert_rule_pipeline_dead()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last timestamptz;
  v_age_min numeric;
  v_hour int;
  v_med numeric;
BEGIN
  SELECT max(received_at) INTO v_last FROM public.events;
  IF v_last IS NULL THEN
    RETURN QUERY SELECT
      'pipeline_dead'::text, 'critical'::text,
      'Aucun event en base — tracker ou Edge track jamais vu ?'::text;
    RETURN;
  END IF;

  v_age_min := extract(epoch FROM (now() - v_last)) / 60.0;
  IF v_age_min <= 90 THEN
    RETURN;
  END IF;

  -- Cette heure Paris est-elle habituellement vivante ? (médiane 7 j, hors heure en cours)
  v_hour := public.cooked_paris_hour(now());
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY n) INTO v_med
  FROM (
    SELECT count(*) AS n
    FROM public.events e
    WHERE e.received_at >= now() - interval '8 days'
      AND e.received_at < now() - interval '1 hour'
      AND public.cooked_paris_hour(e.received_at) = v_hour
    GROUP BY public.paris_date(e.received_at)
  ) s;

  IF coalesce(v_med, 0) < 1 THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT
    'pipeline_dead'::text,
    'critical'::text,
    format(
      'Aucun event reçu depuis %s min (seuil 90 min, heure Paris habituellement active, médiane %s). Tracker ou Edge track en panne ?',
      round(v_age_min), round(v_med)
    )::text;
END;
$function$;

-- 2. cpi_drop : niveau du momentum < 0,90 ; push seulement S/A (B consultatif).
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
               || ', mom ' || round(coalesce(momentum_now, 0)::numeric, 2)
               || ', zvΔ' || round(coalesce(delta_zv, 0)::numeric, 1) || ')',
             ', ' ORDER BY rn
           ) FILTER (WHERE rn <= 3)
      INTO v_n, v_detail
    FROM (
      SELECT path, cpi_ref, cpi_now, delta_zv, momentum_now,
             row_number() OVER (ORDER BY delta_cpi ASC) AS rn
      FROM public.cpi_movers
      WHERE statut = 'present'
        AND grade_now IN ('S', 'A')
        AND grade_ref IN ('S', 'A')
        AND delta_cpi <= -15
        AND coalesce(ecart_jours, 99) <= 8
        AND coalesce(momentum_now, 1) < 0.90
        AND (coalesce(delta_momentum, 0) <= -0.10 OR coalesce(delta_zc, 0) <= -0.5)
        AND NOT EXISTS (
          SELECT 1
          FROM (SELECT public.gsc_last_data_day() AS g_end) g,
               LATERAL (SELECT coalesce(sum(p.clicks) FILTER (WHERE p.day > g.g_end - 7), 0)  AS r1,
                               coalesce(sum(p.clicks) FILTER (WHERE p.day <= g.g_end - 7), 0) AS r0
                        FROM public.gsc_path_daily p
                        WHERE p.path = cpi_movers.path AND p.day > g.g_end - 14) c
          WHERE c.r1 > c.r0
        )
    ) m;
    IF v_n >= 1 THEN
      RETURN QUERY SELECT
        'cpi_drop'::text,
        'warn'::text,
        format(
          '%s page(s) S/A en vrai decay (momentum < 0,90, fenêtre ≤8j) : %s%s — cpi_movers',
          v_n, v_detail,
          CASE WHEN v_n > 3 THEN format(' … et %s autre(s)', v_n - 3) ELSE '' END
        );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 'cpi_movers_failed'::text, 'critical'::text, SQLERRM;
  END;
END;
$function$;

-- 3. Escalade : kinds éditoriaux exclus ; le cap 2 pushs est dans raise_cooked_alert.
CREATE OR REPLACE FUNCTION public.alert_rule_warn_escalation()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT a.kind,
         'critical'::text,
         'Escalade : warn actif depuis ≥ 5 jours sans acquittement — ' || coalesce(a.detail, a.kind)
  FROM (
    SELECT DISTINCT ON (kind) kind, detail
    FROM public.alerts
    WHERE severity = 'warn' AND created_at > now() - interval '26 hours'
      AND kind NOT IN ('cpi_drop')
    ORDER BY kind, created_at DESC
  ) a
  WHERE EXISTS (
      SELECT 1 FROM public.alerts w
      WHERE w.kind = a.kind AND w.severity = 'warn'
        AND w.created_at BETWEEN now() - interval '6 days' AND now() - interval '5 days')
    AND (SELECT count(*) FROM public.alerts w
         WHERE w.kind = a.kind AND w.severity = 'warn'
           AND w.created_at > now() - interval '5 days') >= 4
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts c
      WHERE c.kind = a.kind AND c.severity = 'critical'
        AND c.created_at > now() - interval '26 hours')
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts k
      WHERE k.kind = a.kind AND k.acked
        AND k.created_at > now() - interval '5 days');
$function$;

-- 4. Plancher de volume : heure Paris précédente vs médiane 7 j, −50 %, heures 9-18.
CREATE OR REPLACE FUNCTION public.alert_rule_volume_floor()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_today date := public.paris_today();
  v_hour_now int;
  v_prev_hour int;
  v_prev_day date;
  t0 timestamptz;
  t1 timestamptz;
  v_n bigint;
  v_med numeric;
BEGIN
  v_hour_now := public.cooked_paris_hour(now());
  v_prev_hour := v_hour_now - 1;
  v_prev_day := v_today;
  IF v_prev_hour < 0 THEN
    v_prev_hour := 23;
    v_prev_day := v_today - 1;
  END IF;
  IF v_prev_hour < 9 OR v_prev_hour > 18 THEN
    RETURN;
  END IF;

  t0 := public.cooked_paris_ts_start(v_prev_day) + make_interval(hours => v_prev_hour);
  t1 := t0 + interval '1 hour';

  SELECT count(*) FILTER (WHERE name = 'pageview') INTO v_n
  FROM public.events_human
  WHERE occurred_at >= t0 AND occurred_at < t1;

  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY n) INTO v_med
  FROM (
    SELECT count(*) FILTER (WHERE e.name = 'pageview') AS n
    FROM public.events_human e
    WHERE e.occurred_at >= public.cooked_paris_ts_start(v_prev_day - 7)
      AND e.occurred_at < public.cooked_paris_ts_start(v_prev_day)
      AND public.cooked_paris_hour(e.occurred_at) = v_prev_hour
    GROUP BY public.paris_date(e.occurred_at)
  ) s;

  IF coalesce(v_med, 0) >= 30 AND coalesce(v_n, 0) < 0.5 * v_med THEN
    RETURN QUERY SELECT
      'volume_floor'::text,
      'warn'::text,
      format(
        'Pageviews %sh Paris : %s vs médiane 7 j %s (−%s %%). Heure habituellement ≥ 30.',
        v_prev_hour, v_n, round(v_med),
        round(100.0 * (1 - v_n / nullif(v_med, 0)))
      )::text;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.alert_rule_volume_floor() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_volume_floor() TO service_role;

-- 5. raise_cooked_alert : kinds éditoriaux jamais critical ; ≤ 2 pushs ntfy / épisode.
CREATE OR REPLACE FUNCTION public.raise_cooked_alert(p_kind text, p_sev text, p_detail text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_topic text;
  v_last_acked boolean;
  v_sev text := p_sev;
  v_crit_since_ack int;
BEGIN
  IF p_kind IN ('cpi_drop') AND v_sev = 'critical' THEN
    v_sev := 'warn';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.alerts
    WHERE kind = p_kind AND severity = v_sev
      AND created_at > now() - interval '24 hours'
  ) THEN
    RETURN 0;
  END IF;

  SELECT a.acked INTO v_last_acked
  FROM public.alerts a
  WHERE a.kind = p_kind
  ORDER BY a.created_at DESC
  LIMIT 1;

  INSERT INTO public.alerts (kind, severity, detail) VALUES (p_kind, v_sev, p_detail);

  SELECT count(*) INTO v_crit_since_ack
  FROM public.alerts
  WHERE kind = p_kind AND severity = 'critical'
    AND created_at > coalesce(
      (SELECT max(created_at) FROM public.alerts WHERE kind = p_kind AND acked),
      '-infinity'::timestamptz
    );

  -- critical uniquement, épisode non acquitté, au plus 2 pushs.
  IF v_sev = 'critical'
     AND coalesce(v_last_acked, false) = false
     AND v_crit_since_ack <= 2 THEN
    BEGIN
      SELECT nullif(btrim(value), '') INTO v_topic
      FROM public.cooked_config WHERE key = 'ntfy_topic';
      IF v_topic IS NOT NULL THEN
        PERFORM net.http_post(
          url     := 'https://ntfy.sh/',
          body    := jsonb_build_object(
                       'topic',    v_topic,
                       'title',    'Cooked : alerte critique',
                       'message',  left(coalesce(p_detail, p_kind), 4000),
                       'priority', 5,
                       'tags',     jsonb_build_array('rotating_light')
                     ),
          headers := '{"Content-Type": "application/json"}'::jsonb
        );
      END IF;
    EXCEPTION WHEN others THEN
      NULL;
    END;
  END IF;

  RETURN 1;
END;
$function$;

-- 6. Acquittement : ack_alerts() tout le stock, ou ack_alerts(ARRAY['cpi_drop']).
CREATE OR REPLACE FUNCTION public.ack_alerts(p_kinds text[] DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n int;
BEGIN
  UPDATE public.alerts
     SET acked = true
   WHERE NOT acked
     AND (p_kinds IS NULL OR kind = ANY (p_kinds));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ack_alerts(text[]) IS
  'T-07 : acquitte les alertes ouvertes. NULL = tout le stock. Ex. SELECT ack_alerts(); SELECT ack_alerts(ARRAY[''cpi_drop'']);';

REVOKE ALL ON FUNCTION public.ack_alerts(text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ack_alerts(text[]) TO service_role;
