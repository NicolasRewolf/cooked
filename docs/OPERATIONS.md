# Cooked — Opérations & référence technique

> Ce fichier est la **référence opérationnelle** : architecture détaillée,
> events captés, ingestion GSC/DataForSEO, crons, déploiement, sécurité,
> dépannage, historique des sprints. **L'ambition et la vue d'ensemble du
> système vivent dans [README.md](../README.md)** — commencer par là.
> Contenu déplacé tel quel depuis l'ancien README le 10/06/2026.

---

## Architecture détaillée

```
Browser (Wix Custom Code <head>)
   │  tracker.html — pageview / scroll / engagement / web_vitals /
   │                  click_outbound / page_exit / cta_phone_click /
   │                  cta_booking_click / cta_anchor_click / click_internal
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
   │  canonicalPath(path)        (decode + NFC + strip slash — Sprint 13 ; v22/S39 : aussi props.target_path des click_internal)
   │  reject `props` arrays (Sprint 30 hardening)
   ▼ INSERT

Postgres
   │  events table (raw)
   │     ↓ refresh_bot_fingerprints + refresh_noise_sessions (hourly)
   │     ↓ events_human view (events MINUS bots MINUS noise)
   │
   │  pg_cron 03:40 UTC
   │     ↓ refresh_identity_stitch(90)
   │  identity_stitch — couture d'identité (12/07/2026) : sid|aid →
   │     visitor_key (composantes connexes aid↔sid, 90 j glissants).
   │     Consommée par les lectures d'attribution : conversion_journeys v2,
   │     refresh_dashboard_resources_assisted v2 (→ seo_to_contact_funnel
   │     et content_performance par héritage)
   │
   │  pg_cron 03:00 UTC
   │     ↓ refresh_seo_url_snapshot()
   │
   │  seo_url_snapshot table (1 row / URL × rolling windows 7d/28d/90d/365d)
   │
   │  Google Search Console (Sprint 31-32, ingested via scripts/gsc_ingest.py)
   │     ↓ Service Account JWT → GSC API
   │     ↓ gsc_common.canonical_path() (decode + NFC + slash ; URLs GSC complètes)
   │     ↓ upsert
   │  gsc_path_daily        — day × path
   │  gsc_query_daily       — day × query
   │  gsc_query_page_daily  — day × path × query (brique critique)
   │
   ▼ RPCs cross-source (migrations Sprint 33+)
     │
     ▼ Requêtes ad-hoc via Claude Code + MCP Supabase (mode principal)
       (Nicolas pose une question, Claude appelle les RPCs)
       + dashboard de lecture (articles ressources) sur data.rewolf.studio
```

> **Historique & état** — Une 1ʳᵉ app `dashboard/` a vécu du 22 au
> 25/05/2026 (Sprint 33), supprimée pour repartir sur Claude Code + MCP.
> Puis une **V1 lecture-seule a été reconstruite le 29/06/2026** (Next.js
> 16, sous-app isolée `dashboard/`, articles ressources) — live sur
> **data.rewolf.studio** (Vercel, rootDir=`dashboard`). Le Q/R ad-hoc
> reste le mode principal ; le dashboard le complète. Détails :
> `dashboard/README.md`. Le contrat RPC publié reste l'API canonique
> (le dashboard consomme un sous-ensemble `dashboard_*`).

---

## Privacy & RGPD (détail technique)

- **No cookies. `localStorage` used for visitor identity and session continuity** — same approach as Plausible / Fathom Lite / Pirsch
- `anonymous_id` = random alphanumeric string (~28 chars), stored in `localStorage._ckd_aid` since Sprint 22 (15/05/2026). Persists indefinitely on the device. Falls back to `sha256(IP | User-Agent | daily-salt)` server-side hash if `localStorage` is blocked (Safari ITP strict, Firefox strict, privacy extensions)
- `session_id` lives in `localStorage._ckd` with a 30-minute sliding idle window since Sprint 28 (21/05/2026). Survives hard navigations (the previous `sessionStorage`-only design was producing ~10 % of fake "referral" sessions because Wix Studio's hard-nav was dropping the per-tab storage). Falls back to `sessionStorage` if `localStorage` is blocked
- IPs are never stored — only used as input for the server-side hash fallback, and rotated daily via the salt
- The browser-side identifiers (`_ckd_aid`, `_ckd`) are inspectable in DevTools → Application → Local Storage → the visitor can delete them at any time
- **Ids auto-réparants depuis le tracker `sprint41` (12/07/2026)** : sur un wipe de storage en cours de visite (ITP, extensions privacy), les trackers ≤ `sprint40` re-mintaient un `sid` neuf à chaque event pendant que l'`aid` (en closure) n'était jamais ré-écrit — rotation croisée qui coupait ~22 % des sessions. `sprint41` garde le `sid` en cache mémoire et **ré-écrit** les deux ids dans le storage au lieu d'en re-minter (détail : section « Couture d'identité » ci-dessous)

**Exempted from cookie-banner consent** under CNIL délibération 2020-091 and the 2022 guidelines (mesure d'audience strictement statistique, pas de recoupement, pas de transfert tiers). The use of `localStorage` for a non-PII random UUID with no cross-site tracking and no advertising re-use is accepted by the CNIL within this exemption — see the [2022 guidelines, §"Solutions techniques exemptées"](https://www.cnil.fr/fr/cookies-et-traceurs-que-dit-la-loi).

---

## Couture d'identité (12/07/2026)

### Le bug (trackers ≤ sprint40)

Le `sid` était relu dans le storage **à chaque event** et re-minté sur miss,
tandis que l'`aid` vivait en closure et n'était **jamais ré-écrit** dans le
storage. Sur un wipe de storage en cours de visite, les deux ids tournaient
donc de façon croisée : **~22 % des sessions étaient coupées** en deux ou
plus, et **~95 % des `cta_phone_click` apparaissaient sans amont** visible
(contact « sans parcours »).

### Le fix tracker (`sprint41`, déployé le 12/07/2026)

Quatre gestes, comportement identique par ailleurs :

1. **Cache mémoire `_cachedSid`** : sur miss storage, le `sid` connu est
   **ré-écrit** dans le storage au lieu d'en re-minter un nouveau.
2. **`healAid()` opportuniste** : l'`aid` en closure est ré-écrit dans le
   storage dès qu'il en a disparu.
3. **`sessionStorage` lu sur MISS**, avec rapatriement vers `localStorage`.
4. **`exposeIds()` rejoué au flush** — les query params
   `cooked_aid`/`cooked_sid` (attribution formulaires) restent posés.

Vérification J+1 faite le 13/07/2026 — OK (procédure : « Vérifier un
déploiement tracker (J+1) » plus bas).

### La couture SQL (répare l'historique)

Table `identity_stitch` (`kind` = `sid` | `aid`, `key` → `visitor_key`) :
**composantes connexes du graphe biparti aid↔sid**, calculées par label
propagation (convergence en 2 itérations), sur **90 j glissants**.
Exclusions : identités `webhook-%` et **aid 32-hex** (fallback serveur).
Reconstruite chaque nuit par `refresh_identity_stitch(90)` (cron
`refresh-identity-stitch`, 03:40 UTC). **Horodatée depuis T-10 (03/09/2026)** :
la fonction écrit `cooked_config.identity_stitch_refreshed_at` et
`identity_stitch_rows` à sa fin ; `alert_rule_identity_stitch()` sonne si la
table est vide, si l'horodatage a plus de 30 h, ou si des sessions humaines de
J-1 manquent après la reconstruction du jour ; contract-tests nocturnes
`identity_stitch_couvre_j2` (= 0) et `identity_stitch_horodatee` (= 1).
Aucun consommateur en périmètre ne lit la couture sur le jour en cours
(`conversion_journeys`, `assisted_*`, `seo_to_contact_funnel` : fenêtres closes
à J-1) — `site_kpis_compare` / `cooked_pages_snapshot` (lens `live`) comptent
des sessions brutes, sans couture.

🚨 **Garde-fou : ne JAMAIS coudre via un aid 32-hex.** C'est le fallback
serveur `sha256(IP | UA | sel journalier)`, potentiellement **partagé entre
plusieurs visiteurs** (même IP + même UA) — coudre dessus fusionnerait des
inconnus entre eux.

### Consommateurs v2

- `refresh_dashboard_resources_assisted` **v2** : l'entrée d'un contact =
  première pageview de la **visite recousue** (segmentation à trous
  > 30 min, rattachement à la dernière pageview ≤ 6 h avant le contact),
  fallback session brute. Effet mesuré : contacts assistés « ressource »
  28 j **16 → 37**. Depuis T-08 : `assisted_contacts_by_entry_path` compte aussi
  les forms sans identifiant sur la ligne `(non attribuable)` (Σ = totaux site) ;
  cette ligne n'entre pas dans le snapshot ressources.
- `refresh_dashboard_assisted_quarter` (T-08) : 5ᵉ étape de `cooked_refresh_after_gsc`
  (timeout 600 s) → table `dashboard_assisted_quarter_snapshot`. La RPC
  `dashboard_assisted_quarter()` lit ce snapshot (< 1 s). Trimestre clos à J-1.
  Pas d'objectif (`objectif_assistes_trimestre` absent).
- `conversion_journeys` **v2** : parcours sur le visiteur recousu
  (`visitor_key`, priorité sid > aid > fallback session brute) ; journey =
  pageviews de la visite [t−6h, t+3min], chaîne sans trou > 30 min.
  Contrat de sortie inchangé, ~1 s sur 28 j. `seo_to_contact_funnel` et
  `content_performance` sont réparés **par héritage** (ils la consomment).

---

## Events captés

The browser-side `tracker.html` emits these events. Anything else is rejected by the Edge Function's allow-list.

| Event | When it fires | Useful props |
|---|---|---|
| `pageview` | Initial load + every SPA navigation | `path`, `title`, `referrer`, `utm_*`, `viewport_*` |
| `scroll_depth` | 25 / 50 / 75 / 100 % milestones (once per page) | `percent` |
| `engagement_tick` | Every 10s of active time (paused on idle / hidden tab). **Sprint 37**: batched — non-critical events queue and flush every 30 s / 10 events / pagehide in a single `{events:[…]}` POST (−60/70 % network requests); critical events (pageview, clicks, page_exit) still flush immediately | `active_ms` |
| `web_vitals` | LCP / INP / CLS / TTFB | `metric`, `value` |
| `click_outbound` | Click on an external `<a>` | `href`, `hostname`, `anchor` |
| `page_exit` | `pagehide` / `beforeunload` / tab hidden | `duration_seconds`, `max_scroll` |
| `cta_phone_click` | Click on any `<a href="tel:…">` | `phone`, `anchor`, `placement` (header / footer / sticky / body) |
| `cta_booking_click` | Click on any `<a>` pointing to `/honoraires-rendez-vous` | `anchor`, `placement` (header / footer / sticky / body), `target_path`, `href` |
| `click_internal` (Sprint 36) | Click on any internal `<a>` to **another** page (except `/honoraires-rendez-vous` → that stays `cta_booking_click`). Captures *which* UI element drives each page-to-page hop (the journey itself is already in the `pageview` sequence; this adds element attribution). Self-links (same path, no `#`/`data-anchor`) skipped. | `target_path`, `anchor`, `placement` (header / footer / sticky / body), `href` |
| `cta_anchor_click` (Sprint 19) | Click on an in-page anchor: classic `href="#x"`, Wix anchor-menu (`<a href=current data-anchor="anchors-xxx">`), or any interactive element inside a sticky container. **Sprint 35**: UI chrome is excluded — the Cookiebot consent banner (`#CybotCookiebotDialog`), the mobile burger toggle, and plain nav links (no `#hash`/`data-anchor`) no longer count. | `target_section` (slugified label or hash), `anchor`, `placement` (header / footer / sticky / body), `source` (`click` / `hashchange` / `sticky-fallback`), `data_anchor` (Wix internal ID, optional) |
| `form_submit` (Sprint 18) | Wix Form successfully submitted — fired **server-side** by the `form-webhook` Edge Function, triggered by a Wix Automation on form submission. **Sprint 38**: Wix Forms V2 ne rendant pas les champs cachés dans le DOM, le tracker expose `cooked_aid`/`cooked_sid` en query params (`replaceState`) et `wix/masterpage-cooked.js` (Velo) les écrit dans les champs cachés via `setFieldValues()` ; le webhook (v10, prod v14 depuis le 03/09/2026) les stocke dans `props` → attribution via `form_submits_attributed()` (hidden_field > temporal_unique > unresolved). Première attribution hidden_field : 11/06/2026 08:53 | `form_id`, `submission_id`, `page_source`, `cooked_aid`, `cooked_sid`, `capture_source: 'wix-webhook'` |

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

## Layout du repo

```
cooked/
├── AGENTS.md                          — point d'entrée agents IA / mainteneurs
├── CONTRIBUTING.md                    — workflow Git, migrations, CI
├── CHANGELOG.md                       — historique des jalons
├── SECURITY.md                      — secrets, signalement failles
├── LICENSE                            — propriétaire (tous droits réservés)
├── .env.example                       — modèle variables d'environnement
├── CLAUDE.md                          — Claude Code agent instructions
│                                        + site taxonomy + rules of thumb
├── README.md                          — ambition & vue d'ensemble du système
├── scripts/
│   ├── minify-tracker.py              — Minify tracker.html before Wix paste
│   ├── gsc_common.py                  — Lib partagée ingestion GSC
│   ├── gsc_ingest.py                  — CLI : path-query | query-page
│   ├── dfs_common.py                  — Lib ingestion DataForSEO (search_volume FR)
│   ├── dfs_sync.py                    — CLI sync hebdo top 500 keywords GSC → DFS
│   ├── generate_rpcs_sql.py           — Régénère supabase/rpcs.sql (DATABASE_URL)
│   ├── check_rpcs_sql_fresh.py        — Gate CI : RPC modifiée → miroir à jour
│   ├── check_migration_paris_date.py  — Gates CI C6 (cast Paris brut), C6b (inlining), C6c (bornes d'horloge)
│   ├── validate_gsc_is_branded.sql    — Pilote Arch #3 branded
│   ├── validate_period_bounds_live_j1.sql — Pilote Arch #1 live_j1
│   ├── cpi_validation_j28.sql         — Harnais validation prédictive CPI (tir réel validé le 11/07/2026)
│   ├── test_refresh_dashboard_rolling28.sql — Smoke-test MANUEL post-migration dashboard (articles)
│   ├── test_refresh_expertises_rolling28.sql — Smoke-test MANUEL post-migration dashboard (expertises)
│   ├── cooked_events_window_contract.sql — Contrat cooked_events_window (MANUEL, non exécuté par la CI)
│   ├── requirements-gsc.txt             — pip deps pour scripts GSC
│   └── requirements-dfs.txt           — pip deps pour scripts DataForSEO
├── contracts/
│   ├── canonical_path_vectors.json    — Contrat C3 canonical_path
│   ├── branded_query_vectors.json     — Contrat Arch #3 gsc_is_branded
│   └── rpc_snapshot_meta.json         — Hash + count du miroir rpcs.sql
├── .github/workflows/
│   ├── gsc-daily-ingest.yml           — cron GSC quotidien (06:00 UTC)
│   ├── dfs-weekly-sync.yml            — cron DataForSEO hebdo (lundi 07:00 UTC)
│   ├── sql-contracts.yml              — C6/C6b/C6c paris_date + Arch #5 rpcs.sql
│   ├── canonical-path-contract.yml    — C3 SQL / Edge / Python
│   ├── python-ingest-contract.yml     — C7 tests GSC/DFS
│   ├── dashboard-contract.yml         — C9 vitest dashboard
│   ├── tracker-test.yml               — Suite jsdom tracker
│   └── edge-shared-helpers.yml        — Deno tests Edge _shared/
├── supabase/
│   ├── schema.sql                     — events table + indexes + RLS (référence)
│   ├── migrations/                    — DDL nommé (**source de vérité déploiement**)
│   ├── rpcs.sql                       — corps complets des 138 routines (généré depuis la prod en CI, lecture seule)
│   ├── views.sql                      — vues + signatures RPC (référence partielle)
│   └── functions/
│       ├── track/index.ts             — Tracker ingest Edge Function
│       └── form-webhook/index.ts      — Wix Automations webhook for forms
├── docs/
│   ├── OPERATIONS.md                  — ce fichier
│   ├── PLAYBOOK-analyse-seo.md        — SEO analysis playbook (traps & recipes)
│   ├── cpi-cooked-page-index.md       — CPI v2.2 spec
│   ├── ROADMAP-sprint38-handoff.md    — remaining work P0/P1/P2
│   ├── HISTORY-sprints.md             — sprint chronology
│   ├── data-quality-audit-*.md        — trust audits
│   └── agents/                        — engineering-skills config
├── tests/
│   ├── tracker.test.js                — suite jsdom (source + minifié), câblée en CI (.github/workflows/tracker-test.yml)
│   └── test_dfs_common.py             — DataForSEO sanitize tests
└── wix/
    ├── http-functions.js              — Velo proxy backend
    └── tracker.html                   — Wix Custom Code <head>
```

---

## RPCs internes (analyses historiques)

All RPCs are `granted to service_role only`. No `anon` / `authenticated` access.

| RPC | Returns |
|---|---|
| `snapshot_pages_export(paths text[])` | Latest snapshot rows (70 cols : 4 windows × ~11 metrics + CWV + provenance + device + CTAs + pogo + device CTA rate, post-Sprint-30 ; réparée S39 : colonnes `email_clicks_*` droppées au S30 renvoyées en `0::bigint`, contrat préservé). Filter by paths optional. |
| `site_context_export()` | One row of site-wide context 28d (sessions, bounce rate, top sources, sessions trend) |
| `behavior_pages_for_period(from, to)` | One row / URL with 12-col subset over the requested window |
| `seo_pages_overview(from, to)` | Same as above, parametric date range |
| `outbound_destinations_for_path(path, days)` | Top external hostnames clicked from a given page |
| `cta_breakdown_for_path(path, days)` | CTA clicks split by `(cta_type, placement, anchor)` |
| `engagement_density_for_path(path, days)` | Dwell distribution (p25 / median / p75 + evenness_score) — detects bimodal patterns (bouncers + deep readers) |
| `pogo_rates_for_period(from, to)` | Pogo-stick detection per page (Google sessions returning to SERP) |
| `tracker_first_seen_global()` | Earliest event timestamp (used for pro-rating capture rate during bootstrap) |

### RPCs cross-source (Sprint 33+, migrations `supabase/migrations/`)

Consommées en ad-hoc via le MCP Supabase quand Nicolas pose une question à Claude. Toutes `service_role` only.

**Périodes** : `period_kind` = `today` | `week` | `month` | `rolling_28` | `rolling_90`.
**Lens** (`cooked_period_bounds`) : `live` (Cooked, calendrier Paris, KPIs « aujourd'hui »)
| `live_j1` (dashboard : fin J-1 Paris) | `gsc` | `cross` (fin alignée sur dernier jour GSC ingéré).
**Branded GSC** : `gsc_is_branded(query)` — ne pas réécrire `plouton` à la main.

| RPC | Rôle |
|---|---|
| `gsc_last_data_day()` | Dernier jour consolidé GSC + lag en jours |
| `cooked_period_bounds(period_kind, data_lens)` | Bornes `n_start` / `n_end` selon zone (live / gsc / cross) |
| `site_kpis_compare(period_kind)` | KPIs Cooked N vs N-1 (lens **live**) |
| `site_gsc_kpis_compare(period_kind)` | KPIs GSC N vs N-1 (lens **gsc**) |
| `pages_overview_unified(period_kind, max_rows)` | Univers ~490 paths, tri sessions |
| `gsc_page_performance(target_path, period_kind)` | Fiche page : GSC + Cooked + CWV + device |
| `gsc_top_queries_for_path(path, period_kind, max)` | Top requêtes Google sur une landing |
| `gsc_pages_overview(max_rows)` | Top pages SEO (tri clics) ; GSC = 28 jours clos à `gsc_last_data_day()` (T-05, 03/09/2026 — la doc promettait un `period_kind` qui n'a jamais existé) ; contacts macro = phone + form |
| `gsc_top_queries_global(period_kind, max)` | Top requêtes site + page cible + `volume_fr` / `cpc` / `click_yield_pct` (DataForSEO) |
| `gsc_x_dfs_opportunities(min_vol, pos_min, pos_max, period_kind, max)` | Quick wins SEO (pos 5–15, volume FR ≥ 100) |
| `dfs_keywords_to_sync(limit_n)` | Top N keywords = union clics GSC **28j ∪ 90j** (`scripts/dfs_sync.py`) |
| `site_pulse(period_kind, …)` / `pages_pulse(period_kind, …)` | Quadrants GSC 28v28 × Cooked 7v7 |
| `site_seo_funnel(period_kind)` | Impressions → clics → sessions Google → contacts macro |
| `gsc_page_daily_series(path, days, end_date)` / `cooked_page_daily_series(…)` | Séries journalières par page |
| `refresh_pipeline_health()` | Self-diag 5 axes (snapshot, cron, events, GSC, DataForSEO) |

**Contacts (canonique)** : macro = `cta_phone_click` + `form_submit`. Micro intent RDV =
`cta_booking_click` (`cooked_booking_intent_*`). Ne jamais additionner booking aux contacts.

### RPCs attribution & santé (Sprint 37-38)

**Fenêtres (T-09, 03/09/2026)** : les trois RPC ci-dessous prennent
`(days_back integer DEFAULT 28, p_end date DEFAULT NULL)` et lisent `days_back`
jours **Paris clos** — à J-1 (`cooked_period_bounds('rolling_28','live_j1')`)
pour `form_submits_attributed` / `conversion_journeys`, à `gsc_last_data_day()`
(lens `cross`) pour `seo_to_contact_funnel` ; `p_end` aligne sur une autre borne
close (le CPI passe `gsc_last_data_day()`). Plus de `now() - N jours` : la
réponse ne dépend plus de l'heure. Les bornes sortent dans `window_start` /
`window_end`. `macro_contacts_by_path(days_back)` est ancrée de la même façon.

- `form_submits_attributed(days_back, p_end)` — per form_submit: method = `hidden_field`
  (tracker-seeded `cooked_aid`/`cooked_sid` read by webhook v10) >
  `temporal_unique` > `unresolved`. ~75 % resolved before hidden fields,
  ~95 % expected after. Statut macro par `form_submit_counts_as_macro(props)`.
- `conversion_journeys(days_back, p_end)` — **v2 (12/07/2026)** : one row per macro
  contact (≈190 events/28 j) : entry_path,
  entry_channel, journey[] (page sequence), pages_count, device. Parcours
  reconstruit sur le **visiteur recousu** (`visitor_key` via
  `identity_stitch`, priorité sid > aid > fallback session brute) ;
  journey = pageviews de la visite [t−6h, t+3min], chaîne sans trou
  > 30 min. `entry_channel` via `classify_channel(..., url)` (gclid ⇒ paid).
  Même total que `site_macro_counts` et Σ `macro_contacts_by_path` sur les
  mêmes bornes (contract-test `contacts_28j_une_fenetre`).
- `content_performance(days)` — page_type × theme: sessions, median
  dwell/scroll, booking_intents, assisted contacts. Consomme
  `conversion_journeys` → couture héritée depuis le 12/07/2026.
- `seo_to_contact_funnel(days_back, p_end)` — GSC clicks → organic entries → contacts
  per landing page, **une seule fenêtre** (GSC, entrées, contacts) close à
  `gsc_last_data_day()`. Dénominateur = entrées de **visite recousue**
  (`identity_stitch`, coupure 30 min — le grain du numérateur) ; `FULL JOIN`
  entrées/contacts. Σ contacts = `conversion_journeys` organiques sur la même
  fenêtre (contract-test `funnel_meme_total_que_journeys`).
- `cooked_page_index(days)` / `cooked_cpi_snapshot()` / table `cpi_daily` —
  CPI **v2.2**, score santé 0-100 par page (spec : `docs/cpi-cooked-page-index.md`).
- `cpi_movers` (vue) — Δ CPI ~7j : statuts present/nouveau/disparu, delta_z
  par composante, flag `fiable` ; alimente l'alerte `cpi_drop` (recalibrée S39 :
  vrai decay momentum/capture uniquement, volatilité conversion exclue).
- `cpi_opportunite_contact` (vue, ex-`cpi_gisement`) — pilotage conversion : `potentiel` (capture +
  rétention + lecture, hors conversion) vs badge `convertit`, relu depuis
  `cpi_daily`. Opportunité = Fiabilité S/A/B + `NOT convertit`, trié par potentiel.
  Alias déprécié : `cpi_gisement`. Colonne `grade` = Fiabilité S/A/B/C.
- `page_taxonomy` table + `cooked_page_type(path)` — page typing
  (cabinet/hub/expertise/post/blog-nav) + theme (slug heuristic).
- `alerts` table + `cooked_alerts_refresh()` (hourly cron) — self-monitoring.
  Session reflex: `SELECT * FROM alerts WHERE NOT acked`.
- `annotations` table (`day`, `kind`, `label`, `paths[]`, migration
  `20260611201942`) — journal des **événements hors-site** (passage TV /
  presse, campagnes, changements de site) **et des restatements de séries**
  (ex. restatement CPI du 12/07/2026). Réflexe : la consulter avant
  d'interpréter un mouvement dans `cpi_daily` (voir « Restatements des
  séries » plus bas).

---

## Google Search Console (Sprint 31-32)

Cooked ingère GSC dans les mêmes tables Supabase. Permet les analyses cross-source (acquisition search × comportement on-page).

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

Service Account Google Cloud `gsc-cooked@rewolf-507310.iam.gserviceaccount.com` (projet GCP central `rewolf-507310` depuis le 01/09/2026 — l'ancien projet `plouton-472207` et son SA `gsc-mcp-claude@…` ont été supprimés lors du ménage GCP), credentials JSON en `~/.claude/gsc-credentials.json` (NON commité, miroir base64 dans le secret GitHub `GSC_CREDENTIALS_B64`). Ajouté comme utilisateur sur la propriété GSC `https://www.jplouton-avocat.fr/`. ⚠️ Même migration côté GBP : l'approbation de l'API Business Profile étant liée au projet, elle doit être re-demandée pour `rewolf-507310` (quota à 0 sinon — état au 01/09/2026 : demande à déposer, cron `gbp-daily-ingest` en échec attendu d'ici là).

### Re-ingestion / refresh

```bash
pip install -r scripts/requirements-gsc.txt

# Backfill complet 16 mois (~4-7 min). --end-date défaut = hier.
export SUPABASE_SECRET_KEY='sb_secret_...'
# optionnel : SUPABASE_URL, GSC_CREDENTIALS_PATH (~/.claude/gsc-credentials.json)

python3 scripts/gsc_ingest.py path-query
python3 scripts/gsc_ingest.py query-page
```

DDL : `supabase/migrations/20260522120000_gsc_tables.sql` (à rejouer sur fresh DB).

### Cron quotidien (Sprint 33, 22/05/2026)

GitHub Actions workflow `.github/workflows/gsc-daily-ingest.yml` lance
`python3 scripts/gsc_ingest.py path-query --months 1` puis `query-page --months 1`
tous les jours à 06:00 UTC (≈08:00 Paris en été) — heure **planifiée** : depuis le
27/08/2026 l'ordonnanceur GitHub retarde le run de 4 à 12 h (27/08 17:15, 28/08 18:07,
03/09 10:35 UTC). Upsert idempotent — re-ingère les 2 derniers mois pour capturer
les refinements GSC. L'aval (`cooked-refresh-after-gsc`, tick horaire 6-21 h UTC) repart
dès que `max(ingested_at)` dépasse le marqueur du dernier refresh complet (T-11).

**Secrets à configurer une fois** dans le repo GitHub (Settings → Secrets and variables → Actions) :

| Secret | Valeur |
|---|---|
| `GSC_CREDENTIALS_B64` | base64 du JSON service account (`base64 -w0 < ~/.claude/gsc-credentials.json`) |
| `SUPABASE_SECRET_KEY` | clé `sb_secret_*` du projet Cooked |

Run manuel via le bouton **"Run workflow"** sur l'onglet Actions (ou `gh workflow run
gsc-daily-ingest.yml`). Monitoring via `refresh_pipeline_health()` axe GSC
(gsc_data_age_days, gsc_ingest_age_hours), `cooked_refresh_after_gsc_pending()` (l'aval
a-t-il suivi ?) et `refresh_runs` (durée par étape).

---

## DataForSEO weekly sync (Sprint 33+)

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

Sans `DFS_*` en env → le script s'arrête tout de suite (normal). Les
volumes passent par ce sync → table `dfs_keyword_volume` (le MCP
DataForSEO de l'agent permet aussi des lookups live, voir CLAUDE.md).

**Tests sanitize (local)** :

```bash
pip install -r scripts/requirements-dev.txt
python3 -m pytest tests/test_dfs_common.py -q
```

---

## Bot filtering (Sprint 17) & crons

Cooked detects and excludes crawler traffic at the analytics layer, without touching raw events.

```
events (raw — le bruit > 28 j est purgé chaque dimanche, cf. purge_cooked_noise)
   ↓
bot_fingerprints  (anonymous_ids flagged as bots, refreshed nightly)
   ↓
events_human VIEW  (events MINUS bot_fingerprints MINUS noise_sessions)
   ↓
ALL RPCs + snapshot read from events_human
```

**Detection rule** : `anonymous_id` with > 20 pageviews/day AND 0 scroll events = crawler. Catches the nightly Ahrefs audit crawler and similar bots.

**pg_cron jobs + 4 GitHub Actions planifiés** (état 03/09/2026 ; horaires UTC —
Paris = UTC+2 l'été). La liste pg_cron est **figée dans `contracts/doc_constants.json`**
et comparée à la prod par la gate `prod-drift` (T-12) : 9 jobs. Source de vérité
= `SELECT jobname, schedule FROM cron.job` en prod.

| Job | Schedule (UTC) | What |
|---|---|---|
| `refresh_seo_url_snapshot` | `0 3 * * *` (05:00 Paris) | Rebuild nocturne de `seo_url_snapshot` · `SET statement_timeout='600s'` — rebuild ≈ 230 s depuis la matérialisation d'`events_human` en temp table (30/06) |
| `run_rpc_contract_tests` | `30 3 * * *` (05:30 Paris) | Contract-tests nocturnes des RPCs publiées → `rpc_health` (Sprint 27) |
| `refresh-identity-stitch` | `40 3 * * *` (05:40 Paris) | `refresh_identity_stitch(90)` — reconstruit la table `identity_stitch` (couture d'identité, 90 j glissants) · **horodate sa fin** dans `cooked_config.identity_stitch_refreshed_at` (T-10) |
| `cooked-refresh-after-gsc` | `0 6-21 * * *` (tick horaire, 08:00→23:00 Paris l'été) | **Orchestrateur aval de l'ingestion GSC** (T-11, 03/09/2026) : `cooked_refresh_after_gsc()` enchaîne `cooked_cpi_snapshot` → `refresh_dashboard_snapshots` → `refresh_dashboard_expertises_snapshots` → `refresh_dashboard_resources_assisted` → `refresh_dashboard_assisted_quarter` · budget `SET statement_timeout='2400s'` dans la commande (clé `cooked_config.refresh_after_gsc_budget_s`) · **garde** : ne tourne que si `max(gsc_path_daily.ingested_at)` > marqueur `last_full_refresh_after_gsc_at` (`cooked_refresh_after_gsc_pending()`), quelle que soit l'heure d'arrivée de l'ingestion — le cron GitHub dérive de +4 à +12 h depuis le 27/08 · **durée par étape dans `refresh_runs`** (une ligne par étape + `_total`) · 21 h UTC = dernier tick qui reste dans le jour Paris (`cpi_daily.day = paris_today()`) · séquence ≈ 1 350-1 650 s (p50 30 j ≈ 1 600 s) |
| `purge_old_events_monthly` | `0 4 1 * *` (06:00 Paris, 1er du mois) | Rétention : supprime les events > 400 j (⚠️ destruction d'historique RÉEL — re-poser la question du backup à Nicolas ~juin 2027 avant le 1er run utile) |
| `cooked-purge-noise-weekly` | `30 4 * * 0` (06:30 Paris, dimanche) | **T-09 (03/07)** : `purge_cooked_noise(28)` — supprime le bruit bot/noise > 28 j + TTL 90 j sur `noise_sessions`. Ne change AUCUN résultat (lignes déjà hors `events_human` à toute fenêtre). 1er run : 41 589 lignes |
| `refresh_noise_filters_hourly` | `5 * * * *` | Bot fingerprints + noise sessions, **incrémental 48 h depuis T-08 (02/07)** : ~4 s/run (155 s avant ; fingerprints historiques conservés, noise = delete-récent + réinsertion) |
| `cooked-alerts-hourly` | `15 * * * *` | Table `alerts` — v4 (T-07, 03/09/2026) : voir § Alertes ci-dessous. Les `critical` **poussent sur ntfy** (≤ 2 par épisode, topic dans `cooked_config`) |
| `gsc-daily-ingest` / `dfs-weekly-sync` | GitHub Actions | GSC quotidien **planifié** 06:00 UTC (`--months 2` depuis T-02 — la fenêtre mois-calendaire perdait les fins de mois) — **départ réel +4 à +12 h** depuis le 27/08/2026 (ordonnanceur GitHub) : l'aval `cooked-refresh-after-gsc` suit seul jusqu'à 21:00 UTC, l'alerte `gsc_ingest_missed` sonne à 12:00 UTC (T-11) ; DFS hebdo lundi 07:00 UTC (échec = run rouge). Les 2 notifient ntfy en échec |
| `gbp-daily-ingest` | GitHub Actions | Google Business Profile quotidien 05:30 UTC, fenêtre 30 j (lag ~J-4, la queue rembourrée à zéro est coupée par le script) → `gbp_daily`. Notifie ntfy en échec. ⚠️ **Le credential est un ADC utilisateur : Google exige une reauth périodique** — panne silencieuse de 6 jours du 30/07 au 04/08/2026, réparée le 05/08 (`gcloud auth application-default login --scopes=…business.manage,…cloud-platform` puis secret `GBP_CREDENTIALS_B64` re-poussé). Alerte de fraîcheur **`gbp_daily_stale`** (registre `freshness_contract` : normal J-4, warn > 7 j, critical > 14 j → ntfy). **Depuis le 21/08/2026 la série s'arrête au 20/08** : migration du projet Google vers `rewolf-507310` (01/09), approbation Business Profile redemandée — échec attendu jusqu'au verdict (~10-15/09). Parade durable : client OAuth dédié (voie 2 de `scripts/gbp_ingest.py`) |
| `math-refresh-snapshots-weekly` | `10 5 * * 0` (07:10 Paris, dimanche) | `math_refresh_snapshots(28)` — snapshots `math_*_snapshot` du framework d'analyse mathématique (PR #91, 29/07/2026) ; registre `math_visit_sequences_snapshot` (warn > 9 j) |
| `wix-taxonomy-sync` | GitHub Actions | **T-15 (03/09/2026)** : lundi 05:00 UTC, `scripts/wix_taxonomy_sync.py` lit la liste **publiée** du blog (API Wix, secret `WIX_API_KEY`) et appelle `page_taxonomy_sync_wix(jsonb)` — insère les articles absents (category + theme, source `wix_api`), corrige `category` seule, ne supprime jamais. Sans secret : sort sans écrire (avertissement) ; filets : registre `page_taxonomy` (warn 21 j) + alerte `page_taxonomy_gap` (dès 1 article vu > 8 j) |
| `backup-weekly.yml` | GitHub Actions | **Schedule désactivé** (backup externe décliné le 02/07/2026, risque assumé — ne pas re-proposer) — déclenchable manuellement via `workflow_dispatch` uniquement |

⚠️ **Piège `statement_timeout`** : un `SET statement_timeout` posé *dans*
une fonction ne protège **pas** un statement déjà lancé. C'est pourquoi les
crons lourds posent le `SET` **séparément dans la commande cron, avant
l'appel** de la fonction (cf. `cron.job` en prod).

---

## Recettes & garde-fous (audit 01-03/07/2026)

### One-shot pg_cron (exécuter du SQL lourd côté serveur, > 60 s MCP)

Le connecteur MCP coupe à ~60 s (et rollback). Pour toute requête lourde
(capture CPI, gros refresh) : job pg_cron temporaire — **JAMAIS de
self-unschedule dans la commande** (pg_cron tue le run en cours, gotcha
re-payé le 02/07) :

```sql
SELECT cron.schedule('oneshot-<sujet>', '* * * * *',
  $$SET statement_timeout='540s';
    CREATE TABLE IF NOT EXISTS _oneshot_result AS SELECT ...;$$);
-- attendre le top de minute + la durée du run, vérifier la table,
-- PUIS déschéduler DE L'EXTÉRIEUR :
SELECT cron.unschedule('oneshot-<sujet>');
```
`CREATE TABLE IF NOT EXISTS` rend les re-tirs par minute inoffensifs.
Nettoyer : table + `SELECT * FROM cron.job` vide de one-shots.

### Swarm de bots (depuis ~20/06/2026) — état & trigger de réouverture

Signature : ~12 k `anonymous_id`/j, UA Chrome Windows desktop, uniquement
web_vitals/engagement_tick/page_exit **sans pageview**. `events_human`
reste propre (~10-11 k events/j) ; le brut a culminé à ~69 k/j. Contenu
par : filtres incrémentaux (T-08) + purge hebdo > 28 j (T-09). Le **guard
d'ingestion** (rejet à l'Edge) a été volontairement SKIPPÉ (02/07) — le
ré-instruire si : bruts > 120 k/j soutenus 7 j, OU purge insuffisante pour
tenir `events` < ~2 Go, OU pollution d'`events_human`. Mesure « ce qui
serait rejeté » (shadow, sans toucher l'Edge) :

```sql
-- batches non-pageview de visiteurs sans pageview sur 24 h (candidats au rejet)
SELECT count(*) FROM events e
WHERE e.occurred_at > now() - interval '24 hours'
  AND e.name IN ('web_vitals','engagement_tick','page_exit')
  AND NOT EXISTS (SELECT 1 FROM events p WHERE p.anonymous_id = e.anonymous_id
    AND p.name='pageview' AND p.occurred_at > now() - interval '24 hours');
```

### Alertes v4 (T-07, 03/09/2026) — invariant I6

Chaque seuil a une distribution mesurée le 03/09. Acquittement : `SELECT public.ack_alerts();` (tout le stock) ou `SELECT public.ack_alerts(ARRAY['cpi_drop']);`.

| Kind | Seuil | Distribution / replay | Push ntfy |
|---|---|---|---|
| `pipeline_dead` | âge `now() - max(received_at) > 90 min` **et** cette heure Paris a une médiane ≥ 1 event / 7 j | 40 j : 1 trou diurne 166 min (01/08 13:16→16:02, détecté) ; 3 trous nuit 61-69 min (dont 22/08, **non** détectés). 0 faux positif nocturne | critical, cap 2 / épisode |
| `cpi_drop` | chute ≥ 15 pts, grades **S/A** aux deux dates, **momentum < 0,90**, vrai decay (Δmom ≤ −0,10 ou Δzc ≤ −0,5), clics réels non croissants | 03/09 : 3 pages en v3 (2 S/A à momentum 1,01 / 1,09 + 1 B) → **0** en v4. Grade B = consultatif (`cpi_movers`), pas d'alerte | warn seulement, **jamais critical** |
| `warn_escalation` | warn ≥ 5 j non acquitté, hors kinds éditoriaux (`cpi_drop`) | avant : 9 escalades cpi_drop en 9 j | critical, cap 2 / épisode |
| `volume_floor` | heure Paris précédente (9-18 h), pageviews < 50 % de la médiane 7 j, médiane ≥ 30 | 7 j heures bureau : 2 horaires auraient sonné (med ≥ 30) ; 0 si med ≥ 40 | warn |
| `form_submit_dropped` | insert form échoué → `raise_cooked_alert` (Edge v14) | 0 ligne historique (jamais passé par raise) | critical, cap 2 |
| `gsc_ingest_missed` | **T-11** : dès 12:00 UTC, aucune ingestion GSC datée du jour Paris (attendue 06:00 UTC) | 27/08, 28/08, 31/08 : 3 retards de +6 à +12 h, tous rattrapés le jour même | warn |
| `refresh_after_gsc_stale` | **T-11** : `cooked_refresh_after_gsc_pending()` = true et ingestion > 3 h, entre 8 h et 23 h UTC, sans `refresh_step_failed_*` dans les 6 h | 0 cas historique reconstituable (la garde « ingestion du jour » masquait le cas) | critical, cap 2 |
| `refresh_budget` | **T-11** : dernier `_total` de `refresh_runs` (48 h) ≥ 80 % de `refresh_after_gsc_budget_s` (2 400 s) | 30 j : p50 ≈ 1 600 s (67 %), max 2 166 s le 05/08 (90 % — aurait sonné), 26/07 : 7 runs à 100 % | warn |
| `identity_stitch_empty` | **T-10** : `identity_stitch` vide | jamais observé (30 succès / 30 j) — une couture vidée était un « succeeded » muet | critical, cap 2 |
| `identity_stitch_stale` | **T-10** : `cooked_config.identity_stitch_refreshed_at` absent (critical), > 30 h (warn), > 54 h (critical) | 30 j : 30 reconstructions à 05:40 Paris, 17-25 s ; 0 cas | warn / critical |
| `identity_stitch_coverage` | **T-10** : après la reconstruction du jour, sessions humaines de J-1 (hors webhook, hors aid 32-hex) absentes de la couture | 03/09 : J-1 429/429, J-2 416/416 cousues (0,5 s) | warn |
| `dashboard_resources_snapshot_stale` (registre) | **T-10** : mesuré sur `max(cooked_end)` (fin des données), plus sur `refreshed_at` ; warn > 2 j, critical > 4 j | 28/08 : J-2 affiché en vert de 00:00 à 21:00 Paris — invisible de l'ancien registre | warn / critical |
| `page_taxonomy_stale` (registre) | **T-10** : `max(updated_at)` > 21 j (aucune synchro Wix Blog) | dernière synchro 31/08 11:05 | warn |
| `contact_sans_amont` | **T-17** : ≥ 3 `cta_phone_click`/`cta_booking_click` sur 24 h sans pageview antérieure dans la même session (détection d'injection via `/_functions/track`, garde d'origine forgeable — ou tracker cassé) | 28 j au 04/09 : 0/128 phone, 4/331 booking sans amont | warn ; critical ≥ 10 |

Le stock du 03/09 (55 non acquittées) n'est **pas** vidé par la migration — ack = décision Nicolas.

### Registre de fraîcheur `freshness_contract` (ADR-0002, 23/08/2026) — seuils au 03/09/2026

Une ligne par source ; `alert_rule_freshness()` (cron horaire) lit `last_point_sql`, compare à
`paris_today()` et sonne `<source>_stale` (warn / critical) ou `<source>_gap` (trous dans la série).
Le `repair_hint` de chaque ligne est la consigne de réparation embarquée dans l'alerte.

| Source | Dernier point mesuré sur | Lag normal | warn > | critical > | Note |
|---|---|---|---|---|---|
| `gsc_path_daily` (+ `_query_daily`, `_query_page_daily`) | `max(day)` | 3 j | 6 j | 10 j (12 j pour les deux tables requêtes) | trous sur 90 j → `gsc_path_daily_gap` |
| `gbp_daily` | `max(day)` | 4 j | 7 j | 14 j | en échec attendu depuis le 21/08 (voir cron GBP) |
| `dfs_keyword_volume` | `max(last_synced_at)` | 7 j | 10 j | 21 j | hebdo |
| `cpi_daily` | `max(day)` | 1 j | 1 j | 1 j | trous sur 7 j → `cpi_daily_gap` |
| `dashboard_resources_snapshot` | **`max(cooked_end)`** (fin des données, T-10) | 1 j | 2 j | 4 j | J-2 le matin est normal ; le grain horaire est aux alertes T-11 |
| `seo_url_snapshot` | `max(refreshed_at)` | 1 j | 1 j | 2 j | |
| `form_submit`, `cta_phone_click`, `crm_prospects` | dernier événement | 0 | 2 j | 4 j | cadence événementielle |
| `math_visit_sequences_snapshot` | `max(computed_at)` | 7 j | 9 j | 16 j | hebdo |
| `page_taxonomy` | `max(updated_at)` (T-10) | 7 j | 21 j | — | synchro Wix Blog manuelle jusqu'à T-15 |
| `secib_dossiers` | `max(synced_at)` | 1 j | 3 j | 7 j | **désactivée** (`enabled = false`) tant que le devis SECIB+ n'est pas signé |

`identity_stitch` n'est pas au registre (grain jour) : règle dédiée `alert_rule_identity_stitch()` (T-10).

### Restatements des séries (lire l'historique sans conclure à tort)

Les corrections rétroactives suivantes ont modifié des séries historiques.
Un « avant/après » qui enjambe une de ces dates n'est **pas** un signal
(ni un decay, ni un progrès) :

| Date | Restatement | Effet |
|---|---|---|
| 09/06/2026 (Sprint 37) | Dédup des clics dupliqués même-seconde (double-embed) | `cta_phone_click` corrigé rétroactivement de **−13,6 %** |
| 02/07/2026 | CPI — passage au grain lectures session×path | **±7 pts max** sur 4 pages A/B ; 8 pages C sorties du scoring |
| 02/07/2026 | `classify_channel` v2 — IA détectée aussi par `utm_source` | restatement des canaux (~35 % du canal `organic_ai` récupéré) |
| 12/07/2026 | CPI — conversion recousue (couture d'identité) | **seule la composante conversion zv bouge** (zc/zr/zl/momentum/gate inchangés) ; delta moyen −0,1 pt ; **0 changement de grade** ; 7 movers ≥ 15 pts (ex. arnaque-en-ligne 41→100, /nos-affaires 67→12) |
| 12/07/2026 | Contacts assistés « ressource » (dashboard) — attribution sur la visite recousue | **16 → 37** sur 28 j |
| 27/07/2026 | `classify_channel` v3 — GMB sort d'`organic_google` | home : n_org 305→164, grade S→A ; CPI/journeys/funnel restatés (annotation posée) |
| 03/09/2026 (T-09) | Contacts : `conversion_journeys` / `form_submits_attributed` / `macro_contacts_by_path` sur N jours clos à J-1 ; funnel sur une fenêtre GSC unique au grain recousu ; `classify_channel` v5 (gclid ⇒ paid) ; CPI zv sur la fenêtre du score | « contacts 28 j » **191 partout** (avant 183 / 189 / 195) ; funnel 5 860 entrées, 55 contacts, 0,94 % ; CPI : seul zv bouge, delta moyen +0,3, **0 changement de grade**, 6 movers ≥ 15 pts (annotation posée) |
| 03/09/2026 (T-06) | CPI : momentum sur `gsc_path_daily` moins brandé révélé (option (b), décision Nicolas) au lieu de `gsc_query_page_daily` non brandé (16-28 % des clics) ; `cpi_opportunite_contact.potentiel` hors momentum/gate ; `cpi_drop` ignore une page dont les clics réels montent | seul le momentum bouge (132 pages), delta moyen +3,7, médiane \|Δ\| 4, **0 changement de grade**, 8 movers fiables ≥ 15 pts ; contrefactuel : 0 page fiable en direction inverse (avant 15/47) ; CPI pondéré 45,7 → 45,9 (annotation posée) |
| 03/09/2026 (T-08) | Contacts assistés : forms sans identifiant + contacts sans visite → ligne `(non attribuable)` ; `dashboard_assisted_quarter` lit un snapshot (plus de calcul à l'affichage) | Σ assistés = totaux site (191 = 191 le 03/09, dont 12 non attribuables). Le compteur « articles » du dashboard **ne prend pas** ces 12. Pas d'objectif trimestriel (décision Nicolas). |

Les restatements des 12/07, 27/07 et 03/09/2026 sont annotés dans la table
`annotations` : la consulter avant d'interpréter un mouvement dans
`cpi_daily`. Les tables d'audit `cpi_pre_restatement_20260712` / `_20260727` ont
été supprimées le 10/08/2026 (migration `rangement_post_pivot_secib`) ;
`cpi_pre_restatement_20260903` (phases `t05_avant` / `t09_avant` / `t06_avant`)
est à supprimer au ticket T-19.

### Redémarrage après sinistre — briques ajoutées

- **`dashboard/`** : sous-app Next 16 (Vercel, rootDir=`dashboard`,
  data.rewolf.studio). Env requis : `NEXT_PUBLIC_SUPABASE_URL`,
  `NEXT_PUBLIC_SUPABASE_ANON_KEY` (publishable), `SUPABASE_SECRET_KEY`
  (service, server-only), allowlist e-mail. Local : `.claude/launch.json`
  + `dashboard/.env.local` (gitignored).
- **`wix/masterpage-cooked.js`** : à coller dans masterPage.js (Wix Studio)
  — c'est le rail de l'attribution formulaires (lit `cooked_aid`/`cooked_sid`
  des query params → `setFieldValues()`). Sans lui, l'attribution
  `hidden_field` meurt. Chaque Wix Form doit porter les 3 champs cachés
  `page_source`, `cooked_aid`, `cooked_sid` (clé exacte, onglet Avancé).

---

## Déploiement

### Re-deploying Edge Functions

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref mxycmjkeotrycyneacje
supabase functions deploy track --no-verify-jwt
supabase functions deploy form-webhook --no-verify-jwt
```

Versions (03/09/2026, **prod alignée avec le repo**) : **track v28** (T-04 :
UA littéral « pc » — bot Baidu — et SEBot-WA droppés à l'ingestion, motifs
miroir dans la taxonomie `ua_bot` de `refresh_noise_sessions` + règle
`spam_referrer` ; v27 = gate `x-cooked-key` à l'ingestion ;
v26 = filtre bots à l'ingestion — taxonomie ua_bot appliquée avant l'INSERT,
drops comptés dans `ingest_drops` ; D4 `track_row`), **form-webhook v13**
(10/08/2026 — Pont SECIB : identité prospect en clair → `crm_prospects` ;
v12 = D4 `form_row`) ; tracker Wix
**`sprint41`** (déployé le 12/07/2026). Modules testables dans
`supabase/functions/_shared/` : `events_row`, `track_row`, `form_row`
(+ tests Deno, CI `edge-shared-helpers`).

`--no-verify-jwt` is required: requests come from the Velo proxy without a Supabase user JWT (auth is via service-role key injected by the proxy).

### Re-applying the schema

**Source de vérité = `supabase/migrations/*.sql`** (timestamps réels), à
rejouer via `supabase migration up`. C'est la procédure de bootstrap
canonique d'une base fraîche.

**Miroirs de lecture (ne pas rejouer en déploiement)** :

| Fichier | Contenu | Régénération |
|---|---|---|
| `supabase/rpcs.sql` | **Corps complets** des 138 routines `pg_proc` de `public` (134 Cooked + 4 `unaccent` ; compte dans `contracts/doc_constants.json`) | workflow `rpcs-regenerate.yml` (`gh workflow run rpcs-regenerate.yml --ref <branche>`, rôle `cooked_ci_ro`) ; gate CI Arch #5 si migration touche une RPC + prod-drift (sha = prod) |
| `supabase/views.sql` | DDL complet des 5 vues + **signatures** RPC | Requêtes en bas de fichier (MCP / psql) |
| `supabase/schema.sql` | Table `events` + indexes (référence) | Manuel / dump ciblé |

Les migrations restent le journal ; `rpcs.sql` évite l'archéologie dans
12+ redéfinitions de la même RPC. **Ne jamais éditer `rpcs.sql` à la main**
— régénérer depuis la prod après merge d'une migration SQL.

### Updating the browser tracker

Wix Custom Code is capped at **15 000 characters**. The source
`wix/tracker.html` is ~40 KB (comments + formatting kept for auditability),
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

After publishing, confirm the new version is live (replace with the current
`COOKED_VERSION` from `tracker.html`):

```sql
SELECT props->>'_v' AS version, COUNT(*)
FROM events
WHERE occurred_at > now() - interval '15 minutes'
GROUP BY 1 ORDER BY 2 DESC;
```

If the new version label never appears after 15 min, the paste was
truncated or Wix didn't republish.

Version courante : **`sprint41`** (déployé le 12/07/2026 ~22:20).

### Vérifier un déploiement tracker (J+1)

Le lendemain d'un déploiement tracker, quatre contrôles (réflexe posé pour
`sprint41`, vérification J+1 du 13/07/2026 : OK) :

1. **Version** — les events du jour portent `props->>'_v'` = nouvelle
   version (requête ci-dessus, fenêtre élargie à 24 h).
2. **Sessions saines** — chaque session a une pageview et **un seul
   `anonymous_id`**.
3. **Signature de split ≈ 0** — sessions sans pageview dont l'`aid` a une
   pageview dans une session sœur (c'était la trace du bug de rotation
   corrigé par `sprint41`).
4. **`cooked_config.expected_tracker_version` bumpé** (migration
   `20260713000733` pour `sprint41`) — sinon l'alerte `tracker_drift` se
   déclenche (grâce 48 h).

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
the hidden fields `cooked_aid`/`cooked_sid` (Sprint 37, PII stripped since
Sprint 30).

The webhook bypasses the browser entirely — but it is only as reliable as
the Wix Automation that fires it, and that automation lives outside the
repo, unversioned, deletable by a click. Proven on 11/08/2026: a rework of
the site's automations silently removed it, and 22 submissions (12–21/08)
were lost until an audit caught the silence 11 days later (backfilled by
migration `20260823112541`). Until a pull-reconciliation exists, any
"reliable" claim about this channel is a belief, not a property. The
trade-off stands: no browser-session correlation at insert time —
attribution is resolved at read time by `form_submits_attributed()`.

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

- **`events`, `seo_url_snapshot`, `bot_fingerprints` (etc.) have RLS enabled with no policies — by design.** This is the deny-all-to-clients pattern: only `service_role` bypasses RLS. The "RLS enabled, no policies" INFO-level advisor flag is expected and acceptable.
- **`rls_auto_enable()` event trigger** auto-enables RLS on every newly-created table in `public` — belt-and-suspenders against forgetting the `enable row level security` in a future migration.
- **All RPCs are granted to `service_role` only** — `REVOKE … FROM PUBLIC, anon, authenticated` on every function (`FROM public` alone is defeated by Supabase default privileges : regressions on 25/07 and 31/08/2026). **Invariant I1** (T-01, 02/09/2026) : `alert_rule_exposure()` hourly + `check_prod_drift.py` in CI list any SECURITY DEFINER function or view readable by `anon`/`authenticated`. Exception : `cooked_ci_ro` (CI read-only role) may EXECUTE the 16 `dashboard_*` RPCs (T-13). Full picture : [SECURITY.md](../SECURITY.md).
- **`SECURITY DEFINER` functions pin `search_path`** to prevent search_path injection.
- **`security_invoker = true`** on views (`events_human`, `cpi_movers`, …) — enforces caller's RLS, not creator's.
- Invariant de sortie de sprint : **advisors security = 0 WARN**.

---

## Maintenance

```sql
-- Force snapshot refresh (service_role only)
SELECT public.refresh_seo_url_snapshot();

-- Inspect detected bots
SELECT * FROM public.bot_fingerprints;

-- Santé du pipeline / alertes / santé des RPCs
SELECT * FROM refresh_pipeline_health();
SELECT * FROM alerts WHERE NOT acked;
SELECT * FROM latest_rpc_health();
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

## Sprint history (recent)

> Chronologie une-ligne-par-sprint complète : `docs/HISTORY-sprints.md`.

| Sprint | Date | Scope |
|---|---|---|
| **39 — Consolidation & prod opérationnelle** | 15-18/06/2026 | Edge `track` v22 (`target_path` décodé + backfill 143), `snapshot_pages_export` réparée, **CPI v2.2** (momentum continu + EB dynamique), alertes recalibrées (`double_embed_suspect` seuil 30 ; `cpi_drop` vrai decay), vue `cpi_gisement` (pilotage conversion), 3 revues experts → outil suffisant, croisement Wix↔form_submit fiable. Passage focus site. |
| **38 — CPI & form attribution v2** | 10-11/06/2026 | CPI v2.1 (`cooked_page_index`, `cpi_daily`, cron 07:30 UTC) + vue `cpi_movers` + alerte `cpi_drop`, harnais de validation J+28 (`scripts/cpi_validation_j28.sql`), idées v2.2 instruites. **11/06** : Wix Forms V2 ne rend pas les champs cachés dans le DOM → seeding DOM S37 mort-né ; tracker `sprint38` (ids en query params via replaceState) + `wix/masterpage-cooked.js` (setFieldValues). Première attribution `hidden_field` 08:53. |
| **37 / 37b — Attribution & fiabilité** | 09/06/2026 | Tracker sprint37 (execution guard, batching, seeding champs cachés), webhook v10, `form_submits_attributed` / `conversion_journeys` / `content_performance` / `seo_to_contact_funnel`, dédup double-embed rétroactive (phone 110→95/28j, restatement), table `alerts` + cron horaire, taxonomie `page_taxonomy`, aid stable Safari privé. |
| **36 — click_internal** | 04/06/2026 | Nav interne : quel élément UI mène à quelle page (placement + target_path). |
| **35 — Anchor chrome filter** | 03/06/2026 | `cta_anchor_click` ne compte plus le chrome UI (~90 % du volume était Cookiebot/burger/nav). Fix tracker + helper `cooked_is_chrome_anchor` + exclusion rétroactive dans `events_human` (7 318 → 689). |
| **34 — Dashboard removal** | 25/05/2026 | Suppression de l'app Next.js `dashboard/`. Choix produit : questions directes à Claude Code (MCP Supabase) — les RPCs publiées suffisent. |
| **33 / 33+ — Dashboard & pulse** | 22-24/05/2026 | RPCs `site_kpis_compare`, `pages_overview_unified`, `site_pulse`/`pages_pulse`, `site_seo_funnel`, séries quotidiennes, cron GSC GitHub Actions, fix contacts macro. |
| **32 — Attribution query × page** | 22/05/2026 | 3e table GSC `gsc_query_page_daily` (1M rows, 16 mois) — débloque l'attribution requête → landing. |
| **31 — Ingestion GSC** | 21/05/2026 | Cooked devient l'unique data platform (projet Seo séparé supprimé). `gsc_path_daily` + `gsc_query_daily`, 16 mois, Service Account, canonicalisation symétrique. |
| **30 — Audit chirurgical** | 21/05/2026 | Audit 7 agents : fixes `cta_breakdown` (anchor_nav), `engagement_density` (+19 %), `pogo_rates` (+26 %), Edge track v14, webhook v6 (PII stripped), tracker sprint30 (bfcache, SPA), drop zombies. |
| **29 — Audit hardening** | 21/05/2026 | `form_submit` forge bloquée côté `/track`, guard horloges clients ±2j, REVOKE anon sur RPCs orphelines. |
| **28 — session_id localStorage** | 21/05/2026 | Fix inflation self-referral (sliding 30 min), RPC `classify_channel`. |
| **27 — AMDEC Tier 3** | 17/05/2026 | Contract tests RPC nightly (`rpc_health`), rétention `purge_old_events` (>400j). |
| **26 — Version stamp** | 17/05/2026 | `COOKED_VERSION` dans `props._v` → rollout Wix monitorable. |
| **25 — Hardening Edge** | 17/05/2026 | Fail-fast secrets, webhook idempotent (23505), `refresh_pipeline_health()`. |
| **22-24** | 15-16/05/2026 | `anonymous_id` stable localStorage, filtres noise/prefetch, pipeline bot/noise sériel, anchor dans cta_breakdown. |
| **17-21** | 09-15/05/2026 | Bot filtering `events_human`, form_submit server-side (webhook), anchor-menu Wix, aria-label convention. |
| **0-13bis** | 06-07/05/2026 | Déploiement initial (tracker, Velo proxy, Edge, events, snapshot, cron), fix URL-encoding, premier contrat RPC. |
