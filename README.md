# Cooked

**First-party SEO event tracking for [jplouton-avocat.fr](https://www.jplouton-avocat.fr) (Wix Studio).**

Cookieless, RGPD-exempt, non-sampled — designed to feed clean behavioural data to a downstream AI for SEO analysis (see the consuming repo [seo](https://github.com/NicolasRewolf/seo)).

---

## Architecture

```
Browser (Wix Custom Code <head>)
   │  tracker.html — pageview / scroll / engagement / web_vitals /
   │                  click_outbound / page_exit / cta_phone_click /
   │                  cta_booking_click
   ▼ POST /_functions/track  (same-origin, no CORS, no adblocker)

Wix Velo HTTP proxy
   │  http-functions.js — injects Bearer key server-side
   │                       (key never reaches the browser)
   ▼ POST with Authorization: Bearer <service_role>

Supabase Edge Function `/track` (Deno)
   │  hash(IP | UA | daily-salt) → anonymous_id (rotates daily)
   │  parse UA → device / browser / os
   │  decodeURIComponent(path)   (Sprint 13 fix for French URLs)
   ▼ INSERT

Postgres
   │  events table (raw)
   │     ↓ bot_fingerprints (Sprint 17 — nightly bot detection)
   │     ↓ events_human view (events MINUS bot traffic)
   │
   │  pg_cron 03:00 UTC
   │     ↓ refresh_seo_url_snapshot()
   │
   │  seo_url_snapshot table (1 row / URL × rolling windows 7d/28d/90d/365d)
   ▼ RPCs (service_role only, cross-project secret)

Seo audit tool (separate repo)
   └─ diagnostic pipeline → GitHub issues
```

---

## Privacy & RGPD

- **No cookies, no localStorage, no persistent identifier**
- `anonymous_id` = `sha256(IP | User-Agent | daily-salt)` truncated, rotates daily — irreversible, doesn't survive 24h
- `session_id` lives in `sessionStorage` only (cleared on tab close)
- IPs never stored — only hashed in transit

**Exempted from cookie-banner consent** under CNIL délibération 2020-091 and the 2022 guidelines (mesure d'audience strictement statistique, pas de recoupement, pas de transfert tiers, identifiant non pérenne).

---

## Tracked events

The browser-side `tracker.html` emits these events. Anything else is rejected by the Edge Function's allow-list.

| Event | When it fires | Useful props |
|---|---|---|
| `pageview` | Initial load + every SPA navigation | `path`, `title`, `referrer`, `utm_*`, `viewport_*` |
| `scroll_depth` | 25 / 50 / 75 / 100 % milestones (once per page) | `percent` |
| `engagement_tick` | Every 10s of active time (paused on idle / hidden tab) | `active_ms` |
| `web_vitals` | LCP / INP / CLS / TTFB | `metric`, `value` |
| `click_outbound` | Click on an external `<a>` | `href`, `hostname`, `anchor` |
| `page_exit` | `pagehide` / `beforeunload` / tab hidden | `duration_seconds`, `max_scroll` |
| `cta_phone_click` | Click on any `<a href="tel:…">` | `phone`, `anchor`, `placement` (header / footer / body) |
| `cta_booking_click` | Click on any `<a>` pointing to `/honoraires-rendez-vous` | `anchor`, `placement` (header / footer / body), `target_path`, `href` |

### Anchor capture convention (since 2026-05-10)

The `anchor` field in `cta_*_click` events is captured with this priority:

1. **`aria-label`** if present (semantic intent, accessible name)
2. **`textContent`** as fallback

On jplouton-avocat.fr, all CTA buttons use the convention:

```
aria-label = "<Action> — <Location>"
```

Examples:
- `Appeler le cabinet — hero`
- `Prendre rendez-vous — header`
- `Appeler le cabinet — barre mobile expertise`
- `Demander un RDV — formulaire expertise`

This makes per-emplacement analytics a 1-line query (`split_part(anchor, ' — ', 2)`) instead of guessing from raw textContent.

---

## Repo layout

```
cooked/
├── CLAUDE.md                          — Claude Code agent instructions
│                                        + site taxonomy + coordination
│                                        protocol with the seo agent
├── README.md                          — this file
├── supabase/
│   ├── schema.sql                     — events table + indexes + RLS
│   ├── views.sql                      — all functions, views, snapshot
│   │                                    table, refresh function, pg_cron
│   │                                    schedule, bot filtering, RPCs
│   └── functions/track/index.ts       — Edge Function (Deno)
└── wix/
    ├── http-functions.js              — Velo proxy backend
    └── tracker.html                   — Wix Custom Code <head>
```

---

## What the seo agent can query (cross-project RPCs)

All RPCs are `granted to service_role only`. No `anon` / `authenticated` access.

| RPC | Returns |
|---|---|
| `snapshot_pages_export(paths text[])` | Latest snapshot rows (66 cols : 4 windows × 11 metrics + CWV + provenance + device + CTAs). Filter by paths optional. |
| `site_context_export()` | One row of site-wide context 28d (sessions, bounce rate, top sources, sessions trend) |
| `behavior_pages_for_period(from, to)` | One row / URL with 12-col subset over the requested window |
| `seo_pages_overview(from, to)` | Same as above, parametric date range |
| `outbound_destinations_for_path(path, days)` | Top external hostnames clicked from a given page |
| `cta_breakdown_for_path(path, days)` | CTA clicks split by `(cta_type, placement, anchor)` |
| `engagement_density_for_path(path, days)` | Dwell distribution (p25 / median / p75 + evenness_score) — detects bimodal patterns (bouncers + deep readers) |
| `pogo_rates_for_period(from, to)` | Pogo-stick detection per page (Google sessions returning to SERP) |
| `tracker_first_seen_global()` | Earliest event timestamp (used for pro-rating capture rate during bootstrap) |

The full SQL is in `supabase/views.sql`. Contract signatures are stable since Sprint 13bis.

---

## Bot filtering (Sprint 17)

Cooked detects and excludes crawler traffic at the analytics layer, without touching raw events.

```
events (raw, unchanged — all hits kept for audit)
   ↓
bot_fingerprints  (anonymous_ids flagged as bots, refreshed nightly)
   ↓
events_human VIEW  (events MINUS bot_fingerprints)
   ↓
ALL RPCs + snapshot read from events_human
```

**Detection rule** : `anonymous_id` with > 20 pageviews/day AND 0 scroll events = crawler. Catches the nightly Ahrefs audit crawler and similar bots.

`refresh_bot_fingerprints()` is called automatically at the start of `refresh_seo_url_snapshot()`. One pg_cron job handles both.

---

## Deployment

### Re-deploying the Edge Function

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref mxycmjkeotrycyneacje
supabase functions deploy track --no-verify-jwt
```

`--no-verify-jwt` is required: requests come from the Velo proxy without a Supabase user JWT (auth is via service-role key injected by the proxy).

### Re-applying the schema

In the Supabase SQL Editor:

1. `supabase/schema.sql` (idempotent, safe to re-run)
2. `supabase/views.sql` (idempotent, safe to re-run — also re-schedules the cron)

### Updating the browser tracker

Copy the contents of `wix/tracker.html` into:
**Wix Admin → Settings → Custom Code → Add Custom Code → Head → All pages**

Then republish the site.

### Updating the Velo proxy

Copy `wix/http-functions.js` into the Velo backend:
**Wix Admin → Code → Backend → http-functions.js**

The Velo secrets `SUPABASE_TRACK_URL` and `SUPABASE_SERVICE_KEY` must be set in Wix Admin → Settings → Secrets Manager.

---

## Project IDs (reference)

- **Supabase project ref** : `mxycmjkeotrycyneacje`
- **Project URL** : `https://mxycmjkeotrycyneacje.supabase.co`
- **Edge Function URL** : `https://mxycmjkeotrycyneacje.supabase.co/functions/v1/track`
- **Region** : `eu-west-1` (Ireland)
- **Live endpoint (same-origin)** : `https://www.jplouton-avocat.fr/_functions/track`

---

## Security model

Defense-in-depth on the Supabase side:

- **`events`, `seo_url_snapshot`, `bot_fingerprints` have RLS enabled with no policies — by design.** This is the deny-all-to-clients pattern: only `service_role` (used by the Edge Function and the seo audit tool's cross-project secret) bypasses RLS. The "RLS enabled, no policies" INFO-level advisor flag is expected and acceptable.
- **`rls_auto_enable()` event trigger** auto-enables RLS on every newly-created table in `public` — belt-and-suspenders against forgetting the `enable row level security` in a future migration.
- **All cross-project RPCs are granted to `service_role` only**. `public`, `anon`, `authenticated` have no EXECUTE on any of them.
- **`SECURITY DEFINER` functions pin `search_path`** to prevent search_path injection.
- **`security_invoker = true`** on `events_human` and `seo_expertise_pages` views (Postgres 15+) — enforces caller's RLS, not creator's.

---

## Sprint history (recent)

| Sprint | Date | Scope |
|---|---|---|
| **17** | 2026-05-09 | **Centralized bot filtering** via `events_human` view. `refresh_bot_fingerprints()` runs before each snapshot refresh. All 9 RPCs + 3 views read from `events_human`. Also: body CTA tracking (cta_booking_click no longer scoped to header/footer only), `page_exit.duration_seconds` uses cumulative active time. |
| **Tracker — aria-label capture** | 2026-05-10 | `cta_*_click` events capture `aria-label` in priority over `textContent`. Enables per-emplacement analytics via the `<Action> — <Location>` convention rolled out on the 13 CTA buttons of the site. |
| **13bis** | 2026-05-07 | `tracker_first_seen_global()` RPC for capture-rate pro-rating during bootstrap. |
| **13** | 2026-05-07 | Path-encoding fix — Edge Function decodes `path` via `decodeURIComponent` before insert. Backfill of 6531 historical events with the new `url_decode()` plpgsql helper. |
| **12** | 2026-05-07 | Full-menu RPC contract for the seo audit tool : `snapshot_pages_export`, `site_context_export`, `outbound_destinations_for_path`, `cta_breakdown_for_path`. |
| **10 Phase 1 + 1.5** | 2026-05-07 | Phone + booking CTA event tracking + counter columns on `seo_url_snapshot`. |
| **0** | 2026-05-06 | Initial deploy : tracker + Velo proxy + Edge Function v1 + `events` table + `seo_url_snapshot` + companion views + pg_cron daily refresh + first cross-project RPC. |

---

## Maintenance

```sql
-- Force snapshot refresh (service_role only)
SELECT public.refresh_seo_url_snapshot();

-- Inspect detected bots
SELECT * FROM public.bot_fingerprints;

-- Trim retention (>13 months)
DELETE FROM public.events WHERE occurred_at < now() - interval '13 months';
```

To rotate `ANON_SALT` : update the Edge Function secret. Old `anonymous_id`s will no longer collide with new ones (rotation is daily anyway, so the impact is limited).

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `404` on `/_functions/track` | Site not republished after adding the Velo file |
| `403 forbidden_origin` | Tracker loading from a host other than `www.jplouton-avocat.fr` |
| `500 proxy_error` | Velo Secret missing — check `SUPABASE_TRACK_URL` & `SUPABASE_SERVICE_KEY` |
| Edge Function `401` | JWT verification was re-enabled — redeploy with `--no-verify-jwt` |
| No rows in `events` | Adblocker on `/_functions/track`? Curl from another network to confirm |
| Snapshot empty | Cron didn't run yet — `SELECT public.refresh_seo_url_snapshot();` |
| Anchor stuck on `"Read More"` | Wix icon-only button without aria-label — add `aria-label` in Wix Studio settings |

---

## Working on this repo with Claude Code

See [`CLAUDE.md`](./CLAUDE.md) — it documents:

- The autonomy boundaries for the Cooked agent
- The coordination protocol with the **seo** agent (twin Claude Code session on the consuming project)
- The site taxonomy (4 page types : expertise, cabinet, posts ressources, posts classiques)
- Methodology takeaways from previous sprints

`CLAUDE.md` is auto-read by every Claude Code session that starts in this repo.
