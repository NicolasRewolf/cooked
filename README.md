# Cooked

**First-party SEO event tracking for [jplouton-avocat.fr](https://www.jplouton-avocat.fr) (Wix Studio).**

Cookieless, RGPD-exempt, non-sampled. Cooked ingère également Google Search Console (depuis Sprint 31, 21/05/2026) pour combiner acquisition search × comportement on-page dans un seul Supabase.

---

## Architecture

```
Browser (Wix Custom Code <head>)
   │  tracker.html — pageview / scroll / engagement / web_vitals /
   │                  click_outbound / page_exit / cta_phone_click /
   │                  cta_booking_click / cta_anchor_click
   ▼ POST /_functions/track  (same-origin, no CORS, no adblocker)

   (form_submit is server-side only — see "Configuring form submission
   tracking" below: Wix Automation → form-webhook Edge Function.)

Wix Velo HTTP proxy
   │  http-functions.js — injects Bearer key server-side
   │                       (key never reaches the browser)
   ▼ POST with Authorization: Bearer <service_role>

Supabase Edge Function `/track` (Deno)
   │  resolve anonymous_id (browser-supplied UUID or IP+UA hash fallback)
   │  parse UA → device / browser / os
   │  canonicalPath(path)        (decode + NFC + strip slash — Sprint 13 + refactor 22/05/2026)
   │  reject `props` arrays (Sprint 30 hardening)
   ▼ INSERT

Postgres
   │  events table (raw)
   │     ↓ refresh_bot_fingerprints + refresh_noise_sessions (hourly)
   │     ↓ events_human view (events MINUS bots MINUS noise)
   │
   │  pg_cron 03:00 UTC
   │     ↓ refresh_seo_url_snapshot()
   │
   │  seo_url_snapshot table (1 row / URL × rolling windows 7d/28d/90d/365d)
   │
   │  Google Search Console (Sprint 31-32, ingested via scripts/gsc_ingest_*.py)
   │     ↓ Service Account JWT → GSC API
   │     ↓ gsc_common.canonical_path() (decode + NFC + slash ; URLs GSC complètes)
   │     ↓ upsert
   │  gsc_path_daily        — day × path
   │  gsc_query_daily       — day × query
   │  gsc_query_page_daily  — day × path × query (brique critique)
   │
   ▼ RPCs cross-source (migrations Sprint 33+)
     │
     ▼ dashboard/ (Next.js 15, READ-ONLY)
       Vue d'ensemble · Pages · Requêtes · Fiche page · Pipeline
       (Pulse GSC×Cooked, funnel SEO, sparklines — cf dashboard/README.md)
```

---

## Privacy & RGPD

- **No cookies. `localStorage` used for visitor identity and session continuity** — same approach as Plausible / Fathom Lite / Pirsch
- `anonymous_id` = random alphanumeric string (~28 chars), stored in `localStorage._ckd_aid` since Sprint 22 (2026-05-15). Persists indefinitely on the device. Falls back to `sha256(IP | User-Agent | daily-salt)` server-side hash if `localStorage` is blocked (Safari ITP strict, Firefox strict, privacy extensions)
- `session_id` lives in `localStorage._ckd` with a 30-minute sliding idle window since Sprint 28 (2026-05-21). Survives hard navigations (the previous `sessionStorage`-only design was producing ~10 % of fake "referral" sessions because Wix Studio's hard-nav was dropping the per-tab storage). Falls back to `sessionStorage` if `localStorage` is blocked
- IPs are never stored — only used as input for the server-side hash fallback, and rotated daily via the salt
- The browser-side identifiers (`_ckd_aid`, `_ckd`) are inspectable in DevTools → Application → Local Storage → the visitor can delete them at any time

**Exempted from cookie-banner consent** under CNIL délibération 2020-091 and the 2022 guidelines (mesure d'audience strictement statistique, pas de recoupement, pas de transfert tiers). The use of `localStorage` for a non-PII random UUID with no cross-site tracking and no advertising re-use is accepted by the CNIL within this exemption — see the [2022 guidelines, §"Solutions techniques exemptées"](https://www.cnil.fr/fr/cookies-et-traceurs-que-dit-la-loi).

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
| `cta_phone_click` | Click on any `<a href="tel:…">` | `phone`, `anchor`, `placement` (header / footer / sticky / body) |
| `cta_booking_click` | Click on any `<a>` pointing to `/honoraires-rendez-vous` | `anchor`, `placement` (header / footer / sticky / body), `target_path`, `href` |
| `cta_anchor_click` (Sprint 19) | Click on an in-page anchor: classic `href="#x"`, Wix anchor-menu (`<a href=current data-anchor="anchors-xxx">`), or any interactive element inside a sticky container | `target_section` (slugified label or hash), `anchor`, `placement` (header / footer / sticky / body), `source` (`click` / `hashchange` / `sticky-fallback`), `data_anchor` (Wix internal ID, optional) |
| `form_submit` (Sprint 18) | Wix Form successfully submitted — fired **server-side** by the `form-webhook` Edge Function, triggered by a Wix Automation on form submission | `form_id`, `submission_id`, `page_source`, `capture_source: 'wix-webhook'` |

### Anchor capture convention (depuis le 10/05/2026)

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
│                                        + site taxonomy + rules of thumb
├── README.md                          — this file
├── scripts/
│   ├── minify-tracker.py              — Minify tracker.html before Wix paste
│   ├── gsc_common.py                  — Lib partagée ingestion GSC
│   ├── gsc_ingest.py                  — CLI : path-query | query-page
│   ├── gsc_ingest_path_and_query.py   — Wrapper rétro-compat
│   ├── gsc_ingest_query_page.py       — Wrapper rétro-compat
│   ├── dfs_common.py                  — Lib ingestion DataForSEO (search_volume FR)
│   ├── dfs_sync.py                    — CLI sync hebdo top 500 keywords GSC → DFS
│   ├── deploy_track.py                — Déploi Edge Function track (MCP / CLI)
│   ├── requirements-gsc.txt           — pip deps pour scripts GSC
│   └── requirements-dfs.txt           — pip deps pour scripts DataForSEO
├── dashboard/                         — Interface lecture Cooked × GSC (Next.js)
│   ├── README.md                      — setup dev, routes, wrappers RPC
│   ├── CLAUDE.md                      — règles agent dashboard (silo READ-ONLY)
│   ├── app/                           — App Router (/, /pages, /queries, /p/…, /health)
│   ├── components/                    — KPI, Pulse, funnel, tableaux…
│   └── lib/cooked.ts                  — seul point d'accès Supabase (server-only)
├── .github/workflows/
│   ├── gsc-daily-ingest.yml           — cron GSC quotidien (06:00 UTC)
│   └── dfs-weekly-sync.yml            — cron DataForSEO hebdo (lundi 07:00 UTC)
├── supabase/
│   ├── schema.sql                     — events table + indexes + RLS
│   ├── migrations/                    — DDL nommé (GSC Sprint 31-32, etc.)
│   ├── views.sql                      — all functions, views, snapshot
│   │                                    table, refresh function, pg_cron
│   │                                    schedule, bot filtering, RPCs
│   └── functions/
│       ├── track/index.ts             — Tracker ingest Edge Function
│       └── form-webhook/index.ts      — Wix Automations webhook for forms
└── wix/
    ├── http-functions.js              — Velo proxy backend
    └── tracker.html                   — Wix Custom Code <head>
```

---

## Internal RPCs (consumed by analyses)

All RPCs are `granted to service_role only`. No `anon` / `authenticated` access.

| RPC | Returns |
|---|---|
| `snapshot_pages_export(paths text[])` | Latest snapshot rows (70 cols : 4 windows × ~11 metrics + CWV + provenance + device + CTAs + pogo + device CTA rate, post-Sprint-30). Filter by paths optional. |
| `site_context_export()` | One row of site-wide context 28d (sessions, bounce rate, top sources, sessions trend) |
| `behavior_pages_for_period(from, to)` | One row / URL with 12-col subset over the requested window |
| `seo_pages_overview(from, to)` | Same as above, parametric date range |
| `outbound_destinations_for_path(path, days)` | Top external hostnames clicked from a given page |
| `cta_breakdown_for_path(path, days)` | CTA clicks split by `(cta_type, placement, anchor)` |
| `engagement_density_for_path(path, days)` | Dwell distribution (p25 / median / p75 + evenness_score) — detects bimodal patterns (bouncers + deep readers) |
| `pogo_rates_for_period(from, to)` | Pogo-stick detection per page (Google sessions returning to SERP) |
| `tracker_first_seen_global()` | Earliest event timestamp (used for pro-rating capture rate during bootstrap) |

The full SQL is in `supabase/views.sql`. Contract signatures are stable since Sprint 13bis.

### RPCs cross-source & dashboard (Sprint 33+, migrations `supabase/migrations/`)

Consommées par `dashboard/lib/cooked.ts` et les analyses ad-hoc. Toutes `service_role` only.

| RPC | Rôle |
|---|---|
| `site_kpis_compare(period_days)` | KPIs site N vs N-1 (sessions, phone, form, **macro** contacts) |
| `pages_overview_unified(max_rows)` | Univers ~490 paths (snapshot ∪ GSC 90j), tri sessions |
| `gsc_page_performance(target_path)` | Fiche page : GSC + Cooked + CWV + device |
| `gsc_top_queries_for_path(path, days, max)` | Top requêtes Google sur une landing |
| `gsc_pages_overview(max_rows)` | Vue SEO pure, tri clics GSC (v3 : contacts = phone + form) |
| `gsc_top_queries_global(days, max)` | Top requêtes site + page cible (`/queries`) — v2 enrichi `volume_fr` / `cpc` / `click_yield_pct` via DataForSEO |
| `gsc_x_dfs_opportunities(min_vol, pos_min, pos_max, days, max)` | Requêtes pos 5–15 avec volume FR ≥ 100 → lost potential (clics manqués si pos 1) |
| `dfs_keywords_to_sync(limit_n)` | Top N keywords = union clics GSC **28j ∪ 90j** (consommé par `scripts/dfs_sync.py`) |
| `site_pulse` / `pages_pulse` | Grille 2×2 GSC 28v28 × Cooked 7v7 (quadrants) |
| `site_seo_funnel(period_days)` | Impressions → clics → sessions Google → contacts macro |
| `gsc_page_daily_series` / `cooked_page_daily_series` | Sparklines fiche page |
| `refresh_pipeline_health()` | Self-diag 4 axes (+ fraîcheur GSC) |

**Contacts (canonique)** : macro = `cta_phone_click` + `form_submit`. Micro intent RDV =
`cta_booking_click` (`cooked_booking_intent_*`). Ne jamais additionner booking aux contacts.

Index migrations clés : `20260522113000_gsc_cross_source_rpcs.sql`,
`20260523140000_pages_overview_unified_v2_exhaustive.sql`,
`20260524100000_contacts_macro_per_path.sql`,
`20260524160000_pages_pulse.sql`, `20260524220000_pulse_helpers.sql`,
`20260524260000_site_seo_funnel.sql`,
`20260525100000_dfs_keyword_volume.sql`,
`20260525120000_dfs_keywords_union_28d_90d.sql`.

### DataForSEO weekly sync (Sprint 33+)

Source de vérité pour le volume mensuel France et le CPC sur les top
500 keywords du site (union **28j + 90j** GSC, réévalué chaque run).
Alimente `gsc_top_queries_global` (colonnes `volume_fr` / `cpc` /
`click_yield_pct`) et `gsc_x_dfs_opportunities` (quick wins SEO).
Cron `.github/workflows/dfs-weekly-sync.yml` (lundi 07:00 UTC), coût
estimé ~$2/mois.

**Secrets GitHub Actions** : `DFS_USERNAME`, `DFS_PASSWORD`,
`SUPABASE_SECRET_KEY` (login + mot de passe **API** DataForSEO, pas le
mot de passe du site web).

**Run manuel en local** :

```bash
pip install -r scripts/requirements-dfs.txt
cp scripts/.env.dfs.example scripts/.env.dfs   # puis remplir
set -a && source scripts/.env.dfs && set +a
python3 scripts/dfs_sync.py --limit 500
```

Sans `DFS_*` en env → le script s'arrête tout de suite (normal). Cursor
n'a pas de MCP DataForSEO sur ce repo : les volumes passent par ce sync
→ table `dfs_keyword_volume`, pas par appel API live depuis l'agent.

---

## Dashboard (`dashboard/`)

Interface Next.js **READ-ONLY** pour Nicolas et Me Plouton — pas d'écriture Supabase
depuis l'UI. Setup : voir [`dashboard/README.md`](./dashboard/README.md).

| Route | Contenu |
|---|---|
| `/` | Pulse site, funnel SEO, KPI contacts macro, alertes Pulse, top contributeurs |
| `/pages` | Tableau exhaustif avec filtres / tri |
| `/queries` | Top requêtes Google site-wide |
| `/p/[...slug]` | Fiche page + requêtes + sparklines + quadrant Pulse |
| `/health` | `refresh_pipeline_health` (snapshot, cron, ingestion, GSC) |

---

## Google Search Console (Sprint 31-32)

Cooked ingère désormais GSC dans les mêmes tables Supabase. Permet les analyses cross-source (acquisition search × comportement on-page).

### 3 tables, granularités distinctes

| Table | Grain | Volume (16 mois) | Usage |
|---|---|---|---|
| `gsc_path_daily` | day × path | 121 746 rows, 6.6M imp | Trafic SEO total par page (inclut les impressions sans query identifiable) |
| `gsc_query_daily` | day × query | 872 564 rows, 2.6M imp | Demande globale sur le site, vue search-side seule |
| `gsc_query_page_daily` | day × path × query | **1 005 653 rows, 3.05M imp** | **Brique critique** : attribution "quelle requête a amené sur quelle page" |

### Path canonicalisation (contrat partagé)

Même règle partout : **decode → NFC → slash final retiré (sauf `/`)**.

| Couche | Où |
|--------|-----|
| Ingestion tracker | Edge `canonicalPath()` dans `supabase/functions/track/index.ts` |
| Ingestion GSC | `scripts/gsc_common.canonical_path()` (+ strip domain/query sur URLs GSC) |
| Jointures SQL historiques | `canonical_path(events.path) = gsc_path_daily.path` (fonction Postgres, voir migration GSC) |

→ Nouveaux events : jointure directe `events.path = gsc_path_daily.path`.  
→ Historique pré-NFC/slash : passer par `canonical_path()` côté SQL.

### Anonymisation GSC

54 % du volume impressions est anonymisé par GSC (queries qui apparaissent < ~10 fois sur la fenêtre). Ce volume reste dans `gsc_path_daily` mais n'est pas attribuable à une query précise. **Les clicks restent quasi-tous attribuables** (~100 %) — GSC anonymise les impressions, pas les clics.

### Auth

Service Account Google Cloud `gsc-mcp-claude@plouton-472207.iam.gserviceaccount.com`, credentials JSON en `~/.claude/gsc-credentials.json` (NON commité). Ajouté comme utilisateur Restreint sur la propriété GSC `https://www.jplouton-avocat.fr/`.

### Re-ingestion / refresh

```bash
pip install -r scripts/requirements-gsc.txt

# Backfill complet 16 mois (~4-7 min). --end-date défaut = hier.
export SUPABASE_SECRET_KEY='sb_secret_...'
# optionnel : SUPABASE_URL, GSC_CREDENTIALS_PATH (~/.claude/gsc-credentials.json)

python3 scripts/gsc_ingest.py path-query
python3 scripts/gsc_ingest.py query-page

# Wrappers rétro-compat (même comportement) :
# python3 scripts/gsc_ingest_path_and_query.py
# python3 scripts/gsc_ingest_query_page.py
```

DDL : `supabase/migrations/20260522120000_gsc_tables.sql` (à rejouer sur fresh DB).

### Cron quotidien (Sprint 33, 22/05/2026)

GitHub Actions workflow `.github/workflows/gsc-daily-ingest.yml` lance
`python3 scripts/gsc_ingest.py path-query --months 1` puis `query-page --months 1`
tous les jours à 06:00 UTC (≈08:00 Paris en été). Upsert idempotent —
re-ingère le dernier mois pour capturer les refinements GSC.

**Secrets à configurer une fois** dans le repo GitHub (Settings → Secrets and variables → Actions) :

| Secret | Valeur |
|---|---|
| `GSC_CREDENTIALS_B64` | base64 du JSON service account (`base64 -w0 < ~/.claude/gsc-credentials.json`) |
| `SUPABASE_SECRET_KEY` | clé `sb_secret_*` du projet Cooked |

Run manuel via le bouton **"Run workflow"** sur l'onglet Actions. Monitoring via
`refresh_pipeline_health()` axe GSC (gsc_data_age_days, gsc_ingest_age_hours).

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

**4 active pg_cron jobs** (verified live, post-Sprint-30) :

| Job | Schedule | What |
|---|---|---|
| `refresh_seo_url_snapshot` | `0 3 * * *` (05:00 Paris) | Nightly rebuild of `seo_url_snapshot` (calls `refresh_bot_fingerprints()` first) |
| `refresh_noise_filters_hourly` | `5 * * * *` | Re-scan bot fingerprints + noise sessions every hour (Sprint 28) |
| `run_rpc_contract_tests` | `30 3 * * *` (05:30 Paris) | Nightly contract-test of the 8 published RPCs → logs to `rpc_health` (Sprint 27) |
| `purge_old_events_monthly` | `0 4 1 * *` (06:00 Paris, 1st of month) | Retention policy : deletes events > 400 days (Sprint 27) |

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

Wix Custom Code is capped at **15 000 characters**. The source
`wix/tracker.html` is ~27 KB (comments + formatting kept for auditability),
so it must be minified before pasting into Wix.

**Workflow:**

```bash
# One-time setup
pip3 install jsmin

# Each deploy
python3 scripts/minify-tracker.py --copy
```

The script writes `wix/tracker.min.html` (gitignored — it's a build artifact,
the source of truth is `tracker.html`) and copies its content to the macOS
clipboard. It also enforces the 15 k limit and exits non-zero if the output
overflows.

Then in Wix:
**Wix Admin → Settings → Custom Code → Edit the "Cooked tracker" snippet →
Cmd+A, Cmd+V → Save → Publish.**

After publishing, confirm the new version is live (replace `sprint28` with
the current `COOKED_VERSION` from `tracker.html`):

```sql
SELECT props->>'_v' AS version, COUNT(*)
FROM events
WHERE occurred_at > now() - interval '15 minutes'
GROUP BY 1 ORDER BY 2 DESC;
```

If the new version label never appears after 15 min, the paste was
truncated or Wix didn't republish.

### Updating the Velo proxy

Copy `wix/http-functions.js` into the Velo backend:
**Wix Admin → Code → Backend → http-functions.js**

The Velo secrets `SUPABASE_TRACK_URL` and `SUPABASE_SERVICE_KEY` must be set in Wix Admin → Settings → Secrets Manager.

### Configuring form submission tracking (Sprint 18 — webhooks)

Form submissions are tracked **server-side** via a Wix Automation webhook
that posts to the dedicated `form-webhook` Edge Function. This avoids
the unreliability of browser-side intercepts on Wix Forms V2.

Setup once:

1. Generate a secret token (`openssl rand -hex 24`)
2. Set the env var `FORM_WEBHOOK_SECRET` on the `form-webhook` Edge
   Function (Supabase Dashboard → Edge Functions → form-webhook →
   Secrets)
3. In Wix Admin → Automations, create an automation:
   - **Trigger**: Form Submitted (on every form)
   - **Action**: Send HTTP Request (POST, JSON body)
   - **URL**:
     `https://mxycmjkeotrycyneacje.supabase.co/functions/v1/form-webhook?token=<SECRET>`
4. Activate

After this, every Wix Form submission inserts a `form_submit` event into
the `events` table with the form name, submission ID, page source, and
the full raw payload (in `props.raw_payload` for forensic analysis).

The webhook bypasses the browser entirely, so it's 100% reliable. The
trade-off: no `session_id` / `referrer` / `utm_*` correlation with the
visitor's browsing session (other events still track the session up to
the submit moment).

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
| **33+ — Pulse & funnel** | 24/05/2026 | `site_pulse`, `pages_pulse`, helpers SQL (`pulse_quadrant`, fenêtres 28j Paris). Funnel `site_seo_funnel`, sparklines `*_page_daily_series`, `/queries` via `gsc_top_queries_global`. Fix off-by-one fenêtres 28j (`20260524300000`). |
| **33 — Dashboard & contacts** | 22-24/05/2026 | App Next.js `dashboard/`. RPCs `site_kpis_compare`, `pages_overview_unified`, extension `refresh_pipeline_health` (axe GSC). Cron GSC GitHub Actions. Fix P0 : contacts macro = phone + `form_submit` (plus booking) sur toutes les vues agrégées. |
| **32 — Brique attribution query × page** | 22/05/2026 | Création de la 3e table GSC `gsc_query_page_daily` (1 005 653 rows, 16 mois). Brique critique identifiée par audit multi-agent (5 idéation + 3 critique) : débloque ~13 idées d'analyses cross-source qui nécessitent l'attribution query → landing. Volume attribuable = 46 % du total GSC (le reste est anonymisé par GSC pour les queries rares, mais quasi-tous les clicks restent attribuables). Backfill via `scripts/gsc_ingest_query_page.py`. |
| **31 — Ingestion Google Search Console** | 21/05/2026 | Projet Seo (repo + DB séparée) supprimé par Nicolas (« trop complexe pour le moment »). Cooked devient l'unique data platform. Tables `gsc_path_daily` (121k rows) et `gsc_query_daily` (872k rows) créées avec 16 mois d'historique GSC (01/02/2025 → 19/05/2026). Service Account `gsc-mcp-claude@plouton-472207...` ajouté comme utilisateur Restreint sur la propriété GSC `https://www.jplouton-avocat.fr/`. Path canonicalisation symétrique avec Cooked (decode + NFC + strip domain/query/slash) pour jointure directe. Script `scripts/gsc_ingest_path_and_query.py`. CLAUDE.md nettoyé de toutes les références à l'agent Seo (`docs(claude.md): supprime tout le protocole agent Seo`). |
| **30 — Audit chirurgical** | 21/05/2026 | Audit 7-agents (DB / Edge / tracker). Fixes : `cta_breakdown_for_path` masquait 42 % des anchors (filtre `cta_type IS NOT NULL`) → `anchor_nav` exposé. `engagement_density_for_path` over-counted +19 % (CTE retournait 1 row par page_exit, fix `GROUP BY session_id + MAX`). `pogo_rates_for_period` +26 % via LEFT JOIN dup + sessions sans `page_exit` traitées comme pogo. Edge `track v14` : `props` array → `{}`, ISO strict `occurred_at`, logs des drops. Edge `form-webhook v6` : hostname-spoofing guard (`//evil.com` rejeté), PII stripped (nom/email/téléphone ne sont plus stockés), erreurs PG non-23505 → 200 (stop le retry loop Wix). Tracker `sprint30` : `pageshow` bfcache handler (iOS back-nav perdait page_exit), `exitSent` reset après SPA pushState, `[class*="FOOTER"]` viré du `placementOf`, debounce localStorage 5s, INP threshold 40 (spec), `PerformanceObserver` disconnect sur SPA. Zombies droppés : `idx_events_props_gin`, 5 vues mortes, 4 colonnes `email_clicks_*`. `tracker_first_seen_global()` PK `noise_sessions_pkey`. |
| **29 — Audit hardening** | 21/05/2026 | Audit 10-agents round 1. Fixes : `form_submit` retiré de `ALLOWED_EVENTS` côté `/track` (forge via curl désormais HTTP 400). `tracker_first_seen_global()` guard ±2j contre les horloges clients cassées (retournait 20/05/2025 au lieu de 06/05/2026). `REVOKE EXECUTE` sur `seo_pages_overview` + `url_decode` (étaient appelables avec l'anon key). |
| **28 — session_id en localStorage** | 21/05/2026 | Fixe l'inflation self-referral (461 fausses sessions "referral" / 7j). Wix Studio drop `sessionStorage` entre certaines hard navigations → le tracker créait un nouveau `session_id` avec referrer = jplouton-avocat.fr. Migration vers `localStorage._ckd` avec sliding 30 min. `classify_channel(ref, utm_source, utm_medium, self_host)` RPC pour taxonomie unifiée. |
| **27 — AMDEC Tier 3** | 17/05/2026 | Contract tests RPC nightly (`run_rpc_contract_tests` + table `rpc_health` + cron 03:30 UTC). Politique de rétention `purge_old_events` (>400j, cron 1er du mois 04:00 UTC). |
| **26 — Version stamp** | 17/05/2026 | `COOKED_VERSION` injecté dans chaque event via `props._v` — permet de monitorer le rollout Wix Custom Code (un republish raté n'émet jamais la nouvelle version, détectable par `SELECT props->>'_v', COUNT(*) FROM events …`). |
| **25 — Hardening Edge** | 17/05/2026 | Fail-fast au boot si `SUPABASE_SECRET_KEY` ou `ANON_SALT` manquent / sont placeholder. `form-webhook` idempotent sur 23505 (Wix Automation peut retry sur timeout — partial UNIQUE index `events_form_submit_submission_id_uniq`). `refresh_pipeline_health()` self-diagnostic 3-axes (snapshot freshness, cron status, ingestion live). |
| **24 — Pipeline serial bot/noise** | 16/05/2026 | Séparation propre `events_no_bots` → `events_human`. Les 2 filtres bot et noise étaient cumulés implicitement et générer du double comptage des sessions filtrées. Documentation explicite des invariants. |
| **23 — `cta_breakdown` + anchor** | 16/05/2026 | Inclusion de `cta_anchor_click` dans la breakdown CTA (avant Sprint 23 le funnel ne voyait que phone + booking, l'anchor était orphelin). |
| **22 — `anonymous_id` stable** | 15/05/2026 | UUID random persistant en `localStorage._ckd_aid`. Avant : `hash(IP + UA + dailySalt)` côté Edge → Wix Velo route chaque request par un worker stateless différent → 6+ identités par session pour 93 % des sessions. |
| **21 / 21b — `noise_sessions`** | 15/05/2026 | Filtre des sessions parasites (prefetch, bots qui ne respectent pas robots.txt). 21b a rollback le pattern `instant_close` qui s'est révélé être un signal pogo-stick légitime. |
| **20 — `prefetch_sessions`** | 15/05/2026 | Premier filtre des sessions de prefetch Chrome (Lighthouse, link rel=prefetch). |
| **19 — Wix anchor-menu tracking** | 13/05/2026 | New event `cta_anchor_click` capturing in-page anchor clicks (sticky index, FAQ jumps, "back to top"). Wix Studio's anchor-menu widget renders as `<a href=current-path data-anchor="anchors-xxx">` and scrolls via JS without ever updating `location.hash`, so the tracker detects the widget's signature directly: same-pathname + `data-anchor` attribute. `target_section` is a human-readable slug of the button label (e.g. `accompagnement-immediat`). Also: `placement` taxonomy extended to `{header, footer, sticky, body}` (computed-style detection via `position: sticky / fixed` ancestor). Also: `normalizePathForCompare` kills the duplicate-pageview cascade caused by Wix's internal `pushState` flicker on micro-interactions. |
| **18 — Form submission tracking** | 11/05/2026 | New event `form_submit` fired server-side by the new `form-webhook` Edge Function, triggered by a Wix Automation on every form submission. Captures `form_id`, `submission_id`, `page_source`, and the full raw Wix payload. Browser-side intercept (masterPage.js) was attempted first but Wix Forms V2 swallows the DOM submit event before any JS layer can hook it reliably; the webhook approach is 100% reliable since it fires server-to-server. `track` Edge Function accepts `form_submit` in ALLOWED_EVENTS as a safety net even though the webhook inserts directly. |
| **17** | 09/05/2026 | **Centralized bot filtering** via `events_human` view. `refresh_bot_fingerprints()` runs before each snapshot refresh. All 9 RPCs + 3 views read from `events_human`. Also: body CTA tracking (cta_booking_click no longer scoped to header/footer only), `page_exit.duration_seconds` uses cumulative active time. |
| **Tracker — aria-label capture** | 10/05/2026 | `cta_*_click` events capture `aria-label` in priority over `textContent`. Enables per-emplacement analytics via the `<Action> — <Location>` convention rolled out on the 13 CTA buttons of the site. |
| **13bis** | 07/05/2026 | `tracker_first_seen_global()` RPC for capture-rate pro-rating during bootstrap. |
| **13** | 07/05/2026 | Path-encoding fix — Edge Function decodes `path` via `decodeURIComponent` before insert. Backfill of 6531 historical events with the new `url_decode()` plpgsql helper. |
| **12** | 07/05/2026 | Full-menu RPC contract for the seo audit tool : `snapshot_pages_export`, `site_context_export`, `outbound_destinations_for_path`, `cta_breakdown_for_path`. |
| **10 Phase 1 + 1.5** | 07/05/2026 | Phone + booking CTA event tracking + counter columns on `seo_url_snapshot`. |
| **0** | 06/05/2026 | Initial deploy : tracker + Velo proxy + Edge Function v1 + `events` table + `seo_url_snapshot` + companion views + pg_cron daily refresh + first cross-project RPC. |

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
| `form-webhook` crashes on startup | `FORM_WEBHOOK_SECRET` env var missing — set it in Supabase Dashboard → Edge Functions → form-webhook → Secrets, then redeploy |
| `cta_anchor_click` events with `target_section: anchors-xxx` | The clicked button has no `aria-label` / `textContent` — slugify fell back to the raw Wix ID. Add a label on the Wix anchor-menu button for readability |

---

## Working on this repo with Claude Code

See [`CLAUDE.md`](./CLAUDE.md) — it documents:

- The autonomy boundaries for the Cooked agent (data layer + `dashboard/`)
- The site taxonomy (4 page types : expertise, cabinet, posts ressources, posts classiques)
- Methodology takeaways from previous sprints

Dashboard-specific rules : [`dashboard/CLAUDE.md`](./dashboard/CLAUDE.md).

`CLAUDE.md` is auto-read by every Claude Code session that starts in this repo.
