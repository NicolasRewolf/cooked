-- Sprint 33 (22/05/2026) — fix refresh_seo_url_snapshot
-- Bug : le cron refresh_seo_url_snapshot @ 03:00 UTC échoue depuis le
-- 22/05/2026 05:00 Paris avec :
--   ERROR: INSERT has more expressions than target columns
-- Cause : la table seo_url_snapshot a été altered en Sprint 30 pour drop
-- les 4 colonnes email_clicks_* (jamais alimentées — events.cta_email_click
-- = 0 rows depuis Sprint 0 ; le tracker browser skip explicitement les
-- mailto: ; le site jplouton-avocat.fr n'expose pas de bouton email).
-- La fonction refresh_seo_url_snapshot continuait d'écrire 74 expressions
-- dans une table à 70 colonnes.
-- Conséquence : seo_url_snapshot figé sur les données du 21/05/2026 05:00
-- jusqu'au déploiement de cette migration.
-- Fix : retirer le CTE email_counts, son LEFT JOIN, et les 4 expressions
-- coalesce(email_counts.eN, 0) du SELECT. Aucune perte de données.

CREATE OR REPLACE FUNCTION public.refresh_seo_url_snapshot()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  now_ts timestamptz := now();
begin
  -- Refresh both filter layers before rebuilding snapshot.
  -- bot_fingerprints (Sprint 17): anonymous_id-level crawlers.
  -- noise_sessions (Sprint 21): session-level prefetch + ua_bot + instant_close.
  perform public.refresh_bot_fingerprints();
  perform public.refresh_noise_sessions();

  delete from public.seo_url_snapshot;

  insert into public.seo_url_snapshot
  with
    all_paths as (
      select distinct path
      from public.events_human
      where path is not null
        and occurred_at >= now_ts - interval '365 days'
    ),
    o7   as (select * from public.seo_pages_overview(now_ts - interval '7 days',   now_ts)),
    o28  as (select * from public.seo_pages_overview(now_ts - interval '28 days',  now_ts)),
    o90  as (select * from public.seo_pages_overview(now_ts - interval '90 days',  now_ts)),
    o365 as (select * from public.seo_pages_overview(now_ts - interval '365 days', now_ts)),
    cwv as (
      select
        path,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric)
          filter (where props->>'metric' = 'LCP'))::numeric  as lcp_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric)
          filter (where props->>'metric' = 'INP'))::numeric  as inp_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric)
          filter (where props->>'metric' = 'CLS'))::numeric  as cls_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric)
          filter (where props->>'metric' = 'TTFB'))::numeric as ttfb_p75
      from public.events_human
      where name = 'web_vitals'
        and path is not null
        and occurred_at >= now_ts - interval '28 days'
      group by path
    ),
    top_ref as (
      select distinct on (path) path, referrer_hostname as top_referrer
      from (
        select path, referrer_hostname, count(*) as c
        from public.events_human
        where name = 'pageview'
          and path is not null
          and referrer_hostname is not null
          and occurred_at >= now_ts - interval '28 days'
        group by path, referrer_hostname
      ) r
      order by path, c desc
    ),
    top_src as (
      select distinct on (path) path, utm_source as top_source
      from (
        select path, utm_source, count(*) as c
        from public.events_human
        where name = 'pageview'
          and path is not null
          and utm_source is not null
          and occurred_at >= now_ts - interval '28 days'
        group by path, utm_source
      ) r
      order by path, c desc
    ),
    top_med as (
      select distinct on (path) path, utm_medium as top_medium
      from (
        select path, utm_medium, count(*) as c
        from public.events_human
        where name = 'pageview'
          and path is not null
          and utm_medium is not null
          and occurred_at >= now_ts - interval '28 days'
        group by path, utm_medium
      ) r
      order by path, c desc
    ),
    dev as (
      select path, jsonb_object_agg(device_type, pct) as split
      from (
        select
          path,
          device_type,
          round((100.0 * count(*) / sum(count(*)) over (partition by path))::numeric, 1) as pct
        from public.events_human
        where name = 'pageview'
          and path is not null
          and device_type is not null
          and occurred_at >= now_ts - interval '28 days'
        group by path, device_type
      ) d
      group by path
    ),
    phone_counts as (
      select
        path,
        count(*) filter (where occurred_at >= now_ts - interval '7 days')   as p7,
        count(*) filter (where occurred_at >= now_ts - interval '28 days')  as p28,
        count(*) filter (where occurred_at >= now_ts - interval '90 days')  as p90,
        count(*) filter (where occurred_at >= now_ts - interval '365 days') as p365
      from public.events_human
      where name = 'cta_phone_click'
        and path is not null
        and occurred_at >= now_ts - interval '365 days'
      group by path
    ),
    booking_counts as (
      select
        path,
        count(*) filter (where occurred_at >= now_ts - interval '7 days')   as b7,
        count(*) filter (where occurred_at >= now_ts - interval '28 days')  as b28,
        count(*) filter (where occurred_at >= now_ts - interval '90 days')  as b90,
        count(*) filter (where occurred_at >= now_ts - interval '365 days') as b365
      from public.events_human
      where name = 'cta_booking_click'
        and path is not null
        and occurred_at >= now_ts - interval '365 days'
      group by path
    ),
    pogo as (
      select *
      from public.pogo_rates_for_period(now_ts - interval '28 days', now_ts)
    ),
    device_sessions as (
      select
        path,
        count(distinct session_id) filter (where device_type = 'mobile')  as mob_s,
        count(distinct session_id) filter (where device_type = 'desktop') as dsk_s
      from public.events_human
      where name = 'pageview'
        and path is not null
        and occurred_at >= now_ts - interval '28 days'
      group by path
    ),
    device_cta as (
      select
        path,
        count(*) filter (where device_type = 'mobile')  as mob_cta,
        count(*) filter (where device_type = 'desktop') as dsk_cta
      from public.events_human
      where name in ('cta_phone_click', 'cta_booking_click')
        and path is not null
        and occurred_at >= now_ts - interval '28 days'
      group by path
    )
  select
    p.path,
    coalesce(o7.views, 0),               coalesce(o7.unique_visitors, 0),
    coalesce(o7.sessions, 0),            coalesce(o7.bounce_rate, 0),
    coalesce(o7.avg_dwell_seconds, 0),
    coalesce(o7.scroll_avg, 0),          coalesce(o7.scroll_median, 0),
    coalesce(o7.scroll_complete_pct, 0),
    coalesce(o7.entry_count, 0),         coalesce(o7.exit_count, 0),
    coalesce(o7.outbound_clicks, 0),
    coalesce(o28.views, 0),              coalesce(o28.unique_visitors, 0),
    coalesce(o28.sessions, 0),           coalesce(o28.bounce_rate, 0),
    coalesce(o28.avg_dwell_seconds, 0),
    coalesce(o28.scroll_avg, 0),         coalesce(o28.scroll_median, 0),
    coalesce(o28.scroll_complete_pct, 0),
    coalesce(o28.entry_count, 0),        coalesce(o28.exit_count, 0),
    coalesce(o28.outbound_clicks, 0),
    coalesce(o90.views, 0),              coalesce(o90.unique_visitors, 0),
    coalesce(o90.sessions, 0),           coalesce(o90.bounce_rate, 0),
    coalesce(o90.avg_dwell_seconds, 0),
    coalesce(o90.scroll_avg, 0),         coalesce(o90.scroll_median, 0),
    coalesce(o90.scroll_complete_pct, 0),
    coalesce(o90.entry_count, 0),        coalesce(o90.exit_count, 0),
    coalesce(o90.outbound_clicks, 0),
    coalesce(o365.views, 0),             coalesce(o365.unique_visitors, 0),
    coalesce(o365.sessions, 0),          coalesce(o365.bounce_rate, 0),
    coalesce(o365.avg_dwell_seconds, 0),
    coalesce(o365.scroll_avg, 0),        coalesce(o365.scroll_median, 0),
    coalesce(o365.scroll_complete_pct, 0),
    coalesce(o365.entry_count, 0),       coalesce(o365.exit_count, 0),
    coalesce(o365.outbound_clicks, 0),
    cwv.lcp_p75, cwv.inp_p75, cwv.cls_p75, cwv.ttfb_p75,
    top_ref.top_referrer, top_src.top_source, top_med.top_medium,
    dev.split,
    now_ts,
    coalesce(phone_counts.p7, 0)::bigint,
    coalesce(phone_counts.p28, 0)::bigint,
    coalesce(phone_counts.p90, 0)::bigint,
    coalesce(phone_counts.p365, 0)::bigint,
    coalesce(booking_counts.b7, 0)::bigint,
    coalesce(booking_counts.b28, 0)::bigint,
    coalesce(booking_counts.b90, 0)::bigint,
    coalesce(booking_counts.b365, 0)::bigint,
    coalesce(pogo.google_sessions, 0)::bigint,
    coalesce(pogo.pogo_sticks, 0)::bigint,
    coalesce(pogo.hard_pogo, 0)::bigint,
    pogo.pogo_rate,
    coalesce(device_sessions.mob_s, 0)::bigint,
    coalesce(device_sessions.dsk_s, 0)::bigint,
    case when coalesce(device_sessions.mob_s, 0) > 0
         then round(100.0 * coalesce(device_cta.mob_cta, 0) / device_sessions.mob_s, 2)
         else null end,
    case when coalesce(device_sessions.dsk_s, 0) > 0
         then round(100.0 * coalesce(device_cta.dsk_cta, 0) / device_sessions.dsk_s, 2)
         else null end
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
$function$;

COMMENT ON FUNCTION public.refresh_seo_url_snapshot() IS
  'Sprint 33 (22/05/2026) : email_counts CTE + LEFT JOIN + 4 expressions retirées (drift Sprint 30). 70 expressions = 70 colonnes table.';
