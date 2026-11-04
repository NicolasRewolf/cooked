-- 04/11/2026 : retrait validé par Nicolas, 24 tables et huit vues.
-- Prérequis : form-webhook v17 déployé (écrit uniquement events),
-- GSC deux grains livré et aucun ancien import en cours.
-- Les événements, sources GSC conservées, identités, filtres et inventaire
-- ne sont ni réécrits ni purgés. Pas de CASCADE ni de copie d'archive.
BEGIN;
SET LOCAL lock_timeout = '10s';

DO $guard$
BEGIN
  IF EXISTS(SELECT 1 FROM public.gsc_ingest_batches WHERE status='running') THEN
    RAISE EXCEPTION 'Terminer le lot GSC en cours avant le ménage';
  END IF;
END $guard$;

-- Retirer les quatre tâches déjà suspendues, au lieu de conserver des appels morts.
DO $jobs$
DECLARE j record;
BEGIN
  FOR j IN SELECT jobid FROM cron.job WHERE jobname IN (
    'cooked-refresh-after-gsc','cpi-calibration-monthly',
    'math-refresh-snapshots-weekly','refresh_seo_url_snapshot') LOOP
    PERFORM cron.unschedule(j.jobid);
  END LOOP;
END $jobs$;

DELETE FROM public.freshness_contract WHERE source NOT IN (
  'cta_phone_click','form_submit','gsc_path_daily','gsc_query_page_daily','page_taxonomy');
DELETE FROM public.cooked_config WHERE key IN (
  'cpi_definition_version','last_full_refresh_after_gsc_at',
  'last_full_refresh_gsc_batch_id','refresh_after_gsc_budget_s');

DROP FUNCTION public.refresh_pipeline_health() RESTRICT;
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
$function$;

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
$function$;

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
END $function$;

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
    -- la synchro hebdomadaire (wix-taxonomy-sync) a eu au moins une occasion de passer
    AND v.first_seen < now() - interval '8 days';

  IF v_n >= 1 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j, vus depuis > 8 j) sans catégorie Wix dans page_taxonomy — toute lecture par catégorie (dashboard Articles Ressources, page_visits, contrat éditorial) les ignore. Vérifier les chemins (page réelle, redirection ou URL tronquée), leur catégorie Wix et le dernier workflow wix-taxonomy-sync (lundi 05:00 UTC). Une synchro réussie peut conserver une URL sans catégorie ; ne pas déduire un secret manquant de cette seule alerte. Concernés : %s',
        v_n, left(coalesce(v_ex, ''), 400)
      );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_pipeline_health()
RETURNS TABLE(status text, last_event_at timestamptz, last_event_age_minutes numeric,
  events_last_60min bigint, gsc_last_day date, gsc_data_age_days numeric,
  gsc_last_ingest timestamptz, gsc_ingest_age_hours numeric, issues text[])
LANGUAGE plpgsql STABLE SECURITY DEFINER
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
$function$;

REVOKE ALL ON FUNCTION public.refresh_pipeline_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_pipeline_health() TO service_role;

DROP VIEW public.cpi_capture_perdue,
  public.cpi_gisement,
  public.cpi_movers,
  public.cpi_opportunite_contact,
  public.events_human_outremer,
  public.events_outremer,
  public.pont_couverture,
  public.pont_prospects_dossiers RESTRICT;

DROP FUNCTION public.assisted_contacts_by_entry_path(p_start date, p_end date),
  public.behavior_pages_for_period(date_from timestamp with time zone, date_to timestamp with time zone),
  public.content_performance(days_back integer),
  public.conversion_journeys(days_back integer, p_end date),
  public.cooked_page_daily_series(target_path text, days_back integer, end_date date),
  public.cooked_pages_compare(period_kind text, data_lens text),
  public.cooked_pages_snapshot(p_period_kind text, max_rows integer),
  public.cooked_site_scope(hostname text, props jsonb),
  public.cooked_web_vitals_window(p_from timestamp with time zone, p_to timestamp with time zone),
  public.cpi_compose(zc numeric, zr numeric, zl numeric, zv numeric, mm numeric, gg numeric, exclude_conversion boolean),
  public.cta_breakdown_for_path(path text, days_back integer),
  public.ctr_for_position(pos numeric),
  public.dashboard_annotations(period_kind text),
  public.dashboard_article_detail(p_path text, period_kind text),
  public.dashboard_assisted_quarter(),
  public.dashboard_expertises_kpis(period_kind text),
  public.dashboard_expertises_overview(period_kind text, max_rows integer),
  public.dashboard_expertises_trend(period_kind text),
  public.dashboard_honoraires_funnel(period_kind text),
  public.dashboard_intervention_effect(p_path text, p_day date),
  public.dashboard_lab_gsc_weekly(p_weeks integer),
  public.dashboard_resources_assisted(period_kind text),
  public.dashboard_resources_cohorts(),
  public.dashboard_resources_kpis(period_kind text),
  public.dashboard_resources_overview(period_kind text, max_rows integer),
  public.dashboard_resources_trend(period_kind text),
  public.dashboard_seo_by_query(period_kind text, scope text, min_volume integer, max_rows integer),
  public.dashboard_seo_kpis(period_kind text, scope text),
  public.dfs_keywords_to_sync(limit_n integer),
  public.engagement_density_for_path(target_path text, days integer),
  public.form_submits_attributed(days_back integer, p_end date),
  public.form_submits_per_path(start_date date, end_date date),
  public.gsc_is_branded(p_query text),
  public.gsc_page_daily_series(target_path text, days_back integer, end_date date),
  public.gsc_page_performance(target_path text, period_kind text),
  public.gsc_pages_compare(period_kind text, data_lens text),
  public.gsc_pages_overview(max_rows integer),
  public.gsc_top_queries_global(period_kind text, max_rows integer),
  public.gsc_x_dfs_opportunities(min_volume integer, position_min numeric, position_max numeric, period_kind text, max_rows integer),
  public.macro_contacts_by_path(start_date date, end_date date),
  public.outbound_destinations_for_path(path text, days_back integer),
  public.pages_overview_unified(period_kind text, max_rows integer),
  public.pages_pulse(period_kind text, delta_threshold_pct numeric),
  public.pogo_rates_for_period(date_from timestamp with time zone, date_to timestamp with time zone),
  public.pont_prospects_dossiers_env(p_env text),
  public.pulse_quadrant(gsc_dir text, cooked_dir text),
  public.pulse_status(gsc_n bigint, gsc_prev bigint, cooked_n bigint, cooked_prev bigint, delta_threshold numeric),
  public.refresh_page_taxonomy_heuristic(),
  public.seo_pages_overview(date_from timestamp with time zone, date_to timestamp with time zone),
  public.seo_to_contact_funnel(days_back integer, p_end date),
  public.site_context_export(),
  public.site_gsc_kpis_compare(p_period_kind text),
  public.site_kpis_compare(p_period_kind text),
  public.site_macro_counts(start_date date, end_date date),
  public.site_pulse(p_period_kind text, delta_threshold_pct numeric),
  public.snapshot_pages_export(paths text[]),
  public.top_contact_pages(p_period_kind text, max_rows integer),
  public.tracker_first_seen_global() RESTRICT;

DROP PROCEDURE public.cooked_events_window(IN p_occurred_from timestamp with time zone, IN p_occurred_to timestamp with time zone, IN p_grain text, IN p_site text),
  public.cooked_snapshot_window(IN p_window text, IN p_grain text, OUT o_label_fr text, OUT o_lns date, OUT o_lne date, OUT o_lps date, OUT o_lpe date, OUT o_lpt date, OUT o_ld integer, OUT o_gns date, OUT o_gne date, OUT o_gps date, OUT o_gpe date, OUT o_glast date, OUT o_glag integer) RESTRICT;

DROP TABLE public.annotations,
  public.conversion_weekly,
  public.cpi_calibration_checks,
  public.cpi_daily,
  public.cpi_pre_restatement_20260903,
  public.crm_prospects,
  public.cta_anchor_label_map,
  public.dashboard_assisted_quarter_snapshot,
  public.dashboard_expertises_kpis_snapshot,
  public.dashboard_expertises_snapshot,
  public.dashboard_expertises_trend_snapshot,
  public.dashboard_kpis_snapshot,
  public.dashboard_resources_assisted_snapshot,
  public.dashboard_resources_snapshot,
  public.dashboard_trend_snapshot,
  public.dfs_keyword_volume,
  public.gbp_daily,
  public.gsc_query_daily,
  public.math_internal_edges_snapshot,
  public.math_visit_sequences_snapshot,
  public.refresh_runs,
  public.secib_dossiers,
  public.seo_url_snapshot,
  public.serp_features RESTRICT;

-- Les colonnes générées CRM utilisent encore ces deux normaliseurs.
DROP FUNCTION public.cooked_normalize_email(raw text),
  public.cooked_normalize_phone_fr(raw text) RESTRICT;

-- Un retrait de périmètre clôt uniquement ses alertes ; les alertes de collecte restent.
UPDATE public.alerts SET acked=true WHERE NOT acked
  AND (kind LIKE 'gbp_%' OR kind LIKE 'crm_%' OR kind LIKE 'secib_%'
    OR kind LIKE 'cpi_%' OR kind LIKE 'dfs_%' OR kind LIKE 'dashboard_%');

NOTIFY pgrst, 'reload schema';
COMMIT;
