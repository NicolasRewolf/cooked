# cooked

First-party SEO event tracking for **jplouton-avocat.fr** (Wix Studio).
Cookieless, RGPD-exempt, non-sampled — designed to feed clean behavioural
data to a downstream AI for SEO analysis (see the consuming repo
[seo](https://github.com/NicolasRewolf/seo)).

```
Browser
  │  POST /_functions/track   (same-origin, no CORS, no adblocker)
  ▼
Wix Velo HTTP function
  │  fetch — auth header injected server-side (key never reaches the browser)
  ▼
Supabase Edge Function /track          [ DEPLOYED ]
  │  hash IP+UA → anonymous_id (rotates daily)
  │  parse UA, geo header → enrich row
  ▼
Postgres   ─────────────►   pg_cron 03:00 UTC      [ SCHEDULED ]
  events                    refresh_seo_url_snapshot()
                                       │
                                       ▼
                            seo_url_snapshot   (1 row / URL × rolling windows)
                                       │
                                       ▼
                  behavior_pages_for_period(from, to) RPC
                                       │
                                       ▼
                  Consumed cross-project by the seo audit tool
```

## Repo layout

```
cooked/
├── supabase/
│   ├── schema.sql                    -- events table + indexes + RLS
│   ├── views.sql                     -- parametric function, snapshot table,
│   │                                    refresh function, pg_cron schedule,
│   │                                    companion 28d views, behavior RPC
│   └── functions/track/index.ts      -- Edge Function (Deno)
├── wix/
│   ├── http-functions.js             -- Velo proxy (backend/http-functions.js)
│   └── tracker.html                  -- Wix Custom Code <head>
└── README.md
```

## Deployment status (live as of 2026-05-06)

| Component | State | Notes |
|---|---|---|
| Supabase project | ✅ Created | `cooked` (`mxycmjkeotrycyneacje`), region `eu-west-1` |
| `events` table + indexes + RLS | ✅ Deployed | RLS on, no policies → only service-role can read/write |
| `pg_cron` extension | ✅ Enabled | |
| `seo_pages_overview()` parametric function | ✅ Deployed | with `search_path` pinned |
| `seo_url_snapshot` table | ✅ Deployed | RLS on, refreshed daily via cron, includes Sprint 10 phone/email click counts |
| `seo_traffic_sources_28d` / `seo_landing_pages_28d` / `seo_daily_summary` views | ✅ Deployed | `security_invoker` |
| `behavior_pages_for_period(from, to)` RPC (cross-project) | ✅ Deployed | granted to `service_role` only |
| Daily refresh cron (03:00 UTC) | ✅ Scheduled | `refresh_seo_url_snapshot` job |
| Edge Function `track` | ✅ Deployed v4 | `verify_jwt: false`, `ALLOWED_ORIGIN` baked-in, accepts Sprint 10 events |
| Velo proxy `/_functions/track` | ✅ Live | served same-origin from jplouton-avocat.fr |
| Wix Custom Code `<head>` tracker | ✅ Live | All pages — Sprint 10 conversion listeners included |

## Project IDs (reference)

- **Supabase project ref:** `mxycmjkeotrycyneacje`
- **Project URL:** `https://mxycmjkeotrycyneacje.supabase.co`
- **Edge Function URL:** `https://mxycmjkeotrycyneacje.supabase.co/functions/v1/track`
- **Region:** `eu-west-1` (Ireland)
- **Live endpoint (same-origin):** `https://www.jplouton-avocat.fr/_functions/track`

## Privacy & RGPD

- No cookies, no localStorage, no persistent identifier.
- `anonymous_id` is `sha256(IP | User-Agent | daily-salt)` truncated — rotates
  every day, irreversible, doesn't survive 24 h.
- `session_id` lives in `sessionStorage` only (cleared on tab close).
- IPs never stored — only hashed in transit.

This setup is **exempted from cookie-banner consent** under CNIL délibération
2020-091 and the 2022 guidelines (mesure d'audience strictement statistique,
pas de recoupement, pas de transfert tiers, identifiant non pérenne).

## What the AI gets to query

### Flat snapshot — 1 row per URL (the "440-line table")

```sql
select * from public.seo_url_snapshot;
```

Columns per URL:

- For each window (`_7d`, `_28d`, `_90d`, `_365d`):
  - `views`, `unique_visitors`, `sessions`
  - `bounce_rate`, `avg_dwell_seconds`
  - `scroll_avg`, `scroll_median`, `scroll_complete_pct`
  - `entry_count`, `exit_count`, `outbound_clicks`
  - `phone_clicks` _(Sprint 10 — taps on `tel:` links)_
  - `email_clicks` _(Sprint 10 — taps on `mailto:` links)_
- Core Web Vitals (28d, p75 — the value Google uses for ranking):
  `lcp_p75_28d_ms`, `inp_p75_28d_ms`, `cls_p75_28d`, `ttfb_p75_28d_ms`
- Sources (28d): `top_referrer_28d`, `top_source_28d`, `top_medium_28d`
- `device_split_28d` (jsonb, e.g. `{"desktop":62.0,"mobile":35.5,"tablet":2.5}`)

### Parametric — any window the AI wants

```sql
-- Last 14 days
select * from public.seo_pages_overview(now() - interval '14 days', now());

-- Specific date range
select * from public.seo_pages_overview('2026-04-01', '2026-05-01');
```

### Companion 28-day views

```sql
select * from public.seo_traffic_sources_28d;   -- by source / medium
select * from public.seo_landing_pages_28d;     -- entry pages
select * from public.seo_daily_summary;         -- site-wide daily aggregates
```

### Cross-project RPC (consumed by seo audit tool)

```sql
-- Returns 1 row per URL with full behavioural + CWV + outbound aggregates
-- over the [from, to) window. Granted to service_role only.
-- NOTE: Sprint 10 phone_clicks / email_clicks are NOT yet exposed via this
-- RPC — query seo_url_snapshot directly until a Sprint 11 broadens the
-- contract (kept narrow now to avoid coupling the seo tool to Cooked-side
-- migrations).
select * from public.behavior_pages_for_period(
  '2026-04-01'::timestamptz,
  '2026-05-01'::timestamptz
);
```

### Conversion CTAs (Sprint 10 Phase 1)

```sql
-- Top pages génératrices d'appels
select path, phone_clicks_28d, sessions_28d,
       round(100.0 * phone_clicks_28d / nullif(sessions_28d, 0), 2)
         as call_rate_pct
from public.seo_url_snapshot
where phone_clicks_28d > 0
order by phone_clicks_28d desc
limit 20;

-- Pages qui drainent du trafic mais ne génèrent aucun appel ni e-mail
-- = friction CTA, candidates pour ajout de bouton "Prendre rendez-vous"
select path, sessions_28d, phone_clicks_28d, email_clicks_28d,
       avg_dwell_seconds_28d, scroll_avg_28d
from public.seo_url_snapshot
where sessions_28d >= 30
  and phone_clicks_28d = 0
  and email_clicks_28d = 0
order by sessions_28d desc;

-- Comparaison des deux canaux de conversion par catégorie de page
select
  case
    when path like '/defense-penale/%'        then 'defense_penale'
    when path like '/indemnisation-des-victimes/%' then 'indemnisation'
    when path like '/droit-des-contrats-et-des-personnes/%' then 'droit_contrats'
    when path = '/honoraires-rendez-vous'     then 'honoraires_rdv'
    when path like '/post/%'                  then 'blog'
    else 'other'
  end as bucket,
  sum(sessions_28d)      as sessions,
  sum(phone_clicks_28d)  as phone_clicks,
  sum(email_clicks_28d)  as email_clicks
from public.seo_url_snapshot
group by bucket
order by phone_clicks desc;
```

## Maintenance

- The cron rebuilds `seo_url_snapshot` daily at 03:00 UTC. Force a refresh:
  `select public.refresh_seo_url_snapshot();` (service-role only)
- To rotate `ANON_SALT`: update the Edge Function secret. Old `anonymous_id`s
  no longer collide with new ones.
- Trim retention (e.g. >13 months):
  ```sql
  delete from public.events where occurred_at < now() - interval '13 months';
  ```

## Re-deploying the Edge Function from this repo

```bash
brew install supabase/tap/supabase
cd cooked
supabase login
supabase link --project-ref mxycmjkeotrycyneacje
supabase functions deploy track --no-verify-jwt
```

`--no-verify-jwt` is required: requests come from the Velo proxy without a
Supabase user JWT (we authorise via service-role key in the proxy).

## Re-applying the schema from this repo

Connect to the SQL Editor of the project and run:

1. `supabase/schema.sql` (idempotent, safe to re-run)
2. `supabase/views.sql` (idempotent, safe to re-run — also re-schedules the cron)

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `404` on `/_functions/track` | Site not republished after adding the Velo file |
| `403 forbidden_origin` (Velo) | Tracker loading from a host other than `www.jplouton-avocat.fr` |
| `500 proxy_error` (Velo) | Velo Secret missing/wrong — check `SUPABASE_TRACK_URL` & `SUPABASE_SERVICE_KEY` |
| Edge Function `401` | JWT verification was re-enabled — set `verify_jwt: false` |
| No rows in `events` | Adblocker on `/_functions/track`? Curl from another network |
| Snapshot empty | Cron didn't run yet — `select public.refresh_seo_url_snapshot();` |
