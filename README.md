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

## Deployment status (live as of 2026-05-07)

| Component | State | Notes |
|---|---|---|
| Supabase project | ✅ Created | `cooked` (`mxycmjkeotrycyneacje`), region `eu-west-1` |
| `events` table + indexes + RLS | ✅ Deployed | RLS on, no policies → only service-role can read/write |
| `pg_cron` extension | ✅ Enabled | |
| `seo_pages_overview()` parametric function | ✅ Deployed | with `search_path` pinned |
| `seo_url_snapshot` table | ✅ Deployed | RLS on, refreshed daily via cron, includes Sprint 10 phone + booking CTA counters |
| `seo_traffic_sources_28d` / `seo_landing_pages_28d` / `seo_daily_summary` views | ✅ Deployed | `security_invoker` |
| `behavior_pages_for_period(from, to)` RPC (cross-project, Sprint 8) | ✅ Deployed | granted to `service_role` only |
| Sprint 12 RPCs : `snapshot_pages_export`, `site_context_export`, `outbound_destinations_for_path`, `cta_breakdown_for_path` | ✅ Deployed | full-menu contract for seo audit tool, granted to `service_role` only |
| Daily refresh cron (03:00 UTC) | ✅ Scheduled | `refresh_seo_url_snapshot` job |
| Edge Function `track` | ✅ Deployed v5 | `verify_jwt: false`, `ALLOWED_ORIGIN` baked-in, accepts all Sprint 10 events |
| Velo proxy `/_functions/track` | ✅ Live | served same-origin from jplouton-avocat.fr |
| Wix Custom Code `<head>` tracker | ✅ Live | All pages — Sprint 10 Phase 1 + 1.5 conversion listeners |

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

## Tracked events

The browser-side `tracker.html` snippet (Wix Custom Code, head, all pages)
emits these event types. Anything else is rejected by the Edge Function's
`ALLOWED_EVENTS` allow-list.

| Event name | When it fires | Useful props |
|---|---|---|
| `pageview` | First load + every SPA navigation (push/replace/popstate) | `path`, `title`, `referrer`, `utm_*`, `viewport_*` |
| `scroll_depth` | Each of 25/50/75/100 % is hit once per page | `percent` |
| `engagement_tick` | Every 10 s of **active** time (idle / hidden tab paused) | `active_ms` |
| `web_vitals` | LCP / INP / CLS / TTFB, flushed on tab hide / page unload | `metric`, `value` |
| `click_outbound` | Click on an `<a>` whose hostname differs from the site | `href`, `hostname`, `anchor` |
| `page_exit` | `pagehide` / `beforeunload` / tab hidden — once per page life | `duration_seconds`, `max_scroll` |
| `cta_phone_click` | Click on any `<a href="tel:...">` anywhere on the site | `phone`, `anchor`, `placement` (footer/header/body) |
| `cta_booking_click` | Click on the deliberate header **or** footer CTA pointing to `/honoraires-rendez-vous`. Editorial body links to the same target are filtered out at the tracker level | `anchor`, `placement` (always `header` or `footer`), `target_path`, `href` |

Anonymisation lives in the Edge Function, not the tracker:
the `anonymous_id` is computed server-side from
`sha256(IP | User-Agent | daily-salt)` truncated to 16 hex chars and
rotates daily — no client-side persistent identifier ever leaves the
browser, no cookies, no `localStorage`. Only `sessionStorage` is used to
keep the per-tab `session_id`.

## Sprint history

| Sprint | Date | Scope |
|---|---|---|
| **0 — Initial deploy** | 2026-05-06 | Tracker + Velo proxy + Edge Function `track` v1 + `events` table + `seo_url_snapshot` + 28d companion views + `pg_cron` daily refresh + cross-project `behavior_pages_for_period()` RPC |
| **10 Phase 1 — Phone + email click capture** | 2026-05-07 | New events `cta_phone_click` / `cta_email_click` + 8 new per-window columns on `seo_url_snapshot` (`phone_clicks_*` / `email_clicks_*`) + Edge Function v4 |
| **10 Phase 1.5 — Booking-CTA capture, header/footer scoped** | 2026-05-07 | New event `cta_booking_click` (clicks on header / footer CTAs to `/honoraires-rendez-vous`, body editorial links filtered out at tracker level) + 4 new columns `booking_cta_clicks_*` on `seo_url_snapshot` + Edge Function v5. Mailto branch dropped from the tracker. |
| **12 — Full-menu RPC contract for seo** | 2026-05-07 | 4 new RPCs published as the cross-project contract for the seo full-menu audit (Sprint 12 SEO-side): `snapshot_pages_export(paths)`, `site_context_export()`, `outbound_destinations_for_path(path, days_back)`, `cta_breakdown_for_path(path, days_back)`. The 4th is the central conversion-intent disambiguation signal (header / footer / body breakdown). All four `granted to service_role only`, signatures aligned on the TS shapes published in `seo/src/lib/cooked.ts`. |

### Roadmap (not committed yet)

- **Phase 2 — Form funnel** (planned). When Sprint 11 of the seo audit
  tool ships, instrument the Wix Forms V2 widget on the 14 expertise
  pages + `/honoraires-rendez-vous` to fire `form_view`,
  `form_start`, `form_field_blur`, `form_abandon` from the browser, plus
  `form_submit_success` from a Velo `masterPage.js`
  `$w('#form').onWixFormSubmitted(...)` handler. That gives a per-page
  conversion funnel from impression to booked appointment.

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
  - `phone_clicks` _(Sprint 10 — taps on `tel:` links anywhere on the
     site — every page is a potential conversion point because the
     phone number sits in the global footer)_
  - `email_clicks` _(Sprint 10 — kept for backward-compat, never
     populated since the site has no `mailto:` links and the tracker no
     longer fires `cta_email_click`)_
  - `booking_cta_clicks` _(Sprint 10 Phase 1.5 — clicks on the
     deliberate header / footer CTAs that drive to
     `/honoraires-rendez-vous`. Editorial inline links in article bodies
     pointing to the same target ("cabinet Plouton", "notre équipe", …)
     are intentionally **NOT** counted, so this metric is a clean
     conversion-intent signal)_
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

### Cross-project RPCs (consumed by the seo audit tool)

5 RPCs exposed to the seo audit tool, all `granted to service_role only`.

#### `behavior_pages_for_period(from, to)` — original (Sprint 8)

Returns 1 row per URL with the 12-column subset over a user-supplied
window. Kept stable for the original `snapshotBehaviorPages` pipeline in
seo. Newer signals (Sprint 10 conversion CTAs, multi-window…) are NOT
exposed here — see the Sprint 12 RPCs below.

```sql
select * from public.behavior_pages_for_period(
  '2026-04-01'::timestamptz,
  '2026-05-01'::timestamptz
);
```

#### `snapshot_pages_export(paths text[] default null)` — Sprint 12

Returns the latest pre-computed snapshot rows (full 66 columns of
`seo_url_snapshot`). Filtering by paths is optional. Used by the seo
diagnose / fix-gen / issue-render pipelines to surface CWV + multi-window
+ provenance + device + conversion CTAs all at once.

```sql
-- All pages
select * from public.snapshot_pages_export();

-- Just the pages that have findings this audit run
select * from public.snapshot_pages_export(array[
  '/post/abandon-de-poste-quels-risques',
  '/honoraires-rendez-vous'
]);
```

#### `site_context_export()` — Sprint 12

One row of site-wide context (last 28 days), injected verbatim into the
diagnostic prompt's `<site_context>` block so the LLM can calibrate
per-page metrics against site averages.

```sql
select * from public.site_context_export();
-- global_sessions_28d           : 1396
-- global_bounce_rate_28d        : 0.6203 (already 0..1)
-- sessions_per_day_median_28d   : 49.5
-- sessions_trend_pct_7d_vs_28d  : +12.5  (signed % delta vs 28d rate)
-- top_sources_28d               : [{source, medium, sessions} × top 5]
```

#### `outbound_destinations_for_path(path, days_back)` — Sprint 12

Top-10 external hostnames clicked outbound from a given page over the
last `days_back` days. Lets the LLM diagnose "outbound leak" patterns
("users fleeing toward legifrance.gouv.fr from a juridique page →
suggest an in-page citation").

```sql
select * from public.outbound_destinations_for_path(
  '/post/bail-commercial-la-revision-du-loyer-comment-est-ce-que-cela-fonctionne',
  28
);
-- hostname     | clicks
-- claude.ai    |      2
```

#### `cta_breakdown_for_path(path, days_back)` — Sprint 12

The disambiguating signal. Splits CTA clicks by
`(cta_type, placement, anchor_sample)` so the LLM can tell the
difference between:

- **5 phone clicks all in `footer`** → ambient cabinet-wide CTA, low
  intent
- **5 phone clicks all in `body`** → qualified intent on this specific
  page, high signal

Enum values are exact: `cta_type ∈ {'phone', 'email', 'booking'}`,
`placement ∈ {'header', 'footer', 'body'}`. One row per distinct anchor
(option (c) of the contract — caller can re-aggregate to
`(cta_type, placement)` if needed).

```sql
select * from public.cta_breakdown_for_path('/', 28);
-- cta_type | placement | anchor_sample      | clicks
-- phone    | footer    | 05 56 44 35 96     |      2
-- booking  | header    | Contactez - nous   |      1
```

### Conversion CTAs (Sprint 10 Phase 1 + 1.5)

```sql
-- Top pages génératrices d'appels (Path A — phone)
select path, phone_clicks_28d, sessions_28d,
       round(100.0 * phone_clicks_28d / nullif(sessions_28d, 0), 2)
         as call_rate_pct
from public.seo_url_snapshot
where phone_clicks_28d > 0
order by phone_clicks_28d desc
limit 20;

-- Top pages qui drainent vers le formulaire (Path B — booking)
select path, booking_cta_clicks_28d, sessions_28d,
       round(100.0 * booking_cta_clicks_28d / nullif(sessions_28d, 0), 2)
         as booking_intent_rate_pct
from public.seo_url_snapshot
where booking_cta_clicks_28d > 0
order by booking_cta_clicks_28d desc
limit 20;

-- Funnel total par page (les deux paths combinés)
select path, sessions_28d, phone_clicks_28d, booking_cta_clicks_28d,
       (phone_clicks_28d + booking_cta_clicks_28d) as total_conversion_intents,
       round(100.0 * (phone_clicks_28d + booking_cta_clicks_28d)
             / nullif(sessions_28d, 0), 2) as conversion_intent_rate_pct
from public.seo_url_snapshot
where sessions_28d > 0
order by total_conversion_intents desc
limit 30;

-- Pages high-trafic SANS aucun signal de conversion = vraie friction
-- (candidates pour ajouter une CTA visible)
select path, sessions_28d, avg_dwell_seconds_28d, scroll_avg_28d
from public.seo_url_snapshot
where sessions_28d >= 30
  and phone_clicks_28d = 0
  and booking_cta_clicks_28d = 0
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
  sum(sessions_28d)               as sessions,
  sum(phone_clicks_28d)           as phone_clicks,
  sum(booking_cta_clicks_28d)     as booking_clicks
from public.seo_url_snapshot
group by bucket
order by phone_clicks + booking_clicks desc;
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
