-- ============================================================================
-- supabase/rpcs.sql — CORPS COMPLETS DES RPC (généré, LECTURE SEULE)
--
-- ⚠️  NE PAS REJOUER COMME SOURCE D'UN DÉPLOIEMENT. NE PAS ÉDITER À LA MAIN.
--
-- Source de vérité DDL = supabase/migrations/*.sql (+ état prod).
-- Ce fichier = instantané lisible pour humains et agents (Arch #5, 10/07/2026).
--
-- Régénérer : python3 scripts/generate_rpcs_sql.py  (DATABASE_URL requis)
-- Généré le 04/11/2026 — projet mxycmjkeotrycyneacje.
-- ============================================================================

-- ═══ public.ack_alerts(p_kinds text[]) ═══
CREATE OR REPLACE FUNCTION public.ack_alerts(p_kinds text[] DEFAULT NULL::text[])
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
$function$


-- ═══ public.alert_rule_contact_sans_amont() ═══
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
END $function$


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
DECLARE
  v_n bigint; v_tot bigint; v_pct numeric; v_forms text;
BEGIN
  -- 1. cooked_aid (attribution hidden_field) — inchangé
  SELECT count(*) FILTER (WHERE props->>'cooked_aid' IS NULL), count(*)
    INTO v_n, v_tot
  FROM public.events
  WHERE name = 'form_submit'
    AND occurred_at > now() - interval '7 days';
  IF v_tot >= 5 THEN
    v_pct := round(100.0 * v_n / v_tot, 0);
    IF v_pct > 30 THEN
      kind := 'form_attribution_degraded'; severity := 'warn';
      detail := format('%s %% des form_submit sans cooked_aid sur 7j (%s/%s) — champs cachés Wix manquants ou tracker pas à jour ?', v_pct, v_n, v_tot);
      RETURN NEXT;
    END IF;
  END IF;

  -- 2. T-18 : page_source (path) et objet par formulaire, 28 j, webhook seulement
  WITH f AS (
    SELECT btrim(coalesce(props->>'form_id', '?')) AS form_id,
           count(*) AS n,
           count(*) FILTER (WHERE path IS NULL) AS sans_path,
           count(*) FILTER (WHERE nullif(props->>'objet_de_ma_demande', '') IS NULL) AS sans_objet
    FROM public.events
    WHERE name = 'form_submit'
      AND coalesce(props->>'capture_source', 'wix-webhook') = 'wix-webhook'
      AND occurred_at > now() - interval '28 days'
    GROUP BY 1
  )
  SELECT string_agg(format('%s : %s/%s sans page_source, %s/%s sans objet', form_id, sans_path, n, sans_objet, n), ' ; ' ORDER BY n DESC)
    INTO v_forms
  FROM f
  WHERE (n >= 3 AND (100.0 * sans_path / n > 10 OR 100.0 * sans_objet / n > 10))
     OR (n >= 1 AND sans_path = n);

  IF v_forms IS NOT NULL THEN
    kind := 'form_fields_missing'; severity := 'warn';
    detail := format('Formulaires Wix sans page_source ou sans objet sur 28 j — une page_source absente limite le contexte ; le rattachement à l’entrée dépend des identifiants explicites et des pages observées ; sans objet, il est compté macro par défaut (candidature ?). Câbler les champs cachés `page_source` (seedé par masterPage) et « Objet de ma demande » sur le formulaire puis vérifier la prochaine soumission réelle. %s', v_forms);
    RETURN NEXT;
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
DECLARE b public.gsc_ingest_batches%ROWTYPE; last_complete timestamptz;
BEGIN
  SELECT * INTO b FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF b.status IN ('running','failed') AND b.started_at < now()-interval '3 hours' THEN
    kind:='gsc_ingest_incomplete'; severity:='critical';
    detail:='Le dernier lot GSC est incomplet depuis plus de trois heures. Reprendre les deux sources, pages et requêtes par page, avant lecture.';
    RETURN NEXT;
  END IF;
  SELECT max(completed_at) INTO last_complete FROM public.gsc_ingest_batches WHERE status='completed';
  IF (now() AT TIME ZONE 'UTC')::time >= time '12:00'
     AND (last_complete AT TIME ZONE 'UTC')::date IS DISTINCT FROM (now() AT TIME ZONE 'UTC')::date THEN
    kind:='gsc_ingest_missed'; severity:='warn';
    detail:='Aucun lot GSC complet du jour UTC après midi. Vérifier le workflow gsc-daily-ingest et sa reprise.';
    RETURN NEXT;
  END IF;
END;
$function$


-- ═══ public.alert_rule_identity_stitch() ═══
CREATE OR REPLACE FUNCTION public.alert_rule_identity_stitch()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_rows  bigint;
  v_at    timestamptz;
  v_age_h numeric;
  v_j1    date;
  v_tot   bigint;
  v_miss  bigint;
BEGIN
  SELECT count(*) INTO v_rows FROM public.identity_stitch;
  IF v_rows = 0 THEN
    kind := 'identity_stitch_empty'; severity := 'critical';
    detail := 'identity_stitch est VIDE : Le comptage des visites perd ses correspondances entre identifiants navigateur. Relancer : SELECT public.refresh_identity_stitch(90); puis lire cron.job_run_details du job refresh-identity-stitch.';
    RETURN NEXT; RETURN;
  END IF;

  SELECT nullif(btrim(value), '')::timestamptz INTO v_at
  FROM public.cooked_config WHERE key = 'identity_stitch_refreshed_at';

  IF v_at IS NULL THEN
    kind := 'identity_stitch_stale'; severity := 'critical';
    detail := format('Couture d''identité sans horodatage (clé cooked_config.identity_stitch_refreshed_at absente) : %s lignes d''âge inconnu. Relancer : SELECT public.refresh_identity_stitch(90);', v_rows);
    RETURN NEXT; RETURN;
  END IF;

  v_age_h := extract(epoch FROM (now() - v_at)) / 3600.0;
  IF v_age_h > 30 THEN
    kind := 'identity_stitch_stale';
    severity := CASE WHEN v_age_h > 54 THEN 'critical' ELSE 'warn' END;
    detail := format('Couture d''identité reconstruite il y a %s h (dernière : %s Paris, %s lignes) — attendue chaque nuit à 03:40 UTC (cron refresh-identity-stitch). Le comptage des visites utilise une couture périmée. Relancer : SELECT public.refresh_identity_stitch(90);',
                     round(v_age_h), to_char(v_at AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI'), v_rows);
    RETURN NEXT; RETURN;
  END IF;

  -- Couverture : une fois la reconstruction du jour faite, chaque session humaine de J-1
  -- (hors webhook, hors aid 32-hex — jamais cousu, garde-fou du 12/07/2026) doit être cousue.
  IF public.paris_date(v_at) = public.paris_today() THEN
    v_j1 := public.paris_today() - 1;
    WITH s AS (
      SELECT DISTINCT session_id
      FROM public.events_human
      WHERE public.paris_date(occurred_at) = v_j1
        AND anonymous_id NOT LIKE 'webhook-%'
        AND anonymous_id !~ '^[0-9a-f]{32}$'
    )
    SELECT count(*),
           count(*) FILTER (WHERE NOT EXISTS (
             SELECT 1 FROM public.identity_stitch i WHERE i.kind = 'sid' AND i.key = s.session_id))
    INTO v_tot, v_miss
    FROM s;

    IF v_miss > 0 THEN
      kind := 'identity_stitch_coverage'; severity := 'warn';
      detail := format('%s session(s) humaine(s) de J-1 (%s) sur %s hors couture après la reconstruction de %s Paris : refresh_identity_stitch lit events brut sur %s — vérifier que la reconstruction a bien couvert la journée (durée, timeout 420 s) ; relancer : SELECT public.refresh_identity_stitch(90);',
                       v_miss, to_char(v_j1, 'DD/MM/YYYY'), v_tot,
                       to_char(v_at AT TIME ZONE 'Europe/Paris', 'HH24:MI'),
                       'tout l’historique conservé');
      RETURN NEXT;
    END IF;
  END IF;
END $function$


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
    SELECT e.path, count(*) FILTER (WHERE e.name = 'pageview') AS pv, min(e.occurred_at) AS first_seen
    FROM public.events_human e
    WHERE e.path LIKE '/post/%'
      AND e.occurred_at > now() - interval '30 days'
      -- exclusions structurelles : ignorer les chemins techniques et invalides
      AND e.path NOT LIKE '%/preview/%'   -- previews Wix avec token
      AND e.path !~ 'https?://'           -- URLs concaténées par erreur
      AND e.path !~ '[ÃÂ]'                -- mojibake (double encodage)
      AND e.path !~ '%'                   -- restes d'URL-encoding
      AND length(e.path) <= 140
      -- T-15 (e-07) : un article = /post/<un seul segment de slug>, sans parenthèse ;
      -- exclut les URL de point focal d'image Wix (/post/fp_0.50_0.50/<hex>~mv2.png)
      AND e.path ~ '^/post/[^/()]+$'
      AND e.path !~ '/fp_[0-9.]+_[0-9.]+/'
    GROUP BY e.path
    HAVING count(*) FILTER (WHERE e.name = 'pageview') >= 5
  )
  SELECT count(*), string_agg(v.path, ', ' ORDER BY v.pv DESC)
    INTO v_n, v_ex
  FROM vus v
  LEFT JOIN public.page_taxonomy t ON t.path = v.path
  WHERE (t.path IS NULL OR t.category IS NULL)
    -- la synchronisation de publication a eu plusieurs occasions de passer
    AND v.first_seen < now() - interval '8 days';

  IF v_n >= 1 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j, vus depuis > 8 j) sans catégorie Wix dans page_taxonomy — les visites restent comptées mais leur classement éditorial est incomplet. Vérifier les chemins (page réelle, redirection ou URL tronquée), leur catégorie Wix et le dernier workflow wix-taxonomy-sync (inventaire quotidien). Une synchro réussie peut conserver une URL sans catégorie ; ne pas déduire un secret manquant de cette seule alerte. Concernés : %s',
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
$function$


-- ═══ public.alert_rule_rpc_health() ═══
CREATE OR REPLACE FUNCTION public.alert_rule_rpc_health()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT 'rpc_failed_'||h.rpc_name,'critical'::text,
    'Contrôle '||h.rpc_name||' : '||h.status
  FROM public.latest_rpc_health() h WHERE h.status IS DISTINCT FROM 'ok';
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


-- ═══ public.alert_rule_volume_floor() ═══
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

  -- Construire l'heure murale avant conversion en instant absolu.
  -- Minuit Paris + N heures écoulées se décale les jours de 23/25 heures.
  t0 := (v_prev_day::timestamp + make_interval(hours => v_prev_hour))
        AT TIME ZONE 'Europe/Paris';
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
AS $function$ SELECT hostname IS DISTINCT FROM 'outremer.jplouton-avocat.fr'
  AND (props->>'cooked_site') IS DISTINCT FROM 'outremer' $function$


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


-- ═══ public.cooked_paris_hour(p_ts timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.cooked_paris_hour(p_ts timestamp with time zone)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT extract(hour FROM p_ts AT TIME ZONE 'Europe/Paris')::integer;
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


-- ═══ public.cooked_visit_events(p_start date, p_end date) ═══
CREATE OR REPLACE FUNCTION public.cooked_visit_events(p_start date, p_end date)
 RETURNS TABLE(event_id uuid, event_name text, occurred_at timestamp with time zone, path text, anonymous_id text, objet text, counts_as_macro boolean, attribution_method text, visit_id uuid, entry_at timestamp with time zone, entry_path text, entry_channel text, journey text[], device_type text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET jit TO 'off'
AS $function$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end>=public.paris_today() THEN
    RAISE EXCEPTION 'Expected completed Paris days with start <= end' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
  WITH raw AS MATERIALIZED (
    SELECT e.id,e.name,e.occurred_at AS t,CASE WHEN e.name IN ('pageview','cta_phone_click','form_submit') AND nullif(e.path,'') IS NOT NULL THEN public.canonical_path(e.path) END AS path,
      e.anonymous_id,CASE WHEN e.name='pageview' THEN e.device_type END AS device_type,CASE WHEN e.name='form_submit' THEN e.props->>'objet_de_ma_demande' END AS objet,
      e.name='cta_phone_click' OR (e.name='form_submit' AND public.form_submit_counts_as_macro(e.props)) AS macro,
      CASE WHEN e.name='pageview' THEN e.referrer_hostname END AS referrer_hostname,
      CASE WHEN e.name='pageview' THEN e.utm_source END AS utm_source,
      CASE WHEN e.name='pageview' THEN e.utm_medium END AS utm_medium,
      CASE WHEN e.name='pageview' THEN e.url END AS url,
      CASE WHEN e.name='form_submit' THEN nullif(e.props->>'cooked_sid','') ELSE nullif(e.session_id,'') END AS sid,
      CASE WHEN e.name='form_submit' THEN nullif(e.props->>'cooked_aid','') ELSE nullif(e.anonymous_id,'') END AS aid
    FROM public.events_human e
    WHERE e.occurred_at<public.cooked_paris_ts_end_exclusive(p_end)
  ), keyed AS (
    SELECT r.*,CASE WHEN r.name='form_submit' AND s.visitor_key IS NOT NULL AND a.visitor_key IS NOT NULL
      AND s.visitor_key<>a.visitor_key THEN 'event:'||r.id ELSE coalesce(s.visitor_key,a.visitor_key,
      CASE WHEN r.sid NOT LIKE 'webhook-%' THEN 'sid:'||r.sid END,
      CASE WHEN r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%' THEN 'aid:'||r.aid END,'event:'||r.id) END AS vk
    FROM raw r
    LEFT JOIN public.identity_stitch s ON s.kind='sid' AND s.key=r.sid AND r.sid NOT LIKE 'webhook-%'
    LEFT JOIN public.identity_stitch a ON a.kind='aid' AND a.key=r.aid
      AND r.aid !~ '^[0-9a-f]{32}$' AND r.aid NOT LIKE 'webhook-%'
    WHERE r.name IN ('pageview','engagement_tick','page_exit','scroll_depth','click_internal',
      'click_outbound','cta_anchor_click','cta_booking_click','cta_phone_click','form_submit')
  ), wanted AS (
    SELECT DISTINCT k.vk FROM keyed k WHERE k.t>=public.cooked_paris_ts_start(p_start)
  ), scoped AS (
    -- On conserve tout l'amont des navigateurs concernés, pas une marge arbitraire.
    SELECT k.* FROM keyed k JOIN wanted w ON w.vk=k.vk
  ), gaps AS (
    SELECT k.*,k.t-lag(k.t) OVER(PARTITION BY k.vk ORDER BY k.t,(k.name='pageview') DESC,k.id) AS gap FROM scoped k
  ), segmented AS (
    SELECT g.*,sum((g.gap IS NULL OR g.gap>interval '30 minutes')::int)
      OVER(PARTITION BY g.vk ORDER BY g.t,(g.name='pageview') DESC,g.id) AS seq FROM gaps g
  ), relevant AS (
    SELECT s.* FROM segmented s WHERE (s.name='pageview' AND s.path IS NOT NULL) OR s.name IN ('cta_phone_click','form_submit')
  ), enriched AS (
    SELECT r.*,
      first_value(r.id) OVER entry AS first_id,
      first_value(r.t) OVER entry AS first_time,
      first_value(r.name) OVER entry AS first_name,
      first_value(r.path) OVER entry AS first_path,
      first_value(r.referrer_hostname) OVER entry AS first_ref,
      first_value(r.utm_source) OVER entry AS first_source,
      first_value(r.utm_medium) OVER entry AS first_medium,
      first_value(r.url) OVER entry AS first_url,
      first_value(r.device_type) OVER entry AS first_device,
      array_agg(r.path) FILTER(WHERE r.name='pageview' AND r.path IS NOT NULL) OVER (
        PARTITION BY r.vk,r.seq ORDER BY r.t,(r.name='pageview') DESC,r.id) AS paths
    FROM relevant r WINDOW entry AS (PARTITION BY r.vk,r.seq
      ORDER BY (r.name='pageview') DESC,r.t,r.id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
  )
  SELECT e.id,e.name,e.t,e.path,
    CASE WHEN e.name='form_submit' THEN e.aid ELSE e.anonymous_id END,
    e.objet,e.macro,
    CASE WHEN e.paths IS NULL THEN 'unresolved'
      WHEN e.name='form_submit' THEN 'hidden_field' ELSE 'direct' END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_id END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_time END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_path END,
    CASE WHEN e.paths IS NOT NULL THEN public.classify_channel(e.first_ref,e.first_source,e.first_medium,
      'www.jplouton-avocat.fr',e.first_url) END,
    CASE WHEN e.name<>'pageview' THEN
      ARRAY(SELECT x.p FROM unnest(e.paths) WITH ORDINALITY x(p,n) GROUP BY x.p ORDER BY min(x.n)) END,
    CASE WHEN e.paths IS NOT NULL THEN e.first_device END
  FROM enriched e
  WHERE e.t>=public.cooked_paris_ts_start(p_start)
  ORDER BY e.t,e.id;
END $function$


-- ═══ public.form_submission_counts_for_period(p_start date, p_end date) ═══
CREATE OR REPLACE FUNCTION public.form_submission_counts_for_period(p_start date, p_end date)
 RETURNS TABLE(day date, submissions bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end-p_start>=93 THEN
    RAISE EXCEPTION 'form count window must contain 1 to 93 inclusive calendar days' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
    SELECT ds.d::date,coalesce(c.n,0)::bigint
    FROM generate_series(p_start::timestamp,p_end::timestamp,interval '1 day') ds(d)
    LEFT JOIN (
      SELECT public.paris_date(e.occurred_at) AS d,count(*) AS n
      FROM public.events_human e WHERE e.name='form_submit'
        AND e.occurred_at>=public.cooked_paris_ts_start(p_start)
        AND e.occurred_at<public.cooked_paris_ts_end_exclusive(p_end)
      GROUP BY public.paris_date(e.occurred_at)
    ) c ON c.d=ds.d::date
    ORDER BY ds.d;
END;
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


-- ═══ public.gsc_ingest_begin(p_run_id uuid, p_start date, p_end date) ═══
CREATE OR REPLACE FUNCTION public.gsc_ingest_begin(p_run_id uuid, p_start date, p_end date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_existing public.gsc_ingest_batches%ROWTYPE;
BEGIN
  IF p_run_id IS NULL OR p_start IS NULL OR p_end IS NULL OR p_start > p_end THEN
    RAISE EXCEPTION 'invalid GSC batch id or date range' USING ERRCODE = '22023';
  END IF;
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RAISE EXCEPTION 'GSC refresh is running; retry the full ingestion later' USING ERRCODE = '55P03';
  END IF;
  SELECT * INTO v_existing FROM public.gsc_ingest_batches WHERE run_id=p_run_id;
  IF FOUND THEN
    IF v_existing.status='running' AND v_existing.day_start=p_start AND v_existing.day_end=p_end
       AND v_existing.batch_no=(SELECT max(batch_no) FROM public.gsc_ingest_batches) THEN
      RETURN p_run_id; -- retry après réponse réseau perdue : idempotent
    END IF;
    RAISE EXCEPTION 'GSC batch id already used; start a new full batch' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.gsc_ingest_batches WHERE status='running') THEN
    RAISE EXCEPTION 'another GSC ingestion is running; stop it before marking its batch failed' USING ERRCODE='55P03';
  END IF;
  INSERT INTO public.gsc_ingest_batches(run_id,day_start,day_end) VALUES(p_run_id,p_start,p_end);
  RETURN p_run_id;
END;
$function$


-- ═══ public.gsc_ingest_complete(p_run_id uuid, p_row_counts jsonb) ═══
CREATE OR REPLACE FUNCTION public.gsc_ingest_complete(p_run_id uuid, p_row_counts jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_latest public.gsc_ingest_batches%ROWTYPE; v_key text; v_total numeric := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RAISE EXCEPTION 'GSC refresh is running; retry batch completion later' USING ERRCODE = '55P03';
  END IF;
  IF p_row_counts IS NULL OR jsonb_typeof(p_row_counts) <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_row_counts)) <> 2 THEN
    RAISE EXCEPTION 'row counts must contain exactly the two GSC tables' USING ERRCODE = '22023';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['gsc_path_daily','gsc_query_page_daily'] LOOP
    IF NOT (p_row_counts ? v_key) OR jsonb_typeof(p_row_counts->v_key) <> 'number'
       OR (p_row_counts->>v_key) !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'invalid row count for %', v_key USING ERRCODE = '22023';
    END IF;
    v_total := v_total + (p_row_counts->>v_key)::numeric;
  END LOOP;
  IF v_total=0 THEN
    RAISE EXCEPTION 'cannot mark an entirely empty GSC batch complete' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_latest FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF NOT FOUND OR v_latest.run_id IS DISTINCT FROM p_run_id OR v_latest.status NOT IN ('running','completed') THEN
    RAISE EXCEPTION 'only the latest running GSC batch may complete' USING ERRCODE = '22023';
  END IF;
  IF v_latest.status='completed' THEN
    IF v_latest.row_counts=p_row_counts THEN RETURN; END IF;
    RAISE EXCEPTION 'completed GSC batch has different row counts' USING ERRCODE = '22023';
  END IF;
  UPDATE public.gsc_ingest_batches SET status='completed', completed_at=clock_timestamp(), row_counts=p_row_counts
    WHERE run_id=p_run_id;
END;
$function$


-- ═══ public.gsc_ingest_fail(p_run_id uuid) ═══
CREATE OR REPLACE FUNCTION public.gsc_ingest_fail(p_run_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_batch public.gsc_ingest_batches%ROWTYPE;
BEGIN
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RAISE EXCEPTION 'GSC refresh is running; retry failure marker later' USING ERRCODE='55P03';
  END IF;
  SELECT * INTO v_batch FROM public.gsc_ingest_batches WHERE run_id=p_run_id;
  IF NOT FOUND OR v_batch.status='completed' THEN
    RAISE EXCEPTION 'only a running or already failed GSC batch may fail' USING ERRCODE='22023';
  END IF;
  UPDATE public.gsc_ingest_batches SET status='failed' WHERE run_id=p_run_id;
END;
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


-- ═══ public.latest_rpc_health() ═══
CREATE OR REPLACE FUNCTION public.latest_rpc_health()
 RETURNS TABLE(rpc_name text, status text, detail text, rows_returned bigint, duration_ms numeric, checked_at timestamp with time zone, age_minutes numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT expected.name,
    CASE WHEN h.checked_at IS NULL THEN 'missing'
         WHEN h.checked_at<now()-interval '48 hours' THEN 'stale' ELSE h.status END,
    CASE WHEN h.checked_at IS NULL THEN 'Contrôle du socle jamais exécuté'
         WHEN h.checked_at<now()-interval '48 hours' THEN 'Contrôle du socle à relancer'
         ELSE h.detail END,
    h.rows_returned,h.duration_ms,h.checked_at,
    round(extract(epoch FROM now()-h.checked_at)/60,1)
  FROM (VALUES('core_visit_counts'),('core_unattributed_contacts'),('core_canonical_path'),
    ('core_gsc_batch'),('core_identity_fresh'),('core_private_surface')) expected(name)
  LEFT JOIN LATERAL (
    SELECT r.* FROM public.rpc_health r WHERE r.rpc_name=expected.name
    ORDER BY r.checked_at DESC LIMIT 1
  ) h ON true;
$function$


-- ═══ public.page_taxonomy_sync_wix(p_posts jsonb, p_dry_run boolean) ═══
CREATE OR REPLACE FUNCTION public.page_taxonomy_sync_wix(p_posts jsonb, p_dry_run boolean DEFAULT false)
 RETURNS TABLE(inserted integer, updated integer, unpublished integer, inserted_paths text[], updated_paths text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_complete boolean := jsonb_typeof(p_posts) = 'object';
  v_pages jsonb;
  v_observed_at timestamptz;
  v_count integer;
  v_unique integer;
  v_posts integer;
  v_categories integer;
  v_static integer;
BEGIN
  IF p_posts IS NULL OR p_dry_run IS NULL THEN
    RAISE EXCEPTION 'Wix inventory and dry-run flag are required' USING ERRCODE='22023';
  END IF;
  IF v_complete THEN
    IF jsonb_typeof(p_posts->'pages') IS DISTINCT FROM 'array'
       OR jsonb_typeof(p_posts->'counts') IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'Complete Wix inventory requires pages and source counts' USING ERRCODE='22023';
    END IF;
    v_pages := p_posts->'pages';
    v_observed_at := (p_posts->>'observed_at')::timestamptz;
    IF v_observed_at IS NULL OR v_observed_at > clock_timestamp() + interval '5 minutes'
       OR v_observed_at < clock_timestamp() - interval '24 hours' THEN
      RAISE EXCEPTION 'Wix observation timestamp missing or outside accepted range' USING ERRCODE='22023';
    END IF;
  ELSIF jsonb_typeof(p_posts) = 'array' AND jsonb_array_length(p_posts) >= 300 THEN
    -- Backward compatibility for old CLI clients / historical fixtures:
    -- only blog categories change. Publication status and observation never do.
    SELECT jsonb_agg(jsonb_build_object('path', path, 'category', category)) INTO v_pages
    FROM (
      SELECT DISTINCT public.canonical_path('/post/' || (e->>'slug')) AS path,
        CASE WHEN e->>'category'='ressource' THEN 'ressource' ELSE 'classique' END AS category
      FROM jsonb_array_elements(p_posts) e WHERE coalesce(e->>'slug','')<>''
    ) w;
  ELSE
    RAISE EXCEPTION 'Unsupported or incomplete Wix inventory' USING ERRCODE='22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_pages) e
    WHERE jsonb_typeof(e) <> 'object' OR jsonb_typeof(e->'path') IS DISTINCT FROM 'string'
      OR e->>'path' NOT LIKE '/%' OR e->>'path' LIKE '//%'
      OR e->>'path' ~ '[?#[:cntrl:]]'
      OR e->>'path' IS DISTINCT FROM public.canonical_path(e->>'path')
      OR ((e->>'path' LIKE '/post/%') AND coalesce(e->>'category','') NOT IN ('ressource','classique'))
      OR ((e->>'path' NOT LIKE '/post/%') AND e->>'category' IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Invalid Wix path or category' USING ERRCODE='22023';
  END IF;
  SELECT count(*), count(DISTINCT path),
    count(*) FILTER(WHERE path LIKE '/post/%'),
    count(*) FILTER(WHERE path LIKE '/blog/categories/%'),
    count(*) FILTER(WHERE path NOT LIKE '/post/%' AND path NOT LIKE '/blog/categories/%')
    INTO v_count, v_unique, v_posts, v_categories, v_static
  FROM jsonb_to_recordset(v_pages) w(path text, category text);
  IF v_count=0 OR v_count<>v_unique OR (NOT v_complete AND v_count<300) THEN
    RAISE EXCEPTION 'Incomplete or repeated Wix paths' USING ERRCODE='22023';
  END IF;
  IF v_complete AND (
    v_posts < 1 OR v_categories < 1 OR v_static < 1
    OR v_posts IS DISTINCT FROM (p_posts->'counts'->>'posts')::integer
    OR v_categories IS DISTINCT FROM (p_posts->'counts'->>'categories')::integer
    OR v_static IS DISTINCT FROM (p_posts->'counts'->>'static')::integer
    OR NOT EXISTS (SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE path='/')
  ) THEN
    RAISE EXCEPTION 'Wix source counts or homepage do not match' USING ERRCODE='22023';
  END IF;

  -- Serialise inventory writes and the existing heuristic updater. Any failure
  -- rolls back both category changes and all publication changes in this RPC.
  LOCK TABLE public.page_taxonomy IN SHARE ROW EXCLUSIVE MODE;
  IF v_complete AND v_observed_at < (SELECT max(publication_checked_at) FROM public.page_taxonomy) THEN
    RAISE EXCEPTION 'A newer Wix inventory has already been applied' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(array_agg(w.path ORDER BY w.path), '{}') INTO inserted_paths
  FROM jsonb_to_recordset(v_pages) w(path text, category text)
  LEFT JOIN public.page_taxonomy t USING(path) WHERE t.path IS NULL;
  SELECT coalesce(array_agg(w.path ORDER BY w.path), '{}') INTO updated_paths
  FROM jsonb_to_recordset(v_pages) w(path text, category text)
  JOIN public.page_taxonomy t USING(path)
  WHERE w.path LIKE '/post/%' AND t.category IS DISTINCT FROM w.category;
  SELECT count(*) INTO unpublished FROM public.page_taxonomy t
  WHERE (v_complete OR t.path LIKE '/post/%')
    AND NOT EXISTS (SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE w.path=t.path);
  inserted := cardinality(inserted_paths);
  updated := cardinality(updated_paths);
  IF NOT p_dry_run THEN
    INSERT INTO public.page_taxonomy(path,category,theme,source)
      SELECT w.path,w.category,public.page_taxonomy_theme_from_slug(w.path),'wix_api'
      FROM jsonb_to_recordset(v_pages) w(path text, category text)
      WHERE w.path=ANY(inserted_paths);
    UPDATE public.page_taxonomy t SET category=w.category, updated_at=clock_timestamp()
      FROM jsonb_to_recordset(v_pages) w(path text, category text)
      WHERE w.path=t.path AND t.path=ANY(updated_paths);
    IF v_complete THEN
      UPDATE public.page_taxonomy t SET
        is_published=EXISTS (SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE w.path=t.path),
        publication_checked_at=v_observed_at
      WHERE t.publication_checked_at IS DISTINCT FROM v_observed_at
        OR t.is_published IS DISTINCT FROM EXISTS (
          SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE w.path=t.path);
    END IF;
  END IF;
  RETURN NEXT;
END;
$function$


-- ═══ public.page_taxonomy_theme_from_slug(p_path text) ═══
CREATE OR REPLACE FUNCTION public.page_taxonomy_theme_from_slug(p_path text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when p_path ~* 'garde-.?-vue|gav' then 'garde à vue'
    when p_path ~* 'violence|f.minicide|conjugal|harc.lement|contr.le-coercitif' then 'violences & harcèlement'
    when p_path ~* 'indemnis|victime|civi|sarvi|pr.judice|dommage' then 'indemnisation victimes'
    when p_path ~* 'accident|erreur-m.dicale|route|travail' then 'accidents & réparation'
    when p_path ~* 'stup.fiant|trafic|drogue' then 'stupéfiants'
    when p_path ~* 'd.tention|prison|peine|sursis|bracelet|ddse|suret.|am.nagement' then 'peines & détention'
    when p_path ~* 'affaires|fraude|abus-de|escroquerie|blanchiment|corruption|fiscal' then 'pénal des affaires'
    when p_path ~* 'famille|divorce|filiation|succession|contrat' then 'famille & contrats'
    when p_path ~* 'instruction|proc.dure|comparution|tribunal|cour-d|assises|appel|mise-en-examen|t.moin|pr.venu|accus|perquisition|audition' then 'procédure pénale'
    when p_path ~* 'diffamation|injure|r.putation|presse' then 'réputation & presse'
    else null
  end
$function$


-- ═══ public.page_visits(p_start date, p_end date) ═══
CREATE OR REPLACE FUNCTION public.page_visits(p_start date, p_end date)
 RETURNS TABLE(row_kind text, path text, visits bigint, entries bigint, phone_visits bigint, form_visits bigint, contact_visits bigint, contact_rate_pct numeric, observed_days integer, unattributed_phone_events bigint, unattributed_form_events bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH e AS MATERIALIZED (SELECT * FROM public.cooked_visit_events(p_start,p_end)),
  per_page AS (
    SELECT e.path,count(DISTINCT e.visit_id) AS visits,
      count(DISTINCT e.visit_id) FILTER(WHERE e.event_id=e.visit_id) AS entries
    FROM e WHERE e.event_name='pageview' GROUP BY e.path
  ), contacts AS (
    SELECT e.entry_path,
      count(DISTINCT e.visit_id) FILTER(WHERE e.event_name='cta_phone_click') AS phone,
      count(DISTINCT e.visit_id) FILTER(WHERE e.event_name='form_submit') AS form,
      count(DISTINCT e.visit_id) AS union_count
    FROM e WHERE e.counts_as_macro AND e.entry_at>=public.cooked_paris_ts_start(p_start)
    GROUP BY e.entry_path
  )
  SELECT 'page',p.path,p.visits,p.entries,coalesce(c.phone,0),coalesce(c.form,0),coalesce(c.union_count,0),
    round(100.0*coalesce(c.union_count,0)/nullif(p.entries,0),2),NULL::integer,NULL::bigint,NULL::bigint
  FROM per_page p LEFT JOIN contacts c ON c.entry_path=p.path
  UNION ALL
  SELECT 'coverage',NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    count(DISTINCT public.paris_date(e.occurred_at)) FILTER(WHERE e.event_name='pageview')::integer,
    count(*) FILTER(WHERE e.event_name='cta_phone_click' AND e.visit_id IS NULL),
    count(*) FILTER(WHERE e.event_name='form_submit' AND e.counts_as_macro AND e.visit_id IS NULL)
  FROM e;
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
  where occurred_at < now() - interval '13 months';

  get diagnostics v_deleted = row_count;

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


-- ═══ public.refresh_identity_stitch(p_days integer) ═══
CREATE OR REPLACE FUNCTION public.refresh_identity_stitch(p_days integer DEFAULT 400)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '420s'
AS $function$
DECLARE changed bigint;
BEGIN
  IF p_days IS NULL OR p_days<1 THEN
    RAISE EXCEPTION 'p_days must be positive' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(782028);
  DROP TABLE IF EXISTS pg_temp._st_pairs;
  DROP TABLE IF EXISTS pg_temp._st_labels;
  CREATE TEMP TABLE _st_pairs ON COMMIT DROP AS
    SELECT DISTINCT anonymous_id AS a,session_id AS s FROM public.events
    WHERE nullif(anonymous_id,'') IS NOT NULL AND nullif(session_id,'') IS NOT NULL
      AND anonymous_id NOT LIKE 'webhook-%' AND session_id NOT LIKE 'webhook-%'
      AND anonymous_id !~ '^[0-9a-f]{32}$';
  CREATE TEMP TABLE _st_labels ON COMMIT DROP AS
    SELECT s,min(a) AS label FROM pg_temp._st_pairs GROUP BY s;
  CREATE UNIQUE INDEX ON _st_labels(s);
  ANALYZE pg_temp._st_pairs;
  ANALYZE pg_temp._st_labels;
  -- Converger réellement plutôt que supposer qu'exactement trois passes suffisent.
  LOOP
    WITH aid_labels AS MATERIALIZED (
      SELECT p.a,min(l.label) AS label FROM pg_temp._st_pairs p
      JOIN pg_temp._st_labels l USING(s) GROUP BY p.a
    ), sid_labels AS (
      SELECT p.s,min(a.label) AS label FROM pg_temp._st_pairs p
      JOIN aid_labels a USING(a) GROUP BY p.s
    )
    UPDATE pg_temp._st_labels l SET label=n.label FROM sid_labels n
    WHERE l.s=n.s AND l.label IS DISTINCT FROM n.label;
    GET DIAGNOSTICS changed=ROW_COUNT;
    EXIT WHEN changed=0;
  END LOOP;
  DELETE FROM public.identity_stitch;
  INSERT INTO public.identity_stitch(kind,key,visitor_key)
    SELECT 'sid',s,label FROM pg_temp._st_labels
    UNION ALL
    SELECT 'aid',p.a,min(l.label) FROM pg_temp._st_pairs p JOIN pg_temp._st_labels l USING(s) GROUP BY p.a;
  INSERT INTO public.cooked_config(key,value,updated_at)
    VALUES ('identity_stitch_refreshed_at',now()::text,now()),
      ('identity_stitch_rows',(SELECT count(*)::text FROM public.identity_stitch),now())
  ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=EXCLUDED.updated_at;
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
  -- Seul consommateur de l'ancienne fenêtre multi-sites : même source brute,
  -- mêmes bornes, directement dans le filtre qui en a besoin.
  DROP TABLE IF EXISTS _cooked_ev;
  CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
    SELECT id,anonymous_id,session_id,name,referrer_hostname,user_agent,device_type,occurred_at
    FROM public.events_main
    WHERE occurred_at >= now()-interval '48 hours' AND occurred_at < now();
  ANALYZE _cooked_ev;

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
    'prefetch: 0 ref + 0 tick + 0 scroll + 0 intentional action + 1 pv + <10s'
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
  group by session_id
  having max(referrer_hostname) is null
     and count(*) filter (where name = 'engagement_tick') = 0
     and count(*) filter (where name = 'scroll_depth')    = 0
     and count(*) filter (where name IN ('cta_phone_click','cta_booking_click','cta_anchor_click',
                                         'click_internal','click_outbound','form_submit')) = 0
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


-- ═══ public.refresh_pipeline_health() ═══
CREATE OR REPLACE FUNCTION public.refresh_pipeline_health()
 RETURNS TABLE(status text, last_event_at timestamp with time zone, last_event_age_minutes numeric, events_last_60min bigint, gsc_last_day date, gsc_data_age_days numeric, gsc_last_ingest timestamp with time zone, gsc_ingest_age_hours numeric, issues text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE b public.gsc_ingest_batches%ROWTYPE;
BEGIN
  status:='healthy'; issues:=ARRAY[]::text[];
  SELECT max(e.received_at) INTO last_event_at FROM public.events e;
  last_event_age_minutes:=round(extract(epoch FROM now()-last_event_at)/60,1);
  SELECT count(*) INTO events_last_60min FROM public.events e
    WHERE e.received_at >= now()-interval '60 minutes';
  IF last_event_at IS NULL OR last_event_age_minutes>360 THEN
    issues:=issues||'ingestion_stopped'::text; status:='critical';
  END IF;
  SELECT max(g.day) INTO gsc_last_day FROM public.gsc_path_daily g;
  gsc_data_age_days:=(public.paris_today()-gsc_last_day)::numeric;
  SELECT max(g.completed_at) INTO gsc_last_ingest FROM public.gsc_ingest_batches g WHERE g.status='completed';
  gsc_ingest_age_hours:=round(extract(epoch FROM now()-gsc_last_ingest)/3600,2);
  SELECT * INTO b FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF gsc_last_day IS NULL OR gsc_data_age_days>10
     OR gsc_last_ingest IS NULL OR gsc_ingest_age_hours>72 THEN
    issues:=issues||'gsc_source_stale'::text; status:='critical';
  ELSIF gsc_data_age_days>6 OR gsc_ingest_age_hours>30 THEN
    issues:=issues||'gsc_source_delayed'::text;
    IF status='healthy' THEN status:='degraded'; END IF;
  END IF;
  IF b.status IN ('running','failed') AND b.started_at<now()-interval '3 hours' THEN
    issues:=issues||'gsc_ingest_incomplete'::text; status:='critical';
  END IF;
  RETURN NEXT;
END;
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
 SET statement_timeout TO '120s'
AS $function$
DECLARE t record;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('core_visit_counts',
      $q$SELECT count(*) FROM public.page_visits(public.paris_today()-2,public.paris_today()-1)
        WHERE row_kind='page' AND (phone_visits>contact_visits OR form_visits>contact_visits
          OR contact_visits>entries OR entries>visits OR contact_visits>phone_visits+form_visits
          OR contact_visits<0 OR entries<0 OR visits<0)$q$,0),
    ('core_unattributed_contacts',
      $q$WITH visit_events AS MATERIALIZED (
           SELECT * FROM public.cooked_visit_events(public.paris_today()-2,public.paris_today()-1)),
         sources AS (
           SELECT count(*) AS n FROM public.events_human e
           WHERE e.occurred_at>=public.cooked_paris_ts_start(public.paris_today()-2)
             AND e.occurred_at<public.cooked_paris_ts_start(public.paris_today())
             AND (e.name='cta_phone_click'
               OR (e.name='form_submit' AND public.form_submit_counts_as_macro(e.props))))
         SELECT abs((SELECT count(*) FROM visit_events WHERE counts_as_macro)-(SELECT n FROM sources))$q$,0),
    ('core_canonical_path',
      $q$SELECT count(*) FROM (VALUES('/post/%C3%A9cole/','/post/école'),('/','/')) v(input,expected)
         WHERE public.canonical_path(v.input) IS DISTINCT FROM v.expected$q$,0),
    ('core_gsc_batch',
      $q$SELECT CASE WHEN EXISTS(
          SELECT 1 FROM public.gsc_ingest_batches WHERE status='completed'
            AND completed_at>now()-interval '48 hours') THEN 0 ELSE 1 END$q$,0),
    ('core_identity_fresh',
      $q$SELECT CASE WHEN EXISTS(
          SELECT 1 FROM public.cooked_config WHERE key='identity_stitch_refreshed_at'
            AND value::timestamptz>now()-interval '30 hours') THEN 0 ELSE 1 END$q$,0),
    ('core_private_surface',
      $q$SELECT count(*) FROM public.alert_rule_exposure()$q$,0)
  ) tests(name,sql,expected) LOOP
    PERFORM public.rpc_contract_check(t.name,t.sql,NULL,t.expected);
  END LOOP;
  DELETE FROM public.rpc_health WHERE checked_at<now()-interval '90 days';
END;
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
  -- Le chemin déjà décodé est le cas courant ; le résultat de la boucle serait identique.
  if strpos(input, '%') = 0 then
    return input;
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

