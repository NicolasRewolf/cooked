-- supabase/views.sql — CATALOGUE DE RÉFÉRENCE (généré, LECTURE SEULE)
-- Ne pas rejouer comme source d'un déploiement. Ne pas éditer à la main.
-- Source DDL : supabase/migrations/*.sql et état prod.
-- Corps des routines : supabase/rpcs.sql.
-- Généré depuis pg_get_viewdef, pg_get_function_identity_arguments et
-- pg_get_function_result, avec reloptions effectives le 04/11/2026.
-- Projet mxycmjkeotrycyneacje. Les anciennes vues CPI lisent un historique figé.

-- VUES (11)

-- VIEW public.cpi_capture_perdue
CREATE OR REPLACE VIEW public.cpi_capture_perdue WITH (security_invoker=true) AS
 SELECT path,
    ptype,
    grade,
    clics_perdus,
    couv_gsc_pct,
        CASE
            WHEN couv_gsc_pct >= 40 THEN 'directe'::text
            WHEN couv_gsc_pct >= 20 THEN 'partielle'::text
            ELSE 'extrapolee'::text
        END AS fiabilite_capture,
    (grade = ANY (ARRAY['S'::text, 'A'::text, 'B'::text])) AND couv_gsc_pct >= 20 AS interpretable,
    zc,
    n_org,
    day
   FROM cpi_daily
  WHERE day = (( SELECT max(cpi_daily_1.day) AS max
           FROM cpi_daily cpi_daily_1)) AND clics_perdus > 0;

-- VIEW public.cpi_gisement
CREATE OR REPLACE VIEW public.cpi_gisement WITH (security_invoker=true) AS
 SELECT path,
    ptype,
    grade,
    n_org,
    cpi,
    potentiel,
    convertit,
    zc,
    zr,
    zl,
    zv,
    day
   FROM cpi_opportunite_contact;

-- VIEW public.cpi_movers
CREATE OR REPLACE VIEW public.cpi_movers WITH (security_invoker=true) AS
 WITH bounds AS (
         SELECT l.d1,
            r.d0
           FROM ( SELECT max(cpi_daily.day) AS d1
                   FROM cpi_daily) l
             CROSS JOIN LATERAL ( SELECT max(cpi_daily.day) AS d0
                   FROM cpi_daily
                  WHERE cpi_daily.day >= (l.d1 - 14) AND cpi_daily.day <= (l.d1 - 7)) r
          WHERE r.d0 IS NOT NULL
        ), now_rows AS (
         SELECT c.day,
            c.path,
            c.ptype,
            c.grade,
            c.cpi,
            c.cpi_raw,
            c.momentum,
            c.gate,
            c.zc,
            c.zr,
            c.zl,
            c.zv,
            c.clics_perdus,
            c.n_org,
            c.couv_gsc_pct,
            c.created_at
           FROM cpi_daily c
             JOIN bounds b_1 ON c.day = b_1.d1
        ), ref_rows AS (
         SELECT c.day,
            c.path,
            c.ptype,
            c.grade,
            c.cpi,
            c.cpi_raw,
            c.momentum,
            c.gate,
            c.zc,
            c.zr,
            c.zl,
            c.zv,
            c.clics_perdus,
            c.n_org,
            c.couv_gsc_pct,
            c.created_at
           FROM cpi_daily c
             JOIN bounds b_1 ON c.day = b_1.d0
        )
 SELECT b.d1 AS day_now,
    b.d0 AS day_ref,
    b.d1 - b.d0 AS ecart_jours,
    COALESCE(n.path, p.path) AS path,
    COALESCE(n.ptype, p.ptype) AS ptype,
        CASE
            WHEN p.path IS NULL THEN 'nouveau'::text
            WHEN n.path IS NULL THEN 'disparu'::text
            ELSE 'present'::text
        END AS statut,
    n.cpi AS cpi_now,
    p.cpi AS cpi_ref,
    n.cpi - p.cpi AS delta_cpi,
    n.grade AS grade_now,
    p.grade AS grade_ref,
    COALESCE((n.grade = ANY (ARRAY['S'::text, 'A'::text, 'B'::text])) AND (p.grade = ANY (ARRAY['S'::text, 'A'::text, 'B'::text])), false) AS fiable,
    round(n.zc - p.zc, 1) AS delta_zc,
    round(n.zr - p.zr, 1) AS delta_zr,
    round(n.zl - p.zl, 1) AS delta_zl,
    round(n.zv - p.zv, 1) AS delta_zv,
    round(n.momentum - p.momentum, 2) AS delta_momentum,
    n.momentum AS momentum_now,
    n.n_org AS n_org_now,
    n.clics_perdus AS clics_perdus_now
   FROM now_rows n
     FULL JOIN ref_rows p ON p.path = n.path
     CROSS JOIN bounds b
  ORDER BY (n.cpi - p.cpi);

-- VIEW public.cpi_opportunite_contact
CREATE OR REPLACE VIEW public.cpi_opportunite_contact WITH (security_invoker=true) AS
 SELECT path,
    ptype,
    grade,
    n_org,
    cpi,
    round(cpi_compose(zc, zr, zl, 0::numeric, 1::numeric, 1::numeric, true))::integer AS potentiel,
    COALESCE(convertit, false) AS convertit,
    zc,
    zr,
    zl,
    zv,
    day
   FROM cpi_daily
  WHERE day = (( SELECT max(cpi_daily_1.day) AS max
           FROM cpi_daily cpi_daily_1));

-- VIEW public.events_human
CREATE OR REPLACE VIEW public.events_human WITH (security_invoker=true) AS
 SELECT id,
    anonymous_id,
    session_id,
    name,
    url,
    path,
    hostname,
    title,
    referrer,
    referrer_hostname,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    user_agent,
    device_type,
    os,
    browser,
    viewport_width,
    viewport_height,
    props,
    occurred_at,
    received_at
   FROM events_no_bots e
  WHERE NOT (EXISTS ( SELECT 1
           FROM noise_sessions n
          WHERE n.session_id = e.session_id)) AND NOT (name = 'cta_anchor_click'::text AND cooked_is_chrome_anchor(props)) AND NOT ((name = ANY (ARRAY['cta_phone_click'::text, 'cta_booking_click'::text, 'cta_anchor_click'::text, 'click_internal'::text, 'click_outbound'::text])) AND (EXISTS ( SELECT 1
           FROM events_main d
          WHERE (d.name = ANY (ARRAY['cta_phone_click'::text, 'cta_booking_click'::text, 'cta_anchor_click'::text, 'click_internal'::text, 'click_outbound'::text])) AND d.session_id = e.session_id AND d.name = e.name AND NOT d.path IS DISTINCT FROM e.path AND date_trunc('second'::text, (d.occurred_at AT TIME ZONE 'UTC'::text)) = date_trunc('second'::text, (e.occurred_at AT TIME ZONE 'UTC'::text)) AND NOT (d.props ->> 'anchor'::text) IS DISTINCT FROM (e.props ->> 'anchor'::text) AND d.id < e.id)));

-- VIEW public.events_human_outremer
CREATE OR REPLACE VIEW public.events_human_outremer WITH (security_invoker=true) AS
 SELECT id,
    anonymous_id,
    session_id,
    name,
    url,
    path,
    hostname,
    title,
    referrer,
    referrer_hostname,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    user_agent,
    device_type,
    os,
    browser,
    viewport_width,
    viewport_height,
    props,
    occurred_at,
    received_at
   FROM events_outremer e
  WHERE NOT (EXISTS ( SELECT 1
           FROM bot_fingerprints b
          WHERE b.anonymous_id = e.anonymous_id)) AND NOT (EXISTS ( SELECT 1
           FROM noise_sessions n
          WHERE n.session_id = e.session_id)) AND NOT (name = 'cta_anchor_click'::text AND cooked_is_chrome_anchor(props));

-- VIEW public.events_main
CREATE OR REPLACE VIEW public.events_main WITH (security_invoker=true) AS
 SELECT id,
    anonymous_id,
    session_id,
    name,
    url,
    path,
    hostname,
    title,
    referrer,
    referrer_hostname,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    user_agent,
    device_type,
    os,
    browser,
    viewport_width,
    viewport_height,
    props,
    occurred_at,
    received_at
   FROM events e
  WHERE cooked_is_main_site(hostname, props);

-- VIEW public.events_no_bots
CREATE OR REPLACE VIEW public.events_no_bots WITH (security_invoker=true) AS
 SELECT id,
    anonymous_id,
    session_id,
    name,
    url,
    path,
    hostname,
    title,
    referrer,
    referrer_hostname,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    user_agent,
    device_type,
    os,
    browser,
    viewport_width,
    viewport_height,
    props,
    occurred_at,
    received_at
   FROM events_main e
  WHERE NOT (EXISTS ( SELECT 1
           FROM bot_fingerprints b
          WHERE b.anonymous_id = e.anonymous_id));

-- VIEW public.events_outremer
CREATE OR REPLACE VIEW public.events_outremer WITH (security_invoker=true) AS
 SELECT id,
    anonymous_id,
    session_id,
    name,
    url,
    path,
    hostname,
    title,
    referrer,
    referrer_hostname,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    user_agent,
    device_type,
    os,
    browser,
    viewport_width,
    viewport_height,
    props,
    occurred_at,
    received_at
   FROM events e
  WHERE cooked_site_scope(hostname, props) = 'outremer'::text;

-- VIEW public.pont_couverture
CREATE OR REPLACE VIEW public.pont_couverture WITH (security_invoker=true) AS
 WITH envs AS (
         SELECT DISTINCT secib_dossiers.env
           FROM secib_dossiers
        UNION
         SELECT 'prod'::text
        ), d AS (
         SELECT secib_dossiers.env,
            count(*) AS dossiers,
            count(*) FILTER (WHERE COALESCE(array_length(secib_dossiers.client_emails_norm, 1), 0) > 0) AS dossiers_avec_email,
            count(*) FILTER (WHERE COALESCE(array_length(secib_dossiers.client_tels_norm, 1), 0) > 0) AS dossiers_avec_tel,
            count(*) FILTER (WHERE COALESCE(array_length(secib_dossiers.client_emails_norm, 1), 0) > 0 OR COALESCE(array_length(secib_dossiers.client_tels_norm, 1), 0) > 0) AS dossiers_avec_cle,
            max(secib_dossiers.synced_at) AS derniere_synchro
           FROM secib_dossiers
          GROUP BY secib_dossiers.env
        ), p AS (
         SELECT count(*) AS prospects,
            count(*) FILTER (WHERE crm_prospects.email_norm IS NOT NULL OR crm_prospects.tel_norm IS NOT NULL) AS prospects_avec_cle,
            count(DISTINCT COALESCE(crm_prospects.email_norm, crm_prospects.tel_norm)) AS personnes,
            ( SELECT count(*) AS count
                   FROM ( SELECT 1 AS "?column?"
                           FROM crm_prospects crm_prospects_1
                          WHERE crm_prospects_1.email_norm IS NOT NULL
                          GROUP BY crm_prospects_1.email_norm, (date_trunc('minute'::text, crm_prospects_1.occurred_at))
                         HAVING count(*) > 1) x) AS doublons_email_minute
           FROM crm_prospects
        )
 SELECT e.env,
    COALESCE(d.dossiers, 0::bigint) AS dossiers,
    COALESCE(d.dossiers_avec_cle, 0::bigint) AS dossiers_avec_cle,
        CASE
            WHEN COALESCE(d.dossiers, 0::bigint) > 0 THEN round(100.0 * d.dossiers_avec_cle::numeric / d.dossiers::numeric, 1)
            ELSE NULL::numeric
        END AS dossiers_avec_cle_pct,
    COALESCE(d.dossiers_avec_email, 0::bigint) AS dossiers_avec_email,
    COALESCE(d.dossiers_avec_tel, 0::bigint) AS dossiers_avec_tel,
    d.derniere_synchro,
    p.prospects,
    p.prospects_avec_cle,
    p.personnes,
    p.doublons_email_minute,
        CASE
            WHEN COALESCE(d.dossiers, 0::bigint) = 0 THEN 'aucun dossier ingéré dans cet env : aucun taux publiable'::text
            WHEN (100.0 * d.dossiers_avec_cle::numeric / d.dossiers::numeric) < 80::numeric THEN 'couverture < 80 % : tout taux est un plancher, le dire'::text
            ELSE 'couverture suffisante'::text
        END AS lecture
   FROM envs e
     LEFT JOIN d ON d.env = e.env
     CROSS JOIN p;

-- VIEW public.pont_prospects_dossiers
CREATE OR REPLACE VIEW public.pont_prospects_dossiers WITH (security_invoker=true) AS
 SELECT prospect_id,
    prospect_le,
    source,
    form_id,
    objet,
    page_source_path,
    cooked_aid,
    cooked_sid,
    nom,
    prenom,
    email,
    telephone,
    secib_env,
    dossier_id,
    dossier_code,
    dossier_cree_le,
    matiere_libelle,
    etat_facturable,
    facture_total_ht,
    statut,
    delai_jours,
    cle_match,
    personne_key,
    rang_personne,
    rang_dossier
   FROM pont_prospects_dossiers_env('prod'::text) pont_prospects_dossiers_env(prospect_id, prospect_le, source, form_id, objet, page_source_path, cooked_aid, cooked_sid, nom, prenom, email, telephone, secib_env, dossier_id, dossier_code, dossier_cree_le, matiere_libelle, etat_facturable, facture_total_ht, statut, delai_jours, cle_match, personne_key, rang_personne, rang_dossier);

-- SIGNATURES (122)
-- ack_alerts(p_kinds text[]) -> integer
-- alert_rule_contact_sans_amont() -> TABLE(kind text, severity text, detail text)
-- alert_rule_cron_failed() -> TABLE(kind text, severity text, detail text)
-- alert_rule_double_embed_suspect() -> TABLE(kind text, severity text, detail text)
-- alert_rule_exposure() -> TABLE(kind text, severity text, detail text)
-- alert_rule_form_attribution_degraded() -> TABLE(kind text, severity text, detail text)
-- alert_rule_freshness() -> TABLE(kind text, severity text, detail text)
-- alert_rule_gsc_ingest_missed() -> TABLE(kind text, severity text, detail text)
-- alert_rule_identity_stitch() -> TABLE(kind text, severity text, detail text)
-- alert_rule_page_taxonomy_gap() -> TABLE(kind text, severity text, detail text)
-- alert_rule_pipeline_dead() -> TABLE(kind text, severity text, detail text)
-- alert_rule_rpc_health() -> TABLE(kind text, severity text, detail text)
-- alert_rule_spam_in_events_human() -> TABLE(kind text, severity text, detail text)
-- alert_rule_tracker_drift() -> TABLE(kind text, severity text, detail text)
-- alert_rule_volume_floor() -> TABLE(kind text, severity text, detail text)
-- alert_rule_warn_escalation() -> TABLE(kind text, severity text, detail text)
-- assisted_contacts_by_entry_path(p_start date, p_end date) -> TABLE(entry_path text, contacts bigint)
-- behavior_pages_for_period(date_from timestamp with time zone, date_to timestamp with time zone) -> TABLE(path text, sessions bigint, pages_per_session numeric, avg_session_duration_s numeric, bounce_rate numeric, bounce_rate_pct numeric, scroll_depth_avg numeric, scroll_complete_pct numeric, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, ttfb_p75_ms numeric, outbound_clicks bigint)
-- canonical_path(p text) -> text
-- classify_channel(ref text, utm_source text, utm_medium text, self_host text, url text) -> text
-- content_performance(days_back integer) -> TABLE(page_type text, theme text, pages integer, sessions bigint, dwell_median numeric, scroll_median numeric, booking_intents bigint, contacts_assisted bigint, contact_rate_pct numeric)
-- conversion_journeys(days_back integer, p_end date) -> TABLE(contact_kind text, occurred_at timestamp with time zone, contact_path text, objet text, anonymous_id text, attribution_method text, entry_path text, entry_channel text, pages_count integer, journey text[], device_type text, window_start date, window_end date)
-- cooked_alerts_refresh() -> integer
-- cooked_ci_cron_jobs() -> TABLE(jobname text, schedule text, active boolean)
-- cooked_events_window(IN p_occurred_from timestamp with time zone, IN p_occurred_to timestamp with time zone, IN p_grain text, IN p_site text) -> None
-- cooked_is_chrome_anchor(props jsonb) -> boolean
-- cooked_is_main_site(hostname text, props jsonb) -> boolean
-- cooked_is_spam_referrer(p_hostname text) -> boolean
-- cooked_normalize_email(raw text) -> text
-- cooked_normalize_phone_fr(raw text) -> text
-- cooked_page_daily_series(target_path text, days_back integer, end_date date) -> TABLE(day date, sessions bigint)
-- cooked_page_type(p text) -> text
-- cooked_pages_compare(period_kind text, data_lens text) -> TABLE(path text, sessions_n bigint, sessions_prev bigint, sessions_delta_pct numeric, contacts_n bigint, contacts_prev bigint, contacts_delta_pct numeric)
-- cooked_pages_snapshot(p_period_kind text, max_rows integer) -> TABLE(path text, cooked_sessions bigint, cooked_contacts bigint, cooked_phone_clicks bigint, cooked_form_submits bigint)
-- cooked_paris_hour(p_ts timestamp with time zone) -> integer
-- cooked_paris_ts_end_exclusive(p_day date) -> timestamp with time zone
-- cooked_paris_ts_start(p_day date) -> timestamp with time zone
-- cooked_period_bounds(period_kind text, data_lens text) -> TABLE(period_kind_out text, label_fr text, n_start date, n_end date, prev_start date, prev_end date, day_count integer, paris_today date, gsc_last_day date, lag_days integer, data_lens_out text)
-- cooked_site_scope(hostname text, props jsonb) -> text
-- cooked_snapshot_window(IN p_window text, IN p_grain text, OUT o_label_fr text, OUT o_lns date, OUT o_lne date, OUT o_lps date, OUT o_lpe date, OUT o_lpt date, OUT o_ld integer, OUT o_gns date, OUT o_gne date, OUT o_gps date, OUT o_gpe date, OUT o_glast date, OUT o_glag integer) -> None
-- cooked_visit_events(p_start date, p_end date) -> TABLE(event_id uuid, event_name text, occurred_at timestamp with time zone, path text, anonymous_id text, objet text, counts_as_macro boolean, attribution_method text, visit_id uuid, entry_at timestamp with time zone, entry_path text, entry_channel text, journey text[], device_type text)
-- cooked_web_vitals_window(p_from timestamp with time zone, p_to timestamp with time zone) -> TABLE(id uuid, path text, device_type text, props jsonb, occurred_at timestamp with time zone)
-- cpi_compose(zc numeric, zr numeric, zl numeric, zv numeric, mm numeric, gg numeric, exclude_conversion boolean) -> numeric
-- cta_breakdown_for_path(path text, days_back integer) -> TABLE(cta_type text, placement text, anchor_sample text, clicks bigint)
-- ctr_for_position(pos numeric) -> numeric
-- dashboard_annotations(period_kind text) -> TABLE(day date, kind text, label text, paths text[])
-- dashboard_article_detail(p_path text, period_kind text) -> jsonb
-- dashboard_assisted_quarter() -> jsonb
-- dashboard_expertises_kpis(period_kind text) -> SETOF dashboard_expertises_kpis_snapshot
-- dashboard_expertises_overview(period_kind text, max_rows integer) -> SETOF dashboard_expertises_snapshot
-- dashboard_expertises_trend(period_kind text) -> TABLE(visitors_daily numeric[], pageviews_daily numeric[], contacts_daily numeric[], gsc_clicks_daily numeric[], gsc_impressions_daily numeric[])
-- dashboard_honoraires_funnel(period_kind text) -> TABLE(booking_sessions bigint, honoraires_sessions bigint, booking_then_honoraires bigint, forms_after_booking_6h bigint, forms_on_honoraires bigint, forms_macro_total bigint, rate_booking_to_form numeric, cooked_start date, cooked_end date)
-- dashboard_intervention_effect(p_path text, p_day date) -> jsonb
-- dashboard_lab_gsc_weekly(p_weeks integer) -> jsonb
-- dashboard_resources_assisted(period_kind text) -> TABLE(path text, assisted_contacts integer, assisted_prev integer)
-- dashboard_resources_cohorts() -> jsonb
-- dashboard_resources_kpis(period_kind text) -> SETOF dashboard_kpis_snapshot
-- dashboard_resources_overview(period_kind text, max_rows integer) -> SETOF dashboard_resources_snapshot
-- dashboard_resources_trend(period_kind text) -> TABLE(visitors_daily numeric[], pageviews_daily numeric[], contacts_daily numeric[], gsc_clicks_daily numeric[], gsc_impressions_daily numeric[])
-- dashboard_seo_by_query(period_kind text, scope text, min_volume integer, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, nb_pages integer, top_page text, top_page_clicks bigint, top_page_theme text, volume_fr integer, cpc numeric, competition_level text, capture_pct numeric, is_quick_win boolean, clicks_prev bigint, position_prev numeric, ctr_expected numeric, opportunity_clicks numeric, gsc_start date, gsc_end date)
-- dashboard_seo_kpis(period_kind text, scope text) -> TABLE(total_queries bigint, total_quick_wins bigint, clicks_named_nonbranded bigint, clicks_path_total bigint, impressions_path_total bigint, gsc_start date, gsc_end date)
-- dfs_keywords_to_sync(limit_n integer) -> TABLE(keyword text, clicks_total bigint)
-- engagement_density_for_path(target_path text, days integer) -> TABLE(sessions bigint, dwell_p25 numeric, dwell_median numeric, dwell_p75 numeric, evenness_score numeric)
-- form_submission_counts_for_period(p_start date, p_end date) -> TABLE(day date, submissions bigint)
-- form_submit_counts_as_macro(props jsonb) -> boolean
-- form_submits_attributed(days_back integer, p_end date) -> TABLE(event_id uuid, occurred_at timestamp with time zone, form_path text, objet text, counts_as_macro boolean, resolved_anonymous_id text, resolved_session_id text, attribution_method text, window_start date, window_end date)
-- form_submits_per_path(start_date date, end_date date) -> TABLE(path text, form_submits bigint)
-- gsc_ingest_begin(p_run_id uuid, p_start date, p_end date) -> uuid
-- gsc_ingest_complete(p_run_id uuid, p_row_counts jsonb) -> void
-- gsc_ingest_fail(p_run_id uuid) -> void
-- gsc_is_branded(p_query text) -> boolean
-- gsc_last_data_day() -> date
-- gsc_page_daily_series(target_path text, days_back integer, end_date date) -> TABLE(day date, clicks bigint)
-- gsc_page_performance(target_path text, period_kind text) -> TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_views bigint, cooked_unique_visitors bigint, cooked_bounce_rate numeric, cooked_dwell_avg_s numeric, cooked_scroll_median numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, cooked_google_sessions bigint, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, top_referrer text, device_split jsonb)
-- gsc_pages_compare(period_kind text, data_lens text) -> TABLE(path text, clicks_n bigint, clicks_prev bigint, clicks_delta_pct numeric, impressions_n bigint, impressions_prev bigint, impressions_delta_pct numeric, position_avg_n numeric, position_avg_prev numeric)
-- gsc_pages_overview(max_rows integer) -> TABLE(path text, gsc_clicks_28d bigint, gsc_impressions_28d bigint, gsc_position_avg_28d numeric, gsc_ctr_pct_28d numeric, cooked_sessions_28d bigint, cooked_dwell_avg_s_28d numeric, cooked_bounce_rate_28d numeric, cooked_phone_clicks_28d bigint, cooked_form_submits_28d bigint, cooked_contacts_28d bigint, cooked_booking_intent_28d bigint, cooked_pogo_rate_28d numeric, has_cooked_data boolean)
-- gsc_path_metrics(start_date date, end_date date) -> TABLE(path text, impressions_total bigint, clicks_total bigint, position_avg numeric, ctr_pct numeric)
-- gsc_top_queries_for_path(target_path text, p_period_kind text, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, days_in_period integer)
-- gsc_top_queries_global(period_kind text, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, nb_pages_targeted integer, top_page text, top_page_clicks bigint, volume_fr integer, cpc numeric, click_yield_pct numeric)
-- gsc_x_dfs_opportunities(min_volume integer, position_min numeric, position_max numeric, period_kind text, max_rows integer) -> TABLE(query text, our_position numeric, our_clicks bigint, our_impressions bigint, our_ctr_pct numeric, volume_fr integer, cpc numeric, estimated_ctr_pos_1 numeric, lost_potential integer, top_page text)
-- latest_rpc_health() -> TABLE(rpc_name text, status text, detail text, rows_returned bigint, duration_ms numeric, checked_at timestamp with time zone, age_minutes numeric)
-- macro_contacts_by_path(start_date date, end_date date) -> TABLE(path text, phone_clicks bigint, form_submits bigint, contacts bigint, booking_intent bigint)
-- outbound_destinations_for_path(path text, days_back integer) -> TABLE(hostname text, clicks bigint)
-- page_taxonomy_sync_wix(p_posts jsonb, p_dry_run boolean) -> TABLE(inserted integer, updated integer, unpublished integer, inserted_paths text[], updated_paths text[])
-- page_taxonomy_theme_from_slug(p_path text) -> text
-- page_visits(p_start date, p_end date) -> TABLE(row_kind text, path text, visits bigint, entries bigint, phone_visits bigint, form_visits bigint, contact_visits bigint, contact_rate_pct numeric, observed_days integer, unattributed_phone_events bigint, unattributed_form_events bigint)
-- pages_overview_unified(period_kind text, max_rows integer) -> TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_dwell_avg_s numeric, cooked_bounce_rate numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, has_cooked_data boolean)
-- pages_pulse(period_kind text, delta_threshold_pct numeric) -> TABLE(path text, gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_delta_pct numeric, cooked_sessions_n bigint, cooked_sessions_prev bigint, cooked_sessions_delta_pct numeric, quadrant text)
-- paris_date(ts timestamp with time zone) -> date
-- paris_today() -> date
-- pogo_rates_for_period(date_from timestamp with time zone, date_to timestamp with time zone) -> TABLE(path text, google_sessions bigint, pogo_sticks bigint, hard_pogo bigint, pogo_rate numeric)
-- pont_prospects_dossiers_env(p_env text) -> TABLE(prospect_id bigint, prospect_le timestamp with time zone, source text, form_id text, objet text, page_source_path text, cooked_aid text, cooked_sid text, nom text, prenom text, email text, telephone text, secib_env text, dossier_id integer, dossier_code text, dossier_cree_le timestamp with time zone, matiere_libelle text, etat_facturable text, facture_total_ht numeric, statut text, delai_jours numeric, cle_match text, personne_key text, rang_personne integer, rang_dossier integer)
-- pulse_quadrant(gsc_dir text, cooked_dir text) -> text
-- pulse_status(gsc_n bigint, gsc_prev bigint, cooked_n bigint, cooked_prev bigint, delta_threshold numeric) -> text
-- purge_cooked_noise(retain_days integer) -> TABLE(events_purged bigint, noise_sessions_purged bigint)
-- purge_old_events() -> TABLE(deleted_rows bigint, size_before text, size_after text, duration_ms numeric)
-- raise_cooked_alert(p_kind text, p_sev text, p_detail text) -> integer
-- record_ingest_drop(p_reason text, p_n integer) -> void
-- refresh_bot_fingerprints() -> void
-- refresh_identity_stitch(p_days integer) -> void
-- refresh_noise_sessions() -> void
-- refresh_page_taxonomy_heuristic() -> integer
-- refresh_pipeline_health() -> TABLE(status text, snapshot_refreshed_at timestamp with time zone, snapshot_age_hours numeric, cron_last_status text, cron_last_run timestamp with time zone, cron_age_hours numeric, last_event_at timestamp with time zone, last_event_age_minutes numeric, events_last_60min bigint, gsc_last_day date, gsc_data_age_days numeric, gsc_last_ingest timestamp with time zone, gsc_ingest_age_hours numeric, dfs_last_synced_at timestamp with time zone, dfs_row_count bigint, dfs_sync_age_hours numeric, issues text[])
-- rls_auto_enable() -> event_trigger
-- rpc_contract_check(p_name text, p_sql text, p_min_rows integer, p_exact_rows integer) -> void
-- run_rpc_contract_tests() -> void
-- seo_pages_overview(date_from timestamp with time zone, date_to timestamp with time zone) -> TABLE(path text, views bigint, unique_visitors bigint, sessions bigint, bounce_rate numeric, bounce_rate_pct numeric, avg_dwell_seconds numeric, scroll_avg numeric, scroll_median numeric, scroll_complete_pct numeric, entry_count bigint, exit_count bigint, outbound_clicks bigint)
-- seo_to_contact_funnel(days_back integer, p_end date) -> TABLE(entry_path text, page_type text, theme text, gsc_impressions bigint, gsc_clicks bigint, top_queries text[], organic_entries bigint, contacts bigint, contacts_phone bigint, contacts_form bigint, contact_rate_pct numeric, window_start date, window_end date)
-- site_context_export() -> TABLE(global_sessions_28d bigint, global_bounce_rate_28d numeric, sessions_per_day_median_28d numeric, sessions_trend_pct_7d_vs_28d numeric, top_sources_28d jsonb, global_bounce_rate_pct numeric)
-- site_gsc_kpis_compare(p_period_kind text) -> TABLE(period_kind text, period_label_fr text, period_n_start date, period_n_end date, paris_today date, gsc_last_day date, lag_days integer, period_prev_start date, period_prev_end date, clicks_n bigint, impressions_n bigint, ctr_pct_n numeric, position_avg_n numeric, clicks_prev bigint, impressions_prev bigint, ctr_pct_prev numeric, position_avg_prev numeric, clicks_delta_pct numeric, impressions_delta_pct numeric)
-- site_kpis_compare(p_period_kind text) -> TABLE(period_kind text, period_label_fr text, period_n_start date, period_n_end date, tracker_first_seen date, is_partial_period boolean, sessions_n bigint, pageviews_n bigint, phone_clicks_n bigint, form_submits_n bigint, macro_conversions_n bigint, period_prev_start date, period_prev_end date, sessions_prev bigint, pageviews_prev bigint, phone_clicks_prev bigint, form_submits_prev bigint, macro_conversions_prev bigint, sessions_delta_pct numeric, pageviews_delta_pct numeric, phone_clicks_delta_pct numeric, form_submits_delta_pct numeric, macro_conversions_delta_pct numeric)
-- site_macro_counts(start_date date, end_date date) -> TABLE(phone_clicks bigint, form_submits bigint, macro_conversions bigint)
-- site_pulse(p_period_kind text, delta_threshold_pct numeric) -> TABLE(period_kind text, period_label_fr text, gsc_period_start date, gsc_period_end date, cooked_period_start date, cooked_period_end date, gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_delta_pct numeric, cooked_sessions_n bigint, cooked_sessions_prev bigint, cooked_sessions_delta_pct numeric, quadrant text)
-- snapshot_pages_export(paths text[]) -> TABLE(path text, views_7d bigint, unique_visitors_7d bigint, sessions_7d bigint, bounce_rate_7d numeric, avg_dwell_seconds_7d numeric, scroll_avg_7d numeric, scroll_median_7d numeric, scroll_complete_pct_7d numeric, entry_count_7d bigint, exit_count_7d bigint, outbound_clicks_7d bigint, views_28d bigint, unique_visitors_28d bigint, sessions_28d bigint, bounce_rate_28d numeric, avg_dwell_seconds_28d numeric, scroll_avg_28d numeric, scroll_median_28d numeric, scroll_complete_pct_28d numeric, entry_count_28d bigint, exit_count_28d bigint, outbound_clicks_28d bigint, views_90d bigint, unique_visitors_90d bigint, sessions_90d bigint, bounce_rate_90d numeric, avg_dwell_seconds_90d numeric, scroll_avg_90d numeric, scroll_median_90d numeric, scroll_complete_pct_90d numeric, entry_count_90d bigint, exit_count_90d bigint, outbound_clicks_90d bigint, views_365d bigint, unique_visitors_365d bigint, sessions_365d bigint, bounce_rate_365d numeric, avg_dwell_seconds_365d numeric, scroll_avg_365d numeric, scroll_median_365d numeric, scroll_complete_pct_365d numeric, entry_count_365d bigint, exit_count_365d bigint, outbound_clicks_365d bigint, lcp_p75_28d_ms numeric, inp_p75_28d_ms numeric, cls_p75_28d numeric, ttfb_p75_28d_ms numeric, top_referrer_28d text, top_source_28d text, top_medium_28d text, device_split_28d jsonb, refreshed_at timestamp with time zone, phone_clicks_7d bigint, phone_clicks_28d bigint, phone_clicks_90d bigint, phone_clicks_365d bigint, email_clicks_7d bigint, email_clicks_28d bigint, email_clicks_90d bigint, email_clicks_365d bigint, booking_cta_clicks_7d bigint, booking_cta_clicks_28d bigint, booking_cta_clicks_90d bigint, booking_cta_clicks_365d bigint, google_sessions_28d bigint, pogo_sticks_28d bigint, hard_pogo_28d bigint, pogo_rate_28d numeric, mobile_sessions_28d bigint, desktop_sessions_28d bigint, cta_rate_mobile_28d numeric, cta_rate_desktop_28d numeric)
-- top_contact_pages(p_period_kind text, max_rows integer) -> TABLE(path text, cooked_contacts bigint, cooked_phone_clicks bigint, cooked_form_submits bigint, gsc_clicks bigint, cooked_sessions bigint)
-- tracker_first_seen_global() -> timestamp with time zone
-- tracker_version_distribution(hours_back integer) -> TABLE(version text, events bigint, sessions bigint, first_seen timestamp with time zone, last_seen timestamp with time zone, share_pct numeric)
-- unaccent(regdictionary, text) -> text
-- unaccent(text) -> text
-- unaccent_init(internal) -> internal
-- unaccent_lexize(internal, internal, internal, internal) -> internal
-- url_decode(input text) -> text
