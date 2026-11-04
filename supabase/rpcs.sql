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
    detail := format('Formulaires Wix sans page_source ou sans objet sur 28 j — un contact sans page_source est compté au total site mais invisible par page ; sans objet, il est compté macro par défaut (candidature ?). Câbler les champs cachés `page_source` (seedé par masterPage) et « Objet de ma demande » sur le formulaire (action Nicolas, T-18). %s', v_forms);
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
    detail:='Le dernier lot GSC est incomplet depuis plus de trois heures. Reprendre les trois tables avant lecture.';
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
    detail := 'identity_stitch est VIDE : conversion_journeys, assisted_contacts_by_entry_path, seo_to_contact_funnel et les snapshots dashboard retombent sur la session brute (contacts assistés sous-comptés). Relancer : SELECT public.refresh_identity_stitch(90); puis lire cron.job_run_details du job refresh-identity-stitch.';
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
    detail := format('Couture d''identité reconstruite il y a %s h (dernière : %s Paris, %s lignes) — attendue chaque nuit à 05:40 Paris (cron refresh-identity-stitch). conversion_journeys, assisted_contacts_by_entry_path et seo_to_contact_funnel lisent une couture périmée. Relancer : SELECT public.refresh_identity_stitch(90);',
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
                       '90 j glissants');
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
      -- mêmes exclusions structurelles que refresh_page_taxonomy_heuristic (T-19)
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
    -- la synchro hebdomadaire (wix-taxonomy-sync) a eu au moins une occasion de passer
    AND v.first_seen < now() - interval '8 days';

  IF v_n >= 1 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j, vus depuis > 8 j) sans catégorie Wix dans page_taxonomy — toute lecture par catégorie (dashboard Articles Ressources, content_performance, contrat éditorial) les ignore. Vérifier les chemins (page réelle, redirection ou URL tronquée), leur catégorie Wix et le dernier workflow wix-taxonomy-sync (lundi 05:00 UTC). Une synchro réussie peut conserver une URL sans catégorie ; ne pas déduire un secret manquant de cette seule alerte. Concernés : %s',
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


-- ═══ public.assisted_contacts_by_entry_path(p_start date, p_end date) ═══
CREATE OR REPLACE FUNCTION public.assisted_contacts_by_entry_path(p_start date, p_end date)
 RETURNS TABLE(entry_path text, contacts bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '300s'
AS $function$
  SELECT coalesce(e.entry_path,'(non attribuable)'),count(*)
  FROM public.cooked_visit_events(p_start,p_end) e
  WHERE e.counts_as_macro GROUP BY 1;
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
    FROM public.cooked_web_vitals_window(date_from,date_to)
    WHERE path IS NOT NULL
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
  with w as (
    select b.n_end as d_end, b.n_end - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  base as (
    select e.path, public.cooked_page_type(e.path) as ptype, t.theme, e.session_id, e.name, e.props
    from public.events_human e
    left join public.page_taxonomy t on t.path = e.path
    where e.occurred_at >= public.cooked_paris_ts_start((select d_start from w))
      and e.occurred_at < public.cooked_paris_ts_end_exclusive((select d_end from w))
      and e.path is not null
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
    from public.conversion_journeys(days_back, (select d_end from w)) j
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
  WITH w AS (
    SELECT coalesce(p_end,b.n_end) AS last_day,coalesce(p_end,b.n_end)-days_back+1 AS first_day
    FROM public.cooked_period_bounds('rolling_28','live_j1') b
  )
  SELECT CASE e.event_name WHEN 'cta_phone_click' THEN 'phone' ELSE 'form' END,
    e.occurred_at,e.path,e.objet,e.anonymous_id,e.attribution_method,e.entry_path,e.entry_channel,
    cardinality(e.journey),e.journey,e.device_type,w.first_day,w.last_day
  FROM w CROSS JOIN LATERAL public.cooked_visit_events(w.first_day,w.last_day) e
  WHERE e.counts_as_macro;
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
               e.device_type, e.props, e.occurred_at, e.url,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at, e.url,
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
               e.device_type, e.props, e.occurred_at, e.url,
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
               e.device_type, e.props, e.occurred_at, e.url,
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
             e.device_type, e.props, e.occurred_at, e.url,
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
             e.device_type, e.props, e.occurred_at, e.url,
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
    -- T-16 (e-05) : « +33 (0)6 … » / « 00 33 (0)6 … » — le (0) après l'indicatif
    when d like '00330%' and length(d) = 14 then '+33' || substr(d, 6)
    when d like '330%'   and length(d) = 12 then '+33' || substr(d, 4)
    when d like '0033%'  and length(d) = 13 then '+33' || substr(d, 5)
    when d like '33%'    and length(d) = 11 then '+' || d
    when d like '0%'     and length(d) = 10 then '+33' || substr(d, 2)
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


-- ═══ public.cooked_web_vitals_window(p_from timestamp with time zone, p_to timestamp with time zone) ═══
CREATE OR REPLACE FUNCTION public.cooked_web_vitals_window(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS TABLE(id uuid, path text, device_type text, props jsonb, occurred_at timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT DISTINCT ON (
    CASE WHEN nullif(e.props->>'measurement_id','') IS NOT NULL
      THEN 'document:' || (e.props->>'measurement_id') ELSE 'event:' || e.id::text END,
    e.props->>'metric')
    e.id,e.path,e.device_type,e.props,e.occurred_at
  FROM public.events_human e
  WHERE e.name='web_vitals' AND e.occurred_at>=p_from AND e.occurred_at<p_to
  ORDER BY
    CASE WHEN nullif(e.props->>'measurement_id','') IS NOT NULL
      THEN 'document:' || (e.props->>'measurement_id') ELSE 'event:' || e.id::text END,
    e.props->>'metric',
    CASE WHEN e.props->>'revision' ~ '^[0-9]{1,9}$' THEN (e.props->>'revision')::int ELSE 0 END DESC,
    e.occurred_at DESC,e.id DESC;
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
        'position', round((sum(position*impressions)/nullif(sum(impressions),0))::numeric,1),
        'ctr_pct', CASE WHEN COALESCE(sum(impressions),0)>0 THEN round(100.0*sum(clicks)/sum(impressions),2) END,
        'ctr_expected', NULL::numeric,
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
      FROM (SELECT query, sum(clicks) clicks, sum(impressions) impressions, round((sum(position*impressions)/nullif(sum(impressions),0))::numeric,1) pos
            FROM gsc_query_page_daily WHERE path=p_path AND day BETWEEN gns AND gne AND NOT public.gsc_is_branded(query)
            GROUP BY query ORDER BY sum(impressions) DESC LIMIT 10) q
      LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=q.query AND dfs.location_code=2250),
    'cpi', (SELECT to_jsonb(c) - 'created_at' FROM cpi_daily c WHERE c.path=p_path AND c.day=(SELECT max(day) FROM cpi_daily) ),
    'cpi_series', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', day, 'cpi', cpi, 'cpi_version', cpi_version) ORDER BY day), '[]'::jsonb)
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
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '5s'
AS $function$
  SELECT jsonb_build_object(
    'quarter', coalesce(s.quarter,
      'T' || extract(quarter FROM public.paris_today())::int || ' ' || extract(year FROM public.paris_today())::int),
    'quarter_start', coalesce(s.quarter_start, date_trunc('quarter', public.paris_today())::date),
    'value', coalesce(s.value, 0),
    'target', s.target
  )
  FROM (SELECT 1) dummy
  LEFT JOIN public.dashboard_assisted_quarter_snapshot s
    ON s.quarter = 'T' || extract(quarter FROM public.paris_today())::int
                 || ' ' || extract(year FROM public.paris_today())::int;
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


-- ═══ public.dashboard_lab_gsc_weekly(p_weeks integer) ═══
CREATE OR REPLACE FUNCTION public.dashboard_lab_gsc_weekly(p_weeks integer DEFAULT 70)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
WITH g_end AS (
  SELECT public.gsc_last_data_day() AS d
),
-- Dernier dimanche ≤ gsc_last_data_day (semaine ISO close), puis p_weeks semaines en arrière.
w AS (
  SELECT (date_trunc('week', d)::date - 1) AS w_end,
         (date_trunc('week', d)::date - 1) - (7 * GREATEST(p_weeks, 1)) + 1 AS w_start
  FROM g_end
),
-- MATERIALIZED (v3) : sans ça le planificateur ré-évalue cooked_page_type() par ligne jointe → timeout 2 min.
win AS MATERIALIZED (
  SELECT g.day, g.path, g.clicks, g.impressions
  FROM public.gsc_path_daily g
  WHERE g.day BETWEEN (SELECT w_start FROM w) AND (SELECT w_end FROM w)
),
-- Type par chemin distinct (≈ 800 chemins sur 70 semaines) : cooked_page_type() évaluée une fois par chemin.
ptype AS MATERIALIZED (
  SELECT p.path,
         CASE
           WHEN t.typ = 'post' AND pt.category = 'ressource' THEN 'ressource'
           WHEN t.typ = 'post' AND pt.category = 'classique' THEN 'classique'
           WHEN t.typ = 'expertise' THEN 'expertise'
           ELSE 'divers'
         END AS typ
  FROM (SELECT DISTINCT path FROM win) p
  CROSS JOIN LATERAL (SELECT public.cooked_page_type(p.path) AS typ) t
  LEFT JOIN public.page_taxonomy pt ON pt.path = p.path
),
typed AS (
  SELECT date_trunc('week', win.day)::date AS week_start, ptype.typ, win.clicks, win.impressions
  FROM win JOIN ptype USING (path)
),
weeks AS (
  SELECT week_start,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'ressource'), 0)::bigint AS c_ressource,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'classique'), 0)::bigint AS c_classique,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'expertise'), 0)::bigint AS c_expertise,
         COALESCE(SUM(clicks) FILTER (WHERE typ = 'divers'), 0)::bigint    AS c_divers,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'ressource'), 0)::bigint AS i_ressource,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'classique'), 0)::bigint AS i_classique,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'expertise'), 0)::bigint AS i_expertise,
         COALESCE(SUM(impressions) FILTER (WHERE typ = 'divers'), 0)::bigint    AS i_divers
  FROM typed
  GROUP BY week_start
),
ann AS (
  SELECT a.day, a.kind, a.label, a.paths
  FROM public.annotations a
  WHERE a.day BETWEEN (SELECT w_start FROM w) AND (SELECT w_end FROM w)
  ORDER BY a.day, a.id
)
SELECT jsonb_build_object(
  'gsc_end',      (SELECT d FROM g_end),
  'window_start', (SELECT w_start FROM w),
  'window_end',   (SELECT w_end FROM w),
  'weeks',        COALESCE((SELECT jsonb_agg(to_jsonb(weeks) ORDER BY week_start) FROM weeks), '[]'::jsonb),
  'annotations',  COALESCE((SELECT jsonb_agg(to_jsonb(ann)) FROM ann), '[]'::jsonb)
);
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
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT q.query AS keyword, SUM(q.clicks)::bigint AS clicks_total
  FROM public.gsc_query_daily q
  WHERE q.day BETWEEN public.paris_today()-89 AND public.paris_today()
    AND q.query IS NOT NULL AND q.query <> ''
  GROUP BY q.query
  ORDER BY SUM(q.clicks) DESC
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


-- ═══ public.form_submits_attributed(days_back integer, p_end date) ═══
CREATE OR REPLACE FUNCTION public.form_submits_attributed(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(event_id uuid, occurred_at timestamp with time zone, form_path text, objet text, counts_as_macro boolean, resolved_anonymous_id text, resolved_session_id text, attribution_method text, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH w AS (
    SELECT coalesce(p_end,b.n_end) AS last_day,coalesce(p_end,b.n_end)-days_back+1 AS first_day
    FROM public.cooked_period_bounds('rolling_28','live_j1') b
  )
  SELECT v.event_id,v.occurred_at,v.path,v.objet,v.counts_as_macro,
    CASE WHEN v.attribution_method='hidden_field' THEN v.anonymous_id END,
    CASE WHEN v.attribution_method='hidden_field' THEN nullif(e.props->>'cooked_sid','') END,
    v.attribution_method,w.first_day,w.last_day
  FROM w CROSS JOIN LATERAL public.cooked_visit_events(w.first_day,w.last_day) v
  JOIN public.events e ON e.id=v.event_id
  WHERE v.event_name='form_submit';
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
     OR (SELECT count(*) FROM jsonb_object_keys(p_row_counts)) <> 3 THEN
    RAISE EXCEPTION 'row counts must contain exactly the three GSC tables' USING ERRCODE = '22023';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['gsc_path_daily','gsc_query_daily','gsc_query_page_daily'] LOOP
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
      public.cooked_paris_ts_start(b.n_start) AS date_from,
      public.cooked_paris_ts_end_exclusive(b.n_end) AS date_to
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
    FROM public.cooked_web_vitals_window((SELECT date_from FROM ts),(SELECT date_to FROM ts)) e, cp
    WHERE e.path = cp.p
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


-- ═══ public.pont_prospects_dossiers_env(p_env text) ═══
CREATE OR REPLACE FUNCTION public.pont_prospects_dossiers_env(p_env text DEFAULT 'prod'::text)
 RETURNS TABLE(prospect_id bigint, prospect_le timestamp with time zone, source text, form_id text, objet text, page_source_path text, cooked_aid text, cooked_sid text, nom text, prenom text, email text, telephone text, secib_env text, dossier_id integer, dossier_code text, dossier_cree_le timestamp with time zone, matiere_libelle text, etat_facturable text, facture_total_ht numeric, statut text, delai_jours numeric, cle_match text, personne_key text, rang_personne integer, rang_dossier integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH base AS (
    SELECT p.id AS prospect_id, p.occurred_at AS prospect_le, p.source, p.form_id, p.objet, p.page_source_path,
           p.cooked_aid, p.cooked_sid, p.nom, p.prenom, p.email, p.telephone,
           p.email_norm, p.tel_norm,
           d.env AS secib_env, d.dossier_id, d.code AS dossier_code, d.date_creation AS dossier_cree_le,
           d.matiere_libelle, d.etat_facturable, d.facture_total_ht,
           d.cle_match
    FROM public.crm_prospects p
    LEFT JOIN LATERAL (
      SELECT dd.env, dd.dossier_id, dd.code, dd.date_creation, dd.matiere_libelle, dd.etat_facturable,
             dd.facture_total_ht,
             CASE WHEN p.email_norm IS NOT NULL AND p.email_norm = ANY (dd.client_emails_norm) THEN 'email'
                  ELSE 'telephone' END AS cle_match
      FROM public.secib_dossiers dd
      WHERE dd.env = p_env
        AND ((p.email_norm IS NOT NULL AND p.email_norm = ANY (dd.client_emails_norm))
          OR (p.tel_norm IS NOT NULL AND p.tel_norm = ANY (dd.client_tels_norm)))
      -- priorité : email > téléphone, puis le dossier le plus proche dans le temps
      ORDER BY (p.email_norm IS NOT NULL AND p.email_norm = ANY (dd.client_emails_norm)) DESC,
               abs(extract(epoch FROM dd.date_creation - p.occurred_at))
      LIMIT 1
    ) d ON true
  )
  SELECT b.prospect_id, b.prospect_le, b.source, b.form_id, b.objet, b.page_source_path, b.cooked_aid, b.cooked_sid,
         b.nom, b.prenom, b.email, b.telephone, b.secib_env, b.dossier_id, b.dossier_code, b.dossier_cree_le,
         b.matiere_libelle, b.etat_facturable, b.facture_total_ht,
         CASE
           WHEN b.email_norm IS NULL AND b.tel_norm IS NULL THEN 'non_rapprochable'
           WHEN b.dossier_id IS NULL THEN 'non_converti'
           WHEN b.dossier_cree_le <  b.prospect_le - interval '7 days'   THEN 'client_existant'
           WHEN b.dossier_cree_le <= b.prospect_le + interval '180 days' THEN 'converti'
           ELSE 'dossier_ulterieur'
         END AS statut,
         CASE WHEN b.dossier_id IS NOT NULL
              THEN round(extract(epoch FROM b.dossier_cree_le - b.prospect_le) / 86400.0, 1) END AS delai_jours,
         CASE WHEN b.dossier_id IS NOT NULL THEN b.cle_match END AS cle_match,
         coalesce(b.email_norm, b.tel_norm) AS personne_key,
         row_number() OVER (PARTITION BY coalesce(b.email_norm, b.tel_norm) ORDER BY b.prospect_le, b.prospect_id)::int AS rang_personne,
         CASE WHEN b.dossier_id IS NOT NULL
              THEN row_number() OVER (PARTITION BY b.dossier_id ORDER BY abs(extract(epoch FROM b.dossier_cree_le - b.prospect_le)), b.prospect_id)::int
         END AS rang_dossier
  FROM base b
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
    -- T-15 : heuristique partagée avec page_taxonomy_sync_wix
    select path, public.page_taxonomy_theme_from_slug(path) as theme
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
DECLARE b public.gsc_ingest_batches%ROWTYPE;
BEGIN
  status:='healthy'; issues:=ARRAY[]::text[];
  SELECT max(s.refreshed_at) INTO snapshot_refreshed_at FROM public.seo_url_snapshot s;
  snapshot_age_hours:=round(extract(epoch FROM now()-snapshot_refreshed_at)/3600,2);
  cron_last_status:='suspended';
  SELECT d.start_time INTO cron_last_run FROM cron.job j
    JOIN cron.job_run_details d ON d.jobid=j.jobid
    WHERE j.jobname='refresh_seo_url_snapshot' ORDER BY d.start_time DESC LIMIT 1;
  cron_age_hours:=round(extract(epoch FROM now()-cron_last_run)/3600,2);
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
  SELECT max(d.last_synced_at),count(*) INTO dfs_last_synced_at,dfs_row_count FROM public.dfs_keyword_volume d;
  dfs_sync_age_hours:=round(extract(epoch FROM now()-dfs_last_synced_at)/3600,2);
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
  -- Comptes rectifiés au grain visite. Les actions sont observées avant la
  -- clôture et seules les visites entrées dans cette fenêtre alimentent le taux.
  -- Signature conservée ; contacts/phone/form désignent désormais les visites.
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'cross') b
  ),
  e as materialized (
    select v.* from w cross join lateral public.cooked_visit_events(w.d_start,w.d_end) v
  ),
  organic as (
    select e.entry_path,count(*) as organic_entries
    from e where e.event_name='pageview' and e.event_id=e.visit_id
      and e.entry_channel like 'organic%'
    group by e.entry_path
  ),
  conv as (
    select e.entry_path,count(distinct e.visit_id) as contacts,
      count(distinct e.visit_id) filter(where e.event_name='cta_phone_click') as contacts_phone,
      count(distinct e.visit_id) filter(where e.event_name='form_submit') as contacts_form
    from e where e.counts_as_macro and e.entry_channel like 'organic%'
      and e.entry_at>=public.cooked_paris_ts_start((select d_start from w))
    group by e.entry_path
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

