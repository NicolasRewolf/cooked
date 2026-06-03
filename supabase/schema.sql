-- ============================================================
-- COOKED — first-party SEO event tracking
-- Schema: raw events table
-- ============================================================
-- Run this once in Supabase SQL Editor (or via supabase db push).

create extension if not exists "pgcrypto";

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),

  -- Identifiers (cookieless)
  anonymous_id text not null,        -- daily-rotating server-side hash
  session_id   text not null,        -- 30-min idle timeout, sessionStorage

  -- Event
  name text not null,                -- pageview | scroll_depth | engagement_tick
                                     -- web_vitals | click_outbound | page_exit

  -- Page context
  url               text,
  path              text,
  hostname          text,
  title             text,
  referrer          text,
  referrer_hostname text,

  -- UTM
  utm_source   text,
  utm_medium   text,
  utm_campaign text,
  utm_term     text,
  utm_content  text,

  -- Device
  user_agent      text,
  device_type     text,              -- mobile | tablet | desktop
  os              text,
  browser         text,
  viewport_width  int,
  viewport_height int,

  -- Geo
  country text,                      -- DEPRECATED (Sprint 36) : le header CDN renvoyait le
                                     -- datacenter (IE/US), jamais le visiteur. Capture retirée
                                     -- de l'Edge `track` → NULL pour tout nouvel event. Colonne
                                     -- conservée (events_human est `select e.*` → drop = cascade
                                     -- sur ~30 RPCs). Ne pas requêter. Géo fiable = via GSC.

  -- Custom payload (per-event extras: scroll percent, web-vital value, etc.)
  props jsonb not null default '{}'::jsonb,

  -- Timing
  occurred_at timestamptz not null default now(),  -- client-reported
  received_at timestamptz not null default now()   -- server-stamped
);

-- Indexes for common SEO queries
create index if not exists idx_events_path_occurred  on public.events (path, occurred_at desc);
create index if not exists idx_events_name_occurred  on public.events (name, occurred_at desc);
create index if not exists idx_events_session        on public.events (session_id);
create index if not exists idx_events_anonymous      on public.events (anonymous_id);
create index if not exists idx_events_occurred       on public.events (occurred_at desc);
create index if not exists idx_events_referrer_host  on public.events (referrer_hostname);
create index if not exists idx_events_props_gin      on public.events using gin (props);

-- Lock down: only service-role inserts (via Edge Function) and reads (via Studio).
alter table public.events enable row level security;
-- No policies created => anon and authenticated have no access.
