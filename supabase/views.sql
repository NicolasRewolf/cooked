-- ============================================================
-- COOKED — SEO views & snapshot
-- ============================================================
-- Run AFTER schema.sql. Idempotent.
--
-- What you get:
--   • seo_pages_overview(from, to)  — parametric function, 1 row / URL
--   • seo_url_snapshot              — flat table, 1 row / URL with rolling
--                                     windows (7d, 28d, 90d, 365d) — refreshed
--                                     daily at 03:00 UTC by pg_cron
--   • seo_traffic_sources_28d       — by source / medium / referrer
--   • seo_landing_pages_28d         — entry pages with engagement
--   • seo_daily_summary             — site-wide daily aggregates
--   • behavior_pages_for_period(from, to) — RPC consumed cross-project by
--                                           the seo audit tool
-- ============================================================

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
    select * from public.events
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
  add column if not exists booking_cta_clicks_365d bigint;

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
  delete from public.seo_url_snapshot;

  insert into public.seo_url_snapshot
  with
    all_paths as (
      select distinct path
      from public.events
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
      from public.events
      where name = 'web_vitals'
        and path is not null
        and occurred_at >= now_ts - interval '28 days'
      group by path
    ),
    top_ref as (
      select distinct on (path) path, referrer_hostname as top_referrer
      from (
        select path, referrer_hostname, count(*) as c
        from public.events
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
        from public.events
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
        from public.events
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
        from public.events
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
      from public.events
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
      from public.events
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
      from public.events
      where name = 'cta_booking_click'
        and path is not null
        and occurred_at >= now_ts - interval '365 days'
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
    coalesce(booking_counts.b365, 0)::bigint
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
    left join booking_counts on booking_counts.path = p.path;
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
    select * from public.events
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
    select * from public.events
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
    from public.events
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
    select * from public.events
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


-- ---------- 6. Daily refresh via pg_cron ------------------------
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
