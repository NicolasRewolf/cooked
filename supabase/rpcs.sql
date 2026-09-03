-- ============================================================================
-- supabase/rpcs.sql — CORPS COMPLETS DES RPC (généré, LECTURE SEULE)
--
-- ⚠️  NE PAS REJOUER COMME SOURCE D'UN DÉPLOIEMENT. NE PAS ÉDITER À LA MAIN.
--
-- Source de vérité DDL = supabase/migrations/*.sql (+ état prod).
-- Ce fichier = instantané lisible pour humains et agents (Arch #5, 10/07/2026).
--
-- Régénérer : python3 scripts/generate_rpcs_sql.py  (DATABASE_URL requis)
-- Généré le 03/09/2026 — projet mxycmjkeotrycyneacje.
-- ============================================================================

-- ═══ public.alert_rule_cpi_drop() ═══
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
$function$


-- ═══ public.alert_rule_cron_failed() ═══
CREATE OR REPLACE FUNCTION public.alert_rule_cron_failed()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'cron', 'pg_catalog'
AS $function$
DECLARE v_list text;
BEGIN
  SELECT string_agg(
           x.jobname || ' (' || to_char(x.start_time AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI')
           || ' — ' || left(regexp_replace(coalesce(x.return_message, 'sans message'), '\s+', ' ', 'g'), 90) || ')',
           ' | ' ORDER BY x.start_time DESC)
    INTO v_list
  FROM (
    SELECT j.jobname, d.status, d.return_message, d.start_time
    FROM cron.job j
    JOIN LATERAL (
      SELECT dd.status, dd.return_message, dd.start_time
      FROM cron.job_run_details dd
      WHERE dd.jobid = j.jobid
      ORDER BY dd.start_time DESC
      LIMIT 1
    ) d ON true
    WHERE j.active
      AND d.status = 'failed'
      AND d.start_time > now() - interval '7 days'
  ) x;

  IF v_list IS NOT NULL THEN
    RETURN QUERY SELECT
      'cron_failed'::text,
      'critical'::text,
      ('Tâche(s) planifiée(s) en échec au dernier passage : ' || v_list)::text;
  END IF;
END;
$function$


-- ═══ public.alert_rule_double_embed_suspect() ═══
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
$function$


-- ═══ public.alert_rule_exposure() ═══
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
$function$


-- ═══ public.alert_rule_form_attribution_degraded() ═══
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
$function$


-- ═══ public.alert_rule_freshness() ═══
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
        -- les jours d'avant sa naissance (clamp hérité de feu cpi_stale).
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
$function$


-- ═══ public.alert_rule_gsc_ingest_missed() ═══
CREATE OR REPLACE FUNCTION public.alert_rule_gsc_ingest_missed()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last_ingest date;
BEGIN
  -- Le cron GSC tourne à 06:00 UTC ; on ne juge qu'après 13:00 Paris.
  IF (now() AT TIME ZONE 'Europe/Paris')::time < time '13:00' THEN  -- garde HORAIRE Paris : paris_today() ne porte pas l'heure (C6 ok)
    RETURN;
  END IF;
  SELECT public.paris_date(max(ingested_at)) INTO v_last_ingest
  FROM public.gsc_path_daily;
  IF v_last_ingest IS DISTINCT FROM public.paris_today() THEN
    kind := 'gsc_ingest_missed'; severity := 'warn';
    detail := format(
      'Ingestion GSC absente aujourd''hui (dernière : %s) — vérifier le workflow gsc-daily-ingest.',
      coalesce(to_char(v_last_ingest, 'DD/MM/YYYY'), 'jamais'));
    RETURN NEXT;
  END IF;
END;
$function$


-- ═══ public.alert_rule_page_taxonomy_gap() ═══
CREATE OR REPLACE FUNCTION public.alert_rule_page_taxonomy_gap()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_n  bigint;
  v_ex text;
BEGIN
  WITH vus AS (
    SELECT e.path, count(*) FILTER (WHERE e.name = 'pageview') AS pv
    FROM public.events_human e
    WHERE e.path LIKE '/post/%'
      AND e.occurred_at > now() - interval '30 days'
      -- mêmes exclusions structurelles que refresh_page_taxonomy_heuristic (T-19)
      AND e.path NOT LIKE '%/preview/%'   -- previews Wix avec token
      AND e.path !~ 'https?://'           -- URLs concaténées par erreur
      AND e.path !~ '[ÃÂ]'                -- mojibake (double encodage)
      AND e.path !~ '%'                   -- restes d'URL-encoding
      AND length(e.path) <= 140
    GROUP BY e.path
    HAVING count(*) FILTER (WHERE e.name = 'pageview') >= 5
  )
  SELECT count(*), string_agg(v.path, ', ' ORDER BY v.pv DESC)
    INTO v_n, v_ex
  FROM vus v
  LEFT JOIN public.page_taxonomy t ON t.path = v.path
  WHERE t.path IS NULL OR t.category IS NULL;

  IF v_n >= 3 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j) sans catégorie Wix dans page_taxonomy — toute lecture par catégorie (dashboard Articles Ressources, content_performance, contrat éditorial) les ignore. Rejouer la synchro API Wix : GET /blog/v3/posts, site 0870235c-b92d-4a69-a2f4-25a976ae5f0c, catégorie ressource 9477320f-5902-40e9-ace3-b0e3b6b8b51f. Concernés : %s',
        v_n, left(coalesce(v_ex, ''), 400)
      );
  END IF;
END;
$function$


-- ═══ public.alert_rule_pipeline_dead() ═══
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
$function$


-- ═══ public.alert_rule_rpc_health() ═══
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
$function$


-- ═══ public.alert_rule_spam_in_events_human() ═══
CREATE OR REPLACE FUNCTION public.alert_rule_spam_in_events_human()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
-- T-04 (mission 02/09/2026, invariant I3) : le filet ua_bot / spam_referrer laisse-t-il passer du robot dans
-- events_human ? Fenêtre 24 h (horaire), warn dès 1 % des pageviews (garde ≥ 50 pageviews et ≥ 5 spam).
-- Découverte automatiquement par cooked_alerts_refresh() (préfixe alert_rule_, 0 argument).
DECLARE
  v_pv   bigint;
  v_spam bigint;
  v_pct  numeric;
BEGIN
  SELECT count(*) FILTER (WHERE name = 'pageview'),
         count(*) FILTER (WHERE name = 'pageview'
                            AND (lower(user_agent) = 'pc' OR user_agent ILIKE '%sebot%'
                                 OR public.cooked_is_spam_referrer(referrer_hostname)))
    INTO v_pv, v_spam
  FROM public.events_human
  WHERE occurred_at > now() - interval '24 hours';

  IF coalesce(v_pv, 0) >= 50 AND coalesce(v_spam, 0) >= 5 THEN
    v_pct := round(100.0 * v_spam / v_pv, 1);
    IF v_pct >= 1 THEN
      RETURN QUERY SELECT
        'spam_in_events_human'::text,
        'warn'::text,
        format('%s pageviews de robot / referrer spam sur %s dans events_human (24 h) = %s %% (seuil 1 %%). '
               || 'Le filet ua_bot / spam_referrer laisse passer : vérifier la version Edge (props->>''_v''), '
               || 'ingest_drops et le cron refresh_noise_filters_hourly (T-04, mission 02/09/2026).',
               v_spam, v_pv, v_pct)::text;
    END IF;
  END IF;
END;
$function$


-- ═══ public.alert_rule_tracker_drift() ═══
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
$function$


-- ═══ public.alert_rule_warn_escalation() ═══
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
$function$


-- ═══ public.assisted_contacts_by_entry_path(p_start date, p_end date) ═══
CREATE OR REPLACE FUNCTION public.assisted_contacts_by_entry_path(p_start date, p_end date)
 RETURNS TABLE(entry_path text, contacts bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  t0 timestamptz := (p_start::timestamp AT TIME ZONE 'Europe/Paris');
  t1 timestamptz := ((p_end + 1)::timestamp AT TIME ZONE 'Europe/Paris');
BEGIN
  DROP TABLE IF EXISTS _pvk;
  CREATE TEMP TABLE _pvk ON COMMIT DROP AS
    SELECT COALESCE(st.visitor_key, 'sid:' || e.session_id) AS vk,
           e.occurred_at AS t, e.path
    FROM public.events_human e
    LEFT JOIN public.identity_stitch st ON st.kind = 'sid' AND st.key = e.session_id
    WHERE e.name = 'pageview'
      AND e.occurred_at >= t0 AND e.occurred_at < t1
      AND NOT public.cooked_is_spam_referrer(e.referrer_hostname);

  DROP TABLE IF EXISTS _pvseg;
  CREATE TEMP TABLE _pvseg ON COMMIT DROP AS
    SELECT vk, t, path,
           sum(brk) OVER (PARTITION BY vk ORDER BY t) AS visit_n
    FROM (
      SELECT vk, t, path,
             CASE WHEN lag(t) OVER (PARTITION BY vk ORDER BY t) IS NULL
                    OR t - lag(t) OVER (PARTITION BY vk ORDER BY t) > interval '30 minutes'
                  THEN 1 ELSE 0 END AS brk
      FROM _pvk
    ) x;
  CREATE INDEX ON _pvseg (vk, t);
  ANALYZE _pvseg;

  DROP TABLE IF EXISTS _ventry;
  CREATE TEMP TABLE _ventry ON COMMIT DROP AS
    SELECT vk, visit_n, (array_agg(path ORDER BY t))[1] AS entry_path
    FROM _pvseg GROUP BY vk, visit_n;
  ANALYZE _ventry;

  DROP TABLE IF EXISTS _ct;
  CREATE TEMP TABLE _ct ON COMMIT DROP AS
    SELECT e.occurred_at AS t,
           COALESCE(st.visitor_key, 'sid:' || e.session_id) AS vk
    FROM public.events_human e
    LEFT JOIN public.identity_stitch st ON st.kind = 'sid' AND st.key = e.session_id
    WHERE e.name = 'cta_phone_click'
      AND e.occurred_at >= t0 AND e.occurred_at < t1
    UNION ALL
    SELECT e.occurred_at,
           COALESCE(sts.visitor_key, sta.visitor_key, 'sid:' || (e.props->>'cooked_sid'))
    FROM public.events_human e
    LEFT JOIN public.identity_stitch sts ON sts.kind = 'sid' AND sts.key = e.props->>'cooked_sid'
    LEFT JOIN public.identity_stitch sta ON sta.kind = 'aid' AND sta.key = e.props->>'cooked_aid'
    WHERE e.name = 'form_submit'
      AND public.form_submit_counts_as_macro(e.props)
      AND e.occurred_at >= t0 AND e.occurred_at < t1
      AND COALESCE(e.props->>'cooked_sid', e.props->>'cooked_aid') IS NOT NULL;
  ANALYZE _ct;

  DROP TABLE IF EXISTS _ce;
  CREATE TEMP TABLE _ce ON COMMIT DROP AS
    SELECT COALESCE(v.entry_path, '(non rattaché)') AS entry_path
    FROM _ct c
    JOIN LATERAL (
      SELECT s.vk, s.visit_n
      FROM _pvseg s
      WHERE s.vk = c.vk AND s.t <= c.t AND c.t - s.t <= interval '6 hours'
      ORDER BY s.t DESC LIMIT 1
    ) lp ON true
    LEFT JOIN _ventry v ON v.vk = lp.vk AND v.visit_n = lp.visit_n;

  RETURN QUERY
  SELECT ce.entry_path, count(*)::bigint
  FROM _ce ce
  GROUP BY ce.entry_path;
END;
$function$


-- ═══ public.behavior_pages_for_period(date_from timestamp with time zone, date_to timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.behavior_pages_for_period(date_from timestamp with time zone, date_to timestamp with time zone)
 RETURNS TABLE(path text, sessions bigint, pages_per_session numeric, avg_session_duration_s numeric, bounce_rate numeric, bounce_rate_pct numeric, scroll_depth_avg numeric, scroll_complete_pct numeric, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, ttfb_p75_ms numeric, outbound_clicks bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH we AS (
    SELECT * FROM public.events_human
    WHERE occurred_at >= date_from AND occurred_at < date_to
  ),
  ss AS (
    SELECT session_id,
      count(*) FILTER (WHERE name = 'pageview') AS pages_viewed,
      extract(epoch FROM max(occurred_at) - min(occurred_at))::numeric AS session_seconds
    FROM we GROUP BY session_id
  ),
  sp AS (
    SELECT DISTINCT e.path, e.session_id
    FROM we e
    WHERE e.name = 'pageview' AND e.path IS NOT NULL
  ),
  per_path_session_stats AS (
    SELECT sp.path,
      avg(ss.pages_viewed)::numeric AS pages_per_session,
      avg(ss.session_seconds)::numeric AS avg_session_seconds
    FROM sp JOIN ss ON ss.session_id = sp.session_id
    GROUP BY sp.path
  ),
  cwv AS (
    SELECT path,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'LCP'))::numeric AS lcp_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'INP'))::numeric AS inp_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'CLS'))::numeric AS cls_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'TTFB'))::numeric AS ttfb_p75
    FROM we
    WHERE name = 'web_vitals' AND path IS NOT NULL
    GROUP BY path
  ),
  oc AS (
    SELECT path, count(*) AS clicks
    FROM we
    WHERE name = 'click_outbound' AND path IS NOT NULL
    GROUP BY path
  ),
  base AS (SELECT * FROM public.seo_pages_overview(date_from, date_to))
  SELECT b.path, b.sessions,
    coalesce(round(pp.pages_per_session, 2), 0),
    coalesce(round(pp.avg_session_seconds, 0), 0),
    coalesce(round(b.bounce_rate, 4), 0),      -- T-03 (d-01) : fraction 0-1 déjà produite par seo_pages_overview
    coalesce(round(b.bounce_rate_pct, 2), 0),  -- T-03 (d-01) : pourcentage 0-100
    b.scroll_avg, b.scroll_complete_pct,
    cwv.lcp_p75, cwv.inp_p75, cwv.cls_p75, cwv.ttfb_p75,
    coalesce(oc.clicks, 0)::bigint
  FROM base b
  LEFT JOIN per_path_session_stats pp ON pp.path = b.path
  LEFT JOIN cwv ON cwv.path = b.path
  LEFT JOIN oc ON oc.path = b.path;
$function$


-- ═══ public.canonical_path(p text) ═══
CREATE OR REPLACE FUNCTION public.canonical_path(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT CASE
    WHEN char_length(n) > 1 AND right(n, 1) = '/' THEN left(n, char_length(n) - 1)
    ELSE COALESCE(NULLIF(n, ''), '/')
  END
  FROM (
    SELECT normalize(public.url_decode(COALESCE(p, '')), NFC) AS n
  ) AS s;
$function$


-- ═══ public.classify_channel(ref text, utm_source text, utm_medium text, self_host text, url text) ═══
CREATE OR REPLACE FUNCTION public.classify_channel(ref text, utm_source text, utm_medium text, self_host text DEFAULT 'jplouton-avocat.fr'::text, url text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when ref ilike '%' || self_host || '%' then null
    -- T-04 (mission 02/09/2026, d-05) : referrer spam → canal 'spam' (94 % du canal referral était le bot Baidu).
    when public.cooked_is_spam_referrer(ref) then 'spam'
    -- T-09 (mission 02/09/2026, o-14) : un identifiant de clic Ads (gclid / gbraid / wbraid) dans l'URL d'atterrissage
    -- = paid, quel que soit l'utm_source — décision « paid prime » sur le chevauchement paid/GMB (16 entrées/28 j
    -- taguées utm_source=gmb portaient un gclid). `url` est facultatif : les appels à 4 arguments sont inchangés.
    when url ~* '[?&](gclid|gbraid|wbraid)=' then 'paid'
    when lower(utm_medium) in ('cpc','paid','ppc')
      or lower(utm_source) like '%google%ads%' then 'paid'
    -- Fiche Google Business : posée AVANT la branche google.*, sinon le
    -- referrer (google.com / maps) la ferait tomber dans organic_google.
    -- Le lien de la fiche est `/?utm_source=gmb`; 'gbp' couvre la variante
    -- Google Business Profile vue dans les données.
    when lower(utm_source) like 'gmb%' or lower(utm_source) like 'gbp%'
      then 'gmb'
    when ref ilike '%claude.ai%' or ref ilike '%perplexity.ai%'
      or ref ilike '%chatgpt.com%' or ref ilike '%chat.openai.com%'
      or ref ilike '%gemini.google.com%' or ref ilike '%copilot.microsoft.com%'
      or ref ilike '%grok.com%' or ref = 'x.ai' or ref ilike '%meta.ai%'
      or ref ilike '%chat.mistral.ai%' or ref ilike '%chat.deepseek.com%'
      or lower(utm_source) in ('chatgpt.com','openai','perplexity','perplexity.ai',
                               'claude.ai','gemini','copilot')
      then 'organic_ai'
    when ref ilike '%google.%' then 'organic_google'
    when ref ilike '%yahoo.%' or ref ilike '%ecosia.org%' or ref ilike '%brave.com%'
      or ref ilike '%lilo.org%' or ref ilike '%duckduckgo.%' or ref ilike '%qwant.%'
      or ref ilike '%bing.%'
      then 'organic_other'
    when ref ilike '%facebook.%' or ref ilike '%instagram.%' or ref ilike '%linkedin.%'
      or ref = 't.co' or ref ilike '%twitter.%' or ref = 'x.com'
      or ref ilike '%snapchat.%' or ref ilike '%threads.%' or ref ilike '%tiktok.%'
      or ref ilike '%youtube.%'
      then 'social'
    when ref is null or ref = '' then 'direct'
    else 'referral'
  end;
$function$


-- ═══ public.content_performance(days_back integer) ═══
CREATE OR REPLACE FUNCTION public.content_performance(days_back integer DEFAULT 28)
 RETURNS TABLE(page_type text, theme text, pages integer, sessions bigint, dwell_median numeric, scroll_median numeric, booking_intents bigint, contacts_assisted bigint, contact_rate_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with base as (
    select e.path, public.cooked_page_type(e.path) as ptype, t.theme, e.session_id, e.name, e.props
    from public.events_human e
    left join public.page_taxonomy t on t.path = e.path
    where e.occurred_at > now() - make_interval(days => days_back) and e.path is not null
  ),
  grp as (
    select ptype, theme, count(distinct path) as pages,
      count(distinct session_id) filter (where name='pageview') as sessions,
      count(*) filter (where name='cta_booking_click') as booking_intents
    from base group by ptype, theme
  ),
  dwagg as (
    select ptype, theme, session_id, path,
      max((props->>'duration_seconds')::numeric) as dur,
      max((props->>'max_scroll')::numeric) as scr
    from base where name='page_exit' group by ptype, theme, session_id, path
  ),
  dwm as (
    select ptype, theme,
      percentile_cont(0.5) within group (order by dur) as dwell_median,
      percentile_cont(0.5) within group (order by scr) as scroll_median
    from dwagg group by ptype, theme
  ),
  assists as (
    select public.cooked_page_type(jp.path) as ptype, t.theme,
      count(distinct (j.anonymous_id, j.occurred_at)) as contacts_assisted
    from public.conversion_journeys(days_back) j
    cross join lateral unnest(j.journey) as jp(path)
    left join public.page_taxonomy t on t.path = jp.path
    group by 1, 2
  )
  select g.ptype, g.theme, g.pages::int, g.sessions,
    round(d.dwell_median::numeric,1), round(d.scroll_median::numeric,1),
    g.booking_intents, coalesce(a.contacts_assisted, 0),
    round(100.0 * coalesce(a.contacts_assisted,0) / nullif(g.sessions,0), 2)
  from grp g
  left join dwm d on d.ptype = g.ptype and d.theme is not distinct from g.theme
  left join assists a on a.ptype = g.ptype and a.theme is not distinct from g.theme
  order by g.sessions desc;
$function$


-- ═══ public.conversion_journeys(days_back integer, p_end date) ═══
CREATE OR REPLACE FUNCTION public.conversion_journeys(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(contact_kind text, occurred_at timestamp with time zone, contact_path text, objet text, anonymous_id text, attribution_method text, entry_path text, entry_channel text, pages_count integer, journey text[], device_type text, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-02) : fenêtre = days_back jours Paris CLOS ancrés sur J-1 (lens 'live_j1'), ou sur
  -- p_end (CPI : gsc_last_data_day()). Même fenêtre que form_submits_attributed(days_back, p_end), site_macro_counts et
  -- macro_contacts_by_path sur les mêmes bornes ⇒ un seul total de contacts (contract-test contacts_28j_une_fenetre).
  -- Avant : `occurred_at > now() - make_interval(...)`. Le parcours (visite recousue, coupure 30 min) est inchangé (v2, 12/07).
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  contacts as (
    select 'phone'::text as kind, e.occurred_at, e.path as contact_path,
      null::text as objet, e.anonymous_id, e.session_id, 'direct'::text as method
    from public.events_human e
    where e.name = 'cta_phone_click'
      and public.paris_date(e.occurred_at) between (select d_start from w) and (select d_end from w)
    union all
    select 'form', f.occurred_at, f.form_path, f.objet,
      f.resolved_anonymous_id, f.resolved_session_id, f.attribution_method
    from public.form_submits_attributed(days_back, p_end) f
    where f.counts_as_macro
  ),
  ck as (
    select c.*,
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(c.session_id, c.anonymous_id, 'inconnu')) as vk
    from contacts c
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = c.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = c.anonymous_id
  ),
  -- sessions couvertes par chaque visiteur porteur de contact
  -- (fallback : la session brute du contact si la couture ne la connaît
  -- pas encore — sessions plus récentes que le dernier refresh du stitch)
  vsess as (
    select k.vk, st.key as sid
    from (select distinct vk from ck) k
    join public.identity_stitch st on st.kind = 'sid' and st.visitor_key = k.vk
    union
    select c.vk, c.session_id from ck c where c.session_id is not null
  )
  select s.kind, s.occurred_at, s.contact_path, s.objet, s.anonymous_id, s.method,
    s.journey[1],
    public.classify_channel(s.first_ref, s.first_utm_source, s.first_utm_medium, 'www.jplouton-avocat.fr', s.first_url),
    coalesce(array_length(s.journey, 1), 0),
    s.journey,
    s.dev,
    w.d_start, w.d_end
  from (
    select c.kind, c.occurred_at, c.contact_path, c.objet, c.anonymous_id, c.method,
      j.journey, j.first_ref, j.first_utm_source, j.first_utm_medium, j.first_url,
      (select e6.device_type from public.events_human e6
        where e6.session_id in (select v2.sid from vsess v2 where v2.vk = c.vk)
          and e6.device_type is distinct from 'server'
        limit 1) as dev
    from ck c
    left join lateral (
      with pv as (
        select e2.path, e2.occurred_at as t,
               e2.referrer_hostname, e2.utm_source, e2.utm_medium, e2.url
        from public.events_human e2
        where e2.name = 'pageview'
          and e2.session_id in (select v.sid from vsess v where v.vk = c.vk)
          and e2.occurred_at <= c.occurred_at + interval '3 min'
          and e2.occurred_at >= c.occurred_at - interval '6 hours'
      ),
      seg as (
        select pv.*,
          case when pv.t - lag(pv.t) over (order by pv.t) > interval '30 minutes'
               then pv.t end as brk
        from pv
      ),
      chain as (
        select * from seg
        where seg.t >= coalesce((select max(s2.brk) from seg s2), '-infinity'::timestamptz)
      )
      select
        (select array_agg(q.path order by q.first_seen)
           from (select ch.path, min(ch.t) as first_seen from chain ch group by ch.path) q) as journey,
        (select ch.referrer_hostname from chain ch order by ch.t limit 1) as first_ref,
        (select ch.utm_source from chain ch order by ch.t limit 1) as first_utm_source,
        (select ch.utm_medium from chain ch order by ch.t limit 1) as first_utm_medium,
        (select ch.url from chain ch order by ch.t limit 1) as first_url
    ) j on true
  ) s
  cross join w
  order by s.occurred_at desc;
$function$


-- ═══ public.conversions_leaderboard(p_since date) ═══
CREATE OR REPLACE FUNCTION public.conversions_leaderboard(p_since date DEFAULT NULL::date)
 RETURNS TABLE(page text, conversions_sur_la_page bigint, appels bigint, formulaires bigint, conversions_attribuees_entree bigint, semaines_actives bigint, premiere_semaine date, derniere_semaine date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH base AS (
    SELECT week_start, COALESCE(contact_path, '(page inconnue)') AS page,
           'sur'::text AS role, contact_kind
    FROM public.conversion_weekly
    WHERE week_start >= COALESCE(p_since, '-infinity'::date)
    UNION ALL
    SELECT week_start, COALESCE(entry_path, '(entree inconnue)'),
           'entree', contact_kind
    FROM public.conversion_weekly
    WHERE week_start >= COALESCE(p_since, '-infinity'::date)
  )
  SELECT page,
         count(*) FILTER (WHERE role = 'sur'),
         count(*) FILTER (WHERE role = 'sur' AND contact_kind = 'phone'),
         count(*) FILTER (WHERE role = 'sur' AND contact_kind = 'form'),
         count(*) FILTER (WHERE role = 'entree'),
         count(DISTINCT week_start),
         min(week_start), max(week_start)
  FROM base
  GROUP BY 1
  ORDER BY 2 DESC, 5 DESC, 1;
$function$


-- ═══ public.cooked_alerts_refresh() ═══
CREATE OR REPLACE FUNCTION public.cooked_alerts_refresh()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  p       record;
  r       record;
  v_added int := 0;
BEGIN
  FOR p IN
    SELECT pr.proname
    FROM pg_proc pr
    JOIN pg_namespace n ON n.oid = pr.pronamespace
    WHERE n.nspname = 'public'
      AND pr.proname LIKE 'alert\_rule\_%'
      AND pr.pronargs = 0
    ORDER BY pr.proname
  LOOP
    BEGIN
      FOR r IN EXECUTE format('SELECT kind, severity, detail FROM public.%I()', p.proname) LOOP
        v_added := v_added + public.raise_cooked_alert(r.kind, r.severity, r.detail);
      END LOOP;
    EXCEPTION WHEN others THEN
      v_added := v_added + public.raise_cooked_alert(
        p.proname || '_crashed', 'critical',
        format('La règle %s a levé une exception : %s', p.proname, left(SQLERRM, 300)));
    END;
  END LOOP;
  RETURN v_added;
END;
$function$


-- ═══ public.cooked_ci_cron_jobs() ═══
CREATE OR REPLACE FUNCTION public.cooked_ci_cron_jobs()
 RETURNS TABLE(jobname text, schedule text, active boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'cron', 'public', 'pg_catalog'
AS $function$
  SELECT j.jobname::text, j.schedule::text, j.active
  FROM cron.job j
  ORDER BY 1;
$function$


-- ═══ public.cooked_cpi_snapshot() ═══
CREATE OR REPLACE FUNCTION public.cooked_cpi_snapshot()
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '600s'
AS $function$
  INSERT INTO public.cpi_daily
    (day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit)
  SELECT public.paris_today(),
    path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit
  FROM public.cooked_page_index(28)
  ON CONFLICT (day, path) DO UPDATE SET
    ptype=EXCLUDED.ptype, grade=EXCLUDED.grade, cpi=EXCLUDED.cpi, cpi_raw=EXCLUDED.cpi_raw,
    momentum=EXCLUDED.momentum, gate=EXCLUDED.gate,
    zc=EXCLUDED.zc, zr=EXCLUDED.zr, zl=EXCLUDED.zl, zv=EXCLUDED.zv,
    clics_perdus=EXCLUDED.clics_perdus, n_org=EXCLUDED.n_org, couv_gsc_pct=EXCLUDED.couv_gsc_pct,
    convertit=EXCLUDED.convertit;
$function$


-- ═══ public.cooked_events_window(IN p_occurred_from timestamp with time zone, IN p_occurred_to timestamp with time zone, IN p_grain text, IN p_site text) ═══
CREATE OR REPLACE PROCEDURE public.cooked_events_window(IN p_occurred_from timestamp with time zone, IN p_occurred_to timestamp with time zone, IN p_grain text DEFAULT 'human'::text, IN p_site text DEFAULT 'main'::text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $procedure$
BEGIN
  IF p_grain NOT IN ('raw', 'clean', 'human') THEN
    RAISE EXCEPTION 'cooked_events_window: grain must be raw|clean|human, got %', p_grain;
  END IF;
  IF p_site NOT IN ('main', 'outremer') THEN
    RAISE EXCEPTION 'cooked_events_window: site must be main|outremer, got %', p_site;
  END IF;

  DROP TABLE IF EXISTS _cooked_ev;
  DROP TABLE IF EXISTS _cooked_ev_raw;

  IF p_grain = 'raw' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    END IF;

  ELSIF p_grain = 'clean' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          )
          AND NOT (
            e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
          );
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          )
          AND NOT (
            e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
          );
    END IF;

  ELSIF p_site = 'main' THEN
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at,
             public.paris_date(e.occurred_at) AS d
      FROM public.events_main e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to
        AND NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
        )
        AND NOT (
          e.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(e.props)
        )
        AND NOT (
          e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
        )
        AND NOT (
          e.name IN (
            'cta_phone_click', 'cta_booking_click', 'cta_anchor_click',
            'click_internal', 'click_outbound'
          )
          AND EXISTS (
            SELECT 1 FROM public.events_main dup
            WHERE dup.session_id = e.session_id
              AND dup.name = e.name
              AND dup.path IS NOT DISTINCT FROM e.path
              AND date_trunc('second', dup.occurred_at) = date_trunc('second', e.occurred_at)
              AND (dup.props->>'anchor') IS NOT DISTINCT FROM (e.props->>'anchor')
              AND dup.id < e.id
          )
        );

  ELSE
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at,
             public.paris_date(e.occurred_at) AS d
      FROM public.events_outremer e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to
        AND NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
        )
        AND NOT (
          e.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(e.props)
        )
        AND NOT (
          e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
        );
  END IF;

  ANALYZE _cooked_ev;
END;
$procedure$


-- ═══ public.cooked_is_chrome_anchor(props jsonb) ═══
CREATE OR REPLACE FUNCTION public.cooked_is_chrome_anchor(props jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT
    -- (a) dump de texte (>= 80 car.) : <script>, méga-menu, corps dialog
    --     consent, indicatifs. Vrais libellés courts (max prod : 78).
    char_length(coalesce(props->>'anchor', '')) >= 80
    -- (b) boutons consent + burger + libellés chrome courts
    OR lower(trim(coalesce(props->>'anchor', ''))) = ANY (ARRAY[
      'tout autoriser', 'tout refuser', 'refuser',
      'autoriser la sélection', 'autoriser la selection',
      'personnaliser', 'tout accepter', 'accepter', 'continuer sans accepter',
      'enregistrer', 'afficher les détails', 'menu', 'menu mobile',
      'menu mobile - burger', 'fermer', 'close', 'recherche sur le site'
    ])
    OR lower(coalesce(props->>'anchor', '')) LIKE '%burger%'
    -- (c) corps dialog Cookiebot < 80 car. Phrases SPÉCIFIQUES cookies (pas
    --     le bare 'consentement' : site de droit pénal).
    OR lower(coalesce(props->>'anchor', '')) LIKE '%sélection du consentement%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%modifiez consentement%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%utilise des cookies%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%vendre ou partager mes information%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%iabv2settings%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%paramètres des cookies%'
    -- (d) miroir slugifié (target_section)
    OR lower(trim(coalesce(props->>'target_section', ''))) = ANY (ARRAY[
      'tout-autoriser', 'tout-refuser', 'refuser',
      'autoriser-la-selection', 'personnaliser', 'tout-accepter',
      'accepter', 'continuer-sans-accepter', 'menu', 'menu-mobile-burger'
    ]);
$function$


-- ═══ public.cooked_is_main_site(hostname text, props jsonb) ═══
CREATE OR REPLACE FUNCTION public.cooked_is_main_site(hostname text, props jsonb DEFAULT '{}'::jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT public.cooked_site_scope(hostname, props) = 'main';
$function$


-- ═══ public.cooked_is_spam_referrer(p_hostname text) ═══
CREATE OR REPLACE FUNCTION public.cooked_is_spam_referrer(p_hostname text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT p_hostname IS NOT NULL
    AND p_hostname IN ('m.baidu.com', 'baidu.com');
$function$


-- ═══ public.cooked_normalize_email(raw text) ═══
CREATE OR REPLACE FUNCTION public.cooked_normalize_email(raw text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select nullif(lower(regexp_replace(coalesce(raw, ''), '\s', '', 'g')), '')
$function$


-- ═══ public.cooked_normalize_phone_fr(raw text) ═══
CREATE OR REPLACE FUNCTION public.cooked_normalize_phone_fr(raw text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  select case
    when d = '' then null
    when d like '0033%' and length(d) = 13 then '+33' || substr(d, 5)
    when d like '33%'   and length(d) = 11 then '+' || d
    when d like '0%'    and length(d) = 10 then '+33' || substr(d, 2)
    when length(d) between 8 and 15 then '+' || d
    else null
  end
  from (select regexp_replace(coalesce(raw, ''), '[^0-9]', '', 'g') as d) t
$function$


-- ═══ public.cooked_page_daily_series(target_path text, days_back integer, end_date date) ═══
CREATE OR REPLACE FUNCTION public.cooked_page_daily_series(target_path text, days_back integer, end_date date DEFAULT NULL::date)
 RETURNS TABLE(day date, sessions bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cp AS (SELECT public.canonical_path(target_path) AS p),
  series AS (
    SELECT gs::date AS day
    FROM generate_series(
      coalesce(end_date, public.paris_today()) - (days_back - 1),
      coalesce(end_date, public.paris_today()),
      interval '1 day'
    ) gs
  )
  SELECT s.day,
    coalesce(
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview'
          AND e.device_type IS DISTINCT FROM 'server'
          AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)
      ),
      0
    )::bigint AS sessions
  FROM series s
  LEFT JOIN public.events_human e
    ON public.paris_date(e.occurred_at) = s.day
   AND e.path = (SELECT p FROM cp)
  GROUP BY s.day
  ORDER BY s.day;
$function$


-- ═══ public.cooked_page_index(p_days integer) ═══
CREATE OR REPLACE FUNCTION public.cooked_page_index(p_days integer DEFAULT 28)
 RETURNS TABLE(path text, ptype text, grade text, cpi integer, cpi_raw integer, momentum numeric, momentum_badge text, gate numeric, zc numeric, zr numeric, zl numeric, zv numeric, clics_perdus integer, n_org bigint, couv_gsc_pct integer, convertit boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- T-05 (mission 02/09/2026, #106 — d-03/d-07/f-04) : UNE fenêtre pour tout le score. Côté GSC : p_days jours clos à
-- gsc_last_data_day() (avant : borne sur la date serveur, soit 24 jours de données réelles sur 28 nominaux, lag Google J-4).
-- Côté Cooked : les MÊMES jours Paris, bornés par cooked_paris_ts_start/_end_exclusive (avant : 28 × 24 h glissantes, borne
-- qui glissait avec l'heure du run — deux snapshots consécutifs étaient séparés de 18 à 34 h). Le score d'un jour donné
-- est désormais reproductible. T-09 (#110) : le terme zv (conversion_journeys) est lui aussi clos à gsc_last_data_day() —
-- plus aucune borne d'horloge dans le score ; url passée à classify_channel (gclid ⇒ paid, o-14).
WITH w AS (
  SELECT g.g_end,
         public.cooked_paris_ts_start(g.g_end - (p_days - 1)) AS t0,
         public.cooked_paris_ts_end_exclusive(g.g_end)        AS t1
  FROM (SELECT public.gsc_last_data_day() AS g_end) g
),
fit AS (
  SELECT regr_slope(ln(ctr), ln(pos)) AS pente, regr_intercept(ln(ctr), ln(pos)) AS icept
  FROM (SELECT round(position)::int pos, (sum(clicks)+1.0)/(sum(impressions)+20.0) ctr
        FROM public.gsc_query_page_daily WHERE day > (SELECT g_end FROM w) - 90 AND NOT public.gsc_is_branded(query)
        GROUP BY 1 HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions) >= 200) b
),
capq AS (SELECT g.path, sum(g.impressions) i_qpd,
    sum(g.impressions * least(greatest(exp(f.icept + f.pente*ln(greatest(g.position,1.0))),0.0005),0.5)) e_qpd
  FROM public.gsc_query_page_daily g, fit f WHERE g.day > (SELECT g_end FROM w) - p_days AND NOT public.gsc_is_branded(g.query) GROUP BY g.path),
capb AS (SELECT path, sum(clicks) o_b, sum(impressions) i_b FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - p_days AND public.gsc_is_branded(query) GROUP BY path),
capp AS (SELECT path, sum(clicks) o_full, sum(impressions) i_full FROM public.gsc_path_daily WHERE day > (SELECT g_end FROM w) - p_days GROUP BY path),
cap AS (SELECT p.path, greatest(p.o_full - coalesce(b.o_b,0),0)::numeric AS o,
    CASE WHEN coalesce(q.i_qpd,0)>0 THEN q.e_qpd*(greatest(p.i_full-coalesce(b.i_b,0),0)::numeric/q.i_qpd) ELSE NULL END AS e,
    q.i_qpd, greatest(p.i_full-coalesce(b.i_b,0),0) AS i_nb
  FROM capp p LEFT JOIN capq q ON q.path=p.path LEFT JOIN capb b ON b.path=p.path),
firstpv AS (SELECT DISTINCT ON (session_id) session_id, eh.path,
    public.classify_channel(referrer_hostname, utm_source, utm_medium,'www.jplouton-avocat.fr', url) chan
  FROM public.events_human eh WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) ORDER BY session_id, occurred_at),
orge AS (SELECT session_id, firstpv.path FROM firstpv WHERE chan LIKE 'organic%'),
norg AS (SELECT orge.path, count(*) n_org FROM orge GROUP BY orge.path),
spv AS (SELECT session_id, count(*) pv FROM public.events_human WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) GROUP BY session_id),
pex AS (SELECT e.session_id, e.path,
    max((e.props->>'duration_seconds')::numeric) d,
    max(coalesce((e.props->>'max_scroll')::numeric,0)) s
  FROM public.events_human e
  WHERE e.name='page_exit' AND e.occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w)
  GROUP BY e.session_id, e.path),
ex2 AS (SELECT o.path, public.cooked_page_type(o.path) ptype, px.d,
    coalesce(px.s,0) s,
    (px.d >= 15 OR coalesce(s2.pv,1) >= 2) retained
  FROM orge o JOIN pex px ON px.session_id=o.session_id AND px.path=o.path
  LEFT JOIN spv s2 ON s2.session_id=o.session_id),
thr AS (SELECT ptype, percentile_cont(0.5) WITHIN GROUP (ORDER BY d) tau, percentile_cont(0.5) WITHIN GROUP (ORDER BY s) sig FROM ex2 WHERE retained GROUP BY ptype),
reads AS (SELECT e.path, max(e.ptype) ptype, count(*) n, count(*) FILTER (WHERE retained) r,
    count(*) FILTER (WHERE retained AND d >= t.tau AND s >= t.sig) k FROM ex2 e JOIN thr t ON t.ptype=e.ptype GROUP BY e.path),
tmeans AS (SELECT ptype, coalesce(sum(r)::numeric/nullif(sum(n),0),0.5) rho, coalesce(sum(k)::numeric/nullif(sum(r),0),0.25) q FROM reads GROUP BY ptype),
ebk AS (
  SELECT t.ptype, t.rho, t.q,
    CASE WHEN er.np>=5 AND er.v>0 AND er.v < t.rho*(1-t.rho) THEN least(greatest(t.rho*(1-t.rho)/er.v - 1, 5), 200) ELSE 20 END kappa_ret,
    CASE WHEN el.np>=5 AND el.v>0 AND el.v < t.q*(1-t.q) THEN least(greatest(t.q*(1-t.q)/el.v - 1, 5), 200) ELSE 20 END kappa_lec
  FROM tmeans t
  LEFT JOIN (SELECT ptype, var_samp(r::numeric/n) v, count(*) np FROM reads WHERE n>=10 GROUP BY ptype) er ON er.ptype=t.ptype
  LEFT JOIN (SELECT ptype, var_samp(k::numeric/nullif(r,0)) v, count(*) np FROM reads WHERE r>=10 GROUP BY ptype) el ON el.ptype=t.ptype
),
jx AS (SELECT * FROM public.conversion_journeys(p_days, (SELECT g_end FROM w)) WHERE entry_channel LIKE 'organic%'),
direct AS (SELECT entry_path path, count(*)::numeric v FROM jx WHERE entry_path IS NOT NULL GROUP BY 1),
assist AS (SELECT jp.path, sum(1.0/greatest(j.pages_count,1)) v FROM jx j CROSS JOIN LATERAL unnest(j.journey) jp(path) WHERE jp.path <> j.entry_path GROUP BY jp.path),
book AS (SELECT o.path, 0.25*count(*)::numeric v FROM orge o JOIN public.events_human b ON b.session_id=o.session_id AND b.path=o.path AND b.name='cta_booking_click' GROUP BY o.path),
convv AS (SELECT n.path, n.n_org, coalesce(d.v,0)+coalesce(a.v,0)+coalesce(b.v,0) val
  FROM norg n LEFT JOIN direct d ON d.path=n.path LEFT JOIN assist a ON a.path=n.path LEFT JOIN book b ON b.path=n.path),
tconv AS (SELECT public.cooked_page_type(convv.path) ptype, coalesce(sum(val)/nullif(sum(convv.n_org),0),0) nu FROM convv GROUP BY 1),
xs AS (
  SELECT r.path, r.ptype, c.n_org, c.val, coalesce(cap.o,0) o, cap.e, coalesce(cap.i_qpd,0) i_qpd, coalesce(cap.i_nb,0) i_nb,
    coalesce(ln((coalesce(cap.o,0)+3)/(cap.e+3)),0) x_cap,
    ln( least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999) / (1-least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999)) ) x_ret,
    ln( least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999) / (1-least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999)) ) x_lec,
    ln( (c.val + 30*tc.nu + 0.05)/(c.n_org+30) ) x_conv
  FROM reads r JOIN convv c ON c.path=r.path LEFT JOIN cap ON cap.path=r.path
  JOIN ebk tm ON tm.ptype=r.ptype JOIN tconv tc ON tc.ptype=r.ptype
  WHERE c.n_org >= 5 AND r.n >= 3
),
medt AS (SELECT ptype, count(*) cnt, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs GROUP BY ptype),
madt AS (SELECT x.ptype,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-m.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-m.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-m.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-m.mv)),0.15) sv FROM xs x JOIN medt m ON m.ptype=x.ptype GROUP BY x.ptype),
medg AS (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs),
madg AS (SELECT greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-g.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-g.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-g.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-g.mv)),0.15) sv FROM xs x, medg g),
mom AS (SELECT g.path,
    coalesce(sum(clicks) FILTER (WHERE day > (SELECT g_end FROM w) - p_days),0) c1,
    coalesce(sum(clicks) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days),0) c0,
    avg(position) FILTER (WHERE day > (SELECT g_end FROM w) - p_days) p1,
    avg(position) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days) p0
  FROM public.gsc_query_page_daily g
  WHERE g.day > (SELECT g_end FROM w) - 2*p_days AND NOT public.gsc_is_branded(g.query)
  GROUP BY g.path),
site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom),
lcp AS (SELECT eh.path, percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric) lcp75
  FROM public.events_human eh WHERE name='web_vitals' AND props->>'metric'='LCP' AND device_type='mobile'
    AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) GROUP BY eh.path),
scored AS (
  SELECT x.path, x.ptype, x.n_org, round(greatest(coalesce(x.e,0)-x.o,0))::int clics_perdus,
    CASE WHEN coalesce(x.i_nb,0)>0 THEN round(100.0*x.i_qpd/x.i_nb)::int ELSE 0 END couv,
    round(least(greatest((x.x_cap - CASE WHEN mt.cnt>=15 THEN mt.mc ELSE mg.mc END)/(CASE WHEN mt.cnt>=15 THEN dt.sc ELSE dg.sc END),-3),3)::numeric,1) zc,
    round(least(greatest((x.x_ret - CASE WHEN mt.cnt>=15 THEN mt.mr ELSE mg.mr END)/(CASE WHEN mt.cnt>=15 THEN dt.sr ELSE dg.sr END),-3),3)::numeric,1) zr,
    round(least(greatest((x.x_lec - CASE WHEN mt.cnt>=15 THEN mt.ml ELSE mg.ml END)/(CASE WHEN mt.cnt>=15 THEN dt.sl ELSE dg.sl END),-3),3)::numeric,1) zl,
    round(least(greatest((x.x_conv - CASE WHEN mt.cnt>=15 THEN mt.mv ELSE mg.mv END)/(CASE WHEN mt.cnt>=15 THEN dt.sv ELSE dg.sv END),-3),3)::numeric,1) zv,
    round(exp(least(greatest(
      (1 - 1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (-0.08*coalesce(m.p1-m.p0,0))
      + (1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (ln((coalesce(m.c1,0)+5.0)/(coalesce(m.c0,0)+5.0)) - ln((s.s1+50.0)/(s.s0+50.0)))
    ,-0.336),0.336))::numeric,2) mm,
    round((1 - 0.15*least(greatest((coalesce(l.lcp75,2500)-2500)/2500.0,0),1))::numeric,2) gg,
    CASE
      WHEN x.n_org >= 200 AND coalesce(x.e,0) >= 40 THEN 'S'
      WHEN x.n_org >= 100 AND coalesce(x.e,0) >= 20 THEN 'A'
      WHEN x.n_org >= 30 AND coalesce(x.e,0) >= 5 THEN 'B'
      ELSE 'C'
    END grade,
    coalesce(cv.val, 0) > 0 AS convertit
  FROM xs x LEFT JOIN medt mt ON mt.ptype=x.ptype LEFT JOIN madt dt ON dt.ptype=x.ptype
  CROSS JOIN medg mg CROSS JOIN madg dg LEFT JOIN mom m ON m.path=x.path CROSS JOIN site s LEFT JOIN lcp l ON l.path=x.path
  LEFT JOIN convv cv ON cv.path=x.path
)
SELECT scored.path, scored.ptype, scored.grade,
  least(100, round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int) cpi,
  round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int cpi_raw,
  mm momentum, (CASE WHEN mm>=1.15 THEN '↗' WHEN mm<=0.87 THEN '↘' ELSE '→' END) momentum_badge,
  gg gate, zc, zr, zl, zv, clics_perdus, n_org, couv couv_gsc_pct, convertit
FROM scored
$function$


-- ═══ public.cooked_page_type(p text) ═══
CREATE OR REPLACE FUNCTION public.cooked_page_type(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when p is null then 'autre'
    when p = '/' then 'cabinet'
    when p in ('/notre-cabinet','/honoraires-rendez-vous','/mentions-legales','/comprendre-le-droit') then 'cabinet'
    when p in ('/defense-penale','/indemnisation-des-victimes','/droit-des-contrats-et-des-personnes') then 'hub'
    when p like '/defense-penale/%'
      or p like '/indemnisation-des-victimes/%'
      or p like '/droit-des-contrats-et-des-personnes/%' then 'expertise'
    when p like '/post/%' then 'post'
    when p like '/blog%' then 'blog-nav'
    else 'autre'
  end;
$function$


-- ═══ public.cooked_pages_compare(period_kind text, data_lens text) ═══
CREATE OR REPLACE FUNCTION public.cooked_pages_compare(period_kind text DEFAULT 'rolling_28'::text, data_lens text DEFAULT 'cross'::text)
 RETURNS TABLE(path text, sessions_n bigint, sessions_prev bigint, sessions_delta_pct numeric, contacts_n bigint, contacts_prev bigint, contacts_delta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  b RECORD;
  v_first_seen date;
  v_has_prev   boolean;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, data_lens) LIMIT 1;
  v_first_seen := public.paris_date(public.tracker_first_seen_global());
  v_has_prev := v_first_seen IS NOT NULL AND v_first_seen <= b.prev_start;

  RETURN QUERY
  WITH n_sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview'
          AND e.device_type IS DISTINCT FROM 'server'
          AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)
      )::bigint AS sessions_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL
      AND public.paris_date(e.occurred_at) >= b.n_start
      AND public.paris_date(e.occurred_at) <= b.n_end
    GROUP BY e.path
  ),
  prev_sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview'
          AND e.device_type IS DISTINCT FROM 'server'
          AND NOT public.cooked_is_spam_referrer(e.referrer_hostname)
      )::bigint AS sessions_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL AND v_has_prev
      AND public.paris_date(e.occurred_at) >= b.prev_start
      AND public.paris_date(e.occurred_at) <= b.prev_end
    GROUP BY e.path
  ),
  n_mc AS (
    SELECT mc.path AS p, mc.contacts AS contacts_total
    FROM public.macro_contacts_by_path(b.n_start, b.n_end) mc
  ),
  prev_mc AS (
    SELECT mc.path AS p, mc.contacts AS contacts_total
    FROM public.macro_contacts_by_path(b.prev_start, b.prev_end) mc
    WHERE v_has_prev
  ),
  paths AS (
    SELECT n_sess.p FROM n_sess
    UNION SELECT prev_sess.p FROM prev_sess
    UNION SELECT n_mc.p FROM n_mc
    UNION SELECT prev_mc.p FROM prev_mc
  )
  SELECT
    paths.p,
    coalesce(ns.sessions_total, 0),
    CASE WHEN v_has_prev THEN coalesce(ps.sessions_total, 0) ELSE NULL END,
    CASE WHEN v_has_prev AND coalesce(ps.sessions_total, 0) > 0
         THEN round((100.0 * (coalesce(ns.sessions_total, 0) - ps.sessions_total) / ps.sessions_total)::numeric, 2)
         ELSE NULL END,
    coalesce(nm.contacts_total, 0),
    CASE WHEN v_has_prev THEN coalesce(pm.contacts_total, 0) ELSE NULL END,
    CASE WHEN v_has_prev AND coalesce(pm.contacts_total, 0) > 0
         THEN round((100.0 * (coalesce(nm.contacts_total, 0) - pm.contacts_total) / pm.contacts_total)::numeric, 2)
         ELSE NULL END
  FROM paths
    LEFT JOIN n_sess ns ON ns.p = paths.p
    LEFT JOIN prev_sess ps ON ps.p = paths.p
    LEFT JOIN n_mc nm ON nm.p = paths.p
    LEFT JOIN prev_mc pm ON pm.p = paths.p;
END;
$function$


-- ═══ public.cooked_pages_snapshot(p_period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.cooked_pages_snapshot(p_period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 15)
 RETURNS TABLE(path text, cooked_sessions bigint, cooked_contacts bigint, cooked_phone_clicks bigint, cooked_form_submits bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH b AS (
    SELECT n_start, n_end
    FROM public.cooked_period_bounds(p_period_kind, 'live')
    LIMIT 1
  ),
  sess AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total
    FROM public.events_human e, b
    WHERE e.path IS NOT NULL
      AND public.paris_date(e.occurred_at) >= b.n_start
      AND public.paris_date(e.occurred_at) <= b.n_end
    GROUP BY e.path
  ),
  mc AS (
    SELECT m.path AS p, m.contacts, m.phone_clicks, m.form_submits
    FROM public.macro_contacts_by_path(
      (SELECT n_start FROM b),
      (SELECT n_end FROM b)
    ) m
  )
  SELECT
    coalesce(s.p, mc.p),
    coalesce(s.sessions_total, 0),
    coalesce(mc.contacts, 0),
    coalesce(mc.phone_clicks, 0),
    coalesce(mc.form_submits, 0)
  FROM sess s
    FULL OUTER JOIN mc ON mc.p = s.p
  ORDER BY coalesce(s.sessions_total, 0) DESC, coalesce(mc.contacts, 0) DESC, coalesce(s.p, mc.p)
  LIMIT max_rows;
$function$


-- ═══ public.cooked_paris_ts_end_exclusive(p_day date) ═══
CREATE OR REPLACE FUNCTION public.cooked_paris_ts_end_exclusive(p_day date)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT ((p_day + 1)::timestamp AT TIME ZONE 'Europe/Paris');
$function$


-- ═══ public.cooked_paris_ts_start(p_day date) ═══
CREATE OR REPLACE FUNCTION public.cooked_paris_ts_start(p_day date)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT (p_day::timestamp AT TIME ZONE 'Europe/Paris');
$function$


-- ═══ public.cooked_period_bounds(period_kind text, data_lens text) ═══
CREATE OR REPLACE FUNCTION public.cooked_period_bounds(period_kind text, data_lens text DEFAULT 'live'::text)
 RETURNS TABLE(period_kind_out text, label_fr text, n_start date, n_end date, prev_start date, prev_end date, day_count integer, paris_today date, gsc_last_day date, lag_days integer, data_lens_out text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_kind text; v_lens text; v_today date := public.paris_today();
  v_gsc_last date; v_anchor date; v_n_start date; v_n_end date;
  v_prev_start date; v_prev_end date; v_label text; v_days integer; v_lag integer;
BEGIN
  v_kind := lower(trim(coalesce(period_kind, 'rolling_28')));
  v_lens := lower(trim(coalesce(data_lens, 'live')));
  IF v_lens NOT IN ('live', 'live_j1', 'gsc', 'cross') THEN v_lens := 'live'; END IF;
  v_gsc_last := public.gsc_last_data_day();
  v_lag := CASE WHEN v_gsc_last IS NOT NULL THEN (v_today - v_gsc_last)::integer ELSE NULL END;
  IF v_lens = 'live_j1' THEN v_anchor := v_today - 1;
  ELSIF v_lens = 'live' THEN v_anchor := v_today;
  ELSE v_anchor := coalesce(v_gsc_last, v_today); END IF;
  v_n_end := v_anchor;
  CASE v_kind
    WHEN 'today' THEN v_n_start := v_anchor; v_prev_start := v_anchor - 1; v_prev_end := v_anchor - 1; v_label := 'Aujourd''hui';
    WHEN 'week' THEN v_n_start := date_trunc('week', v_anchor::timestamp)::date; v_prev_start := v_n_start - 7; v_prev_end := v_n_end - 7; v_label := 'Semaine en cours';
    WHEN 'month' THEN v_n_start := date_trunc('month', v_anchor::timestamp)::date; v_prev_end := (v_n_end::timestamp - interval '1 month')::date; v_prev_start := date_trunc('month', v_prev_end::timestamp)::date; v_label := 'Mois en cours';
    WHEN 'rolling_90' THEN v_n_start := v_anchor - 89; v_prev_end := v_n_start - 1; v_prev_start := v_prev_end - 89; v_label := '3 derniers mois';
    ELSE v_kind := 'rolling_28'; v_n_start := v_anchor - 27; v_prev_end := v_n_start - 1; v_prev_start := v_prev_end - 27; v_label := '28 derniers jours';
  END CASE;
  v_days := (v_n_end - v_n_start + 1)::integer;
  RETURN QUERY SELECT v_kind, v_label, v_n_start, v_n_end, v_prev_start, v_prev_end, v_days, v_today, v_gsc_last, v_lag, v_lens;
END;
$function$


-- ═══ public.cooked_refresh_after_gsc() ═══
CREATE OR REPLACE FUNCTION public.cooked_refresh_after_gsc()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last_ingest   timestamptz;
  v_last_complete timestamptz;
  v_today_paris   date := public.paris_today();
  v_steps constant text[] := ARRAY[
    'cooked_cpi_snapshot',
    'refresh_dashboard_snapshots',
    'refresh_dashboard_expertises_snapshots',
    'refresh_dashboard_resources_assisted'
  ];
  v_step     text;
  v_i        integer;
  v_failures text[] := array[]::text[];
  v_detail   text;
  v_err      text;
  v_state    text;
BEGIN
  -- Un seul orchestrateur à la fois : lock de portée transaction, relâché
  -- automatiquement (y compris en cas d'erreur).
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RETURN 'skip: un refresh est déjà en cours';
  END IF;

  SELECT max(ingested_at) INTO v_last_ingest FROM public.gsc_path_daily;

  SELECT value::timestamptz INTO v_last_complete
  FROM public.cooked_config
  WHERE key = 'last_full_refresh_after_gsc_at';

  -- L'ingestion du jour n'a pas encore atterri : on repassera dans une heure.
  IF v_last_ingest IS NULL
     OR public.paris_date(v_last_ingest) < v_today_paris THEN
    RETURN 'skip: ingestion GSC du jour pas encore arrivée';
  END IF;

  -- La séquence COMPLÈTE a déjà tourné après cette ingestion : rien à faire.
  IF v_last_complete IS NOT NULL AND v_last_complete >= v_last_ingest THEN
    RETURN 'skip: séquence déjà complète après l''ingestion du jour';
  END IF;

  -- CPI en PREMIER : un jour manqué de cpi_daily est perdu pour toujours
  -- (cooked_page_index lit now()), un snapshot dashboard se reconstruit à
  -- l'identique une heure plus tard. Chaque étape est une sous-transaction :
  -- son échec — statement_timeout compris, d'où le OR query_canceled que
  -- OTHERS n'inclut pas — n'emporte ni les étapes déjà faites ni les
  -- suivantes.
  FOR v_i IN 1..cardinality(v_steps) LOOP
    v_step := v_steps[v_i];
    BEGIN
      EXECUTE format('SELECT public.%I()', v_step);
    EXCEPTION WHEN OTHERS OR query_canceled THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
      v_detail := format('%s [%s]: %s', v_step, v_state, v_err);
      IF v_state = '57014' AND v_i < cardinality(v_steps) THEN
        v_detail := v_detail || format(' — étapes non lancées (budget timeout épuisé) : %s',
                                       array_to_string(v_steps[v_i + 1:], ', '));
      END IF;
      v_failures := v_failures || v_detail;

      -- Alerte granulaire par étape (dédup 24 h par kind, push ntfy sur
      -- critical). Blindée : elle ne doit jamais annuler le travail déjà
      -- fait en sous-transaction.
      BEGIN
        PERFORM public.raise_cooked_alert(
          'refresh_step_failed_' || v_step, 'critical',
          format('Refresh après GSC — %s. Les étapes réussies sont conservées ; retry complet au prochain tick horaire (cron 46, 8h-20h).',
                 v_detail));
      EXCEPTION WHEN OTHERS OR query_canceled THEN
        NULL;
      END;

      -- Budget 2400 s consommé : l'alarme ne se réarme pas, continuer
      -- ferait tourner les étapes restantes sans borne de temps.
      IF v_state = '57014' THEN
        EXIT;
      END IF;
    END;
  END LOOP;

  IF cardinality(v_failures) = 0 THEN
    -- Marqueur de fin : écrit uniquement si les 4 étapes ont abouti — l'heure
    -- suivante rejoue donc la séquence complète tant qu'une étape échoue.
    -- Blindé : un raté du marqueur vaut un simple rejeu idempotent, pas
    -- l'annulation des 4 étapes.
    BEGIN
      INSERT INTO public.cooked_config (key, value, updated_at)
      VALUES ('last_full_refresh_after_gsc_at', now()::text, now())
      ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
    EXCEPTION WHEN OTHERS OR query_canceled THEN
      NULL;
    END;

    RETURN format('ok: séquence complète après ingestion du %s',
                  to_char(v_last_ingest AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'));
  END IF;

  RETURN format('partiel: %s', array_to_string(v_failures, ' | '));
END;
$function$


-- ═══ public.cooked_site_scope(hostname text, props jsonb) ═══
CREATE OR REPLACE FUNCTION public.cooked_site_scope(hostname text, props jsonb DEFAULT '{}'::jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT CASE
    WHEN COALESCE(hostname, '') = 'outremer.jplouton-avocat.fr'
      OR COALESCE(props->>'cooked_site', '') = 'outremer'
    THEN 'outremer'
    ELSE 'main'
  END;
$function$


-- ═══ public.cooked_snapshot_window(IN p_window text, IN p_grain text, OUT o_label_fr text, OUT o_lns date, OUT o_lne date, OUT o_lps date, OUT o_lpe date, OUT o_lpt date, OUT o_ld integer, OUT o_gns date, OUT o_gne date, OUT o_gps date, OUT o_gpe date, OUT o_glast date, OUT o_glag integer) ═══
CREATE OR REPLACE PROCEDURE public.cooked_snapshot_window(IN p_window text, IN p_grain text, OUT o_label_fr text, OUT o_lns date, OUT o_lne date, OUT o_lps date, OUT o_lpe date, OUT o_lpt date, OUT o_ld integer, OUT o_gns date, OUT o_gne date, OUT o_gps date, OUT o_gpe date, OUT o_glast date, OUT o_glag integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $procedure$
BEGIN
  IF p_window NOT IN ('rolling_28', 'rolling_90') THEN
    RAISE EXCEPTION 'cooked_snapshot_window: unsupported window %', p_window;
  END IF;
  IF p_grain NOT IN ('clean', 'human') THEN
    RAISE EXCEPTION 'cooked_snapshot_window: grain must be clean|human, got %', p_grain;
  END IF;

  SELECT b.label_fr, b.n_start, b.n_end, b.prev_start, b.prev_end, b.paris_today, b.day_count
    INTO o_label_fr, o_lns, o_lne, o_lps, o_lpe, o_lpt, o_ld
  FROM public.cooked_period_bounds(p_window, 'live_j1') b;

  SELECT b.n_start, b.n_end, b.prev_start, b.prev_end, b.gsc_last_day, b.lag_days
    INTO o_gns, o_gne, o_gps, o_gpe, o_glast, o_glag
  FROM public.cooked_period_bounds(p_window, 'gsc') b;

  o_ld := (o_lne - o_lns + 1)::int;

  CALL public.cooked_events_window(
    public.cooked_paris_ts_start(o_lps),
    public.cooked_paris_ts_end_exclusive(o_lne),
    p_grain,
    'main'
  );
END;
$procedure$


-- ═══ public.cooked_weekly_conversions_snapshot(p_week_start date) ═══
CREATE OR REPLACE FUNCTION public.cooked_weekly_conversions_snapshot(p_week_start date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE 'Europe/Paris')::date;
  v_week  date;
  v_days  integer;
  v_rows  integer;
BEGIN
  -- defaut : la derniere semaine COMPLETE (lundi -> dimanche revolus)
  v_week := date_trunc('week',
              COALESCE(p_week_start::timestamp,
                       date_trunc('week', v_today::timestamp) - interval '7 days'))::date;

  IF v_week + 6 >= v_today THEN
    RAISE EXCEPTION 'semaine non terminee (% -> %), rien de fige', v_week, v_week + 6;
  END IF;

  -- fenetre a couvrir depuis maintenant, + 1 jour de marge
  v_days := (v_today - v_week) + 2;

  DELETE FROM public.conversion_weekly WHERE week_start = v_week;

  INSERT INTO public.conversion_weekly (
    week_start, occurred_at, contact_kind, contact_path, entry_path,
    entry_channel, objet, device_type, attribution_method, anonymous_id,
    pages_count, journey)
  SELECT v_week, j.occurred_at, j.contact_kind, j.contact_path, j.entry_path,
         j.entry_channel, j.objet, j.device_type, j.attribution_method,
         j.anonymous_id, j.pages_count, j.journey
  FROM public.conversion_journeys(v_days) j
  WHERE date_trunc('week', (j.occurred_at AT TIME ZONE 'Europe/Paris'))::date = v_week;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$function$


-- ═══ public.cpi_compose(zc numeric, zr numeric, zl numeric, zv numeric, mm numeric, gg numeric, exclude_conversion boolean) ═══
CREATE OR REPLACE FUNCTION public.cpi_compose(zc numeric, zr numeric, zl numeric, zv numeric DEFAULT 0, mm numeric DEFAULT 1, gg numeric DEFAULT 1, exclude_conversion boolean DEFAULT false)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT 100::numeric * (1::numeric / (1::numeric + exp(
    -(
      CASE WHEN exclude_conversion THEN
        0.46::numeric * zc + 0.23::numeric * zr + (0.20::numeric / 0.65::numeric) * zl
      ELSE
        0.30::numeric * zc + 0.15::numeric * zr + 0.20::numeric * zl + 0.35::numeric * zv
      END
    ) / 0.8::numeric
  ))) * mm * gg;
$function$


-- ═══ public.cta_breakdown_for_path(path text, days_back integer) ═══
CREATE OR REPLACE FUNCTION public.cta_breakdown_for_path(path text, days_back integer DEFAULT 28)
 RETURNS TABLE(cta_type text, placement text, anchor_sample text, clicks bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with cta as (
    select
      case e.name
        when 'cta_phone_click'   then 'phone'
        when 'cta_email_click'   then 'email'
        when 'cta_booking_click' then 'booking'
        when 'cta_anchor_click'  then coalesce(m.cta_type, 'anchor_nav')  -- ⬅️ fix : ne plus jeter
      end                                                 as cta_type,
      coalesce(nullif(e.props->>'placement', ''), 'body') as placement,
      coalesce(e.props->>'anchor', '')                    as anchor
    from public.events_human e
    left join public.cta_anchor_label_map m
      on m.label = e.props->>'anchor'
     and e.name = 'cta_anchor_click'
    where e.name in ('cta_phone_click', 'cta_email_click', 'cta_booking_click', 'cta_anchor_click')
      and e.path = cta_breakdown_for_path.path
      and e.occurred_at >= now() - (cta_breakdown_for_path.days_back * interval '1 day')
  )
  select cta_type, placement, anchor as anchor_sample, count(*)::bigint
  from cta
  where cta_type is not null  -- ne sert plus que pour des cas de name=NULL ; sémantique gardée
  group by cta_type, placement, anchor
  order by 4 desc, cta_type, placement;
$function$


-- ═══ public.ctr_for_position(pos numeric) ═══
CREATE OR REPLACE FUNCTION public.ctr_for_position(pos numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN pos IS NULL OR pos < 1 THEN NULL
    WHEN pos <  1.5 THEN 0.280
    WHEN pos <  2.5 THEN 0.150
    WHEN pos <  3.5 THEN 0.110
    WHEN pos <  4.5 THEN 0.080
    WHEN pos <  5.5 THEN 0.060
    WHEN pos <  6.5 THEN 0.040
    WHEN pos <  7.5 THEN 0.030
    WHEN pos <  8.5 THEN 0.025
    WHEN pos <  9.5 THEN 0.020
    WHEN pos < 10.5 THEN 0.015
    WHEN pos < 20.5 THEN 0.005
    ELSE 0.001
  END;
$function$


-- ═══ public.dashboard_annotations(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_annotations(period_kind text DEFAULT 'rolling_90'::text)
 RETURNS TABLE(day date, kind text, label text, paths text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH b AS (
    SELECT n_start, n_end
    FROM public.cooked_period_bounds(
      CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END,
      'live_j1')
  )
  SELECT a.day, a.kind, a.label, a.paths
  FROM public.annotations a, b
  WHERE a.day BETWEEN b.n_start AND b.n_end
  ORDER BY a.day, a.id;
$function$


-- ═══ public.dashboard_article_detail(p_path text, period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_article_detail(p_path text, period_kind text DEFAULT 'rolling_28'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '45s'
AS $function$
DECLARE
  lns date; lne date; lps date; lpe date;
  gns date; gne date; gps date; gpe date;
  result jsonb;
BEGIN
  SELECT b.n_start,b.n_end,b.prev_start,b.prev_end INTO lns,lne,lps,lpe FROM cooked_period_bounds(period_kind,'live_j1') b;
  SELECT b.n_start,b.n_end,b.prev_start,b.prev_end INTO gns,gne,gps,gpe FROM cooked_period_bounds(period_kind,'gsc') b;

  SELECT jsonb_build_object(
    'path', p_path,
    'meta', (SELECT jsonb_build_object(
        'theme', pt.theme, 'category', pt.category,
        'naissance_google', (SELECT min(day) FROM gsc_path_daily g WHERE g.path=p_path AND g.impressions>0),
        'first_tracker_day', (SELECT min(public.paris_date(e.occurred_at)) FROM events_human e WHERE e.path=p_path AND e.name='pageview'),
        'age_jours', (public.paris_today() - (SELECT min(day) FROM gsc_path_daily g WHERE g.path=p_path AND g.impressions>0))::int
      ) FROM page_taxonomy pt WHERE pt.path=p_path),
    'gsc', (SELECT jsonb_build_object(
        'clicks', COALESCE(sum(clicks),0), 'impressions', COALESCE(sum(impressions),0),
        'position', round(avg(position)::numeric,1),
        'ctr_pct', CASE WHEN COALESCE(sum(impressions),0)>0 THEN round(100.0*sum(clicks)/sum(impressions),2) END,
        'ctr_expected', CASE WHEN avg(position) IS NOT NULL THEN round(ctr_for_position(avg(position))*100,2) END,
        'clicks_prev', (SELECT COALESCE(sum(clicks),0) FROM gsc_path_daily g2 WHERE g2.path=p_path AND g2.day BETWEEN gps AND gpe)
      ) FROM gsc_path_daily g WHERE g.path=p_path AND g.day BETWEEN gns AND gne),
    'gsc_daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', ds.d, 'clicks', COALESCE(g.clicks,0), 'impressions', COALESCE(g.impressions,0)) ORDER BY ds.d), '[]'::jsonb)
      FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
      LEFT JOIN (SELECT day, sum(clicks) clicks, sum(impressions) impressions FROM gsc_path_daily WHERE path=p_path AND day BETWEEN gns AND gne GROUP BY day) g ON g.day=ds.d),
    'visitors_daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', ds.d, 'v', COALESCE(v.n,0)) ORDER BY ds.d), '[]'::jsonb)
      FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
      LEFT JOIN (SELECT public.paris_date(e.occurred_at) d, count(DISTINCT e.anonymous_id) n
                 FROM events_human e
                 WHERE e.path=p_path AND e.name='pageview'
                   AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
                   AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
                   AND e.occurred_at >= public.cooked_paris_ts_start(lns)
                   AND e.occurred_at <  public.cooked_paris_ts_end_exclusive(lne)
                 GROUP BY 1) v ON v.d=ds.d),
    'top_queries', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'query', q.query, 'clicks', q.clicks, 'impressions', q.impressions, 'position', q.pos,
        'volume_fr', dfs.search_volume, 'cpc', dfs.cpc) ORDER BY q.impressions DESC), '[]'::jsonb)
      FROM (SELECT query, sum(clicks) clicks, sum(impressions) impressions, round(avg(position)::numeric,1) pos
            FROM gsc_query_page_daily WHERE path=p_path AND day BETWEEN gns AND gne AND NOT public.gsc_is_branded(query)
            GROUP BY query ORDER BY sum(impressions) DESC LIMIT 10) q
      LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=q.query AND dfs.location_code=2250),
    'cpi', (SELECT to_jsonb(c) - 'created_at' FROM cpi_daily c WHERE c.path=p_path AND c.day=(SELECT max(day) FROM cpi_daily) ),
    'cpi_series', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', day, 'cpi', cpi) ORDER BY day), '[]'::jsonb)
      FROM cpi_daily WHERE path=p_path),
    'assisted', (SELECT jsonb_build_object('n', s.assisted_contacts, 'prev', s.assisted_prev)
      FROM dashboard_resources_assisted_snapshot s WHERE s.path=p_path AND s.window_kind=period_kind),
    'bounds', jsonb_build_object('cooked_start', lns, 'cooked_end', lne, 'gsc_start', gns, 'gsc_end', gne)
  ) INTO result;
  RETURN result;
END $function$


-- ═══ public.dashboard_assisted_quarter() ═══
CREATE OR REPLACE FUNCTION public.dashboard_assisted_quarter()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '30s'
AS $function$
DECLARE
  q_start date := date_trunc('quarter', public.paris_today())::date;
  q_end   date := public.paris_today();
  q_label text := 'T' || extract(quarter FROM q_start)::int || ' ' || extract(year FROM q_start)::int;
  v_value int;
  v_target int;
BEGIN
  SELECT coalesce(sum(a.contacts), 0)::int INTO v_value
  FROM public.assisted_contacts_by_entry_path(q_start, q_end) a
  JOIN public.page_taxonomy pt ON pt.path = a.entry_path AND pt.category = 'ressource';

  SELECT NULLIF(btrim(value), '')::int INTO v_target
  FROM public.cooked_config WHERE key = 'objectif_assistes_trimestre';

  RETURN jsonb_build_object(
    'quarter', q_label,
    'quarter_start', q_start,
    'value', COALESCE(v_value, 0),
    'target', v_target
  );
END;
$function$


-- ═══ public.dashboard_expertises_kpis(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_expertises_kpis(period_kind text DEFAULT 'rolling_90'::text)
 RETURNS SETOF dashboard_expertises_kpis_snapshot
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT * FROM public.dashboard_expertises_kpis_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$function$


-- ═══ public.dashboard_expertises_overview(period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.dashboard_expertises_overview(period_kind text DEFAULT 'rolling_90'::text, max_rows integer DEFAULT 100)
 RETURNS SETOF dashboard_expertises_snapshot
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT * FROM public.dashboard_expertises_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END
  ORDER BY unique_visitors DESC NULLS LAST LIMIT max_rows;
$function$


-- ═══ public.dashboard_expertises_trend(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_expertises_trend(period_kind text DEFAULT 'rolling_90'::text)
 RETURNS TABLE(visitors_daily numeric[], pageviews_daily numeric[], contacts_daily numeric[], gsc_clicks_daily numeric[], gsc_impressions_daily numeric[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily
  FROM public.dashboard_expertises_trend_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$function$


-- ═══ public.dashboard_honoraires_funnel(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_honoraires_funnel(period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(booking_sessions bigint, honoraires_sessions bigint, booking_then_honoraires bigint, forms_after_booking_6h bigint, forms_on_honoraires bigint, forms_macro_total bigint, rate_booking_to_form numeric, cooked_start date, cooked_end date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  b record;
  t0 timestamptz;
  t1 timestamptz;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, 'live_j1');
  t0 := (b.n_start::timestamp AT TIME ZONE 'Europe/Paris');
  t1 := ((b.n_end + 1)::timestamp AT TIME ZONE 'Europe/Paris');

  RETURN QUERY
  WITH book AS (
    SELECT e.session_id, min(e.occurred_at) AS bt
    FROM public.events_human e
    WHERE e.occurred_at >= t0 AND e.occurred_at < t1
      AND e.name = 'cta_booking_click'
      AND e.device_type IS DISTINCT FROM 'server'
    GROUP BY e.session_id
  ),
  hon AS (
    SELECT DISTINCT e.session_id
    FROM public.events_human e
    WHERE e.occurred_at >= t0 AND e.occurred_at < t1
      AND e.name = 'pageview'
      AND e.path = '/honoraires-rendez-vous'
  ),
  forms AS (
    SELECT e.occurred_at AS ft,
           e.props->>'cooked_sid' AS sid,
           e.path,
           e.props->>'page_source' AS page_source
    FROM public.events_human e
    WHERE e.occurred_at >= t0 AND e.occurred_at < t1
      AND e.name = 'form_submit'
      AND public.form_submit_counts_as_macro(e.props)
  ),
  agg AS (
    SELECT
      (SELECT count(*)::bigint FROM book) AS booking_sessions,
      (SELECT count(*)::bigint FROM hon) AS honoraires_sessions,
      (SELECT count(*)::bigint FROM book bk INNER JOIN hon h USING (session_id))
        AS booking_then_honoraires,
      (SELECT count(*)::bigint FROM (
         SELECT DISTINCT f.sid
         FROM forms f
         INNER JOIN book bk ON bk.session_id = f.sid
         WHERE f.ft >= bk.bt AND f.ft <= bk.bt + interval '6 hours'
           AND f.sid IS NOT NULL
       ) x) AS forms_after_booking_6h,
      (SELECT count(*)::bigint FROM forms f
        WHERE f.path = '/honoraires-rendez-vous'
           OR coalesce(f.page_source, '') ILIKE '%honoraires%')
        AS forms_on_honoraires,
      (SELECT count(*)::bigint FROM forms) AS forms_macro_total
  )
  SELECT
    a.booking_sessions,
    a.honoraires_sessions,
    a.booking_then_honoraires,
    a.forms_after_booking_6h,
    a.forms_on_honoraires,
    a.forms_macro_total,
    CASE WHEN a.booking_sessions > 0
      THEN round((100.0 * a.forms_after_booking_6h / a.booking_sessions)::numeric, 1)
      ELSE NULL END,
    b.n_start,
    b.n_end
  FROM agg a;
END;
$function$


-- ═══ public.dashboard_intervention_effect(p_path text, p_day date) ═══
CREATE OR REPLACE FUNCTION public.dashboard_intervention_effect(p_path text, p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_gsc_last   date := public.gsc_last_data_day();
  v_pre_start  date := p_day - 28;
  v_pre_end    date := p_day - 1;
  v_post_start date := p_day;
  v_post_end   date := LEAST(public.gsc_last_data_day(), p_day + 27);
  v_days_post  int  := GREATEST(0, (LEAST(public.gsc_last_data_day(), p_day + 27) - p_day) + 1);
  v_pre_clics  numeric := 0; v_pre_imp  numeric := 0; v_pre_posw  numeric := 0;
  v_post_clics numeric := 0; v_post_imp numeric := 0; v_post_posw numeric := 0;
  v_site_pre   numeric := 0; v_site_post numeric := 0;
  v_first_gsc  date;  v_age_gsc int;  v_jeune boolean;
  v_ppd_pre numeric; v_ppd_post numeric; v_spd_pre numeric; v_spd_post numeric;
  v_page_ratio numeric; v_site_ratio numeric; v_effet numeric;
  v_pos_pre numeric; v_pos_post numeric;
  v_conf text; v_base_faible boolean; v_measurable boolean;
BEGIN
  SELECT COALESCE(sum(clicks),0), COALESCE(sum(impressions),0), COALESCE(sum(position*impressions),0)
    INTO v_pre_clics, v_pre_imp, v_pre_posw
  FROM gsc_path_daily WHERE path = p_path AND day BETWEEN v_pre_start AND v_pre_end;

  IF v_days_post > 0 THEN
    SELECT COALESCE(sum(clicks),0), COALESCE(sum(impressions),0), COALESCE(sum(position*impressions),0)
      INTO v_post_clics, v_post_imp, v_post_posw
    FROM gsc_path_daily WHERE path = p_path AND day BETWEEN v_post_start AND v_post_end;
  END IF;

  SELECT COALESCE(sum(clicks),0) INTO v_site_pre FROM gsc_path_daily WHERE day BETWEEN v_pre_start AND v_pre_end;
  IF v_days_post > 0 THEN
    SELECT COALESCE(sum(clicks),0) INTO v_site_post FROM gsc_path_daily WHERE day BETWEEN v_post_start AND v_post_end;
  END IF;

  SELECT min(day) INTO v_first_gsc FROM gsc_path_daily WHERE path = p_path AND impressions > 0;
  v_age_gsc := CASE WHEN v_first_gsc IS NULL THEN NULL ELSE (p_day - v_first_gsc) END;
  v_jeune   := COALESCE(v_age_gsc < 60, true);

  v_conf := CASE
    WHEN v_days_post < 7  THEN 'trop_tot'
    WHEN v_days_post < 14 THEN 'indicatif'
    WHEN v_days_post < 28 THEN 'fiable'
    ELSE 'verdict' END;

  v_base_faible := (v_pre_clics < 10);

  v_ppd_pre  := v_pre_clics / 28.0;
  v_spd_pre  := v_site_pre  / 28.0;
  v_ppd_post := CASE WHEN v_days_post > 0 THEN v_post_clics::numeric / v_days_post ELSE NULL END;
  v_spd_post := CASE WHEN v_days_post > 0 THEN v_site_post::numeric / v_days_post ELSE NULL END;
  v_pos_pre  := CASE WHEN v_pre_imp  > 0 THEN v_pre_posw  / v_pre_imp  ELSE NULL END;
  v_pos_post := CASE WHEN v_post_imp > 0 THEN v_post_posw / v_post_imp ELSE NULL END;

  -- Mesurable seulement à partir de J+7, base pré suffisante, dénominateurs non nuls.
  v_measurable := (v_days_post >= 7) AND (NOT v_base_faible) AND (v_ppd_pre > 0) AND (v_spd_pre > 0) AND (v_spd_post > 0);
  IF v_measurable THEN
    v_page_ratio := v_ppd_post / v_ppd_pre;
    v_site_ratio := v_spd_post / v_spd_pre;
    v_effet := CASE WHEN v_site_ratio > 0 THEN (v_page_ratio / v_site_ratio) - 1 ELSE NULL END;
  END IF;

  RETURN jsonb_build_object(
    'path', p_path,
    'day', p_day,
    'gsc_last', v_gsc_last,
    'days_post', v_days_post,
    'confidence', v_conf,
    'base_trop_faible', v_base_faible,
    'article_jeune', v_jeune,
    'age_gsc_jours', v_age_gsc,
    'pre_total_clics', round(v_pre_clics)::int,
    'page_clics_jour_pre',  round(v_ppd_pre, 2),
    'page_clics_jour_post', CASE WHEN v_ppd_post IS NOT NULL THEN round(v_ppd_post, 2) END,
    'pos_pre',  CASE WHEN v_pos_pre  IS NOT NULL THEN round(v_pos_pre, 1) END,
    'pos_post', CASE WHEN v_pos_post IS NOT NULL THEN round(v_pos_post, 1) END,
    'clics_pct',     CASE WHEN v_measurable THEN round((v_page_ratio - 1) * 100) END,
    'maree_pct',     CASE WHEN v_measurable THEN round((v_site_ratio - 1) * 100) END,
    'effet_net_pct', CASE WHEN v_measurable AND v_effet IS NOT NULL THEN round(v_effet * 100) END
  );
END;
$function$


-- ═══ public.dashboard_resources_assisted(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_resources_assisted(period_kind text DEFAULT 'rolling_90'::text)
 RETURNS TABLE(path text, assisted_contacts integer, assisted_prev integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT s.path, s.assisted_contacts, s.assisted_prev
      FROM dashboard_resources_assisted_snapshot s WHERE s.window_kind = period_kind $function$


-- ═══ public.dashboard_resources_cohorts() ═══
CREATE OR REPLACE FUNCTION public.dashboard_resources_cohorts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
WITH
res AS (SELECT path FROM page_taxonomy WHERE category='ressource'),
j0 AS (SELECT g.path, min(g.day) AS j0
       FROM gsc_path_daily g JOIN res ON res.path=g.path
       WHERE g.impressions > 0 GROUP BY g.path),
art AS (SELECT path, j0, to_char(j0,'YYYY-MM') AS cohort,
               LEAST((public.gsc_last_data_day() - j0), 60) AS cap
        FROM j0 WHERE (public.gsc_last_data_day() - j0) >= 0),
lastc AS (SELECT cohort FROM (SELECT DISTINCT cohort FROM art) d ORDER BY cohort DESC LIMIT 6),
arts AS (SELECT a.* FROM art a JOIN lastc l ON l.cohort=a.cohort),
grid AS (SELECT path, cohort, cap, generate_series(0, cap)::int AS age FROM arts),
da AS (SELECT a.path, (g.day - a.j0)::int AS age, g.clicks
       FROM arts a JOIN gsc_path_daily g
         ON g.path=a.path AND g.day BETWEEN a.j0 AND a.j0 + a.cap),
ca AS (SELECT gr.path, gr.cohort, gr.age, COALESCE(da.clicks,0) AS clicks
       FROM grid gr LEFT JOIN da ON da.path=gr.path AND da.age=gr.age),
cumul AS (SELECT path, cohort, age,
                 sum(clicks) OVER (PARTITION BY path ORDER BY age) AS cumul
          FROM ca),
benj AS (SELECT cohort, count(*) AS n_art, min(cap) AS benjamin FROM arts GROUP BY cohort),
cs AS (SELECT c.cohort, c.age, sum(c.cumul)::numeric / b.n_art AS avg_cumul
       FROM cumul c JOIN benj b ON b.cohort=c.cohort
       WHERE c.age <= b.benjamin
       GROUP BY c.cohort, c.age, b.n_art),
series AS (SELECT cohort, array_agg(round(avg_cumul,1) ORDER BY age) AS ser FROM cs GROUP BY cohort)
SELECT jsonb_build_object('gsc_last', public.gsc_last_data_day(), 'cohorts',
  COALESCE(jsonb_agg(jsonb_build_object(
    'month', s.cohort,
    'n_articles', b.n_art,
    'benjamin_age', b.benjamin,
    'series', to_jsonb(s.ser)
  ) ORDER BY s.cohort), '[]'::jsonb))
FROM series s JOIN benj b ON b.cohort=s.cohort;
$function$


-- ═══ public.dashboard_resources_kpis(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_resources_kpis(period_kind text DEFAULT 'rolling_90'::text)
 RETURNS SETOF dashboard_kpis_snapshot
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT * FROM public.dashboard_kpis_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$function$


-- ═══ public.dashboard_resources_overview(period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.dashboard_resources_overview(period_kind text DEFAULT 'rolling_90'::text, max_rows integer DEFAULT 100)
 RETURNS SETOF dashboard_resources_snapshot
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT * FROM public.dashboard_resources_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END
  ORDER BY unique_visitors DESC NULLS LAST
  LIMIT max_rows;
$function$


-- ═══ public.dashboard_resources_trend(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_resources_trend(period_kind text DEFAULT 'rolling_90'::text)
 RETURNS TABLE(visitors_daily numeric[], pageviews_daily numeric[], contacts_daily numeric[], gsc_clicks_daily numeric[], gsc_impressions_daily numeric[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily
  FROM public.dashboard_trend_snapshot
  WHERE window_kind = CASE WHEN period_kind IN ('rolling_28','rolling_90') THEN period_kind ELSE 'rolling_90' END;
$function$


-- ═══ public.dashboard_seo_by_query(period_kind text, scope text, min_volume integer, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.dashboard_seo_by_query(period_kind text DEFAULT 'rolling_90'::text, scope text DEFAULT 'ressource'::text, min_volume integer DEFAULT 0, max_rows integer DEFAULT 200)
 RETURNS TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, nb_pages integer, top_page text, top_page_clicks bigint, top_page_theme text, volume_fr integer, cpc numeric, competition_level text, capture_pct numeric, is_quick_win boolean, clicks_prev bigint, position_prev numeric, ctr_expected numeric, opportunity_clicks numeric, gsc_start date, gsc_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
WITH gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
qp AS (
  SELECT d.query, d.path, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
    AND NOT public.gsc_is_branded(d.query)
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query, d.path),
agg AS (SELECT query, SUM(clicks) clicks, SUM(impr) impr, SUM(pos_w) pos_w, COUNT(*) nb_pages FROM qp GROUP BY query),
top AS (SELECT DISTINCT ON (query) query, path top_page, clicks top_clicks FROM qp ORDER BY query, clicks DESC, impr DESC),
qprev AS (
  SELECT d.query, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT prev_start FROM gb) AND (SELECT prev_end FROM gb)
    AND NOT public.gsc_is_branded(d.query)
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query)
SELECT a.query, a.clicks, a.impr,
  ROUND(a.pos_w/NULLIF(a.impr,0),1), ROUND(100.0*a.clicks/NULLIF(a.impr,0),2),
  a.nb_pages::int, t.top_page, t.top_clicks, pt.theme,
  dfs.search_volume, dfs.cpc, dfs.competition_level,
  CASE WHEN dfs.search_volume>0 THEN ROUND(100.0*a.clicks/(dfs.search_volume*(SELECT day_count FROM gb)/30.0),1) END,
  (ROUND(a.pos_w/NULLIF(a.impr,0),1) BETWEEN 5 AND 15 AND COALESCE(dfs.search_volume,0)>=100),
  COALESCE(p.clicks,0),
  ROUND(p.pos_w/NULLIF(p.impr,0),1),
  ROUND(ctr_for_position(a.pos_w/NULLIF(a.impr,0))*100,2),
  CASE WHEN COALESCE(dfs.search_volume,0)>0
    THEN GREATEST(0, ROUND(dfs.search_volume*ctr_for_position(3) - a.clicks*30.0/NULLIF((SELECT day_count FROM gb),0)))
  END,
  (SELECT n_start FROM gb), (SELECT n_end FROM gb)
FROM agg a
LEFT JOIN top t ON t.query=a.query
LEFT JOIN page_taxonomy pt ON pt.path=t.top_page
LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=a.query AND dfs.location_code=2250
LEFT JOIN qprev p ON p.query=a.query
WHERE COALESCE(dfs.search_volume,0) >= min_volume
ORDER BY a.clicks DESC, a.impr DESC
LIMIT max_rows;
$function$


-- ═══ public.dashboard_seo_kpis(period_kind text, scope text) ═══
CREATE OR REPLACE FUNCTION public.dashboard_seo_kpis(period_kind text DEFAULT 'rolling_90'::text, scope text DEFAULT 'ressource'::text)
 RETURNS TABLE(total_queries bigint, total_quick_wins bigint, clicks_named_nonbranded bigint, clicks_path_total bigint, impressions_path_total bigint, gsc_start date, gsc_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
WITH gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
qp AS (
  SELECT d.query, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
    AND NOT public.gsc_is_branded(d.query)
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query),
qk AS (
  SELECT q.query, q.clicks,
    (ROUND(q.pos_w/NULLIF(q.impr,0),1) BETWEEN 5 AND 15 AND COALESCE(dfs.search_volume,0)>=100) AS qw
  FROM qp q LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=q.query AND dfs.location_code=2250),
pth AS (SELECT COALESCE(SUM(m.clicks_total),0) ct, COALESCE(SUM(m.impressions_total),0) it
        FROM gsc_path_metrics((SELECT n_start FROM gb),(SELECT n_end FROM gb)) m JOIN res ON res.path=m.path)
SELECT (SELECT COUNT(*) FROM qk),
       (SELECT COUNT(*) FILTER (WHERE qw) FROM qk),
       (SELECT COALESCE(SUM(clicks),0) FROM qk),
       (SELECT ct FROM pth), (SELECT it FROM pth),
       (SELECT n_start FROM gb), (SELECT n_end FROM gb);
$function$


-- ═══ public.dfs_keywords_to_sync(limit_n integer) ═══
CREATE OR REPLACE FUNCTION public.dfs_keywords_to_sync(limit_n integer DEFAULT 500)
 RETURNS TABLE(keyword text, clicks_total bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT
      (now() AT TIME ZONE 'Europe/Paris')::date AS today,
      (now() AT TIME ZONE 'Europe/Paris')::date - 27 AS start_28d,
      (now() AT TIME ZONE 'Europe/Paris')::date - 89 AS start_90d
  ),
  clicks_90 AS (
    SELECT q.query, SUM(q.clicks)::bigint AS clicks_90d
    FROM gsc_query_daily q, bounds b
    WHERE q.day >= b.start_90d
      AND q.day <= b.today
      AND q.query IS NOT NULL
      AND q.query != ''
    GROUP BY q.query
  ),
  clicks_28 AS (
    SELECT q.query, SUM(q.clicks)::bigint AS clicks_28d
    FROM gsc_query_daily q, bounds b
    WHERE q.day >= b.start_28d
      AND q.day <= b.today
      AND q.query IS NOT NULL
      AND q.query != ''
    GROUP BY q.query
  ),
  combined AS (
    SELECT
      COALESCE(a.query, c.query) AS query,
      COALESCE(a.clicks_90d, 0) AS clicks_90d,
      COALESCE(c.clicks_28d, 0) AS clicks_28d
    FROM clicks_90 a
    FULL OUTER JOIN clicks_28 c ON c.query = a.query
  )
  SELECT
    query AS keyword,
    GREATEST(clicks_90d, clicks_28d) AS clicks_total
  FROM combined
  ORDER BY GREATEST(clicks_90d, clicks_28d) DESC, clicks_90d DESC
  LIMIT limit_n;
$function$


-- ═══ public.engagement_density_for_path(target_path text, days integer) ═══
CREATE OR REPLACE FUNCTION public.engagement_density_for_path(target_path text, days integer DEFAULT 28)
 RETURNS TABLE(sessions bigint, dwell_p25 numeric, dwell_median numeric, dwell_p75 numeric, evenness_score numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with session_dwell as (
    select session_id,
           max((props->>'duration_seconds')::numeric) as dwell_s  -- ⬅️ fix : max par session
    from events_human
    where path = target_path
      and name = 'page_exit'
      and (props->>'duration_seconds')::numeric > 0
      and occurred_at >= now() - (days || ' days')::interval
    group by session_id  -- ⬅️ fix : 1 row par session, pas par page_exit
    having max((props->>'duration_seconds')::numeric) > 0
  )
  select
    count(*)::bigint as sessions,
    round((percentile_cont(0.25) within group (order by dwell_s))::numeric, 1) as dwell_p25,
    round((percentile_cont(0.50) within group (order by dwell_s))::numeric, 1) as dwell_median,
    round((percentile_cont(0.75) within group (order by dwell_s))::numeric, 1) as dwell_p75,
    round(case
      when (percentile_cont(0.75) within group (order by dwell_s))::numeric > 0
      then (percentile_cont(0.25) within group (order by dwell_s))::numeric
         / (percentile_cont(0.75) within group (order by dwell_s))::numeric
      else null
    end::numeric, 2) as evenness_score
  from session_dwell;
$function$


-- ═══ public.form_submit_counts_as_macro(props jsonb) ═══
CREATE OR REPLACE FUNCTION public.form_submit_counts_as_macro(props jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN props IS NULL THEN true
    WHEN lower(trim(coalesce(props->>'objet_de_ma_demande', ''))) LIKE '%nous rejoindre%' THEN false
    WHEN coalesce(props->>'counts_as_macro', 'true') = 'false' THEN false
    ELSE true
  END;
$function$


-- ═══ public.form_submits_attributed(days_back integer, p_end date) ═══
CREATE OR REPLACE FUNCTION public.form_submits_attributed(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(event_id uuid, occurred_at timestamp with time zone, form_path text, objet text, counts_as_macro boolean, resolved_anonymous_id text, resolved_session_id text, attribution_method text, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-02) : fenêtre = days_back jours Paris CLOS, ancrés par défaut sur J-1 Paris
  -- (cooked_period_bounds, lens 'live_j1') ; p_end permet d'aligner sur une autre borne close (CPI : gsc_last_data_day()).
  -- Avant : `occurred_at > now() - make_interval(...)` — la réponse changeait avec l'heure de la question.
  -- Le statut macro passe par form_submit_counts_as_macro(props) : une seule définition avec site_macro_counts.
  -- Lecture de `events` brut assumée : les form_submit sont insérés server-side, jamais classés bot ni bruit.
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  forms as (
    select e.id, e.occurred_at, e.path,
      e.props->>'objet_de_ma_demande' as objet,
      public.form_submit_counts_as_macro(e.props) as counts_as_macro,
      nullif(e.props->>'cooked_aid','') as hf_aid,
      nullif(e.props->>'cooked_sid','') as hf_sid
    from public.events e
    where e.name = 'form_submit'
      and public.paris_date(e.occurred_at) between (select d_start from w) and (select d_end from w)
  ),
  temporal as (
    -- candidat unique : visiteurs browser actifs sur la page du form
    -- dans les 20 min avant → 3 min après le submit
    select f.id as form_id,
      (array_agg(distinct e.anonymous_id)) as aids,
      (array_agg(distinct e.session_id)) as sids
    from forms f
    join public.events_human e
      on e.path = coalesce(f.path, '/honoraires-rendez-vous')
     and e.device_type is distinct from 'server'
     and e.anonymous_id not like 'webhook-%'
     and e.occurred_at between f.occurred_at - interval '20 min'
                           and f.occurred_at + interval '3 min'
    where f.hf_aid is null
    group by f.id
    having count(distinct e.anonymous_id) = 1
  )
  select f.id, f.occurred_at, f.path, f.objet, f.counts_as_macro,
    coalesce(f.hf_aid, t.aids[1]),
    coalesce(f.hf_sid, t.sids[1]),
    case
      when f.hf_aid is not null then 'hidden_field'
      when t.aids[1] is not null then 'temporal_unique'
      else 'unresolved'
    end,
    w.d_start, w.d_end
  from forms f
  cross join w
  left join temporal t on t.form_id = f.id;
$function$


-- ═══ public.form_submits_per_path(start_date date, end_date date) ═══
CREATE OR REPLACE FUNCTION public.form_submits_per_path(start_date date, end_date date)
 RETURNS TABLE(path text, form_submits bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    e.path,
    count(*)::bigint
  FROM public.events_human e
  WHERE e.name = 'form_submit'
    AND public.form_submit_counts_as_macro(e.props)
    AND e.path IS NOT NULL
    AND public.paris_date(e.occurred_at) >= start_date
    AND public.paris_date(e.occurred_at) <= end_date
  GROUP BY e.path;
$function$


-- ═══ public.gsc_is_branded(p_query text) ═══
CREATE OR REPLACE FUNCTION public.gsc_is_branded(p_query text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT coalesce(p_query, '') ~* 'plouton';
$function$


-- ═══ public.gsc_last_data_day() ═══
CREATE OR REPLACE FUNCTION public.gsc_last_data_day()
 RETURNS date
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT max(day) FROM public.gsc_path_daily;
$function$


-- ═══ public.gsc_page_daily_series(target_path text, days_back integer, end_date date) ═══
CREATE OR REPLACE FUNCTION public.gsc_page_daily_series(target_path text, days_back integer, end_date date DEFAULT NULL::date)
 RETURNS TABLE(day date, clicks bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cp as (select canonical_path(target_path) as p),
  series as (
    select gs::date as day
    from generate_series(
      coalesce(end_date, (now() at time zone 'Europe/Paris')::date) - (days_back - 1),
      coalesce(end_date, (now() at time zone 'Europe/Paris')::date),
      interval '1 day'
    ) gs
  )
  select
    s.day,
    coalesce(sum(g.clicks), 0)::bigint as clicks
  from series s
    left join public.gsc_path_daily g
      on g.day = s.day
     and g.path = (select p from cp)
  group by s.day
  order by s.day;
$function$


-- ═══ public.gsc_page_performance(target_path text, period_kind text) ═══
CREATE OR REPLACE FUNCTION public.gsc_page_performance(target_path text, period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_views bigint, cooked_unique_visitors bigint, cooked_bounce_rate numeric, cooked_dwell_avg_s numeric, cooked_scroll_median numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, cooked_google_sessions bigint, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, top_referrer text, device_split jsonb)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(period_kind, 'cross') LIMIT 1
  ),
  b AS (SELECT n_start, n_end FROM bounds),
  ts AS (
    SELECT
      (b.n_start::timestamp AT TIME ZONE 'Europe/Paris') AS date_from,
      ((b.n_end + 1)::timestamp AT TIME ZONE 'Europe/Paris') AS date_to
    FROM b
  ),
  cp AS (SELECT public.canonical_path(target_path) AS p),
  g AS (
    SELECT
      coalesce(sum(gd.clicks), 0)::bigint AS clicks_total,
      coalesce(sum(gd.impressions), 0)::bigint AS impressions_total,
      CASE WHEN sum(gd.impressions) > 0
           THEN round((sum(gd.position * gd.impressions) / sum(gd.impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN sum(gd.impressions) > 0
           THEN round((100.0 * sum(gd.clicks) / sum(gd.impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM public.gsc_path_daily gd, cp, b
    WHERE gd.path = cp.p AND gd.day >= b.n_start AND gd.day <= b.n_end
  ),
  cooked AS (
    SELECT o.*
    FROM public.seo_pages_overview((SELECT date_from FROM ts), (SELECT date_to FROM ts)) o, cp
    WHERE o.path = cp.p
    LIMIT 1
  ),
  mc AS (
    SELECT m.*
    FROM public.macro_contacts_by_path((SELECT n_start FROM b), (SELECT n_end FROM b)) m, cp
    WHERE m.path = cp.p
  ),
  pogo AS (
    SELECT pr.pogo_rate
    FROM public.pogo_rates_for_period(
      (SELECT date_from FROM ts),
      (SELECT date_to FROM ts)
    ) pr, cp
    WHERE pr.path = cp.p
    LIMIT 1
  ),
  google_sess AS (
    SELECT count(DISTINCT e.session_id)::bigint AS n
    FROM public.events_human e, cp, b, ts
    WHERE e.path = cp.p
      AND e.name = 'pageview'
      AND e.device_type IS DISTINCT FROM 'server'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      AND (
        e.referrer_hostname LIKE '%google.%'
        OR (e.utm_source = 'google' AND e.utm_medium IN ('organic', 'cpc'))
      )
  ),
  ref_top AS (
    SELECT e.referrer_hostname AS ref, count(*) AS cnt
    FROM public.events_human e, cp, ts
    WHERE e.path = cp.p AND e.name = 'pageview'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      AND e.referrer_hostname IS NOT NULL
    GROUP BY e.referrer_hostname
    ORDER BY cnt DESC
    LIMIT 1
  ),
  dev AS (
    SELECT jsonb_object_agg(device_type, cnt) AS split
    FROM (
      SELECT coalesce(e.device_type, 'unknown') AS device_type, count(*)::bigint AS cnt
      FROM public.events_human e, cp, ts
      WHERE e.path = cp.p AND e.name = 'pageview'
        AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      GROUP BY e.device_type
    ) d
  ),
  cwv AS (
    SELECT
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'LCP') AS lcp,
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'INP') AS inp,
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'CLS') AS cls
    FROM public.events_human e, cp, ts
    WHERE e.path = cp.p AND e.name = 'web_vitals'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
  )
  SELECT
    cp.p,
    coalesce(g.clicks_total, 0),
    coalesce(g.impressions_total, 0),
    g.position_avg,
    g.ctr_pct,
    coalesce(cooked.sessions, 0),
    coalesce(cooked.views, 0),
    coalesce(cooked.unique_visitors, 0),
    cooked.bounce_rate_pct,   -- T-03 (d-04) : même unité (0-100) que pages_overview_unified et seo_url_snapshot
    cooked.avg_dwell_seconds,
    cooked.scroll_median,
    coalesce(mc.phone_clicks, 0),
    coalesce(mc.form_submits, 0),
    coalesce(mc.contacts, 0),
    coalesce(mc.booking_intent, 0),
    pogo.pogo_rate,
    coalesce(google_sess.n, 0),
    cwv.lcp,
    cwv.inp,
    cwv.cls,
    ref_top.ref,
    dev.split
  FROM cp
    LEFT JOIN g ON true
    LEFT JOIN cooked ON true
    LEFT JOIN mc ON true
    LEFT JOIN pogo ON true
    LEFT JOIN google_sess ON true
    LEFT JOIN ref_top ON true
    LEFT JOIN dev ON true
    LEFT JOIN cwv ON true;
$function$


-- ═══ public.gsc_pages_compare(period_kind text, data_lens text) ═══
CREATE OR REPLACE FUNCTION public.gsc_pages_compare(period_kind text DEFAULT 'rolling_28'::text, data_lens text DEFAULT 'gsc'::text)
 RETURNS TABLE(path text, clicks_n bigint, clicks_prev bigint, clicks_delta_pct numeric, impressions_n bigint, impressions_prev bigint, impressions_delta_pct numeric, position_avg_n numeric, position_avg_prev numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  b RECORD;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, data_lens) LIMIT 1;

  RETURN QUERY
  WITH n_agg AS (
    SELECT g.path AS p,
      sum(g.clicks)::bigint AS clicks_total,
      sum(g.impressions)::bigint AS imp_total,
      CASE WHEN sum(g.impressions) > 0
           THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
           ELSE NULL END AS position_avg
    FROM public.gsc_path_daily g
    WHERE g.day >= b.n_start AND g.day <= b.n_end
    GROUP BY g.path
  ),
  prev_agg AS (
    SELECT g.path AS p,
      sum(g.clicks)::bigint AS clicks_total,
      sum(g.impressions)::bigint AS imp_total,
      CASE WHEN sum(g.impressions) > 0
           THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
           ELSE NULL END AS position_avg
    FROM public.gsc_path_daily g
    WHERE g.day >= b.prev_start AND g.day <= b.prev_end
    GROUP BY g.path
  ),
  paths AS (SELECT n_agg.p FROM n_agg UNION SELECT prev_agg.p FROM prev_agg)
  SELECT
    paths.p,
    coalesce(n.clicks_total, 0),
    coalesce(pr.clicks_total, 0),
    CASE WHEN coalesce(pr.clicks_total, 0) > 0
         THEN round((100.0 * (coalesce(n.clicks_total, 0) - pr.clicks_total) / pr.clicks_total)::numeric, 2)
         ELSE NULL END,
    coalesce(n.imp_total, 0),
    coalesce(pr.imp_total, 0),
    CASE WHEN coalesce(pr.imp_total, 0) > 0
         THEN round((100.0 * (coalesce(n.imp_total, 0) - pr.imp_total) / pr.imp_total)::numeric, 2)
         ELSE NULL END,
    n.position_avg,
    pr.position_avg
  FROM paths
    LEFT JOIN n_agg n ON n.p = paths.p
    LEFT JOIN prev_agg pr ON pr.p = paths.p;
END;
$function$


-- ═══ public.gsc_pages_overview(max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.gsc_pages_overview(max_rows integer DEFAULT 30)
 RETURNS TABLE(path text, gsc_clicks_28d bigint, gsc_impressions_28d bigint, gsc_position_avg_28d numeric, gsc_ctr_pct_28d numeric, cooked_sessions_28d bigint, cooked_dwell_avg_s_28d numeric, cooked_bounce_rate_28d numeric, cooked_phone_clicks_28d bigint, cooked_form_submits_28d bigint, cooked_contacts_28d bigint, cooked_booking_intent_28d bigint, cooked_pogo_rate_28d numeric, has_cooked_data boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- T-05 (mission 02/09/2026, #106 — d-03) : « 28 j » = 28 jours GSC clos à gsc_last_data_day() (lens 'gsc'), plus la
  -- fenêtre brute `paris_today() - 27` qui ne contenait que 24-25 jours de données (lag Google J-3/J-4 : −12 à −17 %
  -- de clics selon le jour). Récidive du 24/05/2026 (off-by-one corrigé, alignement GSC jamais fait).
  -- T-09 (#110 — d-02) : les contacts de la ligne sont comptés sur les MÊMES bornes GSC (macro_contacts_by_path(n_start,
  -- n_end)) — avant macro_contacts_by_path(28) = jour en cours inclus. seo_url_snapshot garde sa fenêtre nocturne propre.
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds('rolling_28', 'gsc') LIMIT 1
  ),
  g AS (
    SELECT path,
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_path_daily
    WHERE day BETWEEN (SELECT n_start FROM b) AND (SELECT n_end FROM b)
    GROUP BY path
  )
  SELECT
    g.path,
    g.clicks_total,
    g.impressions_total,
    g.position_avg,
    g.ctr_pct,
    COALESCE(s.sessions_28d, 0),
    s.avg_dwell_seconds_28d,
    s.bounce_rate_28d,
    COALESCE(mc.phone_clicks, 0),
    COALESCE(mc.form_submits, 0),
    COALESCE(mc.contacts, 0),
    COALESCE(mc.booking_intent, 0),
    s.pogo_rate_28d,
    (s.path IS NOT NULL)
  FROM g
  LEFT JOIN seo_url_snapshot s ON s.path = g.path
  LEFT JOIN macro_contacts_by_path((SELECT n_start FROM b), (SELECT n_end FROM b)) mc ON mc.path = g.path
  ORDER BY g.clicks_total DESC, g.impressions_total DESC
  LIMIT max_rows;
$function$


-- ═══ public.gsc_path_metrics(start_date date, end_date date) ═══
CREATE OR REPLACE FUNCTION public.gsc_path_metrics(start_date date, end_date date)
 RETURNS TABLE(path text, impressions_total bigint, clicks_total bigint, position_avg numeric, ctr_pct numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT g.path,
    SUM(g.impressions)::bigint,
    SUM(g.clicks)::bigint,
    CASE WHEN SUM(g.impressions) > 0 THEN ROUND((SUM(g.position * g.impressions) / SUM(g.impressions))::numeric, 2) ELSE NULL END,
    CASE WHEN SUM(g.impressions) > 0 THEN ROUND((100.0 * SUM(g.clicks) / SUM(g.impressions))::numeric, 2) ELSE NULL END
  FROM public.gsc_path_daily g
  WHERE g.day >= start_date AND g.day <= end_date
  GROUP BY g.path;
$function$


-- ═══ public.gsc_top_queries_for_path(target_path text, days_back integer, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.gsc_top_queries_for_path(target_path text, days_back integer DEFAULT 28, max_rows integer DEFAULT 20)
 RETURNS TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, days_in_period integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cp AS (SELECT canonical_path(target_path) AS p)
  SELECT gqp.query, SUM(gqp.clicks)::bigint, SUM(gqp.impressions)::bigint,
    CASE WHEN SUM(gqp.impressions) > 0 THEN ROUND((SUM(gqp.position * gqp.impressions) / SUM(gqp.impressions))::numeric, 2) ELSE NULL END,
    CASE WHEN SUM(gqp.impressions) > 0 THEN ROUND((100.0 * SUM(gqp.clicks) / SUM(gqp.impressions))::numeric, 2) ELSE NULL END,
    COUNT(DISTINCT gqp.day)::integer
  FROM gsc_query_page_daily gqp, cp
  WHERE gqp.path = cp.p
    AND gqp.day >= (now() AT TIME ZONE 'Europe/Paris')::date - (days_back - 1)
  GROUP BY gqp.query
  ORDER BY 2 DESC, 3 DESC
  LIMIT max_rows;
$function$


-- ═══ public.gsc_top_queries_for_path(target_path text, p_period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.gsc_top_queries_for_path(target_path text, p_period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 20)
 RETURNS TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, days_in_period integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1
  ),
  cp AS (SELECT public.canonical_path(target_path) AS p)
  SELECT
    gqp.query,
    sum(gqp.clicks)::bigint,
    sum(gqp.impressions)::bigint,
    CASE WHEN sum(gqp.impressions) > 0
         THEN round((sum(gqp.position * gqp.impressions) / sum(gqp.impressions))::numeric, 2)
         ELSE NULL END,
    CASE WHEN sum(gqp.impressions) > 0
         THEN round((100.0 * sum(gqp.clicks) / sum(gqp.impressions))::numeric, 2)
         ELSE NULL END,
    count(DISTINCT gqp.day)::integer
  FROM public.gsc_query_page_daily gqp
  CROSS JOIN cp
  CROSS JOIN b
  WHERE gqp.path = cp.p
    AND gqp.day >= b.n_start
    AND gqp.day <= b.n_end
  GROUP BY gqp.query
  ORDER BY 2 DESC, 3 DESC
  LIMIT max_rows;
$function$


-- ═══ public.gsc_top_queries_global(period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.gsc_top_queries_global(period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 100)
 RETURNS TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, nb_pages_targeted integer, top_page text, top_page_clicks bigint, volume_fr integer, cpc numeric, click_yield_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(period_kind, 'gsc') LIMIT 1
  ),
  b AS (SELECT n_start, n_end, day_count FROM bounds),
  window_data AS (
    SELECT q.query, q.path, q.clicks, q.impressions, q.position
    FROM public.gsc_query_page_daily q, b
    WHERE q.day >= b.n_start AND q.day <= b.n_end
  ),
  query_path AS (
    SELECT query, path,
      sum(clicks)::bigint AS path_clicks,
      sum(impressions)::bigint AS path_impressions
    FROM window_data
    GROUP BY query, path
  ),
  query_agg AS (
    SELECT query,
      sum(clicks)::bigint AS clicks_total,
      sum(impressions)::bigint AS impressions_total,
      count(DISTINCT path)::int AS nb_pages,
      CASE WHEN sum(impressions) > 0
           THEN round((sum(position * impressions) / sum(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN sum(impressions) > 0
           THEN round((100.0 * sum(clicks) / sum(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM window_data
    GROUP BY query
  ),
  top_per_query AS (
    SELECT DISTINCT ON (query) query, path AS top_page, path_clicks AS top_clicks
    FROM query_path
    ORDER BY query, path_clicks DESC
  )
  SELECT
    a.query,
    a.clicks_total,
    a.impressions_total,
    a.position_avg,
    a.ctr_pct,
    a.nb_pages,
    tp.top_page,
    tp.top_clicks,
    dfs.search_volume,
    dfs.cpc,
    CASE WHEN dfs.search_volume > 0
         THEN round((100.0 * a.clicks_total / (dfs.search_volume::numeric * b.day_count / 30.0))::numeric, 2)
         ELSE NULL END
  FROM query_agg a
    CROSS JOIN b
    LEFT JOIN top_per_query tp ON tp.query = a.query
    LEFT JOIN dfs_keyword_volume dfs
      ON dfs.keyword = a.query AND dfs.location_code = 2250
  ORDER BY a.clicks_total DESC, a.impressions_total DESC
  LIMIT max_rows;
$function$


-- ═══ public.gsc_x_dfs_opportunities(min_volume integer, position_min numeric, position_max numeric, period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.gsc_x_dfs_opportunities(min_volume integer DEFAULT 100, position_min numeric DEFAULT 5.0, position_max numeric DEFAULT 15.0, period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 30)
 RETURNS TABLE(query text, our_position numeric, our_clicks bigint, our_impressions bigint, our_ctr_pct numeric, volume_fr integer, cpc numeric, estimated_ctr_pos_1 numeric, lost_potential integer, top_page text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(period_kind, 'cross') LIMIT 1
  ),
  b AS (SELECT n_start, n_end, day_count FROM bounds),
  our_perf AS (
    SELECT
      q.query,
      sum(q.clicks)::bigint AS clicks,
      sum(q.impressions)::bigint AS impressions,
      CASE WHEN sum(q.impressions) > 0
           THEN round((sum(q.position * q.impressions) / sum(q.impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN sum(q.impressions) > 0
           THEN round((100.0 * sum(q.clicks) / sum(q.impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_query_daily q, b
    WHERE q.day >= b.n_start AND q.day <= b.n_end
      AND q.query IS NOT NULL
    GROUP BY q.query
  ),
  top_pages AS (
    SELECT DISTINCT ON (query) query, path
    FROM (
      SELECT query, path, sum(clicks) AS path_clicks
      FROM gsc_query_page_daily, b
      WHERE day >= b.n_start AND day <= b.n_end
      GROUP BY query, path
    ) x
    ORDER BY query, path_clicks DESC
  )
  SELECT
    op.query,
    op.position_avg AS our_position,
    op.clicks AS our_clicks,
    op.impressions AS our_impressions,
    op.ctr_pct AS our_ctr_pct,
    dfs.search_volume AS volume_fr,
    dfs.cpc,
    (100 * ctr_for_position(1.0))::numeric AS estimated_ctr_pos_1,
    greatest(
      round((
        dfs.search_volume::numeric * b.day_count / 30.0
        * (ctr_for_position(1.0) - coalesce(ctr_for_position(op.position_avg), 0))
      ))::integer,
      0
    ) AS lost_potential,
    tp.path AS top_page
  FROM our_perf op
    CROSS JOIN b
    INNER JOIN dfs_keyword_volume dfs
      ON dfs.keyword = op.query AND dfs.location_code = 2250
    LEFT JOIN top_pages tp ON tp.query = op.query
  WHERE op.position_avg BETWEEN position_min AND position_max
    AND dfs.search_volume IS NOT NULL
    AND dfs.search_volume >= min_volume
  ORDER BY lost_potential DESC NULLS LAST
  LIMIT max_rows;
$function$


-- ═══ public.latest_rpc_health() ═══
CREATE OR REPLACE FUNCTION public.latest_rpc_health()
 RETURNS TABLE(rpc_name text, status text, detail text, rows_returned bigint, duration_ms numeric, checked_at timestamp with time zone, age_minutes numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select distinct on (h.rpc_name)
    h.rpc_name,
    case when h.checked_at < now() - interval '48 hours'
         then 'stale'
         else h.status
    end as status,
    case when h.checked_at < now() - interval '48 hours'
         then 'mesure du ' || to_char(h.checked_at AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI')
              || ' — le contract test n a pas tourné depuis, statut réel inconnu. Dernier état connu : '
              || coalesce(h.status, 'null') || '. ' || coalesce(h.detail, '')
         else h.detail
    end as detail,
    h.rows_returned,
    h.duration_ms,
    h.checked_at,
    round(extract(epoch from (now() - h.checked_at)) / 60, 1) as age_minutes
  from public.rpc_health h
  order by h.rpc_name, h.checked_at desc;
$function$


-- ═══ public.macro_contacts_by_path(days_back integer) ═══
CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(days_back integer)
 RETURNS TABLE(path text, phone_clicks bigint, form_submits bigint, contacts bigint, booking_intent bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-02) : days_back jours Paris CLOS ancrés sur J-1 (lens 'live_j1'), comme
  -- conversion_journeys(days_back). Avant : paris_today() - (days_back - 1) → paris_today() = jour en cours partiel.
  SELECT m.*
  FROM public.cooked_period_bounds('rolling_28', 'live_j1') b,
       LATERAL public.macro_contacts_by_path(b.n_end - (days_back - 1), b.n_end) m;
$function$


-- ═══ public.macro_contacts_by_path(start_date date, end_date date) ═══
CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(start_date date, end_date date)
 RETURNS TABLE(path text, phone_clicks bigint, form_submits bigint, contacts bigint, booking_intent bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    coalesce(e.path, '(non rattaché)'),
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint,
    count(*) FILTER (
      WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
    )::bigint,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (
          WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
        )
    )::bigint,
    count(*) FILTER (
      WHERE e.name = 'cta_booking_click' AND e.device_type != 'server'
    )::bigint
  FROM public.events_human e
  WHERE (
      e.name = 'cta_phone_click'
      OR (e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props))
      OR (e.name = 'cta_booking_click' AND e.device_type != 'server')
    )
    AND public.paris_date(e.occurred_at) >= start_date
    AND public.paris_date(e.occurred_at) <= end_date
  GROUP BY 1;
$function$


-- ═══ public.math_internal_edges(days_back integer) ═══
CREATE OR REPLACE FUNCTION public.math_internal_edges(days_back integer DEFAULT 28)
 RETURNS TABLE(src text, dst text, kind text, placement text, weight bigint, dst_resolved boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with ev as materialized (
    select e.anonymous_id, e.session_id, e.name, e.path, e.occurred_at, e.props
    from public.events_human e
    where e.name in ('pageview', 'click_internal')
      and e.occurred_at > now() - make_interval(days => days_back)
      and e.path is not null
  ),
  seen as (
    select distinct e.path from ev e where e.name = 'pageview'
  ),
  clicks_raw as (
    select e.path as src,
           e.props->>'target_path' as dst_raw,
           coalesce(e.props->>'placement', 'inconnu') as placement,
           count(*)::bigint as weight
    from ev e
    where e.name = 'click_internal' and e.props->>'target_path' is not null
    group by 1, 2, 3
  ),
  clicks as (
    -- resolution ciblee des cibles orphelines : les liens du site pointent
    -- vers des URL accentuees qui redirigent (301) vers la forme desaccentuee
    -- ou atterrissent les pageviews. On ne desaccentue QUE si la cible brute
    -- n'existe pas et que la forme desaccentuee, elle, existe.
    select c.src,
      case when c.raw_exists then c.dst_raw
           when c.flat_exists then c.dst_flat
           else c.dst_raw end as dst,
      c.placement, c.weight,
      (not c.raw_exists and c.flat_exists) as dst_resolved
    from (
      select c0.*,
        translate(c0.dst_raw, 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ',
                              'aaaeeeeiioouuucAAAEEEEIIOOUUUC') as dst_flat,
        exists (select 1 from seen s where s.path = c0.dst_raw) as raw_exists,
        exists (select 1 from seen s where s.path =
                translate(c0.dst_raw, 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ',
                                      'aaaeeeeiioouuucAAAEEEEIIOOUUUC')) as flat_exists
      from clicks_raw c0
    ) c
  ),
  pv as (
    select
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(e.session_id, e.anonymous_id, 'inconnu')) as vk,
      e.path, e.occurred_at as t
    from ev e
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = e.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = e.anonymous_id
    where e.name = 'pageview'
  ),
  seg as (
    select pv.*,
      case when pv.t - lag(pv.t) over (partition by pv.vk order by pv.t)
                > interval '30 minutes'
             or lag(pv.t) over (partition by pv.vk order by pv.t) is null
           then 1 else 0 end as is_new
    from pv
  ),
  vis as (
    select seg.*,
      sum(is_new) over (partition by vk order by t rows unbounded preceding) as visit_no
    from seg
  ),
  flows as (
    select v.path as src,
           lead(v.path) over (partition by v.vk, v.visit_no order by v.t) as dst
    from vis v
  )
  select f.src, f.dst, 'flow'::text, null::text, count(*)::bigint, false
  from flows f
  where f.dst is not null and f.dst <> f.src
  group by f.src, f.dst
  union all
  select c.src, c.dst, 'click'::text, c.placement, c.weight, c.dst_resolved
  from clicks c
  where c.dst <> c.src;
$function$


-- ═══ public.math_refresh_snapshots(p_window_days integer) ═══
CREATE OR REPLACE FUNCTION public.math_refresh_snapshots(p_window_days integer DEFAULT 28)
 RETURNS TABLE(sequences bigint, edges bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_seq bigint;
  v_edg bigint;
BEGIN
  DELETE FROM public.math_visit_sequences_snapshot WHERE window_days = p_window_days;
  INSERT INTO public.math_visit_sequences_snapshot
    (window_days, journey, converted, entry_channel, n)
  SELECT p_window_days, s.journey, s.converted, s.entry_channel, s.n
  FROM public.math_visit_sequences(p_window_days) s;
  GET DIAGNOSTICS v_seq = ROW_COUNT;

  DELETE FROM public.math_internal_edges_snapshot WHERE window_days = p_window_days;
  INSERT INTO public.math_internal_edges_snapshot
    (window_days, src, dst, kind, placement, weight, dst_resolved)
  SELECT p_window_days, e.src, e.dst, e.kind, e.placement, e.weight, e.dst_resolved
  FROM public.math_internal_edges(p_window_days) e;
  GET DIAGNOSTICS v_edg = ROW_COUNT;

  RETURN QUERY SELECT v_seq, v_edg;
END;
$function$


-- ═══ public.math_visit_sequences(days_back integer) ═══
CREATE OR REPLACE FUNCTION public.math_visit_sequences(days_back integer DEFAULT 28)
 RETURNS TABLE(journey text[], converted boolean, entry_channel text, n bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with ev as materialized (
    select e.anonymous_id, e.session_id, e.name, e.path, e.occurred_at,
           e.referrer_hostname, e.utm_source, e.utm_medium
    from public.events_human e
    where e.name in ('pageview', 'cta_phone_click')
      and e.occurred_at > now() - make_interval(days => days_back)
  ),
  pv as materialized (
    select
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(e.session_id, e.anonymous_id, 'inconnu')) as vk,
      e.path, e.occurred_at as t,
      e.referrer_hostname, e.utm_source, e.utm_medium
    from ev e
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = e.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = e.anonymous_id
    where e.name = 'pageview' and e.path is not null
  ),
  contacts as materialized (
    select
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(c.session_id, c.anonymous_id, 'inconnu')) as vk,
      c.occurred_at as t
    from (
      select e.occurred_at, e.anonymous_id, e.session_id
      from ev e where e.name = 'cta_phone_click'
      union all
      select f.occurred_at, f.resolved_anonymous_id, f.resolved_session_id
      from public.form_submits_attributed(days_back) f
      where f.counts_as_macro
    ) c
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = c.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = c.anonymous_id
  ),
  vis as materialized (
    select seg.*,
      sum(is_new) over (partition by vk order by t rows unbounded preceding) as visit_no
    from (
      select pv.*,
        case when pv.t - lag(pv.t) over (partition by pv.vk order by pv.t)
                  > interval '30 minutes'
               or lag(pv.t) over (partition by pv.vk order by pv.t) is null
             then 1 else 0 end as is_new
      from pv
    ) seg
  ),
  bounds as materialized (
    select vk, visit_no, min(t) as t_start, max(t) as t_end
    from vis group by vk, visit_no
  ),
  -- un contact = au plus une visite : la plus recente qui le precede,
  -- dans la limite de 6 h (fenetre de conversion_journeys v2)
  contact_visit as materialized (
    select distinct on (c.vk, c.t) c.vk, c.t as contact_at, b.visit_no
    from contacts c
    join bounds b
      on b.vk = c.vk
     and b.t_start <= c.t + interval '3 minutes'
     and c.t <= b.t_end + interval '6 hours'
    order by c.vk, c.t, b.t_start desc
  ),
  vc as materialized (
    select vk, visit_no, min(contact_at) as contact_at
    from contact_visit group by vk, visit_no
  ),
  kept as materialized (
    select v.vk, v.visit_no, v.path, v.t,
           v.referrer_hostname, v.utm_source, v.utm_medium,
           (vc.contact_at is not null) as converted
    from vis v
    left join vc on vc.vk = v.vk and vc.visit_no = v.visit_no
    where vc.contact_at is null
       or v.t <= vc.contact_at + interval '3 minutes'
  ),
  entry as materialized (
    select distinct on (k.vk, k.visit_no)
           k.vk, k.visit_no, k.referrer_hostname, k.utm_source, k.utm_medium
    from kept k
    order by k.vk, k.visit_no, k.t
  ),
  per_visit as materialized (
    select f.vk, f.visit_no,
      array_agg(f.path order by f.first_seen) as journey,
      bool_or(f.converted) as converted
    from (
      select vk, visit_no, path, min(t) as first_seen, bool_or(converted) as converted
      from kept group by vk, visit_no, path
    ) f
    group by f.vk, f.visit_no
  ),
  raw_grouped as (
    select p.journey, p.converted,
           e.referrer_hostname, e.utm_source, e.utm_medium,
           count(*)::bigint as n
    from per_visit p
    join entry e on e.vk = p.vk and e.visit_no = p.visit_no
    group by 1, 2, 3, 4, 5
  )
  select g.journey, g.converted,
         public.classify_channel(g.referrer_hostname, g.utm_source, g.utm_medium,
                                 'www.jplouton-avocat.fr'),
         sum(g.n)::bigint
  from raw_grouped g
  group by 1, 2, 3;
$function$


-- ═══ public.outbound_destinations_for_path(path text, days_back integer) ═══
CREATE OR REPLACE FUNCTION public.outbound_destinations_for_path(path text, days_back integer DEFAULT 28)
 RETURNS TABLE(hostname text, clicks bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select (e.props->>'hostname') as hostname, count(*)::bigint as clicks
  from public.events_human e
  where e.name = 'click_outbound'
    and e.path = outbound_destinations_for_path.path
    and e.occurred_at >= now() - (outbound_destinations_for_path.days_back * interval '1 day')
    and (e.props->>'hostname') is not null
    and (e.props->>'hostname') <> ''
  group by (e.props->>'hostname')
  order by 2 desc limit 10;
$function$


-- ═══ public.page_reads(p_days integer) ═══
CREATE OR REPLACE FUNCTION public.page_reads(p_days integer DEFAULT 28)
 RETURNS TABLE(session_id text, path text, dwell_s numeric, scroll_pct numeric, session_pageviews bigint, retained boolean, source text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT * FROM public.page_reads(now() - make_interval(days => p_days), now());
$function$


-- ═══ public.page_reads(p_from timestamp with time zone, p_to timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.page_reads(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS TABLE(session_id text, path text, dwell_s numeric, scroll_pct numeric, session_pageviews bigint, retained boolean, source text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH pex AS (
    SELECT e.session_id, e.path,
           max((e.props->>'duration_seconds')::numeric) AS d,
           max(coalesce((e.props->>'max_scroll')::numeric, 0)) AS s
    FROM public.events_human e
    WHERE e.name = 'page_exit'
      AND e.path IS NOT NULL
      AND e.occurred_at > p_from AND e.occurred_at <= p_to
    GROUP BY e.session_id, e.path
  ),
  spv AS (
    SELECT e.session_id, count(*) AS pv
    FROM public.events_human e
    WHERE e.name = 'pageview'
      AND e.occurred_at > p_from AND e.occurred_at <= p_to
    GROUP BY e.session_id
  )
  SELECT pex.session_id,
         pex.path,
         pex.d,
         pex.s,
         coalesce(spv.pv, 1)::bigint,
         (pex.d >= 15 OR coalesce(spv.pv, 1) >= 2),
         'page_exit'::text
  FROM pex LEFT JOIN spv ON spv.session_id = pex.session_id;
$function$


-- ═══ public.pages_overview_unified(period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.pages_overview_unified(period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 1000)
 RETURNS TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_dwell_avg_s numeric, cooked_bounce_rate numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, has_cooked_data boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_kind text := lower(trim(coalesce(period_kind, 'rolling_28')));
BEGIN
  -- ── Fast path : snapshot nocturne (évite seo_pages_overview sur tout events_human)
  IF v_kind IN ('rolling_28', 'rolling_90') THEN
    RETURN QUERY
    WITH b AS (
      SELECT * FROM public.cooked_period_bounds(v_kind, 'cross') LIMIT 1
    ),
    ranked AS (
      SELECT s.path
      FROM public.seo_url_snapshot s
      ORDER BY
        CASE WHEN v_kind = 'rolling_90'
             THEN coalesce(s.sessions_90d, 0)
             ELSE coalesce(s.sessions_28d, 0)
        END DESC,
        s.path
      LIMIT max_rows
    ),
    gsc AS (
      SELECT
        g.path,
        sum(g.impressions)::bigint AS impressions_total,
        sum(g.clicks)::bigint AS clicks_total,
        CASE WHEN sum(g.impressions) > 0
             THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
             ELSE NULL END AS position_avg,
        CASE WHEN sum(g.impressions) > 0
             THEN round((100.0 * sum(g.clicks) / sum(g.impressions))::numeric, 2)
             ELSE NULL END AS ctr_pct
      FROM public.gsc_path_daily g
      INNER JOIN ranked r ON r.path = g.path
      CROSS JOIN b
      WHERE g.day >= b.n_start AND g.day <= b.n_end
      GROUP BY g.path
    ),
    mc AS (
      SELECT m.*
      FROM public.macro_contacts_by_path(
        (SELECT n_start FROM b),
        (SELECT n_end FROM b)
      ) m
      INNER JOIN ranked r ON r.path = m.path
    )
    SELECT
      r.path,
      coalesce(g.clicks_total, 0)::bigint,
      coalesce(g.impressions_total, 0)::bigint,
      g.position_avg,
      g.ctr_pct,
      CASE WHEN v_kind = 'rolling_90'
           THEN coalesce(s.sessions_90d, 0)
           ELSE coalesce(s.sessions_28d, 0)
      END::bigint,
      CASE WHEN v_kind = 'rolling_90'
           THEN s.avg_dwell_seconds_90d
           ELSE s.avg_dwell_seconds_28d
      END,
      CASE WHEN v_kind = 'rolling_90'
           THEN s.bounce_rate_90d
           ELSE s.bounce_rate_28d
      END,
      coalesce(mc.phone_clicks, 0)::bigint,
      coalesce(mc.form_submits, 0)::bigint,
      coalesce(mc.contacts, 0)::bigint,
      coalesce(mc.booking_intent, 0)::bigint,
      CASE WHEN v_kind = 'rolling_90' THEN NULL::numeric ELSE s.pogo_rate_28d END,
      (
        CASE WHEN v_kind = 'rolling_90'
             THEN coalesce(s.sessions_90d, 0)
             ELSE coalesce(s.sessions_28d, 0)
        END > 0
      )
    FROM ranked r
    INNER JOIN public.seo_url_snapshot s ON s.path = r.path
    LEFT JOIN gsc g ON g.path = r.path
    LEFT JOIN mc ON mc.path = r.path
    ORDER BY
      CASE WHEN v_kind = 'rolling_90'
           THEN coalesce(s.sessions_90d, 0)
           ELSE coalesce(s.sessions_28d, 0)
      END DESC,
      coalesce(g.clicks_total, 0) DESC,
      r.path;
    RETURN;
  END IF;

  -- ── Dynamic path (today / week / month) — fenêtre courte, pas de union snapshot
  RETURN QUERY
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(v_kind, 'cross') LIMIT 1
  ),
  b AS (SELECT n_start, n_end FROM bounds),
  ts AS (
    SELECT
      (b.n_start::timestamp AT TIME ZONE 'Europe/Paris') AS date_from,
      ((b.n_end + 1)::timestamp AT TIME ZONE 'Europe/Paris') AS date_to
    FROM b
  ),
  gsc_n AS (
    SELECT * FROM public.gsc_path_metrics((SELECT n_start FROM b), (SELECT n_end FROM b))
  ),
  cooked AS (
    SELECT o.* FROM public.seo_pages_overview(
      (SELECT date_from FROM ts),
      (SELECT date_to FROM ts)
    ) o
  ),
  ranked_paths AS (
    SELECT coalesce(c.path, g.path) AS path
    FROM cooked c
    FULL OUTER JOIN gsc_n g ON g.path = c.path
    ORDER BY coalesce(c.sessions, 0) DESC, coalesce(g.clicks_total, 0) DESC, coalesce(c.path, g.path)
    LIMIT max_rows
  ),
  pogo AS (
    SELECT p.path, p.pogo_rate
    FROM public.pogo_rates_for_period(
      (SELECT date_from FROM ts),
      (SELECT date_to FROM ts)
    ) p
    INNER JOIN ranked_paths rp ON rp.path = p.path
  ),
  mc AS (
    SELECT m.*
    FROM public.macro_contacts_by_path(
      (SELECT n_start FROM b),
      (SELECT n_end FROM b)
    ) m
    INNER JOIN ranked_paths rp ON rp.path = m.path
  )
  SELECT
    rp.path,
    coalesce(g.clicks_total, 0),
    coalesce(g.impressions_total, 0),
    g.position_avg,
    g.ctr_pct,
    coalesce(c.sessions, 0),
    c.avg_dwell_seconds,
    c.bounce_rate_pct,   -- T-03 (d-04) : chemin lent aligné sur le chemin rapide (0-100)
    coalesce(mc.phone_clicks, 0),
    coalesce(mc.form_submits, 0),
    coalesce(mc.contacts, 0),
    coalesce(mc.booking_intent, 0),
    pg.pogo_rate,
    (c.path IS NOT NULL)
  FROM ranked_paths rp
    LEFT JOIN gsc_n g ON g.path = rp.path
    LEFT JOIN cooked c ON c.path = rp.path
    LEFT JOIN pogo pg ON pg.path = rp.path
    LEFT JOIN mc ON mc.path = rp.path
  ORDER BY coalesce(c.sessions, 0) DESC, coalesce(g.clicks_total, 0) DESC, rp.path;
END;
$function$


-- ═══ public.pages_pulse(period_kind text, delta_threshold_pct numeric) ═══
CREATE OR REPLACE FUNCTION public.pages_pulse(period_kind text DEFAULT 'rolling_28'::text, delta_threshold_pct numeric DEFAULT 5.0)
 RETURNS TABLE(path text, gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_delta_pct numeric, cooked_sessions_n bigint, cooked_sessions_prev bigint, cooked_sessions_delta_pct numeric, quadrant text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH g AS (
    SELECT gpc.*,
      CASE
        WHEN gpc.clicks_delta_pct IS NULL THEN 'flat'
        WHEN gpc.clicks_delta_pct >=  delta_threshold_pct THEN 'up'
        WHEN gpc.clicks_delta_pct <= -delta_threshold_pct THEN 'down'
        ELSE 'flat'
      END AS gsc_dir
    FROM public.gsc_pages_compare(period_kind, 'cross') gpc
  ),
  c AS (
    SELECT cpc.*,
      CASE
        WHEN cpc.sessions_delta_pct IS NULL THEN 'flat'
        WHEN cpc.sessions_delta_pct >=  delta_threshold_pct THEN 'up'
        WHEN cpc.sessions_delta_pct <= -delta_threshold_pct THEN 'down'
        ELSE 'flat'
      END AS cooked_dir
    FROM public.cooked_pages_compare(period_kind, 'cross') cpc
  ),
  pp AS (SELECT g.path AS p FROM g UNION SELECT c.path FROM c)
  SELECT
    pp.p,
    coalesce(g.clicks_n, 0),
    coalesce(g.clicks_prev, 0),
    g.clicks_delta_pct,
    coalesce(c.sessions_n, 0),
    c.sessions_prev,
    c.sessions_delta_pct,
    public.pulse_status(
      coalesce(g.clicks_n, 0),
      coalesce(g.clicks_prev, 0),
      coalesce(c.sessions_n, 0),
      c.sessions_prev,
      delta_threshold_pct
    )
  FROM pp
    LEFT JOIN g ON g.path = pp.p
    LEFT JOIN c ON c.path = pp.p;
$function$


-- ═══ public.paris_date(ts timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.paris_date(ts timestamp with time zone)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$ SELECT (ts AT TIME ZONE 'Europe/Paris')::date; $function$


-- ═══ public.paris_today() ═══
CREATE OR REPLACE FUNCTION public.paris_today()
 RETURNS date
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $function$ SELECT public.paris_date(now()); $function$


-- ═══ public.pogo_rates_for_period(date_from timestamp with time zone, date_to timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.pogo_rates_for_period(date_from timestamp with time zone, date_to timestamp with time zone)
 RETURNS TABLE(path text, google_sessions bigint, pogo_sticks bigint, hard_pogo bigint, pogo_rate numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with google_entries as (
    select distinct session_id, path
    from events_human
    where name = 'pageview'
      and referrer_hostname like '%google%'
      and occurred_at >= date_from and occurred_at < date_to
  ),
  session_pages as (
    select session_id, count(*) as pages
    from events_human
    where name = 'pageview'
      and occurred_at >= date_from and occurred_at < date_to
    group by session_id
  ),
  session_exit as (
    select session_id, path,
           max((props->>'duration_seconds')::numeric) as dwell_s,
           max((props->>'max_scroll')::numeric)       as scroll
    from events_human
    where name = 'page_exit'
      and occurred_at >= date_from and occurred_at < date_to
    group by session_id, path  -- ⬅️ fix A : 1 row par (session, path)
  )
  select g.path,
    count(*)::bigint as google_sessions,
    count(*) filter (
      where sp.pages = 1
        and (se.dwell_s < 10 or se.dwell_s is null)  -- ⬅️ fix B : NULL exit = hard pogo
    )::bigint as pogo_sticks,
    count(*) filter (
      where sp.pages = 1
        and ((se.dwell_s < 10 and se.scroll < 5) or se.dwell_s is null)
    )::bigint as hard_pogo,
    round(100.0 * count(*) filter (
      where sp.pages = 1
        and (se.dwell_s < 10 or se.dwell_s is null)
    ) / nullif(count(*), 0), 1) as pogo_rate
  from google_entries g
  left join session_pages sp on sp.session_id = g.session_id
  left join session_exit   se on se.session_id = g.session_id and se.path = g.path
  group by g.path;
$function$


-- ═══ public.pulse_quadrant(gsc_dir text, cooked_dir text) ═══
CREATE OR REPLACE FUNCTION public.pulse_quadrant(gsc_dir text, cooked_dir text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN gsc_dir = 'up'   AND cooked_dir = 'up'   THEN 'up_up'
    WHEN gsc_dir = 'up'   AND cooked_dir = 'flat' THEN 'up_up'
    WHEN gsc_dir = 'up'   AND cooked_dir = 'down' THEN 'up_down'
    WHEN gsc_dir = 'flat' AND cooked_dir = 'up'   THEN 'up_up'
    WHEN gsc_dir = 'flat' AND cooked_dir = 'down' THEN 'up_down'
    WHEN gsc_dir = 'down' AND cooked_dir = 'up'   THEN 'down_up'
    WHEN gsc_dir = 'down' AND cooked_dir = 'flat' THEN 'down_up'
    WHEN gsc_dir = 'down' AND cooked_dir = 'down' THEN 'down_down'
    ELSE 'neutral'
  END;
$function$


-- ═══ public.pulse_status(gsc_n bigint, gsc_prev bigint, cooked_n bigint, cooked_prev bigint, delta_threshold numeric) ═══
CREATE OR REPLACE FUNCTION public.pulse_status(gsc_n bigint, gsc_prev bigint, cooked_n bigint, cooked_prev bigint, delta_threshold numeric DEFAULT 5.0)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  WITH d AS (
    SELECT
      CASE WHEN gsc_prev > 0 THEN 100.0 * (gsc_n - gsc_prev) / gsc_prev END AS gsc_delta,
      CASE WHEN cooked_prev IS NOT NULL AND cooked_prev > 0
           THEN 100.0 * (cooked_n - cooked_prev) / cooked_prev END AS cooked_delta
  )
  SELECT CASE
    WHEN (gsc_n = 0 AND COALESCE(gsc_prev, 0) = 0) THEN 'no_signal'
    WHEN cooked_prev IS NULL THEN 'no_signal'
    WHEN (cooked_n = 0 AND COALESCE(cooked_prev, 0) = 0) THEN 'no_signal'
    ELSE public.pulse_quadrant(
      CASE WHEN d.gsc_delta IS NULL THEN 'flat'
           WHEN d.gsc_delta >=  delta_threshold THEN 'up'
           WHEN d.gsc_delta <= -delta_threshold THEN 'down'
           ELSE 'flat' END,
      CASE WHEN d.cooked_delta IS NULL THEN 'flat'
           WHEN d.cooked_delta >=  delta_threshold THEN 'up'
           WHEN d.cooked_delta <= -delta_threshold THEN 'down'
           ELSE 'flat' END
    )
  END
  FROM d;
$function$


-- ═══ public.purge_cooked_noise(retain_days integer) ═══
CREATE OR REPLACE FUNCTION public.purge_cooked_noise(retain_days integer DEFAULT 28)
 RETURNS TABLE(events_purged bigint, noise_sessions_purged bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '540s'
AS $function$
DECLARE v_ev bigint; v_ns bigint;
BEGIN
  DELETE FROM public.events e
  WHERE e.occurred_at < now() - make_interval(days => retain_days)
    AND (EXISTS (SELECT 1 FROM public.noise_sessions ns WHERE ns.session_id = e.session_id)
      OR EXISTS (SELECT 1 FROM public.bot_fingerprints bf WHERE bf.anonymous_id = e.anonymous_id));
  GET DIAGNOSTICS v_ev = ROW_COUNT;

  DELETE FROM public.noise_sessions WHERE detected_at < now() - interval '90 days';
  GET DIAGNOSTICS v_ns = ROW_COUNT;

  RETURN QUERY SELECT v_ev, v_ns;
END $function$


-- ═══ public.purge_old_events() ═══
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
  where occurred_at < now() - interval '400 days';

  get diagnostics v_deleted = row_count;

  -- Idempotent : si pas mal de rows, VACUUM pour récupérer l'espace
  if v_deleted > 1000 then
    perform pg_advisory_lock(hashtext('purge_old_events_vacuum'));
    -- Note : VACUUM ne peut pas tourner dans une transaction, donc on
    -- log seulement. À appeler manuellement après gros purge si besoin.
    perform pg_advisory_unlock(hashtext('purge_old_events_vacuum'));
  end if;

  v_after := pg_size_pretty(pg_total_relation_size('public.events'));

  return query select
    v_deleted,
    v_before,
    v_after,
    extract(epoch from (clock_timestamp() - v_start)) * 1000;
end;
$function$


-- ═══ public.raise_cooked_alert(p_kind text, p_sev text, p_detail text) ═══
CREATE OR REPLACE FUNCTION public.raise_cooked_alert(p_kind text, p_sev text, p_detail text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_topic      text;
  v_last_acked boolean;
begin
  -- Dédup par (kind, severity) — et non plus par kind seul : le passage
  -- warn→critical d'un même kind s'insère (et pousse) immédiatement au lieu
  -- d'attendre jusqu'à 24 h l'expiration de la fenêtre du warn.
  if exists (
    select 1 from public.alerts
    where kind = p_kind
      and severity = p_sev
      and created_at > now() - interval '24 hours'
  ) then
    return 0;
  end if;

  -- La dernière alerte du kind est-elle acquittée ? (à lire AVANT l'insert)
  select a.acked into v_last_acked
  from public.alerts a
  where a.kind = p_kind
  order by a.created_at desc
  limit 1;

  insert into public.alerts (kind, severity, detail) values (p_kind, p_sev, p_detail);

  -- Push ntfy : critical uniquement, et pas si l'épisode est acquitté
  -- (l'insert a toujours lieu — seule la notification se tait).
  if p_sev = 'critical' and coalesce(v_last_acked, false) = false then
    begin
      select nullif(btrim(value), '') into v_topic
      from public.cooked_config where key = 'ntfy_topic';

      if v_topic is not null then
        perform net.http_post(
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
      end if;
    exception when others then
      null;
    end;
  end if;

  return 1;
end;
$function$


-- ═══ public.record_ingest_drop(p_reason text, p_n integer) ═══
CREATE OR REPLACE FUNCTION public.record_ingest_drop(p_reason text, p_n integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  INSERT INTO public.ingest_drops (day, reason, n)
  VALUES (public.paris_today(), p_reason, greatest(p_n, 0))
  ON CONFLICT (day, reason) DO UPDATE SET n = ingest_drops.n + excluded.n;
$function$


-- ═══ public.refresh_bot_fingerprints() ═══
CREATE OR REPLACE FUNCTION public.refresh_bot_fingerprints()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET lock_timeout TO '15s'
 SET statement_timeout TO '300s'
AS $function$
begin
  -- Monotone : un anonymous_id classé crawler le reste → on NE DELETE PAS,
  -- on ajoute seulement les nouveaux détectés sur la fenêtre 48h.
  insert into public.bot_fingerprints (anonymous_id, reason)
  select distinct on (sub.anonymous_id)
    sub.anonymous_id,
    format('crawl: %s pv, %s paths, 0 scroll on %s',
           sub.pvs, sub.distinct_paths, sub.day) as reason
  from (
    select e.anonymous_id, public.paris_date(e.occurred_at) as day,
      count(*) filter (where e.name = 'pageview') as pvs,
      count(*) filter (where e.name = 'scroll_depth') as scrolls,
      count(distinct e.path) filter (where e.name = 'pageview') as distinct_paths
    from public.events_main e
    where e.anonymous_id is not null
      and e.occurred_at > now() - interval '48 hours'
    group by e.anonymous_id, public.paris_date(e.occurred_at)
    having count(*) filter (where e.name = 'pageview') > 20
       and count(*) filter (where e.name = 'scroll_depth') = 0
  ) sub
  order by sub.anonymous_id, sub.day desc  -- 1 row per anonymous_id, latest day wins
  on conflict (anonymous_id) do nothing;
end;
$function$


-- ═══ public.refresh_dashboard_expertises_snapshots(p_window text) ═══
CREATE OR REPLACE FUNCTION public.refresh_dashboard_expertises_snapshots(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int; cpi_day date;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_expertises_snapshot       WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_kpis_snapshot  WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_trend_snapshot WHERE window_kind = ANY(windows);

  DROP TABLE IF EXISTS _xp;
  CREATE TEMP TABLE _xp ON COMMIT DROP AS
    SELECT * FROM (VALUES
      ('/defense-penale/droit-penal'),
      ('/defense-penale/droit-penal-des-affaires'),
      ('/defense-penale/proces-criminel'),
      ('/defense-penale/trafic-de-stupefiant'),
      ('/defense-penale/violences-conjugales-et-feminicides'),
      ('/indemnisation-des-victimes/accidents-de-la-route'),
      ('/indemnisation-des-victimes/accidents-de-la-vie-courante'),
      ('/indemnisation-des-victimes/accidents-et-erreurs-medicales'),
      ('/indemnisation-des-victimes/droit-et-accidents-du-travail'),
      ('/indemnisation-des-victimes/victimes-de-delits-ou-crimes'),
      ('/droit-des-contrats-et-des-personnes/droit-de-la-famille'),
      ('/droit-des-contrats-et-des-personnes/droit-de-la-famille/avocat-divorce-bordeaux'),
      ('/droit-des-contrats-et-des-personnes/defense-des-consommateurs'),
      ('/droit-des-contrats-et-des-personnes/droit-assurances-particuliers-professionnels')
    ) v(path);
  ANALYZE _xp;

  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'clean', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);
    DROP TABLE IF EXISTS _evx;
    CREATE TEMP TABLE _evx ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.occurred_at,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        e.d
      FROM _cooked_ev e JOIN _xp ON _xp.path=e.path
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com';
    ANALYZE _evx;

    DROP TABLE IF EXISTS _fp;
    CREATE TEMP TABLE _fp ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
        public.classify_channel(e.referrer_hostname,e.utm_source,e.utm_medium,'www.jplouton-avocat.fr') AS chan
      FROM _cooked_ev e
      WHERE e.name='pageview'
        AND e.session_id IN (SELECT DISTINCT session_id FROM _evx WHERE name='pageview' AND d BETWEEN lns AND lne)
        AND e.d BETWEEN lns AND lne
      ORDER BY e.session_id, e.occurred_at;
    ANALYZE _fp;

    INSERT INTO public.dashboard_expertises_snapshot (
      window_kind, path, theme, unique_visitors, pageviews, dwell_median_s, scroll_median,
      gsc_clicks, gsc_impressions, gsc_position_avg, gsc_ctr_pct,
      best_query, best_query_clicks, best_query_volume_fr, best_query_cpc,
      contacts, booking_intent, first_impression_day, first_tracker_day, days_live,
      confidence, cooked_start, cooked_end, gsc_start, gsc_end, refreshed_at,
      unique_visitors_prev, gsc_clicks_prev, cpi, cpi_grade, momentum, potentiel, convertit,
      ctr_expected, paid_share_pct)
    WITH
    reads AS (
      SELECT fp.entry_path AS path,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.dur)) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.scr)) AS scroll
      FROM _fp fp
      JOIN (SELECT session_id, path, max(dur) dur, max(scr) scr FROM _evx WHERE name='page_exit' GROUP BY session_id, path) a
        ON a.session_id=fp.session_id AND a.path=fp.entry_path
      WHERE fp.chan LIKE 'organic%' AND fp.entry_path IN (SELECT path FROM _xp)
      GROUP BY fp.entry_path
    ),
    vis AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv
      FROM _evx GROUP BY path
    ),
    pgchan AS (
      SELECT ev.path,
        COUNT(DISTINCT ev.session_id) AS tot,
        COUNT(DISTINCT ev.session_id) FILTER (WHERE fp.chan='paid') AS paid
      FROM _evx ev JOIN _fp fp ON fp.session_id=ev.session_id
      WHERE ev.name='pageview' AND ev.d BETWEEN lns AND lne
      GROUP BY ev.path
    ),
    gsc AS (SELECT m.path,m.clicks_total,m.impressions_total,m.position_avg,m.ctr_pct
            FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
    gscp AS (SELECT m.path,m.clicks_total AS clicks_prev FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
    cpi_d AS (SELECT path,cpi,grade,momentum FROM cpi_daily WHERE day=cpi_day),
    gis AS (SELECT path,potentiel,convertit FROM cpi_gisement),
    bestq AS (
      SELECT DISTINCT ON (q.path) q.path,q.query,q.clicks FROM (
        SELECT qp.path,qp.query,SUM(qp.clicks) clicks,SUM(qp.impressions) impr
        FROM gsc_query_page_daily qp JOIN _xp ON _xp.path=qp.path
        WHERE qp.day BETWEEN gns AND gne AND NOT public.gsc_is_branded(qp.query)
        GROUP BY qp.path,qp.query) q
      ORDER BY q.path,q.clicks DESC,q.impr DESC
    ),
    contacts AS (SELECT mc.path,mc.contacts,mc.booking_intent FROM macro_contacts_by_path(lns,lne) mc JOIN _xp ON _xp.path=mc.path)
    SELECT w, x.path,
      (SELECT theme FROM page_taxonomy pt WHERE pt.path=x.path),
      COALESCE(v.uv,0), COALESCE(v.pv,0), r.dwell, r.scroll,
      COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
      bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
      COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
      NULL::date, NULL::date, NULL::int,
      CASE WHEN ld>0 AND COALESCE(v.uv,0)::numeric/ld >= 1.5 THEN 'A'
           WHEN ld>0 AND COALESCE(v.uv,0)::numeric/ld >= 0.5 THEN 'B' ELSE 'C' END,
      lns, lne, gns, gne, now(),
      COALESCE(v.uv_prev,0)::int, COALESCE(gp.clicks_prev,0)::int,
      cd.cpi, cd.grade, cd.momentum, gi.potentiel, gi.convertit,
      CASE WHEN g.position_avg IS NOT NULL THEN ROUND(ctr_for_position(g.position_avg)*100,2) END,
      CASE WHEN pc.tot>0 THEN ROUND(100.0*pc.paid/pc.tot,1) END
    FROM _xp x
    LEFT JOIN vis v      ON v.path=x.path
    LEFT JOIN reads r    ON r.path=x.path
    LEFT JOIN pgchan pc  ON pc.path=x.path
    LEFT JOIN gsc g      ON g.path=x.path
    LEFT JOIN gscp gp    ON gp.path=x.path
    LEFT JOIN cpi_d cd   ON cd.path=x.path
    LEFT JOIN gis gi     ON gi.path=x.path
    LEFT JOIN bestq bq   ON bq.path=x.path
    LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=bq.query AND dfs.location_code=2250
    LEFT JOIN contacts ct ON ct.path=x.path;

    INSERT INTO public.dashboard_expertises_kpis_snapshot (
      window_kind, label_fr, cooked_start, cooked_end, gsc_start, gsc_end, gsc_last_day, lag_days,
      is_partial, visitors_n, visitors_prev, pageviews_n, pageviews_prev, contacts_n, contacts_prev,
      gsc_clicks_n, gsc_clicks_prev, gsc_impressions_n, gsc_impressions_prev, refreshed_at,
      current_day_partial, no_prev_baseline, paid_entries_n, organic_entries_n, total_entries_n)
    SELECT w, lbl, lns, lne, gns, gne, glast, glag,
      ((lne >= lpt) OR (tracker_first_seen_global() > lpe::timestamptz)),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lps AND lpe),
      (SELECT COUNT(*) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(*) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lps AND lpe),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lns,lne) mc JOIN _xp ON _xp.path=mc.path),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lps,lpe) mc JOIN _xp ON _xp.path=mc.path),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
      now(), (lne >= lpt), (tracker_first_seen_global() > lpe::timestamptz),
      (SELECT COUNT(*) FILTER (WHERE chan='paid')          FROM _fp),
      (SELECT COUNT(*) FILTER (WHERE chan LIKE 'organic%') FROM _fp),
      (SELECT COUNT(*)                                     FROM _fp);

    INSERT INTO public.dashboard_expertises_trend_snapshot (
      window_kind, visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily, refreshed_at)
    SELECT w,
      (SELECT array_agg(COALESCE(v.uv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT d,COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') uv FROM _evx WHERE d BETWEEN lns AND lne GROUP BY d) v ON v.d=ds.d),
      (SELECT array_agg(COALESCE(p.pv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT d,COUNT(*) pv FROM _evx WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) p ON p.d=ds.d),
      (SELECT array_agg(COALESCE(ct.ct,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (
           SELECT public.paris_date(e.occurred_at) d, COUNT(*) ct
           FROM events_human e JOIN _xp ON _xp.path=e.path
           WHERE e.name IN ('cta_phone_click','form_submit')
             AND (e.name='cta_phone_click' OR form_submit_counts_as_macro(e.props))
             AND public.paris_date(e.occurred_at) BETWEEN lns AND lne
           GROUP BY 1
         ) ct ON ct.d=ds.d),
      (SELECT array_agg(COALESCE(gd.clicks,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp,gne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT day,SUM(clicks) clicks FROM gsc_path_daily WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM _xp) GROUP BY day) gd ON gd.day=ds.d),
      (SELECT array_agg(COALESCE(gd.impr,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp,gne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT day,SUM(impressions) impr FROM gsc_path_daily WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM _xp) GROUP BY day) gd ON gd.day=ds.d),
      now();
  END LOOP;
END $function$


-- ═══ public.refresh_dashboard_resources_assisted(p_window text) ═══
CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lbl text; lns date; lne date; lps date; lpe date; lpt date; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int;
BEGIN
  DELETE FROM public.dashboard_resources_assisted_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'human', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);

    INSERT INTO public.dashboard_resources_assisted_snapshot
      (window_kind, path, assisted_contacts, assisted_prev, refreshed_at)
    SELECT w, pt.path, COALESCE(cur.n, 0), COALESCE(prv.n, 0), now()
    FROM public.page_taxonomy pt
    LEFT JOIN (
      SELECT entry_path, contacts AS n
      FROM public.assisted_contacts_by_entry_path(lns, lne)
    ) cur ON cur.entry_path = pt.path
    LEFT JOIN (
      SELECT entry_path, contacts AS n
      FROM public.assisted_contacts_by_entry_path(lps, lpe)
    ) prv ON prv.entry_path = pt.path
    WHERE pt.category = 'ressource';
  END LOOP;
END;
$function$


-- ═══ public.refresh_dashboard_snapshots(p_window text) ═══
CREATE OR REPLACE FUNCTION public.refresh_dashboard_snapshots(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text;
  lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int;
  cpi_day date;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_resources_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_kpis_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_trend_snapshot WHERE window_kind = ANY(windows);
  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'clean', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);
    DROP TABLE IF EXISTS _ev;
    CREATE TEMP TABLE _ev ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.referrer_hostname AS ref,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        e.d
      FROM _cooked_ev e
      JOIN page_taxonomy pt ON pt.path = e.path AND pt.category='ressource'
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com';
    DROP TABLE IF EXISTS _evc;
    CREATE TEMP TABLE _evc ON COMMIT DROP AS SELECT * FROM _ev;
    ANALYZE _evc;
    INSERT INTO public.dashboard_resources_snapshot
    WITH res AS (SELECT pt.path, pt.theme FROM page_taxonomy pt WHERE pt.category='ressource'),
    dwx AS (
      SELECT path,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY dur)) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY scr)) AS scroll
      FROM (
        SELECT path, session_id, max(dur) AS dur, max(scr) AS scr
        FROM _evc
        WHERE name='page_exit' AND d BETWEEN lns AND lne
          AND ref NOT ILIKE '%linkedin%' AND ref NOT ILIKE '%facebook%'
        GROUP BY path, session_id
      ) a GROUP BY path
    ),
    cooked AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv
      FROM _evc GROUP BY path
    ),
    gsc AS (SELECT m.path, m.clicks_total, m.impressions_total, m.position_avg, m.ctr_pct
            FROM gsc_path_metrics(gns,gne) m JOIN res ON res.path=m.path),
    gscp AS (SELECT m.path, m.clicks_total AS clicks_prev FROM gsc_path_metrics(gps,gpe) m JOIN res ON res.path=m.path),
    cpi_d AS (SELECT path, cpi, grade, momentum FROM cpi_daily WHERE day = cpi_day),
    gis AS (SELECT path, potentiel, convertit FROM cpi_gisement),
    bestq AS (
      SELECT DISTINCT ON (q.path) q.path, q.query, q.clicks FROM (
        SELECT qp.path, qp.query, SUM(qp.clicks) clicks, SUM(qp.impressions) impr
        FROM gsc_query_page_daily qp JOIN res ON res.path=qp.path
        WHERE qp.day BETWEEN gns AND gne AND NOT public.gsc_is_branded(qp.query)
        GROUP BY qp.path, qp.query) q
      ORDER BY q.path, q.clicks DESC, q.impr DESC
    ),
    contacts AS (SELECT mc.path, mc.contacts, mc.booking_intent FROM macro_contacts_by_path(lns,lne) mc JOIN res ON res.path=mc.path),
    fi AS (SELECT g.path, MIN(g.day) first_impr FROM gsc_path_daily g
           WHERE g.impressions>0 AND g.path IN (SELECT path FROM res) GROUP BY g.path),
    fv AS (SELECT e.path, MIN(public.paris_date(e.occurred_at)) first_view
           FROM events_human e
           WHERE e.name='pageview' AND e.path IN (SELECT path FROM res)
           GROUP BY e.path)
    SELECT w, res.path, res.theme,
      COALESCE(c.uv,0), COALESCE(c.pv,0), dw.dwell, dw.scroll,
      COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
      bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
      COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
      fi.first_impr, fv.first_view,
      (lpt - LEAST(COALESCE(fi.first_impr,fv.first_view), COALESCE(fv.first_view,fi.first_impr)))::int,
      CASE WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 1.5 THEN 'A'
           WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 0.5 THEN 'B' ELSE 'C' END,
      lns, lne, gns, gne, now(),
      COALESCE(c.uv_prev,0)::int, COALESCE(gp.clicks_prev,0)::int,
      cd.cpi, cd.grade, cd.momentum, gi.potentiel, gi.convertit,
      CASE WHEN g.position_avg IS NOT NULL THEN ROUND(ctr_for_position(g.position_avg)*100, 2) END
    FROM res
    LEFT JOIN cooked c ON c.path=res.path
    LEFT JOIN dwx dw ON dw.path=res.path
    LEFT JOIN gsc g ON g.path=res.path
    LEFT JOIN gscp gp ON gp.path=res.path
    LEFT JOIN cpi_d cd ON cd.path=res.path
    LEFT JOIN gis gi ON gi.path=res.path
    LEFT JOIN bestq bq ON bq.path=res.path
    LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=bq.query AND dfs.location_code=2250
    LEFT JOIN contacts ct ON ct.path=res.path
    LEFT JOIN fi ON fi.path=res.path
    LEFT JOIN fv ON fv.path=res.path;
    INSERT INTO public.dashboard_kpis_snapshot
      (window_kind, label_fr, cooked_start, cooked_end, gsc_start, gsc_end, gsc_last_day, lag_days,
       is_partial, visitors_n, visitors_prev, pageviews_n, pageviews_prev, contacts_n, contacts_prev,
       gsc_clicks_n, gsc_clicks_prev, gsc_impressions_n, gsc_impressions_prev, refreshed_at,
       current_day_partial, no_prev_baseline)
    SELECT w, lbl, lns, lne, gns, gne, glast, glag,
      ((lne >= lpt) OR (tracker_first_seen_global() > lpe::timestamptz)),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evc WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evc WHERE d BETWEEN lps AND lpe),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lps AND lpe),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lns,lne) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lps,lpe) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      now(), (lne >= lpt), (tracker_first_seen_global() > lpe::timestamptz);
    INSERT INTO public.dashboard_trend_snapshot
      (window_kind, visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily, refreshed_at)
    SELECT w,
      (SELECT array_agg(COALESCE(v.uv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') uv FROM _evc WHERE d BETWEEN lns AND lne GROUP BY d) v ON v.d = ds.d),
      (SELECT array_agg(COALESCE(p.pv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(*) pv FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) p ON p.d = ds.d),
      (SELECT array_agg(COALESCE(ct.ct,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (
           SELECT public.paris_date(e.occurred_at) d, COUNT(*) ct
           FROM events_human e JOIN page_taxonomy pt ON pt.path=e.path AND pt.category='ressource'
           WHERE e.name IN ('cta_phone_click','form_submit')
             AND (e.name='cta_phone_click' OR form_submit_counts_as_macro(e.props))
             AND public.paris_date(e.occurred_at) BETWEEN lns AND lne
           GROUP BY 1
         ) ct ON ct.d = ds.d),
      (SELECT array_agg(COALESCE(gd.clicks,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT day, SUM(clicks) clicks FROM gsc_path_daily
                    WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM page_taxonomy WHERE category='ressource') GROUP BY day) gd ON gd.day = ds.d),
      (SELECT array_agg(COALESCE(gd.impr,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT day, SUM(impressions) impr FROM gsc_path_daily
                    WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM page_taxonomy WHERE category='ressource') GROUP BY day) gd ON gd.day = ds.d),
      now();
  END LOOP;
END $function$


-- ═══ public.refresh_identity_stitch(p_days integer) ═══
CREATE OR REPLACE FUNCTION public.refresh_identity_stitch(p_days integer DEFAULT 90)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '420s'
AS $function$
DECLARE
  t0 timestamptz := now() - make_interval(days => p_days);
BEGIN
  -- Paires (aid, sid) observées. Lecture d'events BRUT, assumée et
  -- volontaire : (a) c'est de la topologie d'identité, pas un chiffre
  -- business — les ids étant aléatoires par navigateur, les sessions
  -- bots forment leurs propres composantes sans polluer celles des
  -- humains ; (b) scanner events_human (anti-joins bots/bruit) coûte
  -- >100 s sur 28 j — prohibitif ici, les consommateurs business
  -- continuent de lire events_human et joignent la couture ensuite.
  DROP TABLE IF EXISTS _st_pairs;
  CREATE TEMP TABLE _st_pairs ON COMMIT DROP AS
    SELECT DISTINCT anonymous_id AS a, session_id AS s
    FROM events
    WHERE occurred_at >= t0
      AND anonymous_id NOT LIKE 'webhook-%'
      AND session_id  NOT LIKE 'webhook-%'
      AND anonymous_id !~ '^[0-9a-f]{32}$';
  ANALYZE _st_pairs;

  -- Label propagation alternée sid→aid→sid. Convergence mesurée à
  -- 2 itérations sur 28 j de prod (12/07/2026) ; 3 par marge.
  DROP TABLE IF EXISTS _st_l0; DROP TABLE IF EXISTS _st_a1;
  DROP TABLE IF EXISTS _st_l1; DROP TABLE IF EXISTS _st_a2;
  DROP TABLE IF EXISTS _st_l2; DROP TABLE IF EXISTS _st_a3;
  DROP TABLE IF EXISTS _st_l3;
  CREATE TEMP TABLE _st_l0 ON COMMIT DROP AS
    SELECT s, min(a) AS lbl FROM _st_pairs GROUP BY s;
  CREATE TEMP TABLE _st_a1 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l0 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l1 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a1 x ON x.a = p.a GROUP BY p.s;
  CREATE TEMP TABLE _st_a2 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l1 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l2 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a2 x ON x.a = p.a GROUP BY p.s;
  CREATE TEMP TABLE _st_a3 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l2 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l3 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a3 x ON x.a = p.a GROUP BY p.s;

  DELETE FROM identity_stitch;
  INSERT INTO identity_stitch (kind, key, visitor_key)
    SELECT 'sid', s, lbl FROM _st_l3
    UNION ALL
    SELECT 'aid', a, lbl FROM _st_a3;
END $function$


-- ═══ public.refresh_noise_sessions() ═══
CREATE OR REPLACE FUNCTION public.refresh_noise_sessions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET lock_timeout TO '15s'
 SET statement_timeout TO '300s'
AS $function$
begin
  CALL public.cooked_events_window(
    now() - interval '48 hours',
    now(),
    'raw',
    'main'
  );

  delete from public.noise_sessions
  where session_id in (
    select distinct session_id from _cooked_ev
    where session_id is not null
  );

  DROP TABLE IF EXISTS _no_bots;
  CREATE TEMP TABLE _no_bots ON COMMIT DROP AS
    SELECT e.id, e.anonymous_id, e.session_id, e.name, e.referrer_hostname,
           e.user_agent, e.device_type, e.occurred_at
    FROM _cooked_ev e
    WHERE NOT EXISTS (
      SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
    );
  ANALYZE _no_bots;

  insert into public.noise_sessions (session_id, reason)
  select
    session_id,
    'prefetch: 0 ref + 0 tick + 0 scroll + 1 pv + <10s'
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
  group by session_id
  having max(referrer_hostname) is null
     and count(*) filter (where name = 'engagement_tick') = 0
     and count(*) filter (where name = 'scroll_depth')    = 0
     and count(*) filter (where name = 'pageview')        = 1
     and extract(epoch from (max(occurred_at) - min(occurred_at))) < 10
  on conflict (session_id) do nothing;

  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'ua_bot: ' || (
      case
        -- T-04 (mission 02/09/2026, a-01) : UA littéral « pc » (bot Baidu) et SEBot-WA — miroir de BOT_UA_RE (Edge v28)
        when lower(user_agent) = 'pc'                   then 'pc'
        when user_agent ilike '%sebot%'                 then 'sebot'
        when user_agent ilike '%headless%'              then 'headless'
        when user_agent ilike '%googlebot%'             then 'googlebot'
        when user_agent ilike '%bingbot%'               then 'bingbot'
        when user_agent ilike '%applebot%'              then 'applebot'
        when user_agent ilike '%duckduckbot%'           then 'duckduckbot'
        when user_agent ilike '%yandexbot%'             then 'yandexbot'
        when user_agent ilike '%baiduspider%'           then 'baiduspider'
        when user_agent ilike '%gptbot%'                then 'gptbot'
        when user_agent ilike '%claudebot%'             then 'claudebot'
        when user_agent ilike '%perplexitybot%'         then 'perplexitybot'
        when user_agent ilike '%chatgpt-user%'          then 'chatgpt-user'
        when user_agent ilike '%googleother%'           then 'googleother'
        when user_agent ilike '%semrushbot%'            then 'semrushbot'
        when user_agent ilike '%ahrefsbot%'             then 'ahrefsbot'
        when user_agent ilike '%mj12bot%'               then 'mj12bot'
        when user_agent ilike '%dotbot%'                then 'dotbot'
        when user_agent ilike '%petalbot%'              then 'petalbot'
        when user_agent ilike '%bytespider%'            then 'bytespider'
        when user_agent ilike '%lighthouse%'            then 'lighthouse'
        when user_agent ilike '%pingdom%'               then 'pingdom'
        when user_agent ilike '%uptimerobot%'           then 'uptimerobot'
        when user_agent ilike '%gtmetrix%'              then 'gtmetrix'
        when user_agent ilike '%facebookexternalhit%'   then 'facebookexternalhit'
        when user_agent ilike '%linkedinbot%'           then 'linkedinbot'
        when user_agent ilike '%twitterbot%'            then 'twitterbot'
        when user_agent ilike '%discordbot%'            then 'discordbot'
        when user_agent ilike '%telegrambot%'           then 'telegrambot'
        when user_agent ilike '%slackbot%'              then 'slackbot'
        when user_agent ilike '%whatsapp/%'             then 'whatsapp-preview'
        when user_agent ilike '%crawler%'               then 'crawler'
        when user_agent ilike '%spider%'                then 'spider'
        when user_agent ilike '%axios/%'                then 'axios'
        when user_agent ilike '%curl/%'                 then 'curl'
        when user_agent ilike '%wget%'                  then 'wget'
        when user_agent ilike '%python%'                then 'python'
        when user_agent ilike '%go-http%'               then 'go-http'
        when user_agent ilike '%node-fetch%'            then 'node-fetch'
        when user_agent ilike '%httpclient%'            then 'httpclient'
        when user_agent ilike '%java/%'                 then 'java-http'
        else 'unknown'
      end
    )
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
    and user_agent is not null
    and (
         lower(user_agent) = 'pc'
      or user_agent ilike '%sebot%'
      or user_agent ilike '%headless%'
      or user_agent ilike '%googlebot%'
      or user_agent ilike '%bingbot%'
      or user_agent ilike '%applebot%'
      or user_agent ilike '%duckduckbot%'
      or user_agent ilike '%yandexbot%'
      or user_agent ilike '%baiduspider%'
      or user_agent ilike '%gptbot%'
      or user_agent ilike '%claudebot%'
      or user_agent ilike '%perplexitybot%'
      or user_agent ilike '%chatgpt-user%'
      or user_agent ilike '%googleother%'
      or user_agent ilike '%semrushbot%'
      or user_agent ilike '%ahrefsbot%'
      or user_agent ilike '%mj12bot%'
      or user_agent ilike '%dotbot%'
      or user_agent ilike '%petalbot%'
      or user_agent ilike '%bytespider%'
      or user_agent ilike '%lighthouse%'
      or user_agent ilike '%pingdom%'
      or user_agent ilike '%uptimerobot%'
      or user_agent ilike '%gtmetrix%'
      or user_agent ilike '%facebookexternalhit%'
      or user_agent ilike '%linkedinbot%'
      or user_agent ilike '%twitterbot%'
      or user_agent ilike '%discordbot%'
      or user_agent ilike '%telegrambot%'
      or user_agent ilike '%slackbot%'
      or user_agent ilike '%whatsapp/%'
      or user_agent ilike '%crawler%'
      or user_agent ilike '%spider%'
      or user_agent ilike '%axios/%'
      or user_agent ilike '%curl/%'
      or user_agent ilike '%wget%'
      or user_agent ilike '%python%'
      or user_agent ilike '%go-http%'
      or user_agent ilike '%node-fetch%'
      or user_agent ilike '%httpclient%'
      or user_agent ilike '%java/%'
    )
  on conflict (session_id) do nothing;

  -- T-04 (mission 02/09/2026, a-01 / c-06 / d-05) : referrer spam (cooked_is_spam_referrer) — la session entière
  -- est du bruit, quel que soit l'UA. Jusqu'ici seules les RPC filtraient ce referrer ; events_human ne le voyait pas.
  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'spam_referrer: ' || referrer_hostname
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
    and name = 'pageview'
    and public.cooked_is_spam_referrer(referrer_hostname)
  on conflict (session_id) do nothing;
end;
$function$


-- ═══ public.refresh_page_taxonomy_heuristic() ═══
CREATE OR REPLACE FUNCTION public.refresh_page_taxonomy_heuristic()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_count int;
begin
  with paths as (
    select distinct path from public.events_human
    where (path like '/post/%' or public.cooked_page_type(path) in ('expertise','hub'))
      -- T-19 : ne considérer que le trafic récent (évite de ressusciter de
      -- vieux paths morts) et exclure la poubelle structurelle
      and occurred_at > now() - interval '90 days'
      and path not like '%/preview/%'   -- previews Wix avec token
      and path !~ 'https?://'           -- URLs concaténées par erreur
      and path !~ '[ÃÂ]'                -- mojibake (double encodage)
      and length(path) <= 140           -- tokens/concaténations aberrantes
  ), themed as (
    select path,
      case
        when path ~* 'garde-.?-vue|gav' then 'garde à vue'
        when path ~* 'violence|f.minicide|conjugal|harc.lement|contr.le-coercitif' then 'violences & harcèlement'
        when path ~* 'indemnis|victime|civi|sarvi|pr.judice|dommage' then 'indemnisation victimes'
        when path ~* 'accident|erreur-m.dicale|route|travail' then 'accidents & réparation'
        when path ~* 'stup.fiant|trafic|drogue' then 'stupéfiants'
        when path ~* 'd.tention|prison|peine|sursis|bracelet|ddse|suret.|am.nagement' then 'peines & détention'
        when path ~* 'affaires|fraude|abus-de|escroquerie|blanchiment|corruption|fiscal' then 'pénal des affaires'
        when path ~* 'famille|divorce|filiation|succession|contrat' then 'famille & contrats'
        when path ~* 'instruction|proc.dure|comparution|tribunal|cour-d|assises|appel|mise-en-examen|t.moin|pr.venu|accus|perquisition|audition' then 'procédure pénale'
        when path ~* 'diffamation|injure|r.putation|presse' then 'réputation & presse'
        else null
      end as theme
    from paths
  )
  insert into public.page_taxonomy (path, theme, source)
  select path, theme, 'slug_heuristic' from themed where theme is not null
  on conflict (path) do update
    set theme = excluded.theme, updated_at = now()
    where page_taxonomy.source = 'slug_heuristic';
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$


-- ═══ public.refresh_pipeline_health() ═══
CREATE OR REPLACE FUNCTION public.refresh_pipeline_health()
 RETURNS TABLE(status text, snapshot_refreshed_at timestamp with time zone, snapshot_age_hours numeric, cron_last_status text, cron_last_run timestamp with time zone, cron_age_hours numeric, last_event_at timestamp with time zone, last_event_age_minutes numeric, events_last_60min bigint, gsc_last_day date, gsc_data_age_days numeric, gsc_last_ingest timestamp with time zone, gsc_ingest_age_hours numeric, dfs_last_synced_at timestamp with time zone, dfs_row_count bigint, dfs_sync_age_hours numeric, issues text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cron', 'pg_catalog'
AS $function$
declare
  v_snapshot_refreshed_at  timestamptz;
  v_snapshot_age_hours     numeric;
  v_cron_last_status       text;
  v_cron_last_run          timestamptz;
  v_cron_age_hours         numeric;
  v_last_event_at          timestamptz;
  v_last_event_age_minutes numeric;
  v_events_last_60min      bigint;
  v_gsc_last_day           date;
  v_gsc_data_age_days      numeric;
  v_gsc_last_ingest        timestamptz;
  v_gsc_ingest_age_hours   numeric;
  v_dfs_last_synced_at     timestamptz;
  v_dfs_row_count          bigint;
  v_dfs_sync_age_hours     numeric;
  v_issues                 text[] := array[]::text[];
  v_status                 text   := 'healthy';
begin
  -- 1. Snapshot freshness
  select max(refreshed_at) into v_snapshot_refreshed_at from public.seo_url_snapshot;
  v_snapshot_age_hours := extract(epoch from (now() - v_snapshot_refreshed_at)) / 3600;

  if v_snapshot_refreshed_at is null then
    v_issues := v_issues || 'snapshot_never_refreshed'::text;
    v_status := 'critical';
  elsif v_snapshot_age_hours > 36 then
    v_issues := v_issues || ('snapshot_stale: '||round(v_snapshot_age_hours,1)||'h old');
    v_status := 'critical';
  elsif v_snapshot_age_hours > 25 then
    v_issues := v_issues || ('snapshot_aging: '||round(v_snapshot_age_hours,1)||'h old');
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  -- 2. Cron last run status (refresh_seo_url_snapshot)
  select d.status, d.start_time into v_cron_last_status, v_cron_last_run
  from cron.job j join cron.job_run_details d on d.jobid = j.jobid
  where j.jobname = 'refresh_seo_url_snapshot'
  order by d.start_time desc limit 1;

  v_cron_age_hours := extract(epoch from (now() - v_cron_last_run)) / 3600;

  if v_cron_last_run is null then
    v_issues := v_issues || 'cron_no_run_history'::text;
    v_status := 'critical';
  elsif v_cron_last_status is distinct from 'succeeded' then
    v_issues := v_issues || ('cron_last_failed: status='||coalesce(v_cron_last_status,'NULL'));
    v_status := 'critical';
  elsif v_cron_age_hours > 25 then
    v_issues := v_issues || ('cron_overdue: '||round(v_cron_age_hours,1)||'h since last run');
    v_status := 'critical';
  end if;

  -- 3. Ingestion freshness (events table)
  select max(occurred_at) into v_last_event_at from public.events;
  v_last_event_age_minutes := extract(epoch from (now() - v_last_event_at)) / 60;
  select count(*) into v_events_last_60min from public.events
  where occurred_at >= now() - interval '60 minutes';

  if v_last_event_at is null then
    v_issues := v_issues || 'no_events_ever'::text;
    v_status := 'critical';
  elsif v_last_event_age_minutes > 360 then
    v_issues := v_issues || ('ingestion_stopped: '||round(v_last_event_age_minutes)||'min since last event');
    v_status := 'critical';
  elsif v_last_event_age_minutes > 60 then
    v_issues := v_issues || ('ingestion_quiet: '||round(v_last_event_age_minutes)||'min since last event');
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  -- 4. GSC freshness
  select max(day) into v_gsc_last_day from public.gsc_path_daily;
  select max(ingested_at) into v_gsc_last_ingest from public.gsc_path_daily;
  v_gsc_data_age_days    := (((now() at time zone 'Europe/Paris')::date - v_gsc_last_day))::numeric;
  v_gsc_ingest_age_hours := extract(epoch from (now() - v_gsc_last_ingest)) / 3600;

  if v_gsc_last_day is null then
    v_issues := v_issues || 'gsc_no_data'::text;
    v_status := 'critical';
  elsif v_gsc_data_age_days > 7 then
    v_issues := v_issues || ('gsc_data_stale: '||round(v_gsc_data_age_days)||' days behind');
    v_status := 'critical';
  elsif v_gsc_data_age_days > 4 then
    v_issues := v_issues || ('gsc_data_aging: '||round(v_gsc_data_age_days)||' days behind');
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  if v_gsc_last_ingest is not null then
    if v_gsc_ingest_age_hours > 72 then
      v_issues := v_issues || ('gsc_ingest_stale: '||round(v_gsc_ingest_age_hours,1)||'h since last ingest');
      v_status := 'critical';
    elsif v_gsc_ingest_age_hours > 30 then
      v_issues := v_issues || ('gsc_ingest_aging: '||round(v_gsc_ingest_age_hours,1)||'h since last ingest');
      if v_status = 'healthy' then v_status := 'degraded'; end if;
    end if;
  end if;

  -- 5. DataForSEO keyword volume sync (hebdo)
  select max(last_synced_at), count(*)::bigint into v_dfs_last_synced_at, v_dfs_row_count
  from public.dfs_keyword_volume;

  if v_dfs_last_synced_at is not null then
    v_dfs_sync_age_hours := extract(epoch from (now() - v_dfs_last_synced_at)) / 3600;
  end if;

  if v_dfs_row_count is null or v_dfs_row_count = 0 then
    v_issues := v_issues || 'dfs_no_data'::text;
    v_status := 'critical';
  elsif v_dfs_row_count < 200 then
    v_issues := v_issues || ('dfs_partial_sync: '||v_dfs_row_count||' rows (expected ~300-500)');
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  if v_dfs_last_synced_at is null then
  elsif v_dfs_sync_age_hours > 240 then
    v_issues := v_issues || ('dfs_sync_stale: '||round(v_dfs_sync_age_hours,1)||'h since last sync');
    v_status := 'critical';
  elsif v_dfs_sync_age_hours > 192 then
    v_issues := v_issues || ('dfs_sync_aging: '||round(v_dfs_sync_age_hours,1)||'h since last sync');
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  return query select
    v_status, v_snapshot_refreshed_at, round(v_snapshot_age_hours, 2),
    v_cron_last_status, v_cron_last_run, round(v_cron_age_hours, 2),
    v_last_event_at, round(v_last_event_age_minutes, 1), v_events_last_60min,
    v_gsc_last_day, round(v_gsc_data_age_days, 2), v_gsc_last_ingest, round(v_gsc_ingest_age_hours, 2),
    v_dfs_last_synced_at, v_dfs_row_count, round(v_dfs_sync_age_hours, 2),
    v_issues;
end;
$function$


-- ═══ public.refresh_seo_url_snapshot() ═══
CREATE OR REPLACE FUNCTION public.refresh_seo_url_snapshot()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  now_ts timestamptz := now();
begin
  perform public.refresh_bot_fingerprints();
  perform public.refresh_noise_sessions();

  call public.cooked_events_window(
    now_ts - interval '365 days',
    now_ts,
    'human',
    'main'
  );

  drop table if exists _eh;
  create temp table _eh on commit drop as
    select id, anonymous_id, session_id, path, name, occurred_at,
           referrer_hostname, utm_source, utm_medium, device_type, props
    from _cooked_ev;
  analyze _eh;

  delete from public.seo_url_snapshot;

  insert into public.seo_url_snapshot
  with
    all_paths as (
      select distinct path from _eh
      where path is not null and occurred_at >= now_ts - interval '365 days'
    ),
    o7 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '7 days'   and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    o28 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '28 days'  and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    o90 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '90 days'  and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    o365 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '365 days' and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    cwv as (
      select path,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='LCP'))::numeric  as lcp_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='INP'))::numeric  as inp_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='CLS'))::numeric  as cls_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='TTFB'))::numeric as ttfb_p75
      from _eh where name='web_vitals' and path is not null and occurred_at >= now_ts - interval '28 days' group by path
    ),
    top_ref as (select distinct on (path) path, referrer_hostname as top_referrer from (
        select path, referrer_hostname, count(*) as c from _eh
        where name='pageview' and path is not null and referrer_hostname is not null and occurred_at >= now_ts - interval '28 days'
        group by path, referrer_hostname) r order by path, c desc),
    top_src as (select distinct on (path) path, utm_source as top_source from (
        select path, utm_source, count(*) as c from _eh
        where name='pageview' and path is not null and utm_source is not null and occurred_at >= now_ts - interval '28 days'
        group by path, utm_source) r order by path, c desc),
    top_med as (select distinct on (path) path, utm_medium as top_medium from (
        select path, utm_medium, count(*) as c from _eh
        where name='pageview' and path is not null and utm_medium is not null and occurred_at >= now_ts - interval '28 days'
        group by path, utm_medium) r order by path, c desc),
    dev as (select path, jsonb_object_agg(device_type, pct) as split from (
        select path, device_type, round((100.0*count(*)/sum(count(*)) over (partition by path))::numeric,1) as pct
        from _eh where name='pageview' and path is not null and device_type is not null and occurred_at >= now_ts - interval '28 days'
        group by path, device_type) d group by path),
    phone_counts as (select path,
        count(*) filter (where occurred_at >= now_ts - interval '7 days')   as p7,
        count(*) filter (where occurred_at >= now_ts - interval '28 days')  as p28,
        count(*) filter (where occurred_at >= now_ts - interval '90 days')  as p90,
        count(*) filter (where occurred_at >= now_ts - interval '365 days') as p365
      from _eh where name='cta_phone_click' and path is not null and occurred_at >= now_ts - interval '365 days' group by path),
    booking_counts as (select path,
        count(*) filter (where occurred_at >= now_ts - interval '7 days')   as b7,
        count(*) filter (where occurred_at >= now_ts - interval '28 days')  as b28,
        count(*) filter (where occurred_at >= now_ts - interval '90 days')  as b90,
        count(*) filter (where occurred_at >= now_ts - interval '365 days') as b365
      from _eh where name='cta_booking_click' and path is not null and occurred_at >= now_ts - interval '365 days' group by path),
    pogo as (
      with google_entries as (select distinct session_id, path from _eh
             where name='pageview' and referrer_hostname like '%google%'
               and occurred_at >= now_ts - interval '28 days' and occurred_at < now_ts),
      session_pages as (select session_id, count(*) as pages from _eh
             where name='pageview' and occurred_at >= now_ts - interval '28 days' and occurred_at < now_ts group by session_id),
      session_exit as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) as dwell_s,
                    max((props->>'max_scroll')::numeric)       as scroll
             from _eh where name='page_exit' and occurred_at >= now_ts - interval '28 days' and occurred_at < now_ts
             group by session_id, path)
      select g.path, count(*)::bigint as google_sessions,
        count(*) filter (where sp.pages=1 and (se.dwell_s<10 or se.dwell_s is null))::bigint as pogo_sticks,
        count(*) filter (where sp.pages=1 and ((se.dwell_s<10 and se.scroll<5) or se.dwell_s is null))::bigint as hard_pogo,
        round(100.0*count(*) filter (where sp.pages=1 and (se.dwell_s<10 or se.dwell_s is null))/nullif(count(*),0),1) as pogo_rate
      from google_entries g
      left join session_pages sp on sp.session_id=g.session_id
      left join session_exit  se on se.session_id=g.session_id and se.path=g.path
      group by g.path
    ),
    device_sessions as (select path,
        count(distinct session_id) filter (where device_type='mobile')  as mob_s,
        count(distinct session_id) filter (where device_type='desktop') as dsk_s
      from _eh where name='pageview' and path is not null and occurred_at >= now_ts - interval '28 days' group by path),
    device_cta as (select path,
        count(*) filter (where device_type='mobile')  as mob_cta,
        count(*) filter (where device_type='desktop') as dsk_cta
      from _eh where name in ('cta_phone_click','cta_booking_click') and path is not null and occurred_at >= now_ts - interval '28 days' group by path)
  select
    p.path,
    coalesce(o7.views,0), coalesce(o7.unique_visitors,0), coalesce(o7.sessions,0), coalesce(o7.bounce_rate,0),
    coalesce(o7.avg_dwell_seconds,0), coalesce(o7.scroll_avg,0), coalesce(o7.scroll_median,0), coalesce(o7.scroll_complete_pct,0),
    coalesce(o7.entry_count,0), coalesce(o7.exit_count,0), coalesce(o7.outbound_clicks,0),
    coalesce(o28.views,0), coalesce(o28.unique_visitors,0), coalesce(o28.sessions,0), coalesce(o28.bounce_rate,0),
    coalesce(o28.avg_dwell_seconds,0), coalesce(o28.scroll_avg,0), coalesce(o28.scroll_median,0), coalesce(o28.scroll_complete_pct,0),
    coalesce(o28.entry_count,0), coalesce(o28.exit_count,0), coalesce(o28.outbound_clicks,0),
    coalesce(o90.views,0), coalesce(o90.unique_visitors,0), coalesce(o90.sessions,0), coalesce(o90.bounce_rate,0),
    coalesce(o90.avg_dwell_seconds,0), coalesce(o90.scroll_avg,0), coalesce(o90.scroll_median,0), coalesce(o90.scroll_complete_pct,0),
    coalesce(o90.entry_count,0), coalesce(o90.exit_count,0), coalesce(o90.outbound_clicks,0),
    coalesce(o365.views,0), coalesce(o365.unique_visitors,0), coalesce(o365.sessions,0), coalesce(o365.bounce_rate,0),
    coalesce(o365.avg_dwell_seconds,0), coalesce(o365.scroll_avg,0), coalesce(o365.scroll_median,0), coalesce(o365.scroll_complete_pct,0),
    coalesce(o365.entry_count,0), coalesce(o365.exit_count,0), coalesce(o365.outbound_clicks,0),
    cwv.lcp_p75, cwv.inp_p75, cwv.cls_p75, cwv.ttfb_p75,
    top_ref.top_referrer, top_src.top_source, top_med.top_medium, dev.split,
    now_ts,
    coalesce(phone_counts.p7,0)::bigint, coalesce(phone_counts.p28,0)::bigint, coalesce(phone_counts.p90,0)::bigint, coalesce(phone_counts.p365,0)::bigint,
    coalesce(booking_counts.b7,0)::bigint, coalesce(booking_counts.b28,0)::bigint, coalesce(booking_counts.b90,0)::bigint, coalesce(booking_counts.b365,0)::bigint,
    coalesce(pogo.google_sessions,0)::bigint, coalesce(pogo.pogo_sticks,0)::bigint, coalesce(pogo.hard_pogo,0)::bigint, pogo.pogo_rate,
    coalesce(device_sessions.mob_s,0)::bigint, coalesce(device_sessions.dsk_s,0)::bigint,
    case when coalesce(device_sessions.mob_s,0)>0 then round(100.0*coalesce(device_cta.mob_cta,0)/device_sessions.mob_s,2) else null end,
    case when coalesce(device_sessions.dsk_s,0)>0 then round(100.0*coalesce(device_cta.dsk_cta,0)/device_sessions.dsk_s,2) else null end
  from all_paths p
    left join o7      on o7.path     = p.path
    left join o28     on o28.path    = p.path
    left join o90     on o90.path    = p.path
    left join o365    on o365.path   = p.path
    left join cwv     on cwv.path    = p.path
    left join top_ref on top_ref.path = p.path
    left join top_src on top_src.path = p.path
    left join top_med on top_med.path = p.path
    left join dev     on dev.path    = p.path
    left join phone_counts   on phone_counts.path   = p.path
    left join booking_counts on booking_counts.path = p.path
    left join pogo            on pogo.path            = p.path
    left join device_sessions on device_sessions.path = p.path
    left join device_cta      on device_cta.path      = p.path;
end;
$function$


-- ═══ public.rls_auto_enable() ═══
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$


-- ═══ public.rpc_contract_check(p_name text, p_sql text, p_min_rows integer, p_exact_rows integer) ═══
CREATE OR REPLACE FUNCTION public.rpc_contract_check(p_name text, p_sql text, p_min_rows integer DEFAULT NULL::integer, p_exact_rows integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_start timestamptz := clock_timestamp();
  v_rows  bigint;
  v_ms    numeric;
BEGIN
  EXECUTE p_sql INTO v_rows;
  v_ms := extract(epoch from (clock_timestamp() - v_start)) * 1000;

  IF p_exact_rows IS NOT NULL AND v_rows <> p_exact_rows THEN
    INSERT INTO rpc_health (rpc_name, status, detail, rows_returned, duration_ms)
    VALUES (p_name, 'failed',
            format('expected exactly %s row(s), got %s', p_exact_rows, v_rows),
            v_rows, v_ms);
  ELSIF p_min_rows IS NOT NULL AND v_rows < p_min_rows THEN
    INSERT INTO rpc_health (rpc_name, status, detail, rows_returned, duration_ms)
    VALUES (p_name, 'failed',
            format('expected at least %s row(s), got %s', p_min_rows, v_rows),
            v_rows, v_ms);
  ELSE
    INSERT INTO rpc_health (rpc_name, status, rows_returned, duration_ms)
    VALUES (p_name, 'ok', v_rows, v_ms);
  END IF;

-- WHEN OTHERS ne rattrape PAS query_canceled (57014) : l'exclusion est
-- explicite en PL/pgSQL. Sans le OR, un statement_timeout sur un seul RPC
-- annulerait la transaction entiere et n'ecrirait aucune ligne — le bug qui
-- a rendu le harnais muet pendant 23 jours. Une fois le timeout rattrape,
-- le minuteur est desarme et les tests suivants s'executent normalement.
EXCEPTION WHEN OTHERS OR query_canceled THEN
  INSERT INTO rpc_health (rpc_name, status, detail, duration_ms)
  VALUES (p_name, 'failed', SQLERRM,
          extract(epoch from (clock_timestamp() - v_start)) * 1000);
END;
$function$


-- ═══ public.run_rpc_contract_tests() ═══
CREATE OR REPLACE FUNCTION public.run_rpc_contract_tests()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '900s'
AS $function$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('snapshot_pages_export',
       $q$select count(*) from public.snapshot_pages_export() where refreshed_at is not null$q$,
       1, NULL),

      ('site_context_export',
       $q$select count(*) from public.site_context_export() where global_sessions_28d > 0$q$,
       NULL, 1),

      ('cta_breakdown_for_path',
       $q$select count(*) from public.cta_breakdown_for_path('/', 28)
          where cta_type in ('phone', 'email', 'booking')
            and placement in ('header', 'footer', 'body', 'sticky')$q$,
       NULL, NULL),

      ('outbound_destinations_for_path',
       $q$select count(*) from public.outbound_destinations_for_path('/', 28)$q$,
       NULL, NULL),

      ('behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())$q$,
       NULL, NULL),

      ('engagement_density_for_path',
       $q$select count(*) from public.engagement_density_for_path('/', 28)$q$,
       NULL, NULL),

      ('tracker_first_seen_global',
       $q$select count(*) from (select public.tracker_first_seen_global() v) s where s.v is not null$q$,
       NULL, 1),

      ('refresh_pipeline_health',
       $q$select count(*) from public.refresh_pipeline_health()$q$,
       NULL, 1),

      -- Ajoute le 28/07/2026 : le module Lecture (CONTEXT.md § Lecture).
      -- Cout d'ajout d'un test au contrat : une ligne. C'etait tout l'objet
      -- de ce depliage. `source` doit rester 'page_exit' tant que la
      -- reconstruction engagement_tick n'est pas decidee et annotee.
      ('page_reads',
       $q$select count(*) from public.page_reads(7) where source = 'page_exit'$q$,
       1, NULL),

      -- T-03 (mission 02/09/2026, invariant I5) : contrat d'unités — *_rate ∈ [0,1], *_pct ∈ [0,100],
      -- et un même nom de colonne = une même unité. exact_rows = 0 : aucune ligne ne doit violer.
      ('units_behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),

      ('units_seo_pages_overview',
       $q$select count(*) from public.seo_pages_overview(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),

      ('units_cooked_bounce_rate_range',
       $q$select count(*) from (
            select cooked_bounce_rate from public.gsc_page_performance('/', 'rolling_28')
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u where cooked_bounce_rate > 100 or cooked_bounce_rate < 0$q$,
       NULL, 0),

      -- Un lot de ≥ 20 pages dont le max ≤ 1 = une fraction 0-1 publiée sous un nom en pourcentage.
      ('units_cooked_bounce_rate_unit',
       $q$select case when count(*) >= 20 and max(cooked_bounce_rate) <= 1 then 1 else 0 end from (
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u$q$,
       NULL, 0),

      -- T-04 (mission 02/09/2026, invariant I3) : part de pageviews de robot / referrer spam dans events_human
      -- < 1 % sur 7 j (1 si violation, 0 sinon ; garde ≥ 100 pageviews). Avant T-04 : 13,6 % (03/09/2026).
      ('spam_share_events_human',
       $q$select case when count(*) filter (where name = 'pageview') >= 100
                    and 100.0 * count(*) filter (where name = 'pageview'
                          and (lower(user_agent) = 'pc' or user_agent ilike '%sebot%'
                               or public.cooked_is_spam_referrer(referrer_hostname)))
                        / count(*) filter (where name = 'pageview') >= 1
                  then 1 else 0 end
          from public.events_human where occurred_at > now() - interval '7 days'$q$,
       NULL, 0),

      -- T-04 (invariant I3) : classify_channel renvoie 'spam' pour tout referrer spam (0 écart attendu).
      ('classify_channel_spam',
       $q$select count(*) from (values ('m.baidu.com'), ('baidu.com')) v(h)
          where public.classify_channel(v.h, null, null, 'www.jplouton-avocat.fr') <> 'spam'$q$,
       NULL, 0),

      -- T-05 (mission 02/09/2026, invariant I4) : « 28 j » GSC = 28 jours clos à gsc_last_data_day(). Écart attendu 0.
      ('gsc_pages_overview_28d_alignes',
       $q$select abs(coalesce((select sum(gsc_clicks_28d) from public.gsc_pages_overview(100000)), 0)
                 - coalesce((select sum(g.clicks) from public.gsc_path_daily g,
                               public.cooked_period_bounds('rolling_28', 'gsc') b
                             where g.day between b.n_start and b.n_end), 0))$q$,
       NULL, 0),

      -- T-05 (invariants I4/I10) : aucune borne d'horloge dans le CPI — ses fenêtres sont closes à gsc_last_data_day()
      -- et le score d'un jour est reproductible. 0 occurrence attendue de now()/current_date/… dans le corps.
      ('cpi_sans_horloge',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'now\(\)|current_date|current_timestamp|localtimestamp', 'gi')$q$,
       NULL, 0),

      -- T-09 (mission 02/09/2026, invariant I4) : « contacts macro 28 j » = UN chiffre. site_macro_counts sur les bornes
      -- live_j1 = Σ macro_contacts_by_path(28) = conversion_journeys(28) (téléphone + formulaires macro). Écart attendu 0.
      ('contacts_28j_une_fenetre',
       $q$with b as (select n_start, n_end from public.cooked_period_bounds('rolling_28', 'live_j1')),
               s as (select sm.macro_conversions as n from b, public.site_macro_counts(b.n_start, b.n_end) sm),
               m as (select coalesce(sum(contacts), 0) as n from public.macro_contacts_by_path(28)),
               j as (select count(*) as n from public.conversion_journeys(28))
          select abs((select n from s) - (select n from m)) + abs((select n from s) - (select n from j))$q$,
       NULL, 0),

      -- T-09 (I4) : le funnel SEO et conversion_journeys comptent les mêmes contacts organiques sur la même fenêtre (cross).
      ('funnel_meme_total_que_journeys',
       $q$with b as (select n_end from public.cooked_period_bounds('rolling_28', 'cross'))
          select abs(coalesce((select sum(contacts) from public.seo_to_contact_funnel(28)), 0)
                   - (select count(*) from b, public.conversion_journeys(28, b.n_end) j
                      where j.entry_channel like 'organic%' and j.entry_path is not null))$q$,
       NULL, 0),

      -- T-09 (o-14) : un identifiant de clic Ads dans l'URL d'atterrissage prime sur utm_source=gmb et sur le referrer.
      ('classify_channel_gclid_paid',
       $q$select count(*) from (values
            ('www.google.com', 'gmb', null, 'https://www.jplouton-avocat.fr/?utm_source=gmb&gclid=abc'),
            ('www.google.com', null, null, 'https://www.jplouton-avocat.fr/defense-penale?gbraid=xyz'),
            (null, null, null, 'https://www.jplouton-avocat.fr/?wbraid=k')) v(r, s, m, u)
          where public.classify_channel(v.r, v.s, v.m, 'www.jplouton-avocat.fr', v.u) is distinct from 'paid'$q$,
       NULL, 0)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;

  -- Retention 90j
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$


-- ═══ public.seo_pages_overview(date_from timestamp with time zone, date_to timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.seo_pages_overview(date_from timestamp with time zone, date_to timestamp with time zone DEFAULT now())
 RETURNS TABLE(path text, views bigint, unique_visitors bigint, sessions bigint, bounce_rate numeric, bounce_rate_pct numeric, avg_dwell_seconds numeric, scroll_avg numeric, scroll_median numeric, scroll_complete_pct numeric, entry_count bigint, exit_count bigint, outbound_clicks bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH we AS (
    SELECT * FROM public.events_human
    WHERE occurred_at >= date_from AND occurred_at < date_to
      -- T-03 (d-04) : les sessions à referrer spam (bot Baidu, UA 'pc') sortaient déjà de pv mais pas de ss :
      -- 99 entrées sur 152 pour /honoraires-rendez-vous étaient le bot (03/09/2026), d'où 21,7 % vs 32,1 % de rebond.
      AND NOT public.cooked_is_spam_referrer(referrer_hostname)
  ),
  pv AS (
    SELECT path,
      count(*) AS views,
      count(DISTINCT anonymous_id) AS unique_visitors,
      count(DISTINCT session_id) AS sessions
    FROM we
    WHERE name = 'pageview'
      AND path IS NOT NULL
      AND NOT public.cooked_is_spam_referrer(referrer_hostname)
    GROUP BY path
  ),
  ss AS (
    SELECT session_id,
      min(occurred_at) AS session_start,
      max(occurred_at) AS session_end,
      count(*) FILTER (WHERE name = 'pageview') AS pages_viewed,
      (array_agg(path ORDER BY occurred_at) FILTER (WHERE name = 'pageview'))[1] AS entry_path,
      (array_agg(path ORDER BY occurred_at DESC) FILTER (WHERE name = 'pageview'))[1] AS exit_path
    FROM we
    GROUP BY session_id
  ),
  sp AS (
    SELECT session_id, path,
      max((props->>'duration_seconds')::numeric) FILTER (WHERE name = 'page_exit') AS dwell,
      coalesce(max((props->>'percent')::numeric) FILTER (WHERE name = 'scroll_depth'), 0) AS max_scroll
    FROM we
    WHERE path IS NOT NULL
    GROUP BY session_id, path
  ),
  scroll_dwell AS (
    SELECT path,
      avg(dwell)::numeric AS avg_dwell,
      avg(max_scroll)::numeric AS scroll_avg,
      (percentile_cont(0.5) WITHIN GROUP (ORDER BY max_scroll))::numeric AS scroll_median,
      (100.0 * count(*) FILTER (WHERE max_scroll >= 100) / nullif(count(*), 0))::numeric AS scroll_complete_pct
    FROM sp
    GROUP BY path
  ),
  entry_exit AS (
    SELECT path,
      sum(is_entry)::bigint AS entry_count,
      sum(is_exit)::bigint AS exit_count,
      sum(is_bounce)::bigint AS bounce_count
    FROM (
      SELECT ss.entry_path AS path, 1 AS is_entry, 0 AS is_exit,
        CASE WHEN ss.pages_viewed = 1
              AND extract(epoch FROM (ss.session_end - ss.session_start)) < 10
             THEN 1 ELSE 0 END AS is_bounce
      FROM ss WHERE ss.entry_path IS NOT NULL
      UNION ALL
      SELECT ss.exit_path, 0, 1, 0 FROM ss WHERE ss.exit_path IS NOT NULL
    ) u
    GROUP BY path
  ),
  oc AS (
    SELECT path, count(*) AS clicks
    FROM we
    WHERE name = 'click_outbound' AND path IS NOT NULL
    GROUP BY path
  )
  SELECT pv.path,
    pv.views::bigint,
    pv.unique_visitors::bigint,
    pv.sessions::bigint,
    coalesce(round((100.0 * ee.bounce_count / nullif(ee.entry_count, 0))::numeric / 100.0, 4), 0) AS bounce_rate,
    coalesce(round((100.0 * ee.bounce_count / nullif(ee.entry_count, 0))::numeric, 2), 0) AS bounce_rate_pct,
    coalesce(round(sd.avg_dwell, 1), 0),
    coalesce(round(sd.scroll_avg, 1), 0),
    coalesce(round(sd.scroll_median, 1), 0),
    coalesce(round(sd.scroll_complete_pct, 1), 0),
    coalesce(ee.entry_count, 0)::bigint,
    coalesce(ee.exit_count, 0)::bigint,
    coalesce(oc.clicks, 0)::bigint
  FROM pv
  LEFT JOIN scroll_dwell sd ON sd.path = pv.path
  LEFT JOIN entry_exit ee ON ee.path = pv.path
  LEFT JOIN oc ON oc.path = pv.path;
$function$


-- ═══ public.seo_to_contact_funnel(days_back integer, p_end date) ═══
CREATE OR REPLACE FUNCTION public.seo_to_contact_funnel(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(entry_path text, page_type text, theme text, gsc_impressions bigint, gsc_clicks bigint, top_queries text[], organic_entries bigint, contacts bigint, contacts_phone bigint, contacts_form bigint, contact_rate_pct numeric, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-06/c-01) : UNE fenêtre pour les trois sources (GSC, entrées, contacts) = days_back
  -- jours clos à gsc_last_data_day() (lens 'cross'), p_end pour surcharger. UN grain pour le ratio : le dénominateur compte
  -- les entrées de VISITE RECOUSUE (identity_stitch, coupure 30 min — la clé de conversion_journeys), plus la session brute.
  -- FULL JOIN entrées/contacts : un contact dont la page d'entrée n'a aucune entrée organique comptée reste visible
  -- (organic_entries = 0, taux NULL) au lieu de disparaître — Σ contacts = conversion_journeys organiques (contract-test).
  -- Avant : entrées sur session brute et `now()` glissant, GSC sur `current_date` UTC sans borne Google (24 j de données).
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'cross') b
  ),
  pv as (
    select coalesce(ss.visitor_key, sa.visitor_key,
                    'sid:' || coalesce(e.session_id, e.anonymous_id, 'inconnu')) as vk,
           e.path, e.occurred_at as t, e.referrer_hostname, e.utm_source, e.utm_medium, e.url
    from public.events_human e
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = e.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = e.anonymous_id
    where e.name = 'pageview' and e.path is not null
      -- bornes en sous-requêtes scalaires (InitPlan) : un CROSS JOIN sur w faisait perdre l'index idx_events_paris_date
      and public.paris_date(e.occurred_at) between (select d_start from w) and (select d_end from w)
  ),
  entries as (
    select s.vk, s.path, s.referrer_hostname, s.utm_source, s.utm_medium, s.url
    from (
      select pv.*, lag(pv.t) over (partition by pv.vk order by pv.t) as prev_t
      from pv
    ) s
    where s.prev_t is null or s.t - s.prev_t > interval '30 minutes'
  ),
  organic as (
    select en.path as entry_path, count(*) as organic_entries
    from entries en
    where public.classify_channel(en.referrer_hostname, en.utm_source, en.utm_medium,
                                  'www.jplouton-avocat.fr', en.url) like 'organic%'
    group by en.path
  ),
  conv as (
    select j.entry_path,
      count(*) as contacts,
      count(*) filter (where j.contact_kind = 'phone') as contacts_phone,
      count(*) filter (where j.contact_kind = 'form')  as contacts_form
    from public.conversion_journeys(days_back, (select d_end from w)) j
    where j.entry_channel like 'organic%' and j.entry_path is not null
    group by j.entry_path
  ),
  gsc as (
    select g.path, sum(g.impressions) as impressions, sum(g.clicks) as clicks
    from public.gsc_path_daily g
    where g.day between (select d_start from w) and (select d_end from w)
    group by g.path
  ),
  topq as (
    select path, array_agg(query order by clicks desc) as top_queries
    from (
      select q.path, q.query, sum(q.clicks) as clicks,
        row_number() over (partition by q.path order by sum(q.clicks) desc) as rn
      from public.gsc_query_page_daily q
      where q.day between (select d_start from w) and (select d_end from w)
      group by q.path, q.query
    ) r where rn <= 3
    group by path
  ),
  pages as (
    select coalesce(o.entry_path, c.entry_path) as entry_path,
           coalesce(o.organic_entries, 0) as organic_entries,
           coalesce(c.contacts, 0) as contacts,
           coalesce(c.contacts_phone, 0) as contacts_phone,
           coalesce(c.contacts_form, 0) as contacts_form
    from organic o
    full join conv c on c.entry_path = o.entry_path
  )
  select
    p.entry_path, public.cooked_page_type(p.entry_path), t.theme,
    coalesce(g.impressions, 0), coalesce(g.clicks, 0), tq.top_queries,
    p.organic_entries, p.contacts, p.contacts_phone, p.contacts_form,
    round(100.0 * p.contacts / nullif(p.organic_entries, 0), 2),
    w.d_start, w.d_end
  from pages p
  cross join w
  left join gsc g   on g.path = p.entry_path
  left join topq tq on tq.path = p.entry_path
  left join public.page_taxonomy t on t.path = p.entry_path
  order by p.contacts desc, coalesce(g.clicks, 0) desc;
$function$


-- ═══ public.site_context_export() ═══
CREATE OR REPLACE FUNCTION public.site_context_export()
 RETURNS TABLE(global_sessions_28d bigint, global_bounce_rate_28d numeric, sessions_per_day_median_28d numeric, sessions_trend_pct_7d_vs_28d numeric, top_sources_28d jsonb, global_bounce_rate_pct numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH first_pv AS (
    SELECT DISTINCT ON (e.session_id)
      e.session_id,
      e.referrer_hostname
    FROM public.events_human e
    WHERE e.name = 'pageview'
      AND e.occurred_at >= now() - interval '28 days'
    ORDER BY e.session_id, e.occurred_at
  ),
  spam_sess AS (
    SELECT session_id FROM first_pv
    WHERE public.cooked_is_spam_referrer(referrer_hostname)
  ),
  ss AS (
    SELECT e.session_id,
      min(e.occurred_at) AS session_start,
      max(e.occurred_at) AS session_end,
      count(*) FILTER (WHERE e.name = 'pageview') AS pages_viewed,
      max(e.referrer_hostname) AS referrer_hostname,
      max(e.utm_source) AS utm_source,
      max(e.utm_medium) AS utm_medium
    FROM public.events_human e
    WHERE e.occurred_at >= now() - interval '28 days'
      AND e.session_id NOT IN (SELECT session_id FROM spam_sess)
    GROUP BY e.session_id
  ),
  agg AS (
    SELECT count(*)::bigint AS s28_total,
      count(*) FILTER (WHERE session_start >= now() - interval '7 days')::bigint AS s7_total,
      count(*) FILTER (
        WHERE pages_viewed = 1
          AND extract(epoch FROM (session_end - session_start)) < 10
      )::numeric AS bounce_count
    FROM ss
  ),
  daily AS (
    SELECT date_trunc('day', session_start)::date AS day, count(*) AS n FROM ss GROUP BY 1
  ),
  median AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY n)::numeric AS v FROM daily
  ),
  sources AS (
    SELECT coalesce(utm_source, referrer_hostname, 'direct') AS source,
      coalesce(utm_medium, CASE WHEN referrer_hostname IS NULL THEN 'none' ELSE 'referral' END) AS medium,
      count(*)::bigint AS sessions
    FROM ss GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 5
  ),
  top_sources AS (
    SELECT coalesce(
      jsonb_agg(
        jsonb_build_object('source', source, 'medium', medium, 'sessions', sessions)
        ORDER BY sessions DESC
      ),
      '[]'::jsonb
    ) AS top
    FROM sources
  )
  SELECT a.s28_total,
    coalesce(round(a.bounce_count / nullif(a.s28_total, 0), 4), 0) AS global_bounce_rate_28d,
    coalesce(round(m.v, 1), 0),
    coalesce(round(
      CASE WHEN a.s28_total > 0
        THEN 100.0 * ((a.s7_total::numeric / 7.0) - (a.s28_total::numeric / 28.0))
             / nullif((a.s28_total::numeric / 28.0), 0)
        ELSE 0 END, 2), 0),
    t.top,
    coalesce(round(100.0 * a.bounce_count / nullif(a.s28_total, 0), 2), 0) AS global_bounce_rate_pct
  FROM agg a, median m, top_sources t;
$function$


-- ═══ public.site_gsc_kpis_compare(p_period_kind text) ═══
CREATE OR REPLACE FUNCTION public.site_gsc_kpis_compare(p_period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(period_kind text, period_label_fr text, period_n_start date, period_n_end date, paris_today date, gsc_last_day date, lag_days integer, period_prev_start date, period_prev_end date, clicks_n bigint, impressions_n bigint, ctr_pct_n numeric, position_avg_n numeric, clicks_prev bigint, impressions_prev bigint, ctr_pct_prev numeric, position_avg_prev numeric, clicks_delta_pct numeric, impressions_delta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  b RECORD;
  v_clicks_n  bigint;
  v_imp_n     bigint;
  v_clicks_p  bigint;
  v_imp_p     bigint;
  v_ctr_n     numeric;
  v_ctr_p     numeric;
  v_pos_n     numeric;
  v_pos_p     numeric;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind, 'gsc') LIMIT 1;

  SELECT
    coalesce(sum(g.clicks), 0)::bigint,
    coalesce(sum(g.impressions), 0)::bigint,
    CASE WHEN sum(g.impressions) > 0
         THEN round((100.0 * sum(g.clicks) / sum(g.impressions))::numeric, 2) ELSE NULL END,
    CASE WHEN sum(g.impressions) > 0
         THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2) ELSE NULL END
  INTO v_clicks_n, v_imp_n, v_ctr_n, v_pos_n
  FROM public.gsc_path_daily g
  WHERE g.day >= b.n_start AND g.day <= b.n_end;

  SELECT
    coalesce(sum(g.clicks), 0)::bigint,
    coalesce(sum(g.impressions), 0)::bigint,
    CASE WHEN sum(g.impressions) > 0
         THEN round((100.0 * sum(g.clicks) / sum(g.impressions))::numeric, 2) ELSE NULL END,
    CASE WHEN sum(g.impressions) > 0
         THEN round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2) ELSE NULL END
  INTO v_clicks_p, v_imp_p, v_ctr_p, v_pos_p
  FROM public.gsc_path_daily g
  WHERE g.day >= b.prev_start AND g.day <= b.prev_end;

  RETURN QUERY SELECT
    b.period_kind_out,
    b.label_fr,
    b.n_start,
    b.n_end,
    b.paris_today,
    b.gsc_last_day,
    b.lag_days,
    b.prev_start,
    b.prev_end,
    v_clicks_n,
    v_imp_n,
    v_ctr_n,
    v_pos_n,
    v_clicks_p,
    v_imp_p,
    v_ctr_p,
    v_pos_p,
    CASE WHEN v_clicks_p > 0
         THEN round((100.0 * (v_clicks_n - v_clicks_p) / v_clicks_p)::numeric, 2) ELSE NULL END,
    CASE WHEN v_imp_p > 0
         THEN round((100.0 * (v_imp_n - v_imp_p) / v_imp_p)::numeric, 2) ELSE NULL END;
END;
$function$


-- ═══ public.site_kpis_compare(p_period_kind text) ═══
CREATE OR REPLACE FUNCTION public.site_kpis_compare(p_period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(period_kind text, period_label_fr text, period_n_start date, period_n_end date, tracker_first_seen date, is_partial_period boolean, sessions_n bigint, pageviews_n bigint, phone_clicks_n bigint, form_submits_n bigint, macro_conversions_n bigint, period_prev_start date, period_prev_end date, sessions_prev bigint, pageviews_prev bigint, phone_clicks_prev bigint, form_submits_prev bigint, macro_conversions_prev bigint, sessions_delta_pct numeric, pageviews_delta_pct numeric, phone_clicks_delta_pct numeric, form_submits_delta_pct numeric, macro_conversions_delta_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  b RECORD;
  v_first_seen date;
  v_sessions_n      bigint;
  v_pageviews_n     bigint;
  v_phone_n         bigint;
  v_form_n          bigint;
  v_macro_n         bigint;
  v_sessions_prev   bigint;
  v_pageviews_prev  bigint;
  v_phone_prev      bigint;
  v_form_prev       bigint;
  v_macro_prev      bigint;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind, 'live') LIMIT 1;
  v_first_seen := public.paris_date(public.tracker_first_seen_global());

  SELECT
    count(DISTINCT session_id) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    )
  INTO v_sessions_n, v_pageviews_n
  FROM public.events_human
  WHERE public.paris_date(occurred_at) >= b.n_start
    AND public.paris_date(occurred_at) <= b.n_end
    AND NOT public.cooked_is_spam_referrer(referrer_hostname);

  SELECT m.phone_clicks, m.form_submits, m.macro_conversions
  INTO v_phone_n, v_form_n, v_macro_n
  FROM public.site_macro_counts(b.n_start, b.n_end) m;

  SELECT
    count(DISTINCT session_id) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    )
  INTO v_sessions_prev, v_pageviews_prev
  FROM public.events_human
  WHERE public.paris_date(occurred_at) >= b.prev_start
    AND public.paris_date(occurred_at) <= b.prev_end
    AND NOT public.cooked_is_spam_referrer(referrer_hostname);

  SELECT m.phone_clicks, m.form_submits, m.macro_conversions
  INTO v_phone_prev, v_form_prev, v_macro_prev
  FROM public.site_macro_counts(b.prev_start, b.prev_end) m;

  RETURN QUERY SELECT
    b.period_kind_out, b.label_fr, b.n_start, b.n_end,
    v_first_seen, (v_first_seen IS NOT NULL AND b.n_start < v_first_seen),
    coalesce(v_sessions_n, 0)::bigint, coalesce(v_pageviews_n, 0)::bigint,
    coalesce(v_phone_n, 0)::bigint, coalesce(v_form_n, 0)::bigint, coalesce(v_macro_n, 0)::bigint,
    b.prev_start, b.prev_end,
    coalesce(v_sessions_prev, 0)::bigint, coalesce(v_pageviews_prev, 0)::bigint,
    coalesce(v_phone_prev, 0)::bigint, coalesce(v_form_prev, 0)::bigint, coalesce(v_macro_prev, 0)::bigint,
    CASE WHEN v_sessions_prev > 0 THEN round((100.0 * (v_sessions_n - v_sessions_prev) / v_sessions_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_pageviews_prev > 0 THEN round((100.0 * (v_pageviews_n - v_pageviews_prev) / v_pageviews_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_phone_prev > 0 THEN round((100.0 * (v_phone_n - v_phone_prev) / v_phone_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_form_prev > 0 THEN round((100.0 * (v_form_n - v_form_prev) / v_form_prev)::numeric, 2) ELSE NULL END,
    CASE WHEN v_macro_prev > 0 THEN round((100.0 * (v_macro_n - v_macro_prev) / v_macro_prev)::numeric, 2) ELSE NULL END;
END;
$function$


-- ═══ public.site_macro_counts(start_date date, end_date date) ═══
CREATE OR REPLACE FUNCTION public.site_macro_counts(start_date date, end_date date)
 RETURNS TABLE(phone_clicks bigint, form_submits bigint, macro_conversions bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint,
    count(*) FILTER (
      WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
    )::bigint,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (
          WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
        )
    )::bigint
  FROM public.events_human e
  WHERE public.paris_date(e.occurred_at) >= start_date
    AND public.paris_date(e.occurred_at) <= end_date;
$function$


-- ═══ public.site_pulse(p_period_kind text, delta_threshold_pct numeric) ═══
CREATE OR REPLACE FUNCTION public.site_pulse(p_period_kind text DEFAULT 'rolling_28'::text, delta_threshold_pct numeric DEFAULT 5.0)
 RETURNS TABLE(period_kind text, period_label_fr text, gsc_period_start date, gsc_period_end date, cooked_period_start date, cooked_period_end date, gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_delta_pct numeric, cooked_sessions_n bigint, cooked_sessions_prev bigint, cooked_sessions_delta_pct numeric, quadrant text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  b RECORD;
  v_first_seen date;
  v_has_prev   boolean;
  v_gsc_n      bigint;
  v_gsc_prev   bigint;
  v_ck_n       bigint;
  v_ck_prev    bigint;
  v_gsc_delta  numeric;
  v_ck_delta   numeric;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1;
  v_first_seen := public.paris_date(public.tracker_first_seen_global());
  v_has_prev := v_first_seen IS NOT NULL AND v_first_seen <= b.prev_start;

  SELECT coalesce(sum(clicks), 0)::bigint INTO v_gsc_n
  FROM public.gsc_path_daily
  WHERE day >= b.n_start AND day <= b.n_end;

  SELECT coalesce(sum(clicks), 0)::bigint INTO v_gsc_prev
  FROM public.gsc_path_daily
  WHERE day >= b.prev_start AND day <= b.prev_end;

  SELECT count(DISTINCT session_id) FILTER (
           WHERE name = 'pageview'
             AND device_type IS DISTINCT FROM 'server'
             AND NOT public.cooked_is_spam_referrer(referrer_hostname)
         )::bigint INTO v_ck_n
  FROM public.events_human
  WHERE public.paris_date(occurred_at) >= b.n_start
    AND public.paris_date(occurred_at) <= b.n_end;

  IF v_has_prev THEN
    SELECT count(DISTINCT session_id) FILTER (
             WHERE name = 'pageview'
               AND device_type IS DISTINCT FROM 'server'
               AND NOT public.cooked_is_spam_referrer(referrer_hostname)
           )::bigint INTO v_ck_prev
    FROM public.events_human
    WHERE public.paris_date(occurred_at) >= b.prev_start
      AND public.paris_date(occurred_at) <= b.prev_end;
  ELSE
    v_ck_prev := NULL;
  END IF;

  v_gsc_delta := CASE WHEN v_gsc_prev > 0
    THEN round((100.0 * (v_gsc_n - v_gsc_prev) / v_gsc_prev)::numeric, 2) ELSE NULL END;
  v_ck_delta := CASE WHEN v_ck_prev IS NOT NULL AND v_ck_prev > 0
    THEN round((100.0 * (v_ck_n - v_ck_prev) / v_ck_prev)::numeric, 2) ELSE NULL END;

  RETURN QUERY SELECT
    b.period_kind_out, b.label_fr, b.n_start, b.n_end, b.n_start, b.n_end,
    v_gsc_n, v_gsc_prev, v_gsc_delta, v_ck_n, v_ck_prev, v_ck_delta,
    public.pulse_status(v_gsc_n, v_gsc_prev, v_ck_n, v_ck_prev, delta_threshold_pct);
END;
$function$


-- ═══ public.site_seo_funnel(period_kind text) ═══
CREATE OR REPLACE FUNCTION public.site_seo_funnel(period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(period_start date, period_end date, impressions bigint, clicks bigint, google_sessions bigint, macro_contacts bigint, impr_to_click_pct numeric, click_to_session_pct numeric, session_to_contact_pct numeric, overall_impr_to_contact_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  b RECORD;
  v_impressions bigint;
  v_clicks bigint;
  v_google_sessions bigint;
  v_macro bigint;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind, 'cross') LIMIT 1;

  SELECT
    coalesce(sum(g.impressions), 0)::bigint,
    coalesce(sum(g.clicks), 0)::bigint
  INTO v_impressions, v_clicks
  FROM public.gsc_path_daily g
  WHERE g.day >= b.n_start AND g.day <= b.n_end;

  SELECT count(DISTINCT e.session_id) FILTER (
           WHERE e.name = 'pageview'
             AND e.device_type IS DISTINCT FROM 'server'
             AND (
               e.referrer_hostname LIKE '%google.%'
               OR (e.utm_source = 'google' AND e.utm_medium IN ('organic', 'cpc'))
             )
         )::bigint INTO v_google_sessions
  FROM public.events_human e
  WHERE public.paris_date(e.occurred_at) >= b.n_start
    AND public.paris_date(e.occurred_at) <= b.n_end;

  SELECT m.macro_conversions INTO v_macro
  FROM public.site_macro_counts(b.n_start, b.n_end) m;

  RETURN QUERY SELECT
    b.n_start,
    b.n_end,
    v_impressions,
    v_clicks,
    v_google_sessions,
    coalesce(v_macro, 0),
    CASE WHEN v_impressions > 0
         THEN round((100.0 * v_clicks / v_impressions)::numeric, 2) ELSE NULL END,
    CASE WHEN v_clicks > 0
         THEN round((100.0 * v_google_sessions / v_clicks)::numeric, 2) ELSE NULL END,
    CASE WHEN v_google_sessions > 0
         THEN round((100.0 * v_macro / v_google_sessions)::numeric, 2) ELSE NULL END,
    CASE WHEN v_impressions > 0
         THEN round((100.0 * v_macro / v_impressions)::numeric, 4) ELSE NULL END;
END;
$function$


-- ═══ public.snapshot_pages_export(paths text[]) ═══
CREATE OR REPLACE FUNCTION public.snapshot_pages_export(paths text[] DEFAULT NULL::text[])
 RETURNS TABLE(path text, views_7d bigint, unique_visitors_7d bigint, sessions_7d bigint, bounce_rate_7d numeric, avg_dwell_seconds_7d numeric, scroll_avg_7d numeric, scroll_median_7d numeric, scroll_complete_pct_7d numeric, entry_count_7d bigint, exit_count_7d bigint, outbound_clicks_7d bigint, views_28d bigint, unique_visitors_28d bigint, sessions_28d bigint, bounce_rate_28d numeric, avg_dwell_seconds_28d numeric, scroll_avg_28d numeric, scroll_median_28d numeric, scroll_complete_pct_28d numeric, entry_count_28d bigint, exit_count_28d bigint, outbound_clicks_28d bigint, views_90d bigint, unique_visitors_90d bigint, sessions_90d bigint, bounce_rate_90d numeric, avg_dwell_seconds_90d numeric, scroll_avg_90d numeric, scroll_median_90d numeric, scroll_complete_pct_90d numeric, entry_count_90d bigint, exit_count_90d bigint, outbound_clicks_90d bigint, views_365d bigint, unique_visitors_365d bigint, sessions_365d bigint, bounce_rate_365d numeric, avg_dwell_seconds_365d numeric, scroll_avg_365d numeric, scroll_median_365d numeric, scroll_complete_pct_365d numeric, entry_count_365d bigint, exit_count_365d bigint, outbound_clicks_365d bigint, lcp_p75_28d_ms numeric, inp_p75_28d_ms numeric, cls_p75_28d numeric, ttfb_p75_28d_ms numeric, top_referrer_28d text, top_source_28d text, top_medium_28d text, device_split_28d jsonb, refreshed_at timestamp with time zone, phone_clicks_7d bigint, phone_clicks_28d bigint, phone_clicks_90d bigint, phone_clicks_365d bigint, email_clicks_7d bigint, email_clicks_28d bigint, email_clicks_90d bigint, email_clicks_365d bigint, booking_cta_clicks_7d bigint, booking_cta_clicks_28d bigint, booking_cta_clicks_90d bigint, booking_cta_clicks_365d bigint, google_sessions_28d bigint, pogo_sticks_28d bigint, hard_pogo_28d bigint, pogo_rate_28d numeric, mobile_sessions_28d bigint, desktop_sessions_28d bigint, cta_rate_mobile_28d numeric, cta_rate_desktop_28d numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select
    s.path, s.views_7d, s.unique_visitors_7d, s.sessions_7d,
    s.bounce_rate_7d, s.avg_dwell_seconds_7d, s.scroll_avg_7d,
    s.scroll_median_7d, s.scroll_complete_pct_7d, s.entry_count_7d,
    s.exit_count_7d, s.outbound_clicks_7d,
    s.views_28d, s.unique_visitors_28d, s.sessions_28d,
    s.bounce_rate_28d, s.avg_dwell_seconds_28d, s.scroll_avg_28d,
    s.scroll_median_28d, s.scroll_complete_pct_28d, s.entry_count_28d,
    s.exit_count_28d, s.outbound_clicks_28d,
    s.views_90d, s.unique_visitors_90d, s.sessions_90d,
    s.bounce_rate_90d, s.avg_dwell_seconds_90d, s.scroll_avg_90d,
    s.scroll_median_90d, s.scroll_complete_pct_90d, s.entry_count_90d,
    s.exit_count_90d, s.outbound_clicks_90d,
    s.views_365d, s.unique_visitors_365d, s.sessions_365d,
    s.bounce_rate_365d, s.avg_dwell_seconds_365d, s.scroll_avg_365d,
    s.scroll_median_365d, s.scroll_complete_pct_365d, s.entry_count_365d,
    s.exit_count_365d, s.outbound_clicks_365d,
    s.lcp_p75_28d_ms, s.inp_p75_28d_ms, s.cls_p75_28d, s.ttfb_p75_28d_ms,
    s.top_referrer_28d, s.top_source_28d, s.top_medium_28d,
    s.device_split_28d, s.refreshed_at,
    s.phone_clicks_7d, s.phone_clicks_28d, s.phone_clicks_90d, s.phone_clicks_365d,
    0::bigint, 0::bigint, 0::bigint, 0::bigint,  -- email_clicks_{7,28,90,365}d : droppées Sprint 30, toujours 0
    s.booking_cta_clicks_7d, s.booking_cta_clicks_28d, s.booking_cta_clicks_90d, s.booking_cta_clicks_365d,
    s.google_sessions_28d, s.pogo_sticks_28d, s.hard_pogo_28d, s.pogo_rate_28d,
    s.mobile_sessions_28d, s.desktop_sessions_28d,
    s.cta_rate_mobile_28d, s.cta_rate_desktop_28d
  from public.seo_url_snapshot s
  where snapshot_pages_export.paths is null
     or s.path = any (snapshot_pages_export.paths);
$function$


-- ═══ public.top_contact_pages(p_period_kind text, max_rows integer) ═══
CREATE OR REPLACE FUNCTION public.top_contact_pages(p_period_kind text DEFAULT 'rolling_28'::text, max_rows integer DEFAULT 10)
 RETURNS TABLE(path text, cooked_contacts bigint, cooked_phone_clicks bigint, cooked_form_submits bigint, gsc_clicks bigint, cooked_sessions bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds(p_period_kind, 'cross') LIMIT 1
  ),
  mc AS (
    SELECT m.path, m.contacts, m.phone_clicks, m.form_submits
    FROM public.macro_contacts_by_path(
      (SELECT n_start FROM b),
      (SELECT n_end FROM b)
    ) m
    WHERE m.contacts > 0
    ORDER BY m.contacts DESC, m.path
    LIMIT max_rows
  ),
  gsc AS (
    SELECT g.path, sum(g.clicks)::bigint AS clicks_total
    FROM public.gsc_path_daily g
    INNER JOIN mc ON mc.path = g.path
    CROSS JOIN b
    WHERE g.day >= b.n_start AND g.day <= b.n_end
    GROUP BY g.path
  )
  SELECT
    mc.path,
    mc.contacts,
    mc.phone_clicks,
    mc.form_submits,
    coalesce(gsc.clicks_total, 0),
    coalesce(
      CASE
        WHEN lower(trim(coalesce(p_period_kind, 'rolling_28'))) = 'rolling_90'
          THEN s.sessions_90d
        ELSE s.sessions_28d
      END,
      0
    )::bigint
  FROM mc
  LEFT JOIN gsc ON gsc.path = mc.path
  LEFT JOIN public.seo_url_snapshot s ON s.path = mc.path;
$function$


-- ═══ public.tracker_first_seen_global() ═══
CREATE OR REPLACE FUNCTION public.tracker_first_seen_global()
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select min(occurred_at)
  from public.events_human
  where occurred_at between received_at - interval '2 days'
                       and received_at + interval '2 days';
$function$


-- ═══ public.tracker_version_distribution(hours_back integer) ═══
CREATE OR REPLACE FUNCTION public.tracker_version_distribution(hours_back integer DEFAULT 24)
 RETURNS TABLE(version text, events bigint, sessions bigint, first_seen timestamp with time zone, last_seen timestamp with time zone, share_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with versioned as (
    select
      coalesce(nullif(e.props->>'_v', ''), 'legacy_pre_sprint26') as version,
      e.session_id,
      e.occurred_at
    from public.events_human e
    where e.occurred_at >= now() - (tracker_version_distribution.hours_back * interval '1 hour')
      and e.device_type is distinct from 'server' -- skip form-webhook rows
  ),
  totals as (
    select count(*)::numeric as total from versioned
  )
  select
    v.version,
    count(*)::bigint                            as events,
    count(distinct v.session_id)::bigint        as sessions,
    min(v.occurred_at)                          as first_seen,
    max(v.occurred_at)                          as last_seen,
    round(100.0 * count(*)::numeric / nullif((select total from totals), 0), 2) as share_pct
  from versioned v
  group by v.version
  order by events desc;
$function$


-- ═══ public.unaccent(regdictionary, text) ═══
CREATE OR REPLACE FUNCTION public.unaccent(regdictionary, text)
 RETURNS text
 LANGUAGE c
 STABLE PARALLEL SAFE STRICT
AS '$libdir/unaccent', $function$unaccent_dict$function$


-- ═══ public.unaccent(text) ═══
CREATE OR REPLACE FUNCTION public.unaccent(text)
 RETURNS text
 LANGUAGE c
 STABLE PARALLEL SAFE STRICT
AS '$libdir/unaccent', $function$unaccent_dict$function$


-- ═══ public.unaccent_init(internal) ═══
CREATE OR REPLACE FUNCTION public.unaccent_init(internal)
 RETURNS internal
 LANGUAGE c
 PARALLEL SAFE
AS '$libdir/unaccent', $function$unaccent_init$function$


-- ═══ public.unaccent_lexize(internal, internal, internal, internal) ═══
CREATE OR REPLACE FUNCTION public.unaccent_lexize(internal, internal, internal, internal)
 RETURNS internal
 LANGUAGE c
 PARALLEL SAFE
AS '$libdir/unaccent', $function$unaccent_lexize$function$


-- ═══ public.url_decode(input text) ═══
CREATE OR REPLACE FUNCTION public.url_decode(input text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  result        text  := '';
  i             int   := 1;
  len           int   := length(input);
  pending       bytea := ''::bytea;
  hex_pair      text;
begin
  if input is null then
    return null;
  end if;
  while i <= len loop
    if substring(input from i for 1) = '%'
       and i + 2 <= len
       and substring(input from i+1 for 2) ~ '^[0-9A-Fa-f]{2}$'
    then
      hex_pair := substring(input from i+1 for 2);
      pending  := pending || decode(hex_pair, 'hex');
      i := i + 3;
    else
      if length(pending) > 0 then
        result  := result || convert_from(pending, 'UTF8');
        pending := ''::bytea;
      end if;
      result := result || substring(input from i for 1);
      i := i + 1;
    end if;
  end loop;
  if length(pending) > 0 then
    result := result || convert_from(pending, 'UTF8');
  end if;
  return result;
exception
  when others then
    return input;
end;
$function$


-- ═══ public.weekly_conversions_report(p_week_start date) ═══
CREATE OR REPLACE FUNCTION public.weekly_conversions_report(p_week_start date DEFAULT NULL::date)
 RETURNS TABLE(semaine date, page_entree text, page_conversion text, appels bigint, formulaires bigint, conversions bigint, canaux text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH w AS (
    SELECT date_trunc('week',
             COALESCE(p_week_start::timestamp,
                      date_trunc('week', (now() AT TIME ZONE 'Europe/Paris')) - interval '7 days'))::date AS ws
  )
  SELECT c.week_start,
         COALESCE(c.entry_path,   '(entree inconnue)'),
         COALESCE(c.contact_path, '(page inconnue)'),
         count(*) FILTER (WHERE c.contact_kind = 'phone'),
         count(*) FILTER (WHERE c.contact_kind = 'form'),
         count(*),
         string_agg(DISTINCT COALESCE(c.entry_channel, 'inconnu'), ', ')
  FROM public.conversion_weekly c, w
  WHERE c.week_start = w.ws
  GROUP BY 1, 2, 3
  ORDER BY 6 DESC, 2, 3;
$function$

