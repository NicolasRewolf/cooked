| routine | dashboard | scripts/tests | workflows | edge | cron | appelants RPC | vues | mentions docs | appelants |
|---|---|---|---|---|---|---|---|---|---|
| alert_rule_cpi_drop | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | alerts_refresh (dynamique) |
| alert_rule_cron_failed | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | alerts_refresh (dynamique) |
| alert_rule_double_embed_suspect | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | alerts_refresh (dynamique) |
| alert_rule_form_attribution_degraded | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | alerts_refresh (dynamique) |
| alert_rule_freshness | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | alerts_refresh (dynamique) |
| alert_rule_gsc_ingest_missed | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | alerts_refresh (dynamique) |
| alert_rule_page_taxonomy_gap | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | alerts_refresh (dynamique) |
| alert_rule_pipeline_dead | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | alerts_refresh (dynamique) |
| alert_rule_rpc_health | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | alerts_refresh (dynamique) |
| alert_rule_tracker_drift | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | alerts_refresh (dynamique) |
| alert_rule_warn_escalation | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | alerts_refresh (dynamique) |
| assisted_contacts_by_entry_path | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 3 | dashboard_assisted_quarter,refresh_dashboard_resources_assisted |
| behavior_pages_for_period | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 6 | run_rpc_contract_tests |
| canonical_path | 0 | 5 | 0 | 0 | 0 | 4 | 1 | 16 | cooked_page_daily_series,gsc_page_daily_series,gsc_page_performance,gsc_top_queries_for_path |
| classify_channel | 0 | 2 | 0 | 0 | 0 | 5 | 1 | 34 | conversion_journeys,cooked_page_index,math_visit_sequences,refresh_dashboard_expertises_snapshots,seo_to_contact_funnel |
| content_performance | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 15 | alert_rule_rpc_health |
| conversion_journeys | 0 | 3 | 0 | 0 | 0 | 4 | 1 | 37 | alert_rule_rpc_health,content_performance,cooked_page_index,seo_to_contact_funnel |
| conversions_leaderboard | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |
| cooked_alerts_refresh | 0 | 2 | 0 | 0 | 1 | 0 | 1 | 19 |  |
| cooked_cpi_snapshot | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 5 | cooked_refresh_after_gsc |
| cooked_events_window | 0 | 4 | 0 | 0 | 0 | 3 | 0 | 11 | cooked_snapshot_window,refresh_noise_sessions,refresh_seo_url_snapshot |
| cooked_is_chrome_anchor | 0 | 0 | 0 | 0 | 0 | 1 | 3 | 4 | cooked_events_window |
| cooked_is_main_site | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |  |
| cooked_is_spam_referrer | 0 | 0 | 0 | 0 | 0 | 8 | 0 | 1 | assisted_contacts_by_entry_path,cooked_events_window,cooked_page_daily_series,cooked_pages_compare,seo_pages_overview |
| cooked_normalize_email | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |  |
| cooked_normalize_phone_fr | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 1 |  |
| cooked_page_daily_series | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 3 |  |
| cooked_page_index | 0 | 1 | 0 | 0 | 0 | 1 | 1 | 19 | cooked_cpi_snapshot |
| cooked_page_type | 0 | 0 | 0 | 0 | 0 | 4 | 1 | 9 | content_performance,cooked_page_index,refresh_page_taxonomy_heuristic,seo_to_contact_funnel |
| cooked_pages_compare | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 6 | pages_pulse |
| cooked_pages_snapshot | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |  |
| cooked_paris_ts_end_exclusive | 0 | 3 | 0 | 0 | 0 | 2 | 0 | 0 | cooked_snapshot_window,dashboard_article_detail |
| cooked_paris_ts_start | 0 | 3 | 0 | 0 | 0 | 2 | 0 | 0 | cooked_snapshot_window,dashboard_article_detail |
| cooked_period_bounds | 0 | 3 | 0 | 0 | 0 | 19 | 1 | 7 | cooked_pages_compare,cooked_pages_snapshot,cooked_snapshot_window,dashboard_annotations,dashboard_article_detail |
| cooked_refresh_after_gsc | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 7 |  |
| cooked_site_scope | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | cooked_is_main_site |
| cooked_snapshot_window | 0 | 0 | 0 | 0 | 0 | 3 | 0 | 5 | refresh_dashboard_expertises_snapshots,refresh_dashboard_resources_assisted,refresh_dashboard_snapshots |
| cooked_weekly_conversions_snapshot | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |
| cpi_compose | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 1 | cooked_page_index |
| cta_breakdown_for_path | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 6 | run_rpc_contract_tests |
| ctr_for_position | 0 | 0 | 0 | 0 | 0 | 5 | 1 | 1 | dashboard_article_detail,dashboard_seo_by_query,gsc_x_dfs_opportunities,refresh_dashboard_expertises_snapshots,refresh_dashboard_snapshots |
| dashboard_annotations | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |  |
| dashboard_article_detail | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |  |
| dashboard_assisted_quarter | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 6 |  |
| dashboard_expertises_kpis | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |  |
| dashboard_expertises_overview | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |  |
| dashboard_expertises_trend | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |  |
| dashboard_honoraires_funnel | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 1 |  |
| dashboard_intervention_effect | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |  |
| dashboard_resources_assisted | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 12 |  |
| dashboard_resources_cohorts | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |  |
| dashboard_resources_kpis | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |  |
| dashboard_resources_overview | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 3 |  |
| dashboard_resources_trend | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |  |
| dashboard_seo_by_query | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 4 |  |
| dashboard_seo_kpis | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |  |
| dfs_keywords_to_sync | 0 | 4 | 0 | 0 | 0 | 0 | 1 | 2 |  |
| engagement_density_for_path | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 4 | run_rpc_contract_tests |
| form_submit_counts_as_macro | 0 | 0 | 0 | 0 | 0 | 7 | 1 | 0 | assisted_contacts_by_entry_path,dashboard_honoraires_funnel,form_submits_per_path,macro_contacts_by_path,refresh_dashboard_expertises_snapshots |
| form_submits_attributed | 0 | 0 | 0 | 0 | 0 | 3 | 1 | 10 | alert_rule_rpc_health,conversion_journeys,math_visit_sequences |
| form_submits_per_path | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |  |
| gsc_is_branded | 0 | 3 | 0 | 0 | 0 | 6 | 0 | 13 | cooked_page_index,dashboard_article_detail,dashboard_seo_by_query,dashboard_seo_kpis,refresh_dashboard_expertises_snapshots |
| gsc_last_data_day | 0 | 1 | 0 | 0 | 0 | 5 | 1 | 10 | alert_rule_gsc_gap,alert_rule_gsc_lag,cooked_period_bounds,dashboard_intervention_effect,dashboard_resources_cohorts |
| gsc_page_daily_series | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 3 |  |
| gsc_page_performance | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 12 |  |
| gsc_pages_compare | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 3 | pages_pulse |
| gsc_pages_overview | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 6 |  |
| gsc_path_metrics | 0 | 0 | 0 | 0 | 0 | 4 | 4 | 2 | dashboard_seo_kpis,pages_overview_unified,refresh_dashboard_expertises_snapshots,refresh_dashboard_snapshots |
| gsc_top_queries_for_path | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 6 |  |
| gsc_top_queries_global | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 7 |  |
| gsc_x_dfs_opportunities | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 5 |  |
| latest_rpc_health | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 12 |  |
| macro_contacts_by_path | 0 | 1 | 0 | 0 | 0 | 8 | 2 | 7 | cooked_pages_compare,cooked_pages_snapshot,gsc_page_performance,gsc_pages_overview,pages_overview_unified |
| math_internal_edges | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 5 | math_refresh_snapshots |
| math_refresh_snapshots | 0 | 2 | 0 | 0 | 1 | 0 | 0 | 3 |  |
| math_visit_sequences | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 8 | math_refresh_snapshots |
| outbound_destinations_for_path | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 5 | run_rpc_contract_tests |
| page_reads | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 2 | run_rpc_contract_tests |
| pages_overview_unified | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 24 |  |
| pages_pulse | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 11 |  |
| paris_date | 0 | 23 | 0 | 0 | 0 | 16 | 1 | 7 | cooked_events_window,cooked_page_daily_series,cooked_pages_compare,cooked_pages_snapshot,cooked_refresh_after_gsc |
| paris_today | 0 | 10 | 0 | 0 | 0 | 10 | 1 | 4 | alert_rule_cpi_stale,alert_rule_gbp_gap,cooked_cpi_snapshot,cooked_page_daily_series,cooked_period_bounds |
| pogo_rates_for_period | 0 | 0 | 0 | 0 | 0 | 2 | 1 | 3 | gsc_page_performance,pages_overview_unified |
| pulse_quadrant | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 4 | pulse_status |
| pulse_status | 0 | 0 | 0 | 0 | 0 | 2 | 1 | 2 | pages_pulse,site_pulse |
| purge_cooked_noise | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 5 |  |
| purge_old_events | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 4 |  |
| raise_cooked_alert | 0 | 0 | 0 | 0 | 0 | 2 | 1 | 7 | cooked_alerts_refresh,cooked_refresh_after_gsc |
| record_ingest_drop | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 |  |
| refresh_bot_fingerprints | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 5 | refresh_seo_url_snapshot |
| refresh_dashboard_expertises_snapshots | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 2 | cooked_refresh_after_gsc |
| refresh_dashboard_resources_assisted | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 10 | cooked_refresh_after_gsc |
| refresh_dashboard_snapshots | 0 | 1 | 0 | 0 | 0 | 1 | 1 | 1 | cooked_refresh_after_gsc |
| refresh_identity_stitch | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 6 |  |
| refresh_noise_sessions | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 5 | refresh_seo_url_snapshot |
| refresh_page_taxonomy_heuristic | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 | alert_rule_page_taxonomy_gap |
| refresh_pipeline_health | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 18 | run_rpc_contract_tests |
| refresh_seo_url_snapshot | 0 | 0 | 0 | 0 | 1 | 1 | 1 | 14 | refresh_pipeline_health |
| rls_auto_enable | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |  |
| rpc_contract_check | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 2 | run_rpc_contract_tests |
| run_rpc_contract_tests | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 1 |  |
| seo_pages_overview | 0 | 0 | 0 | 0 | 0 | 3 | 1 | 8 | behavior_pages_for_period,gsc_page_performance,pages_overview_unified |
| seo_to_contact_funnel | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 18 |  |
| site_context_export | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 6 | run_rpc_contract_tests |
| site_gsc_kpis_compare | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 2 |  |
| site_kpis_compare | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 29 |  |
| site_macro_counts | 0 | 0 | 0 | 0 | 0 | 2 | 1 | 6 | site_kpis_compare,site_seo_funnel |
| site_pulse | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 15 |  |
| site_seo_funnel | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 16 |  |
| snapshot_pages_export | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 7 | run_rpc_contract_tests |
| top_contact_pages | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |  |
| tracker_first_seen_global | 0 | 0 | 0 | 0 | 0 | 6 | 1 | 5 | cooked_pages_compare,refresh_dashboard_expertises_snapshots,refresh_dashboard_snapshots,run_rpc_contract_tests,site_kpis_compare |
| tracker_version_distribution | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |  |
| unaccent | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 8 |  |
| unaccent_init | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |
| unaccent_lexize | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |
| url_decode | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 3 | canonical_path |
| weekly_conversions_report | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |  |

Sans consommateur détecté dans le repo/cron/dashboard (hors docs) : 6/118
- conversions_leaderboard (mentions docs : 0)
- cooked_weekly_conversions_snapshot (mentions docs : 0)
- unaccent (mentions docs : 8)
- unaccent_init (mentions docs : 0)
- unaccent_lexize (mentions docs : 0)
- weekly_conversions_report (mentions docs : 0)
