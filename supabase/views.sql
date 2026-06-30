-- ============================================================================
-- supabase/views.sql — CATALOGUE DE RÉFÉRENCE (généré, LECTURE SEULE)
--
-- ⚠️  NE PAS REJOUER COMME SOURCE D'UN DÉPLOIEMENT. NE PAS ÉDITER À LA MAIN.
--
-- Source de vérité du DDL = supabase/migrations/*.sql (+ l'état prod, qui
-- reste l'arbitre — le dossier migrations local n'est pas un miroir complet).
--
-- Ce fichier est un INSTANTANÉ LISIBLE de l'état prod (projet
-- mxycmjkeotrycyneacje) au 30/06/2026 :
--   • définition COMPLÈTE des 5 vues publiques ;
--   • SIGNATURES des 70 fonctions / RPC publiques (le corps vit dans les
--     migrations — on ne le duplique plus ici : c'était la cause du drift,
--     l'ancien views.sql était figé au Sprint 37, ~40 migrations de retard).
--
-- Régénérer (MCP Supabase execute_sql, ou psql) : voir les 2 requêtes en bas.
-- ============================================================================


-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║ VUES (5) — définition complète                                            ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- VIEW public.cpi_gisement
--   Pilotage conversion (Sprint 39) : relit le dernier cpi_daily, sépare le
--   potentiel (capture+rétention+lecture, hors conversion) du badge convertit.
CREATE OR REPLACE VIEW public.cpi_gisement AS
 SELECT path,
    ptype,
    grade,
    n_org,
    cpi,
    round(100::numeric * (1::numeric / (1::numeric + exp((- (0.46 * zc + 0.23 * zr + 0.20 / 0.65 * zl)) / 0.8))) * momentum * gate)::integer AS potentiel,
    zv > 0::numeric AS convertit,
    zc,
    zr,
    zl,
    zv,
    day
   FROM cpi_daily
  WHERE day = (( SELECT max(cpi_daily_1.day) AS max
           FROM cpi_daily cpi_daily_1));

-- VIEW public.cpi_movers
--   Δ CPI sur ~7j glissants depuis cpi_daily (statuts present/nouveau/disparu,
--   fiable = grade A/B aux deux dates, delta_z par composante).
CREATE OR REPLACE VIEW public.cpi_movers AS
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
         SELECT c.day, c.path, c.ptype, c.grade, c.cpi, c.cpi_raw, c.momentum,
            c.gate, c.zc, c.zr, c.zl, c.zv, c.clics_perdus, c.n_org,
            c.couv_gsc_pct, c.created_at
           FROM cpi_daily c
             JOIN bounds b_1 ON c.day = b_1.d1
        ), ref_rows AS (
         SELECT c.day, c.path, c.ptype, c.grade, c.cpi, c.cpi_raw, c.momentum,
            c.gate, c.zc, c.zr, c.zl, c.zv, c.clics_perdus, c.n_org,
            c.couv_gsc_pct, c.created_at
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
    COALESCE((n.grade = ANY (ARRAY['A'::text, 'B'::text])) AND (p.grade = ANY (ARRAY['A'::text, 'B'::text])), false) AS fiable,
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

-- VIEW public.events_human
--   Base canonique des analyses : events_no_bots MINUS noise_sessions, MINUS
--   chrome anchors (Sprint 35), MINUS clics dupliqués même-seconde (Sprint 37).
CREATE OR REPLACE VIEW public.events_human AS
 SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer,
    referrer_hostname, utm_source, utm_medium, utm_campaign, utm_term, utm_content,
    user_agent, device_type, os, browser, viewport_width, viewport_height, country,
    props, occurred_at, received_at
   FROM events_no_bots e
  WHERE NOT (EXISTS ( SELECT 1
           FROM noise_sessions n
          WHERE n.session_id = e.session_id))
    AND NOT (name = 'cta_anchor_click'::text AND cooked_is_chrome_anchor(props))
    AND NOT ((name = ANY (ARRAY['cta_phone_click'::text, 'cta_booking_click'::text, 'cta_anchor_click'::text, 'click_internal'::text, 'click_outbound'::text]))
      AND (EXISTS ( SELECT 1
           FROM events d
          WHERE d.session_id = e.session_id AND d.name = e.name
            AND NOT d.path IS DISTINCT FROM e.path
            AND date_trunc('second'::text, d.occurred_at) = date_trunc('second'::text, e.occurred_at)
            AND NOT (d.props ->> 'anchor'::text) IS DISTINCT FROM (e.props ->> 'anchor'::text)
            AND d.id < e.id)));

-- VIEW public.events_no_bots
--   events MINUS bot_fingerprints (1er niveau du filet anti-bot, Sprint 17).
CREATE OR REPLACE VIEW public.events_no_bots AS
 SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer,
    referrer_hostname, utm_source, utm_medium, utm_campaign, utm_term, utm_content,
    user_agent, device_type, os, browser, viewport_width, viewport_height, country,
    props, occurred_at, received_at
   FROM events e
  WHERE NOT (EXISTS ( SELECT 1
           FROM bot_fingerprints b
          WHERE b.anonymous_id = e.anonymous_id));

-- VIEW public.gsc_path_metrics_28d
--   Raccourci 28j glissants sur gsc_path_metrics (fenêtre Paris).
CREATE OR REPLACE VIEW public.gsc_path_metrics_28d AS
 SELECT path, impressions_total, clicks_total, position_avg, ctr_pct
   FROM gsc_path_metrics(((now() AT TIME ZONE 'Europe/Paris'::text)::date - '28 days'::interval)::date, (now() AT TIME ZONE 'Europe/Paris'::text)::date) gsc_path_metrics(path, impressions_total, clicks_total, position_avg, ctr_pct);


-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║ FONCTIONS / RPC publiques (70) — SIGNATURES                               ║
-- ║ Corps complet : voir supabase/migrations/ (source de vérité).             ║
-- ║ Format : nom(args) -> type de retour                                      ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- behavior_pages_for_period(date_from timestamp with time zone, date_to timestamp with time zone) -> TABLE(path text, sessions bigint, pages_per_session numeric, avg_session_duration_s numeric, bounce_rate numeric, scroll_depth_avg numeric, scroll_complete_pct numeric, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, ttfb_p75_ms numeric, outbound_clicks bigint)
-- canonical_path(p text) -> text
-- classify_channel(ref text, utm_source text, utm_medium text, self_host text) -> text
-- content_performance(days_back integer) -> TABLE(page_type text, theme text, pages integer, sessions bigint, dwell_median numeric, scroll_median numeric, booking_intents bigint, contacts_assisted bigint, contact_rate_pct numeric)
-- conversion_journeys(days_back integer) -> TABLE(contact_kind text, occurred_at timestamp with time zone, contact_path text, objet text, anonymous_id text, attribution_method text, entry_path text, entry_channel text, pages_count integer, journey text[], device_type text)
-- cooked_alerts_refresh() -> integer
-- cooked_cpi_snapshot() -> void
-- cooked_is_chrome_anchor(props jsonb) -> boolean
-- cooked_page_daily_series(target_path text, days_back integer, end_date date) -> TABLE(day date, sessions bigint)
-- cooked_page_index(p_days integer) -> TABLE(path text, ptype text, grade text, cpi integer, cpi_raw integer, momentum numeric, momentum_badge text, gate numeric, zc numeric, zr numeric, zl numeric, zv numeric, clics_perdus integer, n_org bigint, couv_gsc_pct integer)
-- cooked_page_type(p text) -> text
-- cooked_pages_compare(period_kind text, data_lens text) -> TABLE(path text, sessions_n bigint, sessions_prev bigint, sessions_delta_pct numeric, contacts_n bigint, contacts_prev bigint, contacts_delta_pct numeric)
-- cooked_pages_snapshot(p_period_kind text, max_rows integer) -> TABLE(path text, cooked_sessions bigint, cooked_contacts bigint, cooked_phone_clicks bigint, cooked_form_submits bigint)
-- cooked_period_bounds(period_kind text, data_lens text) -> TABLE(period_kind_out text, label_fr text, n_start date, n_end date, prev_start date, prev_end date, day_count integer, paris_today date, gsc_last_day date, lag_days integer, data_lens_out text)
-- cta_breakdown_for_path(path text, days_back integer) -> TABLE(cta_type text, placement text, anchor_sample text, clicks bigint)
-- ctr_for_position(pos numeric) -> numeric
-- dashboard_check_stale() -> void
-- dashboard_resources_kpis(period_kind text) -> SETOF dashboard_kpis_snapshot
-- dashboard_resources_overview(period_kind text, max_rows integer) -> SETOF dashboard_resources_snapshot
-- dashboard_seo_by_query(period_kind text, scope text, min_volume integer, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, nb_pages integer, top_page text, top_page_clicks bigint, top_page_theme text, volume_fr integer, cpc numeric, competition_level text, capture_pct numeric, is_quick_win boolean, gsc_start date, gsc_end date)
-- dashboard_seo_kpis(period_kind text, scope text) -> TABLE(total_queries bigint, total_quick_wins bigint, clicks_named_nonbranded bigint, clicks_path_total bigint, impressions_path_total bigint, gsc_start date, gsc_end date)
-- dfs_keywords_to_sync(limit_n integer) -> TABLE(keyword text, clicks_total bigint)
-- engagement_density_for_path(target_path text, days integer) -> TABLE(sessions bigint, dwell_p25 numeric, dwell_median numeric, dwell_p75 numeric, evenness_score numeric)
-- form_submit_counts_as_macro(props jsonb) -> boolean
-- form_submits_attributed(days_back integer) -> TABLE(event_id uuid, occurred_at timestamp with time zone, form_path text, objet text, counts_as_macro boolean, resolved_anonymous_id text, resolved_session_id text, attribution_method text)
-- form_submits_per_path(start_date date, end_date date) -> TABLE(path text, form_submits bigint)
-- gsc_last_data_day() -> date
-- gsc_page_daily_series(target_path text, days_back integer, end_date date) -> TABLE(day date, clicks bigint)
-- gsc_page_performance(target_path text, period_kind text) -> TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_views bigint, cooked_unique_visitors bigint, cooked_bounce_rate numeric, cooked_dwell_avg_s numeric, cooked_scroll_median numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, cooked_google_sessions bigint, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, top_referrer text, device_split jsonb)
-- gsc_pages_compare(period_kind text, data_lens text) -> TABLE(path text, clicks_n bigint, clicks_prev bigint, clicks_delta_pct numeric, impressions_n bigint, impressions_prev bigint, impressions_delta_pct numeric, position_avg_n numeric, position_avg_prev numeric)
-- gsc_pages_overview(max_rows integer) -> TABLE(path text, gsc_clicks_28d bigint, gsc_impressions_28d bigint, gsc_position_avg_28d numeric, gsc_ctr_pct_28d numeric, cooked_sessions_28d bigint, cooked_dwell_avg_s_28d numeric, cooked_bounce_rate_28d numeric, cooked_phone_clicks_28d bigint, cooked_form_submits_28d bigint, cooked_contacts_28d bigint, cooked_booking_intent_28d bigint, cooked_pogo_rate_28d numeric, has_cooked_data boolean)
-- gsc_path_metrics(start_date date, end_date date) -> TABLE(path text, impressions_total bigint, clicks_total bigint, position_avg numeric, ctr_pct numeric)
-- gsc_top_queries_for_path(target_path text, days_back integer, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, days_in_period integer)
-- gsc_top_queries_for_path(target_path text, p_period_kind text, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, days_in_period integer)
-- gsc_top_queries_global(period_kind text, max_rows integer) -> TABLE(query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric, nb_pages_targeted integer, top_page text, top_page_clicks bigint, volume_fr integer, cpc numeric, click_yield_pct numeric)
-- gsc_x_dfs_opportunities(min_volume integer, position_min numeric, position_max numeric, period_kind text, max_rows integer) -> TABLE(query text, our_position numeric, our_clicks bigint, our_impressions bigint, our_ctr_pct numeric, volume_fr integer, cpc numeric, estimated_ctr_pos_1 numeric, lost_potential integer, top_page text)
-- latest_rpc_health() -> TABLE(rpc_name text, status text, detail text, rows_returned bigint, duration_ms numeric, checked_at timestamp with time zone, age_minutes numeric)
-- macro_contacts_by_path(days_back integer) -> TABLE(path text, phone_clicks bigint, form_submits bigint, contacts bigint, booking_intent bigint)
-- macro_contacts_by_path(start_date date, end_date date) -> TABLE(path text, phone_clicks bigint, form_submits bigint, contacts bigint, booking_intent bigint)
-- outbound_destinations_for_path(path text, days_back integer) -> TABLE(hostname text, clicks bigint)
-- pages_overview_unified(period_kind text, max_rows integer) -> TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_dwell_avg_s numeric, cooked_bounce_rate numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, has_cooked_data boolean)
-- pages_pulse(period_kind text, delta_threshold_pct numeric) -> TABLE(path text, gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_delta_pct numeric, cooked_sessions_n bigint, cooked_sessions_prev bigint, cooked_sessions_delta_pct numeric, quadrant text)
-- paris_date(ts timestamp with time zone) -> date
-- paris_today() -> date
-- pogo_rates_for_period(date_from timestamp with time zone, date_to timestamp with time zone) -> TABLE(path text, google_sessions bigint, pogo_sticks bigint, hard_pogo bigint, pogo_rate numeric)
-- pulse_quadrant(gsc_dir text, cooked_dir text) -> text
-- pulse_status(gsc_n bigint, gsc_prev bigint, cooked_n bigint, cooked_prev bigint, delta_threshold numeric) -> text
-- purge_old_events() -> TABLE(deleted_rows bigint, size_before text, size_after text, duration_ms numeric)
-- raise_cooked_alert(p_kind text, p_sev text, p_detail text) -> integer
-- refresh_bot_fingerprints() -> void
-- refresh_dashboard_snapshots(p_window text) -> void
-- refresh_noise_sessions() -> void
-- refresh_page_taxonomy_heuristic() -> integer
-- refresh_pipeline_health() -> TABLE(status text, snapshot_refreshed_at timestamp with time zone, snapshot_age_hours numeric, cron_last_status text, cron_last_run timestamp with time zone, cron_age_hours numeric, last_event_at timestamp with time zone, last_event_age_minutes numeric, events_last_60min bigint, gsc_last_day date, gsc_data_age_days numeric, gsc_last_ingest timestamp with time zone, gsc_ingest_age_hours numeric, dfs_last_synced_at timestamp with time zone, dfs_row_count bigint, dfs_sync_age_hours numeric, issues text[])
-- refresh_seo_url_snapshot() -> void
-- rls_auto_enable() -> event_trigger
-- run_rpc_contract_tests() -> void
-- seo_pages_overview(date_from timestamp with time zone, date_to timestamp with time zone) -> TABLE(path text, views bigint, unique_visitors bigint, sessions bigint, bounce_rate numeric, avg_dwell_seconds numeric, scroll_avg numeric, scroll_median numeric, scroll_complete_pct numeric, entry_count bigint, exit_count bigint, outbound_clicks bigint)
-- seo_to_contact_funnel(days_back integer) -> TABLE(entry_path text, page_type text, theme text, gsc_impressions bigint, gsc_clicks bigint, top_queries text[], organic_entries bigint, contacts bigint, contacts_phone bigint, contacts_form bigint, contact_rate_pct numeric)
-- site_context_export() -> TABLE(global_sessions_28d bigint, global_bounce_rate_28d numeric, sessions_per_day_median_28d numeric, sessions_trend_pct_7d_vs_28d numeric, top_sources_28d jsonb)
-- site_gsc_kpis_compare(p_period_kind text) -> TABLE(period_kind text, period_label_fr text, period_n_start date, period_n_end date, paris_today date, gsc_last_day date, lag_days integer, period_prev_start date, period_prev_end date, clicks_n bigint, impressions_n bigint, ctr_pct_n numeric, position_avg_n numeric, clicks_prev bigint, impressions_prev bigint, ctr_pct_prev numeric, position_avg_prev numeric, clicks_delta_pct numeric, impressions_delta_pct numeric)
-- site_kpis_compare(p_period_kind text) -> TABLE(period_kind text, period_label_fr text, period_n_start date, period_n_end date, tracker_first_seen date, is_partial_period boolean, sessions_n bigint, pageviews_n bigint, phone_clicks_n bigint, form_submits_n bigint, macro_conversions_n bigint, period_prev_start date, period_prev_end date, sessions_prev bigint, pageviews_prev bigint, phone_clicks_prev bigint, form_submits_prev bigint, macro_conversions_prev bigint, sessions_delta_pct numeric, pageviews_delta_pct numeric, phone_clicks_delta_pct numeric, form_submits_delta_pct numeric, macro_conversions_delta_pct numeric)
-- site_macro_counts(start_date date, end_date date) -> TABLE(phone_clicks bigint, form_submits bigint, macro_conversions bigint)
-- site_pulse(p_period_kind text, delta_threshold_pct numeric) -> TABLE(period_kind text, period_label_fr text, gsc_period_start date, gsc_period_end date, cooked_period_start date, cooked_period_end date, gsc_clicks_n bigint, gsc_clicks_prev bigint, gsc_delta_pct numeric, cooked_sessions_n bigint, cooked_sessions_prev bigint, cooked_sessions_delta_pct numeric, quadrant text)
-- site_seo_funnel(period_kind text) -> TABLE(period_start date, period_end date, impressions bigint, clicks bigint, google_sessions bigint, macro_contacts bigint, impr_to_click_pct numeric, click_to_session_pct numeric, session_to_contact_pct numeric, overall_impr_to_contact_pct numeric)
-- snapshot_pages_export(paths text[]) -> TABLE(... 70 colonnes : 4 fenêtres × metrics + CWV + provenance + device + CTAs + pogo ; les colonnes email_clicks_* renvoient 0::bigint depuis le Sprint 30, conservées pour le contrat)
-- top_contact_pages(p_period_kind text, max_rows integer) -> TABLE(path text, cooked_contacts bigint, cooked_phone_clicks bigint, cooked_form_submits bigint, gsc_clicks bigint, cooked_sessions bigint)
-- tracker_first_seen_global() -> timestamp with time zone
-- tracker_version_distribution(hours_back integer) -> TABLE(version text, events bigint, sessions bigint, first_seen timestamp with time zone, last_seen timestamp with time zone, share_pct numeric)
-- url_decode(input text) -> text


-- ============================================================================
-- RÉGÉNÉRATION (état prod → ce fichier). Lancer via MCP Supabase execute_sql :
--
-- 1) Vues (DDL complet) :
--    SELECT string_agg(format(E'-- VIEW public.%s\nCREATE OR REPLACE VIEW public.%s AS\n%s\n',
--             c.relname, c.relname, pg_get_viewdef(c.oid, true)), E'\n' ORDER BY c.relname)
--    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
--    WHERE n.nspname='public' AND c.relkind='v';
--
-- 2) Fonctions (signatures) :
--    SELECT string_agg(format('%s(%s) -> %s', p.proname,
--             pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid)),
--             E'\n' ORDER BY p.proname)
--    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--    WHERE n.nspname='public' AND p.prokind='f';
--
-- Pour le CORPS d'une fonction : SELECT pg_get_functiondef('public.<nom>(<args>)'::regprocedure);
-- Généré le 30/06/2026 — projet mxycmjkeotrycyneacje.
-- ============================================================================
