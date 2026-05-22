-- ============================================================
-- COOKED — SEO views & snapshot
-- ============================================================
-- Run AFTER schema.sql. Idempotent.
--
-- What you get:
--   • bot_fingerprints table + refresh_bot_fingerprints() — centralized
--     bot detection (Sprint 17). anonymous_ids with >20 pv/day + 0 scroll.
--   • noise_sessions table + refresh_noise_sessions() — session-level
--     noise detection (Sprint 20 → renamed & expanded in Sprint 21,
--     then trimmed back in Sprint 21b).
--     Two patterns, each with a distinct `reason` value:
--       (a) prefetch  — Safari/Chrome/Cloudflare prerender ghosts
--       (b) ua_bot    — explicit User-Agent matches (Sprint 21)
--     NOTE: pattern (c) instant_close (1 pv + 0 eng + <5s) was added
--     in Sprint 21 then immediately removed in Sprint 21b — those
--     sessions are pogo-stick signals consumed by
--     pogo_rates_for_period(), not noise. Do not re-add it.
--   • events_human view — events minus bot traffic minus noise
--     sessions. ALL RPCs and views below read from events_human, never
--     from events directly.
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
-- 0. Bot + noise filtering — centralized detection + filtered view
-- ============================================================
-- Architecture (Sprint 24 — serial pipeline):
--
--   events (raw, unchanged)
--     ↓ Layer 1 — refresh_bot_fingerprints()
--   events_no_bots (view: events minus bot_fingerprints)
--     ↓ Layer 2 — refresh_noise_sessions()
--   noise_sessions (materialised from events_no_bots)
--     ↓
--   events_human (view: events_no_bots minus noise_sessions)
--     ↓
--   all RPCs + snapshot
--
-- Serial, not parallel: noise_sessions is built from events_no_bots,
-- so it never re-processes sessions already eliminated by Layer 1.
-- Before Sprint 24, both filters were applied in parallel directly on
-- events, causing bot sessions to appear in noise_sessions as well —
-- inflating its count and creating redundancy. With the serial
-- pipeline, noise_sessions is a clean count of behavioral noise only.
--
-- Layer 1 — bot_fingerprints (Sprint 17):
--   Rule: anonymous_id with >20 pageviews/day AND 0 scroll events.
--   Targets: classic SEO crawlers, monitoring services, bulk scrapers
--   that hammer the site over a day. Captures high-volume patterns.
--   Keyed on anonymous_id.
--
-- Layer 2 — noise_sessions (Sprint 20 + 21, trimmed in Sprint 21b,
--            now running on events_no_bots since Sprint 24):
--   Two sub-patterns. Each populated row has a `reason` column
--   ("prefetch:...", "ua_bot:<name>") for forensic traceability.
--
--   (a) prefetch — Sprint 20 (5 conditions, ALL required):
--       • referrer_hostname IS NULL
--       • COUNT(engagement_tick) = 0
--       • COUNT(scroll_depth)    = 0
--       • COUNT(pageview)        = 1
--       • duration < 10 seconds
--       Plus: device_type != 'server' (spare form-webhook rows).
--       Targets: Safari Top Hit prefetch, Chrome prerender, iMessage /
--       WhatsApp link preview, Cloudflare prefetch — ghosts no human
--       ever saw.
--
--   (b) ua_bot — Sprint 21 (explicit User-Agent ILIKE list):
--       headless, googlebot, bingbot, applebot, duckduckbot, yandexbot,
--       baiduspider, gptbot, claudebot, perplexitybot, chatgpt-user,
--       googleother, semrushbot, ahrefsbot, mj12bot, dotbot, petalbot,
--       bytespider, lighthouse, pingdom, uptimerobot, gtmetrix,
--       facebookexternalhit, linkedinbot, twitterbot, discordbot,
--       telegrambot, slackbot, whatsapp/, crawler, spider, axios/,
--       curl/, wget, python, go-http, node-fetch, httpclient, java/.
--       Every entry is technically impossible in a real human browser
--       UA — verified by sampling on 2026-05-15 audit (zero false
--       positives). Runs on events_no_bots (Sprint 24) so it only
--       catches UA-bots not already covered by Layer 1's behavioral
--       detection.
--
--   (c) instant_close — REMOVED in Sprint 21b. Those sessions are real
--       humans pogo-sticking from search results back to the SERP,
--       which Cooked already measures in pogo_rates_for_period() (a
--       NavBoost-style page-quality signal). Filtering them upstream
--       would silently destroy that metric. Do not re-introduce.
--
-- Why a real human survives both filters:
--   - Search/referral visitors have referrer → survive (a).
--   - Readers emit at least one tick or scroll → survive (a).
--   - Multi-page visitors have pageview ≥ 2 → survive (a).
--   - Visitors staying ≥ 10s on the page survive (a).
--   - Real browsers (Chrome/Safari/Firefox/Edge/Mobile Safari) never
--     match any (b) UA pattern.
--
-- Both refresh functions are called automatically at the start of
-- refresh_seo_url_snapshot(), so pg_cron only needs one entry.
--
-- Sprint 24 observed baseline (2026-05-17, 12-day window):
--   events_raw      : 123 594
--   events_no_bots  : 109 404  (−14 190 via bot_fingerprints)
--   noise_sessions  :   2 960  (was 8 456 before Sprint 24 — 5 496
--                               were bot sessions double-counted)
--   events_human    : 101 547  (−7 857 via noise_sessions)

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


-- ---------- events_no_bots (Sprint 24) ---------------------------
-- Intermediate view: events minus bot_fingerprints.
-- refresh_noise_sessions() reads from this view so it never
-- processes sessions already caught by Layer 1.

create or replace view public.events_no_bots
with (security_invoker = true) as
select e.*
from public.events e
where not exists (
  select 1 from public.bot_fingerprints b
  where b.anonymous_id = e.anonymous_id
);


-- ---------- noise_sessions (Sprint 20 + 21 + 21b) ----------------
--
-- Materialised list of sessions matching one of the two noise
-- patterns (prefetch / ua_bot). Refreshed at the start of
-- refresh_seo_url_snapshot() alongside refresh_bot_fingerprints(), so
-- events_human is computed as a fast set difference rather than a
-- recursive subquery on every read.
--
-- History:
--   • Sprint 20 introduced this table as `prefetch_sessions` with the
--     (a) pattern only.
--   • Sprint 21 renamed it to `noise_sessions` and added (b) ua_bot
--     and (c) instant_close.
--   • Sprint 21b removed (c) instant_close — those sessions are real
--     human pogo-sticks that pogo_rates_for_period() counts as a
--     page-quality signal; filtering them upstream would have
--     silently destroyed that metric.
-- The `reason` column tracks which pattern flagged each session.
--
-- 2026-05-15 observed baseline (10-day window, post Sprint 21b):
--   prefetch : 6 768 sessions
--   ua_bot   :   834 sessions
--   total (after deduplication via ON CONFLICT) : ~7 600 sessions
--
-- There is significant overlap between Layer 1 (bot_fingerprints) and
-- pattern (b) here — same crawler can match both. That's fine, defence
-- in depth.

create table if not exists public.noise_sessions (
  session_id  text primary key,
  detected_at timestamptz default now(),
  reason      text
);

alter table public.noise_sessions enable row level security;

create or replace function public.refresh_noise_sessions()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  truncate public.noise_sessions;

  -- Pattern (a) — prefetch (Sprint 20). 5 conditions, ALL required.
  -- Runs on events_no_bots (Sprint 24) — crawlers already excluded.
  insert into public.noise_sessions (session_id, reason)
  select
    session_id,
    'prefetch: 0 ref + 0 tick + 0 scroll + 1 pv + <10s'
  from public.events_no_bots
  where session_id is not null
    and device_type is distinct from 'server'
  group by session_id
  having max(referrer_hostname) is null
     and count(*) filter (where name = 'engagement_tick') = 0
     and count(*) filter (where name = 'scroll_depth')    = 0
     and count(*) filter (where name = 'pageview')        = 1
     and extract(epoch from (max(occurred_at) - min(occurred_at))) < 10
  on conflict (session_id) do nothing;

  -- Pattern (b) — ua_bot (Sprint 21). Explicit User-Agent ILIKE list.
  -- Every entry verified to be impossible in a real human browser UA.
  -- Runs on events_no_bots (Sprint 24) — catches UA-bots not covered
  -- by Layer 1 (behavioral crawler detection via anonymous_id).
  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'ua_bot: ' || (
      case
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
  from public.events_no_bots
  where session_id is not null
    and device_type is distinct from 'server'
    and user_agent is not null
    and (
         user_agent ilike '%headless%'
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

  -- Pattern (c) instant_close was added in Sprint 21 then immediately
  -- removed in Sprint 21b — those sessions are pogo-stick signals
  -- consumed by pogo_rates_for_period(), not noise. Do not re-add.
end;
$$;

revoke execute on function public.refresh_noise_sessions() from public;
revoke execute on function public.refresh_noise_sessions() from anon;
revoke execute on function public.refresh_noise_sessions() from authenticated;
grant  execute on function public.refresh_noise_sessions() to service_role;


-- events_human (Sprint 24 — serial pipeline):
-- Stage 2 of the serial filter: events_no_bots minus noise_sessions.
-- security_invoker = true: enforce caller's RLS, not creator's (Postgres 15+).
create or replace view public.events_human
with (security_invoker = true) as
select e.*
from public.events_no_bots e
where not exists (
  select 1 from public.noise_sessions n
  where n.session_id = e.session_id
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
  -- Refresh both filter layers before rebuilding snapshot.
  -- bot_fingerprints (Sprint 17): anonymous_id-level crawlers.
  -- noise_sessions (Sprint 20 + 21 + 21b): session-level prefetch + ua_bot.
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
--    placement ∈ {'header', 'footer', 'body', 'sticky'}
-- One row per distinct anchor (option (c) of the contract — the caller
-- can re-aggregate to (cta_type, placement) if needed).
--
-- Sprint 23 (2026-05-16) — added cta_anchor_click:
--   Two anchor CTAs on expertise pages (TOC sticky sidebar + sticky bar
--   mobile) were invisible to this RPC because their placement is 'sticky',
--   not 'header'|'footer'|'body'. Fixed by:
--     1. Adding 'sticky' to the placement enum (comment + SEO wrapper).
--     2. Including cta_anchor_click in the WHERE clause, but only mapping
--        the two RDV-intent labels to cta_type='booking'. Navigation anchors
--        (section jumps like "Défendre vos intérêts") are explicitly excluded
--        via the null branch of the CASE — they are NOT conversion CTAs.
--   Known RDV anchor labels (stable, set via aria-label in Wix Studio):
--     • "Je prends rendez-vous — table des matières"  → TOC, all devices
--     • "Demander un RDV — formulaire expertise"       → sticky bar, tab+mobile

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
        when 'cta_anchor_click'  then
          case e.props->>'anchor'
            when 'Je prends rendez-vous — table des matières' then 'booking'
            when 'Demander un RDV — formulaire expertise'      then 'booking'
            else null  -- navigation anchors (section jumps) → excluded
          end
      end                                                 as cta_type,
      coalesce(nullif(e.props->>'placement', ''), 'body') as placement,
      coalesce(e.props->>'anchor', '')                    as anchor
    from public.events_human e
    where e.name in ('cta_phone_click', 'cta_email_click', 'cta_booking_click', 'cta_anchor_click')
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

-- Sprint 29 (2026-05-21) — guard against clock-skewed events.
-- 13 events discovered with occurred_at=2025-05-20 (one full year off)
-- but received_at=2026-05-21 09:26 → broken browser system clock or
-- bot forging timestamps. Without the BETWEEN guard,
-- tracker_first_seen_global() returned 2025-05-20 instead of the real
-- deploy date 2026-05-06, breaking pro-rating math in the seo agent.
-- Tolerance ±2d absorbs legitimate timezone drift / queued offline
-- events without trusting events older than the server window.
create or replace function public.tracker_first_seen_global()
returns timestamptz
language sql
stable
set search_path = public, pg_catalog
as $$
  select min(occurred_at)
  from public.events_human
  where occurred_at between received_at - interval '2 days'
                       and received_at + interval '2 days';
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

create or replace view public.seo_expertise_pages
with (security_invoker = true) as
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


-- ---------- 6.X refresh_pipeline_health (Sprint 25 — 2026-05-17) --
-- Single-row health endpoint surfacing the 3 silent-failure modes
-- identified in the AMDEC consolidation:
--   1. pg_cron job failed or paused (refresh_seo_url_snapshot)
--   2. seo_url_snapshot stale (snapshot age > 25h)
--   3. events ingestion stopped (no event in last hour)
--
-- Consumed by Seo at the start of each pipeline run. If
-- status='critical', Seo should abort the diagnostic run rather than
-- producing recommendations on stale or absent data.
--
-- Thresholds:
--   snapshot_age > 25h               → degraded
--   snapshot_age > 36h               → critical
--   cron_last_status != 'succeeded'  → critical
--   last_event_age > 60min           → degraded
--   last_event_age > 6h              → critical

create or replace function public.refresh_pipeline_health()
returns table (
  status                  text,
  snapshot_refreshed_at   timestamptz,
  snapshot_age_hours      numeric,
  cron_last_status        text,
  cron_last_run           timestamptz,
  cron_age_hours          numeric,
  last_event_at           timestamptz,
  last_event_age_minutes  numeric,
  events_last_60min       bigint,
  issues                  text[]
)
language plpgsql
stable
security definer
set search_path = public, cron, pg_catalog
as $$
declare
  v_snapshot_refreshed_at  timestamptz;
  v_snapshot_age_hours     numeric;
  v_cron_last_status       text;
  v_cron_last_run          timestamptz;
  v_cron_age_hours         numeric;
  v_last_event_at          timestamptz;
  v_last_event_age_minutes numeric;
  v_events_last_60min      bigint;
  v_issues                 text[] := array[]::text[];
  v_status                 text   := 'healthy';
begin
  -- 1. Snapshot freshness
  select max(refreshed_at) into v_snapshot_refreshed_at
  from public.seo_url_snapshot;

  v_snapshot_age_hours := extract(epoch from (now() - v_snapshot_refreshed_at)) / 3600;

  if v_snapshot_refreshed_at is null then
    v_issues := v_issues || 'snapshot_never_refreshed';
    v_status := 'critical';
  elsif v_snapshot_age_hours > 36 then
    v_issues := v_issues || format('snapshot_stale: %.1fh old', v_snapshot_age_hours);
    v_status := 'critical';
  elsif v_snapshot_age_hours > 25 then
    v_issues := v_issues || format('snapshot_aging: %.1fh old', v_snapshot_age_hours);
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  -- 2. Cron last run status
  select d.status, d.start_time
    into v_cron_last_status, v_cron_last_run
  from cron.job j
  join cron.job_run_details d on d.jobid = j.jobid
  where j.jobname = 'refresh_seo_url_snapshot'
  order by d.start_time desc
  limit 1;

  v_cron_age_hours := extract(epoch from (now() - v_cron_last_run)) / 3600;

  if v_cron_last_run is null then
    v_issues := v_issues || 'cron_no_run_history';
    v_status := 'critical';
  elsif v_cron_last_status is distinct from 'succeeded' then
    v_issues := v_issues || format('cron_last_failed: status=%s', coalesce(v_cron_last_status, 'NULL'));
    v_status := 'critical';
  elsif v_cron_age_hours > 25 then
    v_issues := v_issues || format('cron_overdue: %.1fh since last run', v_cron_age_hours);
    v_status := 'critical';
  end if;

  -- 3. Ingestion freshness
  select max(occurred_at) into v_last_event_at
  from public.events;

  v_last_event_age_minutes := extract(epoch from (now() - v_last_event_at)) / 60;

  select count(*) into v_events_last_60min
  from public.events
  where occurred_at >= now() - interval '60 minutes';

  if v_last_event_at is null then
    v_issues := v_issues || 'no_events_ever';
    v_status := 'critical';
  elsif v_last_event_age_minutes > 360 then  -- 6h
    v_issues := v_issues || format('ingestion_stopped: %.0fmin since last event', v_last_event_age_minutes);
    v_status := 'critical';
  elsif v_last_event_age_minutes > 60 then
    v_issues := v_issues || format('ingestion_quiet: %.0fmin since last event', v_last_event_age_minutes);
    if v_status = 'healthy' then v_status := 'degraded'; end if;
  end if;

  return query select
    v_status,
    v_snapshot_refreshed_at,
    round(v_snapshot_age_hours, 2),
    v_cron_last_status,
    v_cron_last_run,
    round(v_cron_age_hours, 2),
    v_last_event_at,
    round(v_last_event_age_minutes, 1),
    v_events_last_60min,
    v_issues;
end;
$$;

revoke execute on function public.refresh_pipeline_health() from public;
revoke execute on function public.refresh_pipeline_health() from anon;
revoke execute on function public.refresh_pipeline_health() from authenticated;
grant  execute on function public.refresh_pipeline_health() to service_role;


-- ============================================================
-- Sprint 26 (2026-05-17) — Tier 2 AMDEC consolidation
-- ============================================================
-- 6 actions issues du Tier 2 de l'AMDEC :
--   1. revoke select on filter surfaces from anon/authenticated
--   2. bot_fingerprints reason enrichi (pv, distinct paths)
--   3. cta_anchor_label_map table + cta_breakdown_for_path en JOIN
--   4. snapshot_pages_export returns table(...) explicite
--   5. tracker version hash (props._v) + tracker_version_distribution()
--   6. (escaladé Seo) — assertion bounce_rate côté src/lib/cooked.ts
--
-- Voir la migration sprint26_* dans Supabase pour le SQL complet.
-- Notable :
--   - cta_anchor_label_map est administrable sans migration
--   - cta_anchor_labels_unmapped expose les labels non-classés (audit)
--   - tracker_version_distribution(hours_back) détecte un republish raté

-- ---------- 6.Y cta_anchor_label_map (Sprint 26) ----------------
-- Table de référence pour le mapping cta_anchor_click → cta_type.
-- Remplace le CASE/WHEN hardcoded de cta_breakdown_for_path Sprint 23.
-- Administrable via INSERT/UPDATE sans migration.
create table if not exists public.cta_anchor_label_map (
  label       text primary key,
  cta_type    text not null check (cta_type in ('phone', 'email', 'booking')),
  notes       text,
  created_at  timestamptz default now()
);
alter table public.cta_anchor_label_map enable row level security;
revoke select on public.cta_anchor_label_map from anon, authenticated;
grant  select, insert, update, delete on public.cta_anchor_label_map to service_role;

-- ---------- 6.Z tracker_version_distribution (Sprint 26) --------
-- Tracker injecte props._v = 'sprintXX' depuis Sprint 26. Cette RPC
-- expose la distribution des versions vues sur N heures pour valider
-- qu'un republish Wix a bien pris.
create or replace function public.tracker_version_distribution(hours_back int default 24)
returns table (
  version            text,
  events             bigint,
  sessions           bigint,
  first_seen         timestamptz,
  last_seen          timestamptz,
  share_pct          numeric
)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  with versioned as (
    select
      coalesce(nullif(e.props->>'_v', ''), 'legacy_pre_sprint26') as version,
      e.session_id,
      e.occurred_at
    from public.events_human e
    where e.occurred_at >= now() - (tracker_version_distribution.hours_back * interval '1 hour')
      and e.device_type is distinct from 'server'
  ),
  totals as (select count(*)::numeric as total from versioned)
  select
    v.version,
    count(*)::bigint,
    count(distinct v.session_id)::bigint,
    min(v.occurred_at),
    max(v.occurred_at),
    round(100.0 * count(*)::numeric / nullif((select total from totals), 0), 2)
  from versioned v
  group by v.version
  order by 2 desc;
$$;
revoke execute on function public.tracker_version_distribution(int) from public, anon, authenticated;
grant  execute on function public.tracker_version_distribution(int) to service_role;


-- ============================================================
-- Sprint 28 (2026-05-21) — classify_channel() utility
-- ============================================================
-- Diagnosis (2026-05-21): the `referral` channel as historically
-- computed in ad-hoc analyses (CASE WHEN ref ILIKE ...) was 21 % CR
-- on n=471 sessions/7d, looking like a hidden goldmine. Drilling
-- down showed 461 / 471 of those "referrals" had
-- referrer_hostname = www.jplouton-avocat.fr — self-referrals
-- produced by Wix Studio's hard navigations dropping sessionStorage
-- between pages. The "referral" channel was therefore mostly an
-- artefact of session breakage, not an acquisition source.
--
-- Sprint 28 tracker change persists session_id in localStorage to
-- prevent the breakage going forward. This SQL function centralises
-- the channel taxonomy so every consumer (RPCs, ad-hoc queries,
-- the SEO agent wrappers) uses the same rules — including the
-- self-referral filter (returns NULL).
--
-- Returned labels:
--   'paid'           — utm_medium in (cpc/paid/ppc) or google ads utm_source
--   'organic_ai'     — referrer is claude.ai, perplexity.ai, chatgpt.com,
--                      gemini.google.com, copilot.microsoft.com
--   'organic_google' — referrer is google.* (and not paid)
--   'organic_other'  — yahoo, ecosia, brave, lilo, duckduckgo, qwant, bing
--   'social'         — facebook, instagram, linkedin, t.co, threads, tiktok, youtube
--   'direct'         — no referrer
--   'referral'       — any other third-party host
--   NULL             — self-referral (referrer matches self_host).
--                      Callers should exclude NULLs from acquisition counts
--                      and instead trust the first event of the session.

create or replace function public.classify_channel(
  ref         text,
  utm_source  text,
  utm_medium  text,
  self_host   text default 'jplouton-avocat.fr'
) returns text
language sql immutable
set search_path = public, pg_catalog
as $$
  select case
    -- Self-referral: not an acquisition channel
    when ref ilike '%' || self_host || '%' then null
    -- Paid first (UTM beats referrer)
    when lower(utm_medium) in ('cpc','paid','ppc')
      or lower(utm_source) like '%google%ads%' then 'paid'
    -- AI search referrers (separate bucket — emerging signal)
    when ref ilike '%claude.ai%' or ref ilike '%perplexity.ai%'
      or ref ilike '%chatgpt.com%' or ref ilike '%chat.openai.com%'
      or ref ilike '%gemini.google.com%' or ref ilike '%copilot.microsoft.com%'
      then 'organic_ai'
    -- Google organic
    when ref ilike '%google.%' then 'organic_google'
    -- Other search engines
    when ref ilike '%yahoo.%' or ref ilike '%ecosia.org%' or ref ilike '%brave.com%'
      or ref ilike '%lilo.org%' or ref ilike '%duckduckgo.%' or ref ilike '%qwant.%'
      or ref ilike '%bing.%'
      then 'organic_other'
    -- Social
    when ref ilike '%facebook.%' or ref ilike '%instagram.%' or ref ilike '%linkedin.%'
      or ref ilike '%t.co%' or ref ilike '%threads.%' or ref ilike '%tiktok.%'
      or ref ilike '%youtube.%'
      then 'social'
    -- Direct
    when ref is null or ref = '' then 'direct'
    -- Anything else
    else 'referral'
  end;
$$;

revoke execute on function public.classify_channel(text,text,text,text) from public, anon, authenticated;
grant  execute on function public.classify_channel(text,text,text,text) to service_role;

-- Quick smoke test (run manually after apply):
-- SELECT classify_channel('www.jplouton-avocat.fr', null, null) AS expect_null;
-- SELECT classify_channel('www.google.com', null, null)         AS expect_organic_google;
-- SELECT classify_channel('www.google.com', 'google', 'cpc')    AS expect_paid;
-- SELECT classify_channel('claude.ai', null, null)              AS expect_organic_ai;
-- SELECT classify_channel(null, null, null)                     AS expect_direct;


-- ============================================================
-- Sprint 27 (2026-05-17) — Tier 3 AMDEC consolidation
-- ============================================================
-- 2 actions Tier 3 livrées :
--   1. Contract test SQL nightly (table rpc_health + run_rpc_contract_tests +
--      latest_rpc_health + pg_cron 03:30 UTC). Couvre risque #1 criticité 100.
--   2. Politique de rétention events (purge_old_events + pg_cron 1er du mois
--      à 04:00 UTC, suppression > 400 jours). Couvre risque #11.
--
-- Voir migrations sprint27_* pour le SQL complet.
-- Note : tous les jobs pg_cron actifs (vérifier avec `SELECT * FROM cron.job`):
--   - refresh_seo_url_snapshot   : 0 3 * * *
--   - run_rpc_contract_tests     : 30 3 * * *
--   - purge_old_events_monthly   : 0 4 1 * *


-- ============================================================
-- Sprint 29 (2026-05-21) — audit hardening
-- ============================================================
-- Findings d'un audit multi-agent (10 personas indépendantes). Tous
-- les fixes vérifiés et déployés en prod le 2026-05-21 :
--
--   1. tracker_first_seen_global() retournait 2025-05-20 (event-fantôme
--      avec horloge client cassée d'1 an). Fix : guard ±2j entre
--      occurred_at et received_at. Cf section 6.5 ci-dessus.
--
--   2. seo_pages_overview et url_decode étaient anon-executable
--      (oversight des Sprint 13ter / 17). Revoked anon, authenticated,
--      public — granted service_role uniquement.

revoke execute on function public.seo_pages_overview(timestamptz, timestamptz) from public;
revoke execute on function public.seo_pages_overview(timestamptz, timestamptz) from anon;
revoke execute on function public.seo_pages_overview(timestamptz, timestamptz) from authenticated;
grant  execute on function public.seo_pages_overview(timestamptz, timestamptz) to service_role;

revoke execute on function public.url_decode(text) from public;
revoke execute on function public.url_decode(text) from anon;
revoke execute on function public.url_decode(text) from authenticated;
grant  execute on function public.url_decode(text) to service_role;

-- 3. form_submit retiré de ALLOWED_EVENTS de l'Edge `track`. La forge
--    via /track public est désormais rejetée (HTTP 400 no_valid_events,
--    vérifié par curl). Voir supabase/functions/track/index.ts L42-82.
--
-- 4. À investiguer (Sprint 30) : bots Adwords/Display WebView Android
--    qui passent à travers events_human (4 sessions identifiées sur
--    2026-05-19 → 21, ~88 anchor clicks sur /). Pattern : UA contient
--    "wv)" + country='IE' + referrer ad-tech (safeframe.googlesyndication,
--    doubleclick.net, atlas.taboolanews) + >5 anchor_clicks/session.
--    À ajouter dans refresh_noise_sessions().


-- ============================================================
-- Sprint 30 (2026-05-21) — audit chirurgical : fix biais RPCs + zombies + drift
-- ============================================================
-- Sortie d'un audit multi-agent (7 personas DB + tracking + code). Tous les
-- findings cross-validés runtime avant fix. Détails dans le commit Sprint 30.
--
-- 1. Zombies droppés (idx_events_props_gin 0 scans/3.5MB, 5 vues mortes,
--    colonnes email_clicks_*, PK rename) — migration sprint30_drop_zombies_v2.
--
-- 2. Fix 3 RPCs avec biais validés en SQL :
--    - cta_breakdown_for_path : masquait 42% des CTAs anchor (filtre cta_type
--      IS NOT NULL après LEFT JOIN du map de mapping). Fix : anchor non
--      mappé devient 'anchor_nav', plus jamais jeté.
--    - engagement_density_for_path : sessions over-counted 19% (CTE retournait
--      1 row par page_exit). Fix : GROUP BY session_id + max(dwell).
--    - pogo_rates_for_period : LEFT JOIN session_exit dupliquait 26% +
--      sessions sans page_exit (pagehide bloqué) traitées comme "pas pogo"
--      alors qu'elles sont les pogos les plus durs. Fix : GROUP BY (session_id,
--      path) + traiter NULL exit comme pogo single-page.
--    Migration sprint30_fix_biased_rpcs.

-- ============================================================
-- Sprint 27/29 pulled-from-prod (2026-05-21) — drift repo↔prod fermé
-- ============================================================
-- Ces objets ont été créés en prod via apply_migration MCP entre Sprint 25 et
-- Sprint 29 mais jamais commités dans le repo. Marek Kowalski (code archéologie)
-- les a identifiés comme drift. Sync ici pour disaster recovery et lisibilité.

-- ---------- rpc_health (Sprint 27 contract tests) ----------
create table if not exists public.rpc_health (
  id            bigserial primary key,
  rpc_name      text not null,
  status        text not null,            -- 'ok' | 'failed'
  detail        text,
  rows_returned bigint,
  duration_ms   numeric,
  checked_at    timestamptz not null default now()
);
create index if not exists idx_rpc_health_checked_at on public.rpc_health (checked_at desc);
create index if not exists idx_rpc_health_rpc_status on public.rpc_health (rpc_name, status, checked_at desc);
alter table public.rpc_health enable row level security;

-- ---------- form_submit dedup unique partial index (Sprint 25) ----------
create unique index if not exists events_form_submit_submission_id_uniq
  on public.events (((props->>'submission_id')))
  where name = 'form_submit' and (props->>'submission_id') is not null;

-- ---------- purge_old_events() (Sprint 27 retention) ----------
-- Voir prod pour body complet. Tourne via pg_cron monthly (1st @ 04:00 UTC).
-- Supprime tout event > 400 jours. À 12k events/jour = 4.8M lignes annuelles
-- jamais purgées avant 13 mois — donc le job ne supprime rien pendant 13 mois,
-- c'est normal. Pas de VACUUM dans la fonction (interdit en transaction) →
-- à scripter manuellement après le 1er gros run en juin 2027.

-- ---------- run_rpc_contract_tests() (Sprint 27) ----------
-- Exécute 8 RPC publiées avec args triviaux + log dans rpc_health.
-- Tourne nightly 03:30 UTC. Détecte les régressions de contrat ou les
-- exceptions PG. Voir latest_rpc_health() pour la vue agrégée.

-- ---------- refresh_pipeline_health() (Sprint 25 diagnostic) ----------
-- Self-diagnostic 3-axes : snapshot freshness, cron last status, ingestion
-- last event. Retourne 1 row avec status text in ('healthy','degraded','critical')
-- + issues text[]. À brancher sur un GitHub Action externe pour alerting.

-- ---------- latest_rpc_health() (Sprint 27) ----------
-- DISTINCT ON par rpc_name de la table rpc_health pour ne garder que le
-- dernier test de chaque RPC. + age_minutes calculé pour détecter les
-- contract_tests qui ne tournent plus.

-- ---------- pg_cron schedule ----------
-- 4 jobs actifs :
--   refresh_seo_url_snapshot    0 3 * * *     (rebuild snapshot nightly 05:00 Paris)
--   refresh_noise_filters_hourly 5 * * * *    (bot + noise re-scan toutes les heures)
--   run_rpc_contract_tests      30 3 * * *    (contract tests 05:30 Paris)
--   purge_old_events_monthly    0 4 1 * *     (rétention 400j, 1er du mois 06:00 Paris)
--
-- Le code exact des CREATE FUNCTION lives en prod. Pour rebuild from scratch,
-- récupérer via `pg_get_functiondef()` ou Supabase CLI `db pull`.


-- ============================================================
-- Sprint 31-32 (21-22/05/2026) — Google Search Console
-- ============================================================
-- Schéma DDL + fonction canonical_path(text) :
--   → supabase/migrations/20260522120000_gsc_tables.sql
--
-- Ingestion : scripts/gsc_common.py, CLI scripts/gsc_ingest.py
--   (wrappers rétro-compat gsc_ingest_path_and_query.py / query_page.py)
--
-- Jointure Cooked × GSC :
--   canonical_path(events.path) = gsc_path_daily.path
--   (Edge track canonicalPath() aligné depuis refactor qualité 22/05/2026)
--
-- Volume backfill initial (16 mois → 19/05/2026) : voir README section GSC.
--
-- TODO Sprint 33+ : pg_cron quotidien (J-3 → J-1, dataState=final).
