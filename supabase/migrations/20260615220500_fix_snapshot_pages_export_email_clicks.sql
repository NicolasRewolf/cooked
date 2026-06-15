-- 16/06/2026 — répare snapshot_pages_export, cassée depuis le Sprint 30
-- (21/05/2026) : elle référençait s.email_clicks_{7,28,90,365}d, colonnes
-- droppées de seo_url_snapshot (toujours 0 depuis l'origine). Contract test
-- en échec ("column s.email_clicks_7d does not exist") depuis cette date.
-- On préserve le contrat publié (mêmes colonnes, ordre, grants) via
-- CREATE OR REPLACE en renvoyant 0::bigint pour ces 4 colonnes —
-- sémantiquement identique à leur valeur historique. RPC orpheline depuis
-- la suppression du dashboard (25/05) mais publiée → on la garde alignée.
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
$function$;
