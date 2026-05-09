-- ============================================================
-- COOKED — SEO views & snapshot
-- ============================================================
-- Run AFTER schema.sql. Idempotent.
--
-- What you get:
--   • bot_fingerprints table + refresh_bot_fingerprints() — centralized
--     bot detection (Sprint 17). anonymous_ids with >20 pv/day + 0 scroll.
--   • events_human view — events minus bot traffic. ALL RPCs and views
--     below read from events_human, never from events directly.
--   • seo_pages_overview(from, to)  — parametric function, 1 row / URL
--   • seo_url_snapshot              — flat table, 1 row / URL with rolling
--                                     windows (7d, 28d, 90d, 365d) — refreshed
--                                     daily at 03:00 UTC by pg_cron
--   • seo_traffic_sources_28d       — by source / medium / referrer
--   • seo_landing_pages_28d         — entry pages with engagement
--   • seo_daily_summary             — site-wide daily aggregates
--   • behavior_pages_for_period(from, to) — original RPC for seo (period-parametric)
--   • Sprint 12 RPCs (cross-project contract for seo full-menu audit)
--       - snapshot_pages_export(paths)
--       - site_context_export()
--       - outbound_destinations_for_path(path, days_back)
--       - cta_breakdown_for_path(path, days_back)
--   • rls_auto_enable() + ensure_rls event trigger — security hardening,
--     auto-enables RLS on every new public table.
--   • pogo_rates_for_period(from, to) — pogo-stick detection per page
--       (Google sessions, pogo count, hard pogo, pogo rate %)
--   • engagement_density_for_path(path, days) — dwell distribution
--       (p25/median/p75 + evenness_score) for a single page
--   • seo_expertise_pages view — domain-specific filter on
--     seo_url_snapshot for the 3 practice-area URL trees of
--     jplouton-avocat.fr (defense-penale / indemnisation-des-victimes /
--     droit-des-contrats-et-des-personnes).
-- ============================================================


-- ============================================================
-- 0. Bot filtering — centralized detection + filtered view
-- ============================================================
-- Architecture:
--   events (raw, unchanged) → bot_fingerprints (detected bots)
--   → events_human (view: events minus bots)
--   → all RPCs + snapshot use events_human
--
-- Detection rule: anonymous_id with >20 pageviews/day AND 0 scroll
-- events = crawler. No human visits 20+ pages without ever scrolling.
--
-- refresh_bot_fingerprints() is called automatically at the start of
-- refresh_seo_url_snapshot(), so pg_cron only needs one entry.

create table if not exists public.bot_fingerprints (
  anonymous_id  text primary key,
  detected_at   timestamptz default now(),
  reason        text
);

alter table public.bot_fingerprints enable row level security;

create or replace function public.refresh_bot_fingerprints()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  truncate public.bot_fingerprints;

  insert into public.bot_fingerprints (anonymous_id, reason)
  select distinct sub.anonymous_id, 'crawl: >20 pv/day, 0 scroll'
  from (
    select e.anonymous_id, e.occurred_at::date as day,
      count(*) filter (where e.name = 'pageview') as pvs,
      count(*) filter (where e.name = 'scroll_depth') as scrolls
    from public.events e
    where e.anonymous_id is not null
    group by e.anonymous_id, e.occurred_at::date
    having count(*) filter (where e.name = 'pageview') > 20
       and count(*) filter (where e.name = 'scroll_depth') = 0
  ) sub
  on conflict (anonymous_id) do nothing;
end;
$$;

revoke execute on function public.refresh_bot_fingerprints() from public;
revoke execute on function public.refresh_bot_fingerprints() from anon;
revoke execute on function public.refresh_bot_fingerprints() from authenticated;
grant  execute on function public.refresh_bot_fingerprints() to service_role;

create or replace view public.events_human as
select e.*
from public.events e
where not exists (
  select 1 from public.bot_fingerprints b
  where b.anonymous_id = e.anonymous_id
);


-- ---------- 1. Parametric per-URL overview ------------------

create or replace function public.seo_pages_overview(
  date_from timestamptz,
  date_to   timestamptz default now()
)
returns table (
  path                text,
  views               bigint,
  unique_visitors     bigint,
  sessions            bigint,
  bounce_rate         numeric,   -- % of landings that bounced (0..100)
  avg_dwell_seconds   numeric,   -- mean active time on page
  scroll_avg          numeric,   -- mean of max scroll % per session
  scroll_median       numeric,
  scroll_complete_pct numeric,   -- % of sessions reaching 100%
  entry_count         bigint,
  exit_count          bigint,
  outbound_clicks     bigint
)
language sql stable
set search_path = public, pg_catalog
as $$
  with we as (
    select * from public.events_human
    where occurred_at >= date_from and occurred_at < date_to
  ),
  pv as (
    select
      path,
      count(*)                       as views,
      count(distinct anonymous_id)   as unique_visitors,
      count(distinct session_id)     as sessions
    from we
    where name = 'pageview' and path is not null
    group by path
  ),
  ss as (
    select
      session_id,
      min(occurred_at) as session_start,
      max(occurred_at) as session_end,
      count(*) filter (where name = 'pageview') as pages_viewed,
      (array_agg(path order by occurred_at)
        filter (where name = 'pageview'))[1] as entry_path,
      (array_agg(path order by occurred_at desc)
        filter (where name = 'pageview'))[1] as exit_path
    from we
    group by session_id
  ),
  sp as (
    -- per (session, path): max dwell + max scroll % reached
    select
      session_id,
      path,
      max((props->>'duration_seconds')::numeric)
        filter (where name = 'page_exit') as dwell,
      coalesce(
        max((props->>'percent')::numeric)
          filter (where name = 'scroll_depth'),
        0
      ) as max_scroll
    from we
    where path is not null
    group by session_id, path
  ),
  scroll_dwell as (
    select
      path,
      avg(dwell)::numeric                                                as avg_dwell,
      avg(max_scroll)::numeric                                           as scroll_avg,
      (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
      (100.0 * count(*) filter (where max_scroll >= 100)
        / nullif(count(*), 0))::numeric                                  as scroll_complete_pct
    from sp
    group by path
  ),
  entry_exit as (
    select
      path,
      sum(is_entry)::bigint  as entry_count,
      sum(is_exit)::bigint   as exit_count,
      sum(is_bounce)::bigint as bounce_count
    from (
      select
        ss.entry_path as path,
        1 as is_entry, 0 as is_exit,
        case when ss.pages_viewed = 1
              and extract(epoch from (ss.session_end - ss.session_start)) < 10
             then 1 else 0 end as is_bounce
      from ss where ss.entry_path is not null
      union all
      select ss.exit_path, 0, 1, 0
      from ss where ss.exit_path is not null
    ) u
    group by path
  ),
  oc as (
    select path, count(*) as clicks
    from we
    where name = 'click_outbound' and path is not null
    group by path
  )
  select
    pv.path,
    pv.views::bigint,
    pv.unique_visitors::bigint,
    pv.sessions::bigint,
    coalesce(round((100.0 * ee.bounce_count
              / nullif(ee.entry_count, 0))::numeric, 2), 0)   as bounce_rate,
    coalesce(round(sd.avg_dwell, 1), 0)                      as avg_dwell_seconds,
    coalesce(round(sd.scroll_avg, 1), 0)                     as scroll_avg,
    coalesce(round(sd.scroll_median, 1), 0)                  as scroll_median,
    coalesce(round(sd.scroll_complete_pct, 1), 0)            as scroll_complete_pct,
    coalesce(ee.entry_count, 0)::bigint                      as entry_count,
    coalesce(ee.exit_count, 0)::bigint                       as exit_count,
    coalesce(oc.clicks, 0)::bigint                           as outbound_clicks
  from pv
  left join scroll_dwell sd on sd.path = pv.path
  left join entry_exit   ee on ee.path = pv.path
  left join oc              on oc.path = pv.path
  order by pv.views desc;
$$;


-- ---------- 2. Snapshot table (1 row per URL, rolling windows) -----

create table if not exists public.seo_url_snapshot (
  path text primary key,

  -- Per-window CTA conversion counts (Sprint 10 Phase 1).
  -- Re-declared here so a fresh `views.sql` run on an empty project
  -- creates the table with these columns; the alter-table block at the
  -- bottom of this file is the safety net for already-deployed projects.

  -- 7d
  views_7d               bigint,
  unique_visitors_7d     bigint,
  sessions_7d            bigint,
  bounce_rate_7d         numeric,
  avg_dwell_seconds_7d   numeric,
  scroll_avg_7d          numeric,
  scroll_median_7d       numeric,
  scroll_complete_pct_7d numeric,
  entry_count_7d         bigint,
  exit_count_7d          bigint,
  outbound_clicks_7d     bigint,

  -- 28d (Google Search Console-aligned window)
  views_28d               bigint,
  unique_visitors_28d     bigint,
  sessions_28d            bigint,
  bounce_rate_28d         numeric,
  avg_dwell_seconds_28d   numeric,
  scroll_avg_28d          numeric,
  scroll_median_28d       numeric,
  scroll_complete_pct_28d numeric,
  entry_count_28d         bigint,
  exit_count_28d          bigint,
  outbound_clicks_28d     bigint,

  -- 90d
  views_90d               bigint,
  unique_visitors_90d     bigint,
  sessions_90d            bigint,
  bounce_rate_90d         numeric,
  avg_dwell_seconds_90d   numeric,
  scroll_avg_90d          numeric,
  scroll_median_90d       numeric,
  scroll_complete_pct_90d numeric,
  entry_count_90d         bigint,
  exit_count_90d          bigint,
  outbound_clicks_90d     bigint,

  -- 365d
  views_365d               bigint,
  unique_visitors_365d     bigint,
  sessions_365d            bigint,
  bounce_rate_365d         numeric,
  avg_dwell_seconds_365d   numeric,
  scroll_avg_365d          numeric,
  scroll_median_365d       numeric,
  scroll_complete_pct_365d numeric,
  entry_count_365d         bigint,
  exit_count_365d          bigint,
  outbound_clicks_365d     bigint,

  -- Core Web Vitals (28d, p75 — the value Google uses for ranking signals)
  lcp_p75_28d_ms  numeric,
  inp_p75_28d_ms  numeric,
  cls_p75_28d     numeric,
  ttfb_p75_28d_ms numeric,

  -- Top sources (28d)
  top_referrer_28d text,
  top_source_28d   text,
  top_medium_28d   text,

  -- Device split (28d) — {"desktop": 60.0, "mobile": 35.0, "tablet": 5.0}
  device_split_28d jsonb,

  -- Sprint 10 Phase 1 — conversion CTA tracking
  phone_clicks_7d   bigint,
  phone_clicks_28d  bigint,
  phone_clicks_90d  bigint,
  phone_clicks_365d bigint,
  -- email_clicks_* are kept as columns for backward compat but the tracker
  -- no longer fires cta_email_click events (the site never exposes mailto:).
  email_clicks_7d   bigint,
  email_clicks_28d  bigint,
  email_clicks_90d  bigint,
  email_clicks_365d bigint,
  -- Sprint 10 Phase 1.5 — booking-CTA clicks (internal links to
  -- /honoraires-rendez-vous, regardless of anchor text).
  booking_cta_clicks_7d   bigint,
  booking_cta_clicks_28d  bigint,
  booking_cta_clicks_90d  bigint,
  booking_cta_clicks_365d bigint,

  -- Pogo-stick (NavBoost signal, 28d, Google-origin only)
  google_sessions_28d  bigint,
  pogo_sticks_28d      bigint,
  hard_pogo_28d        bigint,
  pogo_rate_28d        numeric,

  -- CTA rate by device (28d)
  mobile_sessions_28d   bigint,
  desktop_sessions_28d  bigint,
  cta_rate_mobile_28d   numeric,
  cta_rate_desktop_28d  numeric,

  refreshed_at timestamptz not null default now()
);

-- Safety net for projects that were created before Sprint 10 Phase 1
-- (CREATE TABLE IF NOT EXISTS skips the new columns on existing tables).
alter table public.seo_url_snapshot
  add column if not exists phone_clicks_7d   bigint,
  add column if not exists phone_clicks_28d  bigint,
  add column if not exists phone_clicks_90d  bigint,
  add column if not exists phone_clicks_365d bigint,
  add column if not exists email_clicks_7d   bigint,
  add column if not exists email_clicks_28d  bigint,
  add column if not exists email_clicks_90d  bigint,
  add column if not exists email_clicks_365d bigint,
  add column if not exists booking_cta_clicks_7d   bigint,
  add column if not exists booking_cta_clicks_28d  bigint,
  add column if not exists booking_cta_clicks_90d  bigint,
  add column if not exists booking_cta_clicks_365d bigint,
  add column if not exists google_sessions_28d     bigint,
  add column if not exists pogo_sticks_28d         bigint,
  add column if not exists hard_pogo_28d           bigint,
  add column if not exists pogo_rate_28d           numeric,
  add column if not exists mobile_sessions_28d     bigint,
  add column if not exists desktop_sessions_28d    bigint,
  add column if not exists cta_rate_mobile_28d     numeric,
  add column if not exists cta_rate_desktop_28d    numeric;

alter table public.seo_url_snapshot enable row level security;


-- ---------- 3. Refresh function ----------------------------------

create or replace function public.refresh_seo_url_snapshot()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  now_ts timestamptz := now();
begin
  -- Refresh bot detection before rebuilding snapshot
  perform public.refresh_bot_fingerprints();

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
    -- Sprint 10 Phase 1 — phone / email click counts per path × 4 windows.
    -- Single CTE with FILTER clauses = 1 table scan instead of 4.
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
    email_counts as (
      select
        path,
        count(*) filter (where occurred_at >= now_ts - interval '7 days')   as e7,
        count(*) filter (where occurred_at >= now_ts - interval '28 days')  as e28,
        count(*) filter (where occurred_at >= now_ts - interval '90 days')  as e90,
        count(*) filter (where occurred_at >= now_ts - interval '365 days') as e365
      from public.events_human
      where name = 'cta_email_click'
        and path is not null
        and occurred_at >= now_ts - interval '365 days'
      group by path
    ),
    -- Sprint 10 Phase 1.5 — booking-CTA clicks (internal links to /honoraires-rendez-vous)
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
    -- Pogo-stick (NavBoost signal, 28d window, Google-origin only)
    pogo as (
      select *
      from public.pogo_rates_for_period(now_ts - interval '28 days', now_ts)
    ),
    -- CTA rate by device (28d) — mobile vs desktop conversion gap
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

    -- Sprint 10 Phase 1 — phone / email click counters
    coalesce(phone_counts.p7, 0)::bigint,
    coalesce(phone_counts.p28, 0)::bigint,
    coalesce(phone_counts.p90, 0)::bigint,
    coalesce(phone_counts.p365, 0)::bigint,
    coalesce(email_counts.e7, 0)::bigint,
    coalesce(email_counts.e28, 0)::bigint,
    coalesce(email_counts.e90, 0)::bigint,
    coalesce(email_counts.e365, 0)::bigint,
    -- Sprint 10 Phase 1.5 — booking-CTA click counters
    coalesce(booking_counts.b7, 0)::bigint,
    coalesce(booking_counts.b28, 0)::bigint,
    coalesce(booking_counts.b90, 0)::bigint,
    coalesce(booking_counts.b365, 0)::bigint,

    -- Pogo-stick (NavBoost signal, 28d)
    coalesce(pogo.google_sessions, 0)::bigint,
    coalesce(pogo.pogo_sticks, 0)::bigint,
    coalesce(pogo.hard_pogo, 0)::bigint,
    pogo.pogo_rate,

    -- CTA rate by device (28d)
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
    left join email_counts   on email_counts.path   = p.path
    left join booking_counts on booking_counts.path = p.path
    left join pogo            on pogo.path            = p.path
    left join device_sessions on device_sessions.path = p.path
    left join device_cta      on device_cta.path      = p.path;
end;
$$;

revoke execute on function public.refresh_seo_url_snapshot() from public;
revoke execute on function public.refresh_seo_url_snapshot() from anon;
revoke execute on function public.refresh_seo_url_snapshot() from authenticated;
grant  execute on function public.refresh_seo_url_snapshot() to service_role;


-- ---------- 4. Companion views (28d) -----------------------------

create or replace view public.seo_traffic_sources_28d
with (security_invoker = true) as
  with we as (
    select * from public.events_human
    where name = 'pageview'
      and occurred_at >= now() - interval '28 days'
  ),
  ss as (
    select
      session_id,
      max(referrer_hostname) as referrer_hostname,
      max(utm_source)        as utm_source,
      max(utm_medium)        as utm_medium,
      min(occurred_at)       as session_start,
      max(occurred_at)       as session_end,
      count(*)               as pages_viewed
    from we
    group by session_id
  )
  select
    coalesce(utm_source, referrer_hostname, 'direct') as source,
    coalesce(utm_medium, case when referrer_hostname is null then 'none' else 'referral' end) as medium,
    count(*)::bigint as sessions,
    round(avg(pages_viewed)::numeric, 2) as avg_pages_per_session,
    round(avg(extract(epoch from (session_end - session_start)))::numeric, 1) as avg_session_seconds,
    round((100.0 * count(*) filter (
      where pages_viewed = 1
        and extract(epoch from (session_end - session_start)) < 10
    ) / nullif(count(*), 0))::numeric, 2) as bounce_rate
  from ss
  group by 1, 2
  order by sessions desc;


create or replace view public.seo_landing_pages_28d
with (security_invoker = true) as
  with we as (
    select * from public.events_human
    where occurred_at >= now() - interval '28 days'
  ),
  ss as (
    select
      session_id,
      min(occurred_at) as session_start,
      max(occurred_at) as session_end,
      count(*) filter (where name = 'pageview') as pages_viewed,
      (array_agg(path order by occurred_at)
        filter (where name = 'pageview'))[1] as entry_path,
      max(referrer_hostname) as referrer_hostname
    from we
    group by session_id
  )
  select
    entry_path as path,
    count(*)::bigint as landings,
    count(distinct referrer_hostname)::bigint as distinct_referrers,
    round((100.0 * count(*) filter (
      where pages_viewed = 1
        and extract(epoch from (session_end - session_start)) < 10
    ) / nullif(count(*), 0))::numeric, 2) as bounce_rate,
    round(avg(pages_viewed)::numeric, 2) as avg_pages_per_session,
    round(avg(extract(epoch from (session_end - session_start)))::numeric, 1) as avg_session_seconds
  from ss
  where entry_path is not null
  group by entry_path
  order by landings desc;


create or replace view public.seo_daily_summary
with (security_invoker = true) as
  with ss as (
    select
      session_id,
      date_trunc('day', min(occurred_at))::date as day,
      min(occurred_at) as session_start,
      max(occurred_at) as session_end,
      count(*) filter (where name = 'pageview') as pages_viewed
    from public.events_human
    group by session_id
  )
  select
    day,
    count(*)::bigint                                                    as sessions,
    sum(pages_viewed)::bigint                                           as pageviews,
    round(avg(pages_viewed)::numeric, 2)                                as avg_pages_per_session,
    round(avg(extract(epoch from (session_end - session_start)))::numeric, 1) as avg_session_seconds,
    round((100.0 * count(*) filter (
      where pages_viewed = 1
        and extract(epoch from (session_end - session_start)) < 10
    ) / nullif(count(*), 0))::numeric, 2)                               as bounce_rate
  from ss
  group by day
  order by day desc;


-- ---------- 5. Cross-project RPC consumed by seo audit tool ------
-- Combines seo_pages_overview + CWV p75 + outbound clicks + per-session
-- aggregates that aren't in seo_pages_overview directly.
-- Returns 1 row per URL with shape compatible with the seo behavior_page_snapshots
-- table.

create or replace function public.behavior_pages_for_period(
  date_from timestamptz,
  date_to   timestamptz
)
returns table (
  path                    text,
  sessions                bigint,
  pages_per_session       numeric,
  avg_session_duration_s  numeric,
  bounce_rate             numeric,        -- 0..1 (converted from %)
  scroll_depth_avg        numeric,
  scroll_complete_pct     numeric,
  lcp_p75_ms              numeric,
  inp_p75_ms              numeric,
  cls_p75                 numeric,
  ttfb_p75_ms             numeric,
  outbound_clicks         bigint
)
language sql
stable
set search_path = public, pg_catalog
as $$
  with we as (
    select * from public.events_human
    where occurred_at >= date_from and occurred_at < date_to
  ),
  ss as (
    select
      session_id,
      count(*) filter (where name = 'pageview')                       as pages_viewed,
      extract(epoch from max(occurred_at) - min(occurred_at))::numeric as session_seconds
    from we
    group by session_id
  ),
  sp as (
    select distinct e.path, e.session_id
    from we e
    where e.name = 'pageview' and e.path is not null
  ),
  per_path_session_stats as (
    select
      sp.path,
      avg(ss.pages_viewed)::numeric                                  as pages_per_session,
      avg(ss.session_seconds)::numeric                               as avg_session_seconds
    from sp
    join ss on ss.session_id = sp.session_id
    group by sp.path
  ),
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
    from we
    where name = 'web_vitals' and path is not null
    group by path
  ),
  oc as (
    select path, count(*) as clicks
    from we
    where name = 'click_outbound' and path is not null
    group by path
  ),
  base as (
    select * from public.seo_pages_overview(date_from, date_to)
  )
  select
    b.path,
    b.sessions,
    coalesce(round(pp.pages_per_session, 2), 0)         as pages_per_session,
    coalesce(round(pp.avg_session_seconds, 0), 0)       as avg_session_duration_s,
    coalesce(round(b.bounce_rate / 100.0, 4), 0)        as bounce_rate,
    b.scroll_avg                                        as scroll_depth_avg,
    b.scroll_complete_pct,
    cwv.lcp_p75                                         as lcp_p75_ms,
    cwv.inp_p75                                         as inp_p75_ms,
    cwv.cls_p75                                         as cls_p75,
    cwv.ttfb_p75                                        as ttfb_p75_ms,
    coalesce(oc.clicks, 0)::bigint                      as outbound_clicks
  from base b
  left join per_path_session_stats pp on pp.path = b.path
  left join cwv on cwv.path = b.path
  left join oc  on oc.path  = b.path;
$$;

revoke execute on function public.behavior_pages_for_period(timestamptz, timestamptz) from public;
revoke execute on function public.behavior_pages_for_period(timestamptz, timestamptz) from anon;
revoke execute on function public.behavior_pages_for_period(timestamptz, timestamptz) from authenticated;
grant  execute on function public.behavior_pages_for_period(timestamptz, timestamptz) to service_role;


-- ============================================================
-- 5b. URL-decode helper (Sprint 13)
-- ============================================================
-- Postgres has no native url_decode. Used by the Sprint 13 backfill that
-- normalised existing events.path to decoded form, and available as a
-- general utility for ad-hoc queries.
--
-- Algorithm: walk the input character-by-character, accumulate contiguous
-- %XX sequences as a bytea, then decode that bytea as UTF-8. Multi-byte
-- codepoints (é = 0xC3 0xA9, à = 0xC3 0xA0, …) decode correctly because
-- consecutive %XX bytes are batched together before convert_from().
-- Falls back to the original string on any error.

create or replace function public.url_decode(input text)
returns text
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
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
$$;

revoke execute on function public.url_decode(text) from public;
grant  execute on function public.url_decode(text) to service_role;


-- ============================================================
-- 6. Sprint 12 RPCs — full-menu contract for the seo audit tool
-- ============================================================
-- The 4 functions below are the cross-project contract published for
-- consumption by the seo repo (https://github.com/NicolasRewolf/seo)
-- as of Sprint 12. Their TypeScript shapes are defined in
-- seo/src/lib/cooked.ts (PageSnapshotExtras, SiteContext,
-- OutboundDestination, CtaBreakdownRow). DO NOT change a return-table
-- signature without coordinating a corresponding bump in cooked.ts.
-- All four are granted to service_role only.

-- ---------- 6.1 snapshot_pages_export ---------------------------
-- Returns the latest pre-computed snapshot rows. Optional filtering by
-- paths (pass null to get the full snapshot). The seo wrapper
-- reconstructs the nested TS type from the flat 66-column row.

create or replace function public.snapshot_pages_export(
  paths text[] default null
)
returns setof public.seo_url_snapshot
language sql
stable
set search_path = public, pg_catalog
as $$
  select *
  from public.seo_url_snapshot s
  where snapshot_pages_export.paths is null
     or s.path = any (snapshot_pages_export.paths);
$$;

revoke execute on function public.snapshot_pages_export(text[]) from public;
revoke execute on function public.snapshot_pages_export(text[]) from anon;
revoke execute on function public.snapshot_pages_export(text[]) from authenticated;
grant  execute on function public.snapshot_pages_export(text[]) to service_role;

-- ---------- 6.2 site_context_export -----------------------------
-- One row of site-wide context over the last 28 days, injected verbatim
-- into the diagnostic prompt's <site_context> block to let the LLM
-- calibrate per-page metrics against site averages.

create or replace function public.site_context_export()
returns table (
  global_sessions_28d            bigint,
  global_bounce_rate_28d         numeric,
  sessions_per_day_median_28d    numeric,
  sessions_trend_pct_7d_vs_28d   numeric,
  top_sources_28d                jsonb
)
language sql
stable
set search_path = public, pg_catalog
as $$
  with ss as (
    select
      e.session_id,
      min(e.occurred_at)                                         as session_start,
      max(e.occurred_at)                                         as session_end,
      count(*) filter (where e.name = 'pageview')                as pages_viewed,
      max(e.referrer_hostname)                                   as referrer_hostname,
      max(e.utm_source)                                          as utm_source,
      max(e.utm_medium)                                          as utm_medium
    from public.events_human e
    where e.occurred_at >= now() - interval '28 days'
    group by e.session_id
  ),
  agg as (
    select
      count(*)::bigint                                                                     as s28_total,
      count(*) filter (where session_start >= now() - interval '7 days')::bigint           as s7_total,
      count(*) filter (
        where pages_viewed = 1
          and extract(epoch from (session_end - session_start)) < 10
      )::numeric                                                                           as bounce_count
    from ss
  ),
  daily as (
    select date_trunc('day', session_start)::date as day, count(*) as n
    from ss
    group by 1
  ),
  median as (
    select percentile_cont(0.5) within group (order by n)::numeric as v
    from daily
  ),
  sources as (
    select
      coalesce(utm_source, referrer_hostname, 'direct')                                    as source,
      coalesce(utm_medium,
               case when referrer_hostname is null then 'none' else 'referral' end)        as medium,
      count(*)::bigint                                                                     as sessions
    from ss
    group by 1, 2
    order by 3 desc
    limit 5
  ),
  top_sources as (
    select coalesce(
      jsonb_agg(jsonb_build_object(
        'source',   source,
        'medium',   medium,
        'sessions', sessions
      ) order by sessions desc),
      '[]'::jsonb
    ) as top
    from sources
  )
  select
    a.s28_total,
    coalesce(round(a.bounce_count / nullif(a.s28_total, 0), 4), 0),
    coalesce(round(m.v, 1), 0),
    coalesce(round(
      case
        when a.s28_total > 0 then
          100.0 * ((a.s7_total::numeric / 7.0) - (a.s28_total::numeric / 28.0))
                 / nullif((a.s28_total::numeric / 28.0), 0)
        else 0
      end, 2
    ), 0),
    t.top
  from agg a, median m, top_sources t;
$$;

revoke execute on function public.site_context_export() from public;
revoke execute on function public.site_context_export() from anon;
revoke execute on function public.site_context_export() from authenticated;
grant  execute on function public.site_context_export() to service_role;

-- ---------- 6.3 outbound_destinations_for_path ------------------
-- Top-10 hostnames clicked outbound from a given page over `days_back`
-- days. Lets the LLM diagnose "outbound leak" patterns.

create or replace function public.outbound_destinations_for_path(
  path      text,
  days_back int default 28
)
returns table (
  hostname text,
  clicks   bigint
)
language sql
stable
set search_path = public, pg_catalog
as $$
  select
    (e.props->>'hostname')      as hostname,
    count(*)::bigint            as clicks
  from public.events_human e
  where e.name      = 'click_outbound'
    and e.path      = outbound_destinations_for_path.path
    and e.occurred_at >= now() - (outbound_destinations_for_path.days_back * interval '1 day')
    and (e.props->>'hostname') is not null
    and (e.props->>'hostname') <> ''
  group by (e.props->>'hostname')
  order by 2 desc
  limit 10;
$$;

revoke execute on function public.outbound_destinations_for_path(text, int) from public;
revoke execute on function public.outbound_destinations_for_path(text, int) from anon;
revoke execute on function public.outbound_destinations_for_path(text, int) from authenticated;
grant  execute on function public.outbound_destinations_for_path(text, int) to service_role;

-- ---------- 6.4 cta_breakdown_for_path --------------------------
-- THE central conversion-intent disambiguation signal. Splits CTA clicks
-- by (cta_type, placement, anchor_sample) so the LLM can tell the
-- difference between "ambient footer phone CTA" and "qualified body CTA".
-- Enum values are exact:
--    cta_type  ∈ {'phone', 'email', 'booking'}
--    placement ∈ {'header', 'footer', 'body'}
-- One row per distinct anchor (option (c) of the contract — the caller
-- can re-aggregate to (cta_type, placement) if needed).

create or replace function public.cta_breakdown_for_path(
  path      text,
  days_back int default 28
)
returns table (
  cta_type      text,
  placement     text,
  anchor_sample text,
  clicks        bigint
)
language sql
stable
set search_path = public, pg_catalog
as $$
  with cta as (
    select
      case e.name
        when 'cta_phone_click'   then 'phone'
        when 'cta_email_click'   then 'email'
        when 'cta_booking_click' then 'booking'
      end                                                 as cta_type,
      coalesce(nullif(e.props->>'placement', ''), 'body') as placement,
      coalesce(e.props->>'anchor', '')                    as anchor
    from public.events_human e
    where e.name in ('cta_phone_click', 'cta_email_click', 'cta_booking_click')
      and e.path = cta_breakdown_for_path.path
      and e.occurred_at >= now() - (cta_breakdown_for_path.days_back * interval '1 day')
  )
  select
    cta_type,
    placement,
    anchor       as anchor_sample,
    count(*)::bigint
  from cta
  where cta_type is not null
  group by cta_type, placement, anchor
  order by 4 desc, cta_type, placement;
$$;

revoke execute on function public.cta_breakdown_for_path(text, int) from public;
revoke execute on function public.cta_breakdown_for_path(text, int) from anon;
revoke execute on function public.cta_breakdown_for_path(text, int) from authenticated;
grant  execute on function public.cta_breakdown_for_path(text, int) to service_role;

-- ---------- 6.5 tracker_first_seen_global -----------------------
-- Returns the timestamp of the earliest event in the events table —
-- effectively "when did Cooked start collecting?". The seo audit tool
-- uses this during the bootstrap phase to pro-rate Cooked sessions
-- against the 28d GSC window (raw cooked_sessions / gsc_clicks * 100
-- gives a fake "5% capture rate" when Cooked has only been collecting
-- for ~36h vs 28 days of GSC data; the right denominator is
-- min(28, days_since_first_seen)).
--
-- Replaces the COOKED_TRACKER_DEPLOY_DATE hardcode in seo's
-- diagnostic.v1.ts so the deploy date stays single-source-of-truth on
-- the Cooked side and works automatically when the same seo pipeline
-- is plugged into a 2nd tracker (different first_seen) or after a
-- retention purge that drops old events.

create or replace function public.tracker_first_seen_global()
returns timestamptz
language sql
stable
set search_path = public, pg_catalog
as $$
  select min(occurred_at) from public.events_human;
$$;

revoke execute on function public.tracker_first_seen_global() from public;
revoke execute on function public.tracker_first_seen_global() from anon;
revoke execute on function public.tracker_first_seen_global() from authenticated;
grant  execute on function public.tracker_first_seen_global() to service_role;


-- ---------- 7. Daily refresh via pg_cron ------------------------
-- pg_cron must be enabled: Supabase Dashboard → Database → Extensions → pg_cron.
-- Alternatively, run this once after the extension is enabled:
--   create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('refresh_seo_url_snapshot')
    where exists (select 1 from cron.job where jobname = 'refresh_seo_url_snapshot');

    perform cron.schedule(
      'refresh_seo_url_snapshot',
      '0 3 * * *',  -- 03:00 UTC every day
      $cron$ select public.refresh_seo_url_snapshot(); $cron$
    );
  else
    raise notice 'pg_cron not enabled — enable it in Dashboard, then re-run views.sql';
  end if;
end $$;


-- ============================================================
-- 8. Security hardening — RLS auto-enable on new tables
-- ============================================================
-- Belt-and-suspenders security guardrail. Every new table created in the
-- `public` schema automatically gets RLS enabled by an event trigger, so
-- a forgotten `alter table … enable row level security` can never expose
-- a freshly-created table via PostgREST to anon/authenticated.
--
-- Important contract notes:
--   • The function is SECURITY DEFINER because it must alter tables on
--     behalf of whoever ran the CREATE TABLE — search_path is pinned to
--     pg_catalog to prevent search_path injection.
--   • EXECUTE is revoked from public/anon/authenticated/service_role:
--     the function is fired by the `ensure_rls` event trigger which
--     runs with the privileges of the function owner regardless of
--     grants. There is no legitimate reason to call it via /rest/v1/rpc/
--     and Supabase advisors flag any SECURITY DEFINER fn that's
--     externally callable.
--   • Tables created via `apply_migration` MCP / direct CREATE TABLE in
--     the public schema are covered. System schemas (pg_catalog,
--     information_schema, pg_toast*, pg_temp*) are skipped.

create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  cmd record;
begin
  for cmd in
    select *
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
  loop
     if cmd.schema_name is not null
        and cmd.schema_name in ('public')
        and cmd.schema_name not in ('pg_catalog', 'information_schema')
        and cmd.schema_name not like 'pg_toast%'
        and cmd.schema_name not like 'pg_temp%'
     then
      begin
        execute format('alter table if exists %s enable row level security', cmd.object_identity);
        raise log 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      exception
        when others then
          raise log 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      end;
     else
        raise log 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     end if;
  end loop;
end;
$$;

-- Revoke direct EXECUTE from every role that PostgREST might surface this
-- function under. The event trigger keeps firing because event triggers
-- run as the function owner (postgres), not as the caller.
revoke execute on function public.rls_auto_enable() from public;
revoke execute on function public.rls_auto_enable() from anon;
revoke execute on function public.rls_auto_enable() from authenticated;
revoke execute on function public.rls_auto_enable() from service_role;

-- Wire the event trigger if not already present.
do $$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'ensure_rls') then
    create event trigger ensure_rls
      on ddl_command_end
      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      execute function public.rls_auto_enable();
  end if;
end $$;


-- ============================================================
-- 9. Domain-specific views — jplouton-avocat.fr expertise pages
-- ============================================================
-- Filtered slice of seo_url_snapshot restricted to the 3 practice-area
-- URL trees used by the cabinet jplouton-avocat.fr:
--
--   /defense-penale/*                       → expertise_area = 'defense_penale'
--   /indemnisation-des-victimes/*           → expertise_area = 'indemnisation_victimes'
--   /droit-des-contrats-et-des-personnes/*  → expertise_area = 'droit_contrats_personnes'
--
-- Each row is tagged with:
--   expertise_area  : the practice area (3 values above)
--   expertise_level : 'hub' for the area landing page (e.g. /defense-penale)
--                     'leaf' for sub-pages (e.g. /defense-penale/droit-penal)
--
-- Excludes paths ending with apostrophe (`/defense-penale/droit-penal'`) —
-- these come from broken hrefs in the site's content where an apostrophe
-- got concatenated to the URL. They have real traffic and should be
-- diagnosed/fixed on the Wix side, but they pollute analytics.
--
-- Inherits seo_url_snapshot's RLS deny-all: only service_role can SELECT.

create or replace view public.seo_expertise_pages as
select
  case
    when path ~ '^/defense-penale'                       then 'defense_penale'
    when path ~ '^/indemnisation-des-victimes'           then 'indemnisation_victimes'
    when path ~ '^/droit-des-contrats-et-des-personnes'  then 'droit_contrats_personnes'
  end as expertise_area,
  case
    when path ~ '^/[^/]+$' then 'hub'
    else 'leaf'
  end as expertise_level,
  s.*
from public.seo_url_snapshot s
where
  path ~ '^/(defense-penale|indemnisation-des-victimes|droit-des-contrats-et-des-personnes)(/|$)'
  and right(path, 1) <> ''''
;

comment on view public.seo_expertise_pages is
  'Filtered view of seo_url_snapshot restricted to the 3 practice-area URL trees + tagged with expertise_area / expertise_level. Excludes malformed paths ending with apostrophe.';

grant select on public.seo_expertise_pages to service_role;

-- ---------- 10. Pogo-stick rates per page (NavBoost signal) ----
--
-- A "pogo-stick" is when a visitor arrives from Google, views only
-- one page, and leaves in under 10 seconds — a strong negative
-- signal in Google's NavBoost ranking system.
--
-- "hard_pogo" adds scroll < 5% — the visitor didn't even try to read.
--
-- Usage:
--   SELECT * FROM pogo_rates_for_period(now() - interval '28 days', now())
--   WHERE google_sessions >= 5
--   ORDER BY pogo_rate DESC;

create or replace function public.pogo_rates_for_period(
  date_from timestamptz,
  date_to   timestamptz
)
returns table (
  path             text,
  google_sessions  bigint,
  pogo_sticks      bigint,
  hard_pogo        bigint,
  pogo_rate        numeric
)
language sql stable security definer
set search_path = public, pg_catalog
as $$
  with google_entries as (
    select distinct session_id, path
    from events_human
    where name = 'pageview'
      and referrer_hostname like '%google%'
      and occurred_at >= date_from
      and occurred_at < date_to
  ),
  session_pages as (
    select session_id, count(*) as pages
    from events_human
    where name = 'pageview'
      and occurred_at >= date_from
      and occurred_at < date_to
    group by session_id
  ),
  session_exit as (
    select session_id, path,
           (props->>'duration_seconds')::numeric as dwell_s,
           (props->>'max_scroll')::numeric as scroll
    from events_human
    where name = 'page_exit'
      and occurred_at >= date_from
      and occurred_at < date_to
  )
  select
    g.path,
    count(*)::bigint as google_sessions,
    count(*) filter (
      where sp.pages = 1 and se.dwell_s < 10
    )::bigint as pogo_sticks,
    count(*) filter (
      where sp.pages = 1 and se.dwell_s < 10 and se.scroll < 5
    )::bigint as hard_pogo,
    round(100.0 * count(*) filter (where sp.pages = 1 and se.dwell_s < 10)
          / nullif(count(*), 0), 1) as pogo_rate
  from google_entries g
  left join session_pages sp on sp.session_id = g.session_id
  left join session_exit se on se.session_id = g.session_id and se.path = g.path
  group by g.path;
$$;

grant execute on function public.pogo_rates_for_period(timestamptz, timestamptz) to service_role;
revoke execute on function public.pogo_rates_for_period(timestamptz, timestamptz) from anon, authenticated;

-- ---------- 11. Engagement density per page (ad-hoc RPC) -------
--
-- Returns dwell time distribution (p25/median/p75) and an evenness
-- score for a single page. evenness = p25/p75 — close to 1 means
-- uniform reading, close to 0 means bimodal (quick bouncers + deep
-- readers).
--
-- Usage:
--   SELECT * FROM engagement_density_for_path('/post/...', 28);

create or replace function public.engagement_density_for_path(
  target_path text,
  days        int default 28
)
returns table (
  sessions        bigint,
  dwell_p25       numeric,
  dwell_median    numeric,
  dwell_p75       numeric,
  evenness_score  numeric
)
language sql stable security definer
set search_path = public, pg_catalog
as $$
  with session_dwell as (
    select
      session_id,
      (props->>'duration_seconds')::numeric as dwell_s
    from events_human
    where path = target_path
      and name = 'page_exit'
      and (props->>'duration_seconds')::numeric > 0
      and occurred_at >= now() - (days || ' days')::interval
  )
  select
    count(*)::bigint as sessions,
    round((percentile_cont(0.25) within group (order by dwell_s))::numeric, 1) as dwell_p25,
    round((percentile_cont(0.50) within group (order by dwell_s))::numeric, 1) as dwell_median,
    round((percentile_cont(0.75) within group (order by dwell_s))::numeric, 1) as dwell_p75,
    round(
      case
        when (percentile_cont(0.75) within group (order by dwell_s))::numeric > 0
        then (percentile_cont(0.25) within group (order by dwell_s))::numeric
           / (percentile_cont(0.75) within group (order by dwell_s))::numeric
        else null
      end::numeric, 2
    ) as evenness_score
  from session_dwell;
$$;

grant execute on function public.engagement_density_for_path(text, int) to service_role;
revoke execute on function public.engagement_density_for_path(text, int) from anon, authenticated;
