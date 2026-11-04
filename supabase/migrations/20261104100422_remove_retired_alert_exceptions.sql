-- Retire les exceptions de notification CPI, dont le producteur a été supprimé.
-- Aucune modification des événements, visites, contacts ou seuils de fraîcheur.
BEGIN;
SET LOCAL statement_timeout='30s';

CREATE OR REPLACE FUNCTION public.alert_rule_freshness()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  c         record;
  v_last    date;
  v_age     int;
  v_sev     text;
  v_missing int;
  v_days    text;
BEGIN
  FOR c IN SELECT * FROM public.freshness_contract WHERE enabled ORDER BY source LOOP
    BEGIN
      EXECUTE c.last_point_sql INTO v_last;

      IF v_last IS NULL THEN
        kind := c.source || '_stale'; severity := 'critical';
        detail := format('%s : aucune donnée (table vide ?). %s',
                         c.label, coalesce(c.repair_hint, ''));
        RETURN NEXT;
        CONTINUE;
      END IF;

      -- Clamp : un dernier point « dans le futur » (horloge client clampée
      -- ±48 h par l'Edge track) ne doit jamais masquer une panne.
      v_last := least(v_last, public.paris_today());

      v_age := public.paris_today() - v_last;
      v_sev := CASE
        WHEN c.critical_after_days IS NOT NULL AND v_age > c.critical_after_days THEN 'critical'
        WHEN v_age > c.warn_after_days THEN 'warn'
        ELSE NULL
      END;

      IF v_sev IS NOT NULL THEN
        kind := c.source || '_stale'; severity := v_sev;
        detail := format(
          '%s : dernier jour de donnée %s (J-%s ; lag normal ~J-%s, warn > %s j%s). %s',
          c.label, to_char(v_last, 'DD/MM/YYYY'), v_age, c.normal_lag_days,
          c.warn_after_days,
          CASE WHEN c.critical_after_days IS NOT NULL
               THEN ', critical > ' || c.critical_after_days || ' j' ELSE '' END,
          coalesce(c.repair_hint, ''));
        RETURN NEXT;
      END IF;

      -- Trous à l'intérieur de la série, sur [last_point - fenêtre, last_point].
      IF c.gap_relation IS NOT NULL AND c.gap_day_column IS NOT NULL
         AND c.gap_window_days IS NOT NULL THEN
        -- Début de série borné au premier jour réellement présent : une
        -- source plus jeune que la fenêtre ne doit pas compter « manquants »
        -- les jours d'avant sa naissance.
        EXECUTE format(
          'SELECT count(*)::int, string_agg(to_char(d.d::date, %L), '', '' ORDER BY d.d) '
          'FROM generate_series(GREATEST(%L::date, (SELECT min(%I) FROM public.%I)), %L::date, interval ''1 day'') d(d) '
          'LEFT JOIN (SELECT DISTINCT %I AS day FROM public.%I '
          '           WHERE %I BETWEEN %L AND %L) t ON t.day = d.d::date '
          'WHERE t.day IS NULL',
          'DD/MM', v_last - c.gap_window_days, c.gap_day_column, c.gap_relation, v_last,
          c.gap_day_column, c.gap_relation, c.gap_day_column,
          v_last - c.gap_window_days, v_last
        ) INTO v_missing, v_days;
        IF v_missing > 0 THEN
          kind := c.source || '_gap'; severity := 'warn';
          detail := format('%s : %s jour(s) manquant(s) entre le %s et le %s : %s',
                           c.label, v_missing,
                           to_char(v_last - c.gap_window_days, 'DD/MM'),
                           to_char(v_last, 'DD/MM'), left(v_days, 300));
          RETURN NEXT;
        END IF;
      END IF;

    EXCEPTION WHEN others THEN
      kind := c.source || '_contract_failed'; severity := 'critical';
      detail := format('Contrat de fraîcheur « %s » en échec : %s',
                       c.source, left(SQLERRM, 300));
      RETURN NEXT;
    END;
  END LOOP;
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.raise_cooked_alert(p_kind text, p_sev text, p_detail text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_topic text;
  v_last_acked boolean;
  v_crit_since_ack int;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.alerts
    WHERE kind = p_kind AND severity = p_sev
      AND created_at > now() - interval '24 hours'
  ) THEN
    RETURN 0;
  END IF;

  SELECT a.acked INTO v_last_acked
  FROM public.alerts a
  WHERE a.kind = p_kind
  ORDER BY a.created_at DESC
  LIMIT 1;

  INSERT INTO public.alerts (kind, severity, detail) VALUES (p_kind, p_sev, p_detail);

  SELECT count(*) INTO v_crit_since_ack
  FROM public.alerts
  WHERE kind = p_kind AND severity = 'critical'
    AND created_at > coalesce(
      (SELECT max(created_at) FROM public.alerts WHERE kind = p_kind AND acked),
      '-infinity'::timestamptz
    );

  IF p_sev = 'critical'
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

REVOKE ALL ON FUNCTION public.alert_rule_freshness(), public.alert_rule_warn_escalation(), public.raise_cooked_alert(text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_freshness(), public.alert_rule_warn_escalation(), public.raise_cooked_alert(text,text,text) TO service_role;
COMMIT;
