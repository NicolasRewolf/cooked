-- supabase/views.sql — CATALOGUE DE RÉFÉRENCE (généré, LECTURE SEULE)
-- Ne pas rejouer comme source d'un déploiement. Ne pas éditer à la main.
-- Source DDL : supabase/migrations/*.sql et état prod.
-- Corps des routines : supabase/rpcs.sql.
-- Généré depuis pg_get_viewdef, pg_get_function_identity_arguments et
-- pg_get_function_result, avec reloptions effectives le 04/11/2026.
-- Projet mxycmjkeotrycyneacje. Socle minimal : événements humains et sources directes.

-- VUES (3)

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

-- SIGNATURES (61)
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
-- canonical_path(p text) -> text
-- cooked_alerts_refresh() -> integer
-- cooked_ci_cron_jobs() -> TABLE(jobname text, schedule text, active boolean)
-- cooked_is_chrome_anchor(props jsonb) -> boolean
-- cooked_is_main_site(hostname text, props jsonb) -> boolean
-- cooked_is_spam_referrer(p_hostname text) -> boolean
-- cooked_page_type(p text) -> text
-- cooked_paris_hour(p_ts timestamp with time zone) -> integer
-- cooked_paris_ts_end_exclusive(p_day date) -> timestamp with time zone
-- cooked_paris_ts_start(p_day date) -> timestamp with time zone
-- cooked_period_bounds(period_kind text, data_lens text) -> TABLE(period_kind_out text, label_fr text, n_start date, n_end date, prev_start date, prev_end date, day_count integer, paris_today date, gsc_last_day date, lag_days integer, data_lens_out text)
-- cooked_visit_events(p_start date, p_end date) -> TABLE(event_id uuid, event_name text, occurred_at timestamp with time zone, path text, counts_as_macro boolean, visit_id uuid, entry_at timestamp with time zone, entry_path text)
-- form_submission_counts_for_period(p_start date, p_end date) -> TABLE(day date, submissions bigint)
-- form_submit_counts_as_macro(props jsonb) -> boolean
-- gsc_ingest_begin(p_run_id uuid, p_start date, p_end date) -> uuid
-- gsc_ingest_complete(p_run_id uuid, p_row_counts jsonb) -> void
-- gsc_ingest_fail(p_run_id uuid) -> void
-- gsc_last_data_day() -> date
-- gsc_path_metrics(start_date date, end_date date) -> TABLE(path text, impressions_total bigint, clicks_total bigint, position_avg numeric, ctr_pct numeric)
-- gsc_top_queries_for_path(target_path text, p_period_kind text, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, days_in_period integer)
-- latest_rpc_health() -> TABLE(rpc_name text, status text, detail text, rows_returned bigint, duration_ms numeric, checked_at timestamp with time zone, age_minutes numeric)
-- page_query_counts(p_path text, p_days integer) -> jsonb
-- page_taxonomy_sync_wix(p_posts jsonb, p_dry_run boolean) -> TABLE(inserted integer, updated integer, unpublished integer, inserted_paths text[], updated_paths text[])
-- page_taxonomy_theme_from_slug(p_path text) -> text
-- page_view_counts(p_days integer) -> jsonb
-- page_visits(p_start date, p_end date) -> TABLE(row_kind text, path text, visits bigint, entries bigint, phone_visits bigint, form_visits bigint, contact_visits bigint, contact_rate_pct numeric, observed_days integer, unattributed_phone_events bigint, unattributed_form_events bigint)
-- paris_date(ts timestamp with time zone) -> date
-- paris_today() -> date
-- purge_cooked_noise(retain_days integer) -> TABLE(events_purged bigint, noise_sessions_purged bigint)
-- purge_old_events() -> TABLE(deleted_rows bigint, size_before text, size_after text, duration_ms numeric)
-- raise_cooked_alert(p_kind text, p_sev text, p_detail text) -> integer
-- record_ingest_drop(p_reason text, p_n integer) -> void
-- refresh_bot_fingerprints() -> void
-- refresh_identity_stitch(p_days integer) -> void
-- refresh_noise_sessions() -> void
-- refresh_pipeline_health() -> TABLE(status text, last_event_at timestamp with time zone, last_event_age_minutes numeric, events_last_60min bigint, gsc_last_day date, gsc_data_age_days numeric, gsc_last_ingest timestamp with time zone, gsc_ingest_age_hours numeric, issues text[])
-- rls_auto_enable() -> event_trigger
-- rpc_contract_check(p_name text, p_sql text, p_min_rows integer, p_exact_rows integer) -> void
-- run_rpc_contract_tests() -> void
-- tracker_version_distribution(hours_back integer) -> TABLE(version text, events bigint, sessions bigint, first_seen timestamp with time zone, last_seen timestamp with time zone, share_pct numeric)
-- unaccent(regdictionary, text) -> text
-- unaccent(text) -> text
-- unaccent_init(internal) -> internal
-- unaccent_lexize(internal, internal, internal, internal) -> internal
-- url_decode(input text) -> text
