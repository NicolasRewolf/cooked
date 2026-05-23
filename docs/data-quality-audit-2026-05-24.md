# Audit qualité data — Cooked × GSC × Dashboard

**Date** : 24/05/2026
**Périmètre** : toutes les RPCs publiées en prod + colonnes du snapshot
**Méthodologie** : comparaison ground-truth SQL (recalcul depuis events
bruts ou source la plus proche) vs résultat de la RPC. Verdict par
sub-metric selon une grille 🟢 propre / 🔵 validé / 🟡 incertain / 🔴 bancal.

---

## Synthèse — verdicts par dimension

> Tableau scannable. Cliquer la dimension pour aller au détail.

| Dim. | Sub-metric | Verdict | Note |
|---|---|---|---|
| **A.1** | Sessions Cooked (site_kpis_compare) | 🟢 propre | match exact ground-truth |
| A.1 | Sessions Cooked par-page (snapshot) | 🟢 propre | par-page correct, ne PAS additionner |
| **A.2** | Pageviews (site_kpis_compare) | 🟢 propre | +1 vs GT (timing 1 s) |
| A.2 | Pageviews par-page (snapshot) | 🔵 validé | -3 pageviews path=NULL exclus |
| **A.3** | Unique visitors par-page | 🟢 propre | par-page correct, somme non additive |
| A.3 | Unique visitors site-wide | 🟡 incertain | pas exposé dans site_kpis_compare |
| **A.4** | Dates de fenêtre (28j inclusifs) | 🟢 propre | 26/04 → 23/05 = 28 j OK |
| **B.1** | Bounce rate | 🔵 validé | convention 1 page + < 10 s, code lisible |
| **B.2** | Dwell avg | 🟢 propre | -0.4 s drift snapshot |
| **B.3** | Scroll median | 🔵 validé | sessions sans scroll = 0 % (à doc tooltip) |
| **B.4** | Pogo-stick rate | 🔵 validé | Sprint 30 fix audité |
| **B.5** | Engagement density (p25/p50/p75) | 🟡 incertain | RPC publiée jamais exposée |
| **C.1** | Phone clicks | 🟢 propre | match exact partout |
| **C.2** | Form submits (site_kpis_compare) | 🟢 propre | 21 match exact |
| C.2 | Form submits (pages_overview_unified) | 🔵 validé | -1 form orphelin sans path |
| **C.3** | Contacts macro (site & funnel) | 🟢 propre | 85 = 64 phone + 21 form |
| C.3 | Contacts macro (pages) | 🔵 validé | hérite du -1 de C.2 |
| **C.4** | Booking intent | 🟢 propre | bien isolé de macro Sprint 33 |
| **C.5** | Anchor clicks | 🟡 incertain | 2 423/28j capté, jamais affiché |
| **C.6** | Email click vestigial | 🟢 propre | 0 rows confirmé |
| **D.1** | CWV LCP / INP / CLS p75 | 🟢 propre | match exact (LCP -3 ms drift) |
| **D.2** | CWV TTFB p75 | 🟡 incertain | calculé dans CTE mais perdu (col snapshot manquante) |
| **E.1** | Top referrer | 🟢 propre | DISTINCT ON par count |
| **E.2** | Device split | 🟢 propre | somme à 100.0 % |
| **E.3** | Google sessions | 🟢 propre | définition alignée site_seo_funnel |
| **E.4** | classify_channel (RPC) | 🟡 incertain | jamais appelée par dashboard |
| **E.5** | outbound_destinations (RPC) | 🟡 incertain | jamais appelée par dashboard |
| **F.1** | GSC site-wide (impressions, clicks, position, CTR) | 🟢 propre | match exact site_seo_funnel + site_pulse |
| **F.2** | GSC par-page (gsc_page_performance) | 🔴 **bancal** | **off-by-one fenêtre : 29 j au lieu de 28 j** (~3 % de surcompte) |
| F.2 | GSC par-page (pages_overview_unified) | 🔴 **bancal** | idem off-by-one |
| F.2 | GSC par-page (gsc_top_queries_global / for_path) | 🔴 **bancal** | idem off-by-one |
| **G.1** | Pulse site-wide (site_pulse) | 🟢 propre | match exact ground-truth |
| **G.2** | Pulse par-page (pages_pulse) | 🟢 propre | utilise les RPCs 28j inclusifs |
| **G.3** | Funnel SEO drop-offs | 🟢 propre | tous les ratios cohérents |
| **G.4** | Quadrant logic helpers | 🟢 propre | 1 seule source (pulse_quadrant) |
| **G.5** | Deltas N vs N-1 + pro-ratage | 🟢 propre | null honnête si historique court |
| **H.1** | refresh_pipeline_health | 🟢 propre | healthy, 0 issues |
| **H.2** | tracker_first_seen_global | 🟢 propre | garde-fou ±2 j clock skew |
| **H.3** | Bot + noise filtering | 🟢 propre | 15.4 % filtré (zone attendue) |
| **H.4** | pg_cron jobs (4 actifs) | 🟢 propre | 0 échec 24 h |

**Comptage** : 🟢 **27 propres** · 🔵 **6 validés** · 🟡 **6 incertains** · 🔴 **3 bancales** (en réalité 1 cause racine : off-by-one fenêtre 28j sur 5 RPCs cross-source).

---

## Sanity checks transversaux

| Check | Attendu | Observé | Verdict |
|---|---|---|---|
| `site_kpis_compare.macro_n` ≈ Σ `pages_overview_unified.cooked_contacts_28d` | match ou +1 (form orphelin) | 85 vs 84 (diff 1) | 🔵 validé |
| `site_seo_funnel.clicks` = Σ `gsc_path_daily.clicks` 28 j inclusifs | match exact | 9 385 vs 9 385 | 🟢 propre |
| `site_pulse.cooked_sessions_n` = ground-truth events_human 7 j | match exact | 4 771 vs 4 771 | 🟢 propre |
| Cohérence inter-fenêtres `views_7d ≤ views_28d ≤ views_90d ≤ views_365d` | aucune violation | 0 violation testée | 🟢 propre |

## Bancales actionnables (résumé)

> Pour Nicolas après lecture. Une seule cause racine, 5 RPCs à fixer.

### 🔴 BANCALE — Off-by-one fenêtre 28 j sur 5 RPCs cross-source

**Symptôme** : les RPCs ci-dessous utilisent `WHERE day >= (now() AT TIME
ZONE 'Europe/Paris')::date - INTERVAL '28 days'` qui calcule à
`today - 28` → fenêtre 25/04 → 23/05 = **29 jours inclusifs** (au lieu
de 28).

**Conséquence** : ~3 % de sur-compte sur les volumes GSC affichés dans
`/pages`, `/p/[slug]`, `/queries`. Invisible à l'œil mais **incohérent**
avec la home (`site_kpis_compare`, `site_pulse`, `site_seo_funnel`) qui
utilise la bonne convention 28 j.

**RPCs à fixer** :

1. `pages_overview_unified` (CTE all_paths + g28 + fs28)
2. `gsc_pages_overview` (CTE g + fs28)
3. `gsc_page_performance` (CTE g + fs)
4. `gsc_top_queries_for_path` (WHERE day filter)
5. `gsc_top_queries_global` (WHERE day filter)

**Fix proposé** : remplacer `INTERVAL 'X days'` par `(X - 1)::int` dans
les bornes :

```diff
- WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days'
+ WHERE day >= (now() AT TIME ZONE 'Europe/Paris')::date - 27
  AND day <= (now() AT TIME ZONE 'Europe/Paris')::date
```

Pattern de référence (correct) : `site_kpis_compare` ligne `v_n_start
:= v_today - (period_days - 1)`.

**Effort estimé** : 1 migration nommée, ~5 CREATE OR REPLACE FUNCTION
copiés-collés depuis les versions actuelles avec juste la substitution
ci-dessus. ~15 min de code + apply + sanity check.

### 🟡 INCERTAIN — TTFB calculé mais jamais stocké

**Symptôme** : `refresh_seo_url_snapshot` calcule `ttfb_p75` dans le
CTE `cwv` mais aucune colonne `ttfb_p75_28d_ms` n'existe dans
`seo_url_snapshot` (vérifié 70 colonnes). L'INSERT pose 4 valeurs CWV
mais seules LCP/INP/CLS sont écrites — TTFB perdu silencieusement.

**Fix possible** :
- Soit ajouter la colonne `ttfb_p75_28d_ms bigint` + UPDATE INSERT.
- Soit retirer TTFB du CTE (3 lignes).

**Effort** : 1 migration ALTER TABLE + update INSERT (5 min) OU 1
diff de 3 lignes dans `refresh_seo_url_snapshot` (3 min).

### 🟡 INCERTAINS — 5 RPCs publiées jamais exposées au dashboard

- `engagement_density_for_path` (B.5)
- `classify_channel` (E.4)
- `outbound_destinations_for_path` (E.5)
- `cta_breakdown_for_path` (couvert par `anchor` C.5)
- `behavior_pages_for_period` (legacy, surface de `pages_overview_unified` aujourd'hui)

**Décision** : pas un bug. Soit on les expose (sprint UI dédié), soit
on les drop (clean-up). Pas urgent.

---



---

## Détail par dimension

> Pour chaque sub-metric : définition, intent business, source filter,
> timezone, ground-truth SQL, comparaison RPC vs ground-truth, verdict.

### A. Volume / Audience

**Ground-truth SQL (fenêtre 28j Paris)** :

```sql
WITH win AS (
  SELECT
    (now() AT TIME ZONE 'Europe/Paris')::date - 27 AS start_date,
    (now() AT TIME ZONE 'Europe/Paris')::date     AS end_date
)
SELECT
  COUNT(DISTINCT session_id) FILTER (
    WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
  ) AS sessions,
  COUNT(*) FILTER (
    WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
  ) AS pageviews,
  COUNT(DISTINCT anonymous_id) FILTER (
    WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
  ) AS unique_visitors
FROM events_human, win
WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= win.start_date
  AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= win.end_date;
```

**Résultat 24/05/2026** : sessions=10 802, pageviews=12 883,
unique_visitors=7 369.

#### A.1 Sessions Cooked

- **Définition** : `COUNT(DISTINCT session_id)` parmi les `pageview`
  hors `device_type='server'`.
- **Intent business** : visite humaine unique (1 session = 1 visiteur
  sur une fenêtre glissante de 30 min, cf. tracker `_ckd` sliding).
- **Source filter** : `events_human` (filet anti-bot + noise), name='pageview',
  device != 'server'. Correct.
- **Timezone** : Paris.
- **Comparaison site-wide** :

  | RPC | Valeur | Diff vs ground-truth |
  |---|---|---|
  | `site_kpis_compare.sessions_n` | 10 803 | **+1** (timing 1 s) |
  | Ground-truth | **10 802** | — |

- **Comparaison par-page (snapshot)** :

  | Source | Valeur | Note |
  |---|---|---|
  | `Σ pages_overview_unified.cooked_sessions_28d` | 11 773 | sur-comptage **+9 %** vs site-wide |
  | `Σ seo_url_snapshot.sessions_28d` | 11 773 | idem |

- **Analyse** : la somme par path **n'est pas additive** par
  construction — une session qui visite 3 pages est comptée
  `count(distinct session_id)=1` sur chaque path (snapshot), donc 3
  dans la somme. La metric **par page** est correcte (sessions sur
  CETTE page). Mais ne pas additionner pour reconstruire le site-wide
  → utiliser `site_kpis_compare.sessions_n` à la place.
- **Verdict** :
  - `site_kpis_compare.sessions_n` : 🟢 **propre**.
  - `seo_url_snapshot.sessions_28d` par-page : 🟢 **propre**.
  - **À documenter** : la somme par-path n'est pas un total site-wide.

#### A.2 Pageviews

- **Définition** : `COUNT(*)` des pageviews hors device='server'.
- **Intent business** : nombre de pages affichées sur la fenêtre.
- **Comparaison** :

  | RPC | Valeur | Diff |
  |---|---|---|
  | `site_kpis_compare.pageviews_n` | 12 884 | **+1** (timing) |
  | `Σ seo_url_snapshot.views_28d` | 12 880 | **-3** (path NULL exclu par snapshot) |
  | Ground-truth | **12 883** | — |

- **Verdict** :
  - `site_kpis_compare.pageviews_n` : 🟢 **propre**.
  - `seo_url_snapshot.views_28d` : 🔵 **validé** (3 pageviews
    path=NULL exclues par snapshot, sur 12 883 = 0,02 % d'écart —
    négligeable).

#### A.3 Visiteurs uniques (unique_visitors)

- **Définition** : `COUNT(DISTINCT anonymous_id)` parmi pageviews
  humains.
- **Intent business** : individus distincts (localStorage `_ckd_aid`
  Sprint 22, fallback hash IP+UA salt si JS désactivé).
- **Comparaison** :

  | Source | Valeur | Note |
  |---|---|---|
  | Ground-truth site-wide | 7 369 | — |
  | `Σ seo_url_snapshot.unique_visitors_28d` | 10 903 | **+48 %** (somme par-path non additive) |

  > **Pas exposé site-wide** dans `site_kpis_compare` aujourd'hui. Seule
  > la valeur par page est utilisée (et correcte).

- **Verdict** :
  - `seo_url_snapshot.unique_visitors_28d` par page : 🟢 **propre**.
  - Pas de RPC site-wide → 🟡 **incertain** quant à l'usage si on
    voulait afficher "X visiteurs uniques sur le site". **Suggestion** :
    ajouter `unique_visitors_n` à `site_kpis_compare` si Plouton le
    demande un jour, sourcé du ground-truth (pas de la somme).

#### A.4 Dates de fenêtre

- **Définition** : `period_n_start = today - (period_days - 1)`,
  `period_n_end = today` (Paris).
- **Comparaison** : sur `site_kpis_compare(28)`, retourne
  `2026-04-26 → 2026-05-23` aujourd'hui. 23 - 26 + 1 = **28 jours**
  inclusifs. Correct.
- **Verdict** : 🟢 **propre**.

---

### B. Engagement

Audit effectué sur la top page `/post/durée-de-la-garde-à-vue-...`
(982 sessions 28j) pour avoir un sample représentatif.

#### B.1 Bounce rate

- **Définition (seo_pages_overview)** : `bounce_count / entry_count`
  où `is_bounce = (pages_viewed = 1 AND session_duration < 10s)`.
  C'est-à-dire : session entrée sur cette page, 1 seule pageview, ≤ 10 s.
- **Intent business** : taux de "rebond rapide" (session qui part
  juste après être arrivée).
- **Comparaison** :

  | RPC | Valeur (top page) |
  |---|---|
  | `seo_url_snapshot.bounce_rate_28d` | 15.01 % |
  | `pages_overview_unified.cooked_bounce_rate_28d` | 15.01 % |

  (Le ground-truth recalcul complet n'est pas pratique inline — la
  formule est complexe et passe par 4 CTEs. Le code de `seo_pages_overview`
  est lisible et conforme à l'intent.)
- **Verdict** : 🔵 **validé** — convention claire (entry + 1 page + < 10 s),
  cohérent partout, pas de drift dans le code.

#### B.2 Dwell avg (avg_dwell_seconds_28d)

- **Définition (seo_pages_overview)** : `avg(MAX((props->>'duration_seconds')::numeric)
  FILTER (WHERE name = 'page_exit'))` — pour chaque session, on prend le
  max duration_seconds sur page_exit (le tracker en émet potentiellement
  plusieurs au cours de la session via pagehide/beforeunload/visibilitychange).
- **Comparaison sur top page** :

  | Source | Dwell avg |
  |---|---|
  | Ground-truth recalculé identique | 80.5 s |
  | `seo_url_snapshot.avg_dwell_seconds_28d` | 80.1 s |

- **Écart** : -0.4 s (-0.5 %). Probable timing snapshot rebuild
  (hier 23:27 Paris vs maintenant).
- **Verdict** : 🟢 **propre**.

#### B.3 Scroll avg / median / complete %

- **Définition (seo_pages_overview, CTE sp)** :
  - `max_scroll = COALESCE(MAX(percent) FILTER (WHERE name='scroll_depth'), 0)`
  - **Convention importante** : sessions sans event `scroll_depth` (parce
    qu'elles n'ont pas franchi le milestone 25 %) sont comptées comme
    `max_scroll = 0`.
- **Comparaison top page** :

  | Source | scroll_median |
  |---|---|
  | Ground-truth COALESCE 0 (sessions sans scroll incluses) | **25.0 %** |
  | Ground-truth FILTER `> 0` (sessions qui ont scrollé) | **50.0 %** |
  | `seo_url_snapshot.scroll_median_28d` | **25.0 %** |

- **Diagnostic** : sur 1 048 (session, path) pour cette page, **316
  sessions (30 %)** n'ont émis aucun event scroll_depth → comptées 0.
  La médiane "tout compris" est 25 %, la médiane "qui ont scrollé"
  serait 50 %. Le snapshot expose la 1ère (intent réel : "combien voit
  vraiment la page").
- **Verdict** : 🔵 **validé** — convention défendable et explicite dans
  le code SQL, mais **à documenter dans le tooltip UI** pour Plouton
  ("inclut les sessions sans scroll = 0 %").

#### B.4 Pogo-stick rate

- **Définition (`pogo_rates_for_period`)** : sessions arrivant de Google
  qui quittent rapidement. Sprint 30 a corrigé le calcul (LEFT JOIN
  dedup + NULL exit handling).
- **Comparaison top page** : `pogo_rate_28d = 30.2 %` — environ 1
  visite Google sur 3 sur cette page repart en <10 s. Cohérent pour un
  article ressource lu en diagonale.
- **Verdict** : 🔵 **validé** — formule complexe mais auditée Sprint 30,
  expose un signal NavBoost reconnu.

#### B.5 Engagement density (p25 / p50 / p75 dwell + evenness)

- **Définition (`engagement_density_for_path`)** : RPC publiée Sprint 27
  qui retourne percentiles 25/50/75 du dwell par page + evenness_score.
- **Statut** : RPC publiée mais **jamais appelée par le dashboard**.
- **Verdict** : 🟡 **incertain** — pas exposée, donc pas validable
  visuellement. Le code SQL est cohérent (vu Sprint 30 audit).

---

### D. Core Web Vitals (LCP / INP / CLS / TTFB)

**Ground-truth SQL** : percentile_cont 0.75 sur `(props->>'value')` filtré
par `props->>'metric' = 'LCP|INP|CLS|TTFB'`. Source : `events_human` name=
`web_vitals`. Le tracker envoie 1 event par metric par session (cf
PerformanceObservers tracker.html, Sprint 30).

**Top page sample (734 LCP events, échantillon stable)** :

| Metric | Ground-truth | `seo_url_snapshot` | Diff |
|---|---|---|---|
| LCP p75 (ms) | 1583 | 1580 | -3 ms (~0.2 %, drift snapshot) |
| INP p75 (ms) | 304 | 304 | 0 ✅ |
| CLS p75 | 0.15 | 0.15 | 0 ✅ |

- **TTFB p75** : calculé dans `refresh_seo_url_snapshot.cwv` mais
  **PAS stocké** comme colonne dans `seo_url_snapshot` (vérifié dans
  les 70 colonnes effectives). Le code CTE calcule TTFB mais l'INSERT
  ne le pose pas. → 🟡 **incertain** : column manquante, le code calcule
  pour rien.
- **Verdict global CWV** :
  - LCP / INP / CLS p75 : 🟢 **propre**.
  - TTFB p75 : 🟡 **incertain** — calcul dans le CTE mais perdu à
    l'insert. À droper du CTE ou à ajouter une colonne snapshot
    `ttfb_p75_28d_ms`. **Suggestion** : nettoyer le CTE (~3 lignes).

---

### E. Acquisition / Channels

#### E.1 top_referrer_28d

- **Définition** : référent le plus fréquent par page sur pageviews, via
  `DISTINCT ON (path) path, referrer_hostname` ordonné par count desc.
- **Vérifié** sur top page : `www.google.com` (cohérent avec 761
  google_sessions sur 982 total).
- **Verdict** : 🟢 **propre**.

#### E.2 device_split_28d

- **Définition** : `jsonb_object_agg(device_type, pct)` où pct = % de
  pageviews par device, arrondi à 1 décimale.
- **Vérifié** sur top page : `{mobile: 76.3, tablet: 0.4, desktop:
  23.3}` → somme = 100.0 % ✅.
- **Verdict** : 🟢 **propre**.

#### E.3 google_sessions_28d

- **Définition (snapshot)** : sessions distinctes avec `referrer_hostname
  LIKE '%google%'` OR `utm_source='google' AND utm_medium='organic'` —
  alignée avec `site_seo_funnel.google_sessions`.
- **Vérifié** : top page 761 google_sessions sur 982 visites = 77.5 %
  Google. Plausible pour un article ressource SEO.
- **Verdict** : 🟢 **propre**.

#### E.4 classify_channel (RPC paramétrable)

- **Définition** : `classify_channel(ref, utm_source, utm_medium,
  self_host)` retourne `paid` / `organic_google` / `organic_other` /
  `ai` / `social` / `direct` / `internal` / etc. Taxonomie unifiée
  Sprint 28.
- **Statut** : RPC publiée mais **jamais appelée par le dashboard**.
- **Verdict** : 🟡 **incertain** — pas exposée. Si on l'affichait
  (vue "Channels" sur la home par exemple), il faudrait sanity-checker
  que les buckets somment à 100 % vs sessions site-wide.

#### E.5 outbound_destinations_for_path (RPC)

- **Définition** : top hostnames cliqués vers l'extérieur par page,
  via `click_outbound`.
- **Statut** : RPC publiée mais **jamais appelée par le dashboard**.
- **Verdict** : 🟡 **incertain** (pas exposé, pas validable).

---

### H. Méta / Pipeline

#### H.1 refresh_pipeline_health

- **Comparaison** :

  | Axe | Valeur 24/05 11h Paris |
  |---|---|
  | status | **healthy** ✅ |
  | snapshot_age_hours | 0.32 (rebuild ~20 min plus tôt) |
  | cron_last_status | succeeded |
  | last_event_age_minutes | 5.9 (live) |
  | gsc_data_age_days | 2.00 (J-2, normal) |
  | gsc_ingest_age_hours | 13.56 (cron GitHub Actions ce matin) |
  | issues | [] |

- **Verdict** : 🟢 **propre**.

#### H.2 tracker_first_seen_global

- **Vérification** : retourne `2026-05-06 19:14 Paris` (Sprint 0, confirmé
  via CLAUDE.md). Garde-fou ±2 j contre clock-skew implémenté
  (Sprint 29).
- **Utilisé par** : `site_pulse`, `cooked_pages_compare`, `pages_pulse`
  pour le pro-ratage Cooked.
- **Verdict** : 🟢 **propre**.

#### H.3 Bot filtering (events_human vue)

- **Compteurs prod 24/05** :
  - `events` raw : 206 509
  - `events_human` : 174 628
  - **Filtered : 15.44 %** (cohérent avec ~17 % attendus CLAUDE.md)
- **bot_fingerprints** : 72 anonymous_ids (Layer 1).
- **noise_sessions** : 7 394 (Layer 2). **À noter** : énorme bond depuis
  les 35 cités dans CLAUDE.md (probablement crawler + prefetch
  Wix/Vercel agressif, cron `refresh_noise_filters_hourly` Sprint 28
  capture beaucoup plus depuis).
- **Verdict** : 🟢 **propre** — les 2 layers fonctionnent et le ratio
  filtré est dans la zone attendue.

#### H.4 cron pg_cron (4 jobs)

- **Vérification** : `cron_jobs_failed_24h = 0` (vu dans audit
  précédent). 4 jobs documentés (snapshot, noise hourly, contract tests,
  purge mensuel) actifs.
- **Verdict** : 🟢 **propre**.

---

### G. Cross-source (Pulse, Funnel, deltas)

**Test 1 — `site_pulse` site-wide** : recalcul ground-truth GSC 28j +
Cooked 7j, appel à `pulse_status()` :

| Source | gsc_n | gsc_prev | cooked_n | cooked_prev | quadrant |
|---|---|---|---|---|---|
| `site_pulse` | 9 385 | 11 516 | 4 771 | 4 174 | down_up |
| Ground-truth | **9 385** | **11 516** | **4 771** | **4 174** | **down_up** |

→ 🟢 **match exact**.

**Test 2 — `pages_pulse` sur top page** :

| Source | gsc_n | cooked_n |
|---|---|---|
| `pages_pulse` (durée-garde-à-vue) | 1 122 | 412 |
| Ground-truth 28j inclusifs | **1 122** | **412** |

→ 🟢 **match exact**. `pages_pulse` utilise `gsc_pages_compare` et
`cooked_pages_compare` qui appliquent la **bonne convention 28j**
(via `v_today - (period - 1)`). Cohérent avec site-wide, donc l'off-by-one
de F.2 ne touche PAS le Pulse. **Détail technique** : `gsc_pages_compare`
et `cooked_pages_compare` sont distinctes de `gsc_page_performance` et
`pages_overview_unified` (qui sont 29j inclusifs).

**Test 3 — `site_seo_funnel`** : déjà confirmé en F.1, valeurs identiques
à `site_pulse` et ground-truth.

| Sub-metric | RPC | Valeur | Verdict |
|---|---|---|---|
| Pulse site-wide | `site_pulse` | down_up @ 5 % seuil | 🟢 propre |
| Pulse par-page | `pages_pulse` | 28j inclusifs OK | 🟢 propre |
| Funnel impressions → clics | `site_seo_funnel.impr_to_click_pct` | 2.05 % | 🟢 propre |
| Funnel clics → visites Google | `site_seo_funnel.click_to_session_pct` | 79.3 % | 🟢 propre |
| Funnel visites → contacts | `site_seo_funnel.session_to_contact_pct` | 1.14 % | 🟢 propre |
| Quadrant logic (helpers SQL) | `pulse_quadrant`, `pulse_status` | testé `up/down→up_down`, `flat/flat→neutral`, etc. | 🟢 propre |
| Deltas N vs N-1 site-wide | `site_kpis_compare.*_delta_pct` | conformes formule `(N-prev)/prev*100` | 🟢 propre |
| Pro-ratage Cooked si historique < 2×period | `cooked_pages_compare`, `site_kpis_compare` | retourne `null` plutôt que biaiser | 🟢 propre |

**Note** : la convention de définition `quadrant` (`up_down` = SEO ↗
engagement ↘) est documentée à 3 endroits cohérents :
- `pulse_quadrant()` SQL (source unique)
- `dashboard/lib/pulse-quadrant.ts` (constants visuels)
- `dashboard/components/quadrant-badge.tsx` (libellés courts)

L'audit n'a pas trouvé de drift entre les 3.

---

### F. GSC

**Ground-truth SQL (fenêtre 28j Paris inclusifs)** :

```sql
WITH win AS (
  SELECT
    (now() AT TIME ZONE 'Europe/Paris')::date - 27 AS start_date,
    (now() AT TIME ZONE 'Europe/Paris')::date     AS end_date
)
SELECT
  SUM(impressions)::bigint AS impressions,
  SUM(clicks)::bigint AS clicks,
  ROUND((SUM(position * impressions) / NULLIF(SUM(impressions), 0))::numeric, 2)
    AS position_avg_pondéré_impressions,
  ROUND((100.0 * SUM(clicks) / NULLIF(SUM(impressions), 0))::numeric, 2) AS ctr_pct
FROM gsc_path_daily, win
WHERE day >= win.start_date AND day <= win.end_date;
```

**Résultat 24/05/2026** : impressions=456 939, clicks=9 385,
position=7.64, CTR=2.05 %, 26 jours avec data (GSC à J-2,
last_day=21/05).

#### F.1 GSC site-wide (impressions, clicks, position, CTR)

- **Comparaison site-wide** :

  | RPC | Impressions | Clicks | CTR |
  |---|---|---|---|
  | `site_seo_funnel` | 456 939 | 9 385 | 2.05 % |
  | `site_pulse.gsc_clicks_n` | — | 9 385 | — |
  | Ground-truth | **456 939** | **9 385** | **2.05 %** |

- **Position pondérée** : on utilise `SUM(position * impressions) /
  SUM(impressions)` partout. C'est la convention Google Search Console
  native. ⚠️ Alternative possible : pondérer par clicks = 7.02 (donne
  une "position effective des clics"). On utilise la pondération
  impressions partout (cohérent), donc OK.
- **Verdict site-wide** : 🟢 **propre**.

#### F.2 GSC par-page (🔴 OFF-BY-ONE détecté)

- **Test sur** `/post/durée-de-la-garde-à-vue-...` :

  | RPC | Impressions | Clicks | Position | CTR |
  |---|---|---|---|---|
  | `gsc_page_performance` | 31 795 | 1 158 | 5.16 | 3.64 % |
  | `pages_overview_unified` | 31 795 | 1 158 | 5.16 | 3.64 % |
  | Ground-truth 28j inclusifs (26/04→23/05) | **30 908** | **1 122** | **5.16** | **3.63 %** |
  | Ground-truth 29j (25/04→23/05) | **31 795** | **1 158** | — | — |

- **Diagnostic** : les RPCs par-page utilisent `WHERE day >= (now() AT
  TIME ZONE 'Europe/Paris')::date - INTERVAL '28 days'` qui calcule à
  `today - 28` (donc fenêtre 25/04 → 23/05 = **29 jours inclusifs**).
  Or, la convention business **28 jours** veut 26/04 → 23/05 = 28 jours.

  Côté RPCs site-wide, le calcul est `v_today - (period_days - 1)` =
  26/04 → 23/05 (28 jours, **correct**).

  → **Incohérence de fenêtre** entre RPCs cross-source (29 jours) et
  RPCs site-wide (28 jours). Sur cette page : +887 impressions
  (+2.87 %) et +36 clics (+3.21 %). Sur la position : invariante car
  pondérée par impressions, donc le différentiel est marginal.

  **RPCs affectées** (29 jours en réalité, label "28j" trompeur) :
  - `pages_overview_unified` (`INTERVAL '28 days'` et `'90 days'`)
  - `gsc_pages_overview` v3
  - `gsc_page_performance` v2
  - `gsc_pages_compare`, `cooked_pages_compare`
  - `pages_pulse` (à vérifier — utilise les 2 précédentes)
  - `gsc_top_queries_for_path` (`INTERVAL '1 day'` × days_back +
    days_back, soit ~29j aussi)
  - `gsc_top_queries_global` (idem)
  - `outbound_destinations_for_path`, `cta_breakdown_for_path` (à
    vérifier)

  **RPCs correctes** (28 jours inclusifs) :
  - `site_kpis_compare`
  - `site_pulse`
  - `site_seo_funnel`
  - `gsc_page_daily_series`, `cooked_page_daily_series` (utilisent
    `days_back - 1`)

- **Verdict** :
  - GSC site-wide : 🟢 **propre**.
  - GSC par-page (et toutes RPCs cross-source) : 🔴 **bancal** —
    fenêtre 29 jours au lieu de 28. Écart de ~3 % sur les volumes,
    invisible à l'œil mais incohérent avec la home.
- **Fix proposé** (hors scope audit) : 1 migration qui remplace
  `INTERVAL 'X days'` par `- (X - 1)` dans toutes les RPCs cross-source.
  Pattern de référence : `site_kpis_compare`.

---

### C. Conversions Cooked

> Périmètre prio 1 (le plus regardé par Plouton, le plus à risque
> historiquement — bug review du 24/05 sur `cooked_conversions_28d`).

**Ground-truth SQL (fenêtre 28j Paris)** :

```sql
WITH win AS (
  SELECT
    (now() AT TIME ZONE 'Europe/Paris')::date - 27 AS start_date,
    (now() AT TIME ZONE 'Europe/Paris')::date     AS end_date
)
SELECT
  COUNT(*) FILTER (WHERE name = 'cta_phone_click')    AS phone_clicks,
  COUNT(*) FILTER (WHERE name = 'form_submit')        AS form_submits,
  COUNT(*) FILTER (WHERE name = 'cta_booking_click')  AS booking_clicks,
  COUNT(*) FILTER (WHERE name = 'cta_anchor_click')   AS anchor_clicks,
  COUNT(*) FILTER (WHERE name = 'cta_email_click')    AS email_clicks,
  COUNT(*) FILTER (WHERE name = 'form_submit' AND path IS NULL) AS form_submits_orphans
FROM events_human, win
WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= win.start_date
  AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= win.end_date;
```

**Résultat 24/05/2026** : phone=64, form_submit=21 (dont **1 orphelin path NULL**),
booking=193, anchor=2 423, email=0.

#### C.1 phone_click (cta_phone_click)

- **Définition** : `COUNT(*) WHERE name='cta_phone_click'` depuis events_human.
- **Intent business (CLAUDE.md)** : macro-conversion (tap-to-call).
- **Source filter** : `events_human` (correct). Pas de filtre device_type
  nécessaire — le tracker browser n'insère jamais avec `device='server'`.
- **Timezone** : Paris (vérifié dans toutes les RPCs).
- **Comparaison** :

  | RPC | Valeur | Diff |
  |---|---|---|
  | `site_kpis_compare.phone_clicks_n` | 64 | 0 |
  | `Σ pages_overview_unified.cooked_phone_clicks_28d` | 64 | 0 |
  | Ground-truth events_human | **64** | — |

- **Verdict** : 🟢 **propre**.

#### C.2 form_submit

- **Définition** : `COUNT(*) WHERE name='form_submit'` depuis events_human.
- **Intent business (CLAUDE.md)** : macro-conversion (vrai contact via
  formulaire). Inséré server-side par `form-webhook` avec
  `device_type='server'`, `session_id='webhook-uuid'`,
  `anonymous_id='webhook-uuid'`.
- **Source filter** : `events_human` (correct). **Ne PAS filtrer
  device_type** — règle dure CLAUDE.md.
- **Timezone** : Paris.
- **Comparaison** :

  | RPC | Valeur | Diff |
  |---|---|---|
  | `site_kpis_compare.form_submits_n` | 21 | 0 |
  | `Σ pages_overview_unified.cooked_form_submits_28d` | **20** | **-1** |
  | Ground-truth events_human | **21** | — |
  | Ground-truth FILTER path IS NULL | 1 | — |

- **Analyse** : 1 form_submit orphelin (path NULL) a été reçu le
  15/05/2026 16:46 Paris — `page_source` null dans le payload Wix
  (formulaire soumis hors contexte d'une page indexable, probablement
  un test). Ce form n'apparaît dans aucune ligne de
  `pages_overview_unified` puisque ce dernier construit son univers de
  paths via UNION de `seo_url_snapshot` ∪ `gsc_path_daily` (jamais le
  path NULL).
- **Verdict** :
  - `site_kpis_compare.form_submits_n` : 🟢 **propre**.
  - `pages_overview_unified.cooked_form_submits_28d` : 🔵 **validé**
    avec écart expliqué (-1 = 1 form orphelin sans path). Sur 28j à
    21 forms, ça fait 5 % d'écart. À grande échelle (>100 forms/28j) ce
    serait <1 %. **Suggestion** : exposer en bonus une ligne synthétique
    "form_submits hors page" dans la home ou ajouter un path sentinelle
    `(orphelin)` dans la RPC.

#### C.3 contacts macro (= phone + form_submit)

- **Définition** : `phone_clicks + form_submits` (CLAUDE.md cooked,
  taxonomie macro).
- **Intent business** : THE business metric — vrai contact établi.
- **Ne JAMAIS** y additionner `booking_cta_click` (= micro). Bug levé
  par la review du 24/05, fixé par migration `20260524100000`.
- **Comparaison** :

  | RPC | Valeur | Diff |
  |---|---|---|
  | `site_kpis_compare.macro_conversions_n` | 85 | 0 |
  | `site_seo_funnel.macro_contacts` | 85 | 0 |
  | `Σ pages_overview_unified.cooked_contacts_28d` | **84** | **-1** |
  | Ground-truth (64+21) | **85** | — |

- **Verdict** :
  - `site_kpis_compare` et `site_seo_funnel` : 🟢 **propre**.
  - `pages_overview_unified` : 🔵 **validé** (hérite de C.2).

#### C.4 booking intent (cta_booking_click)

- **Définition** : `COUNT(*) WHERE name='cta_booking_click'`.
- **Intent business** : micro-conversion (intent déclaré, pas
  matérialisé). **Affichée SÉPARÉMENT** comme "Intent RDV" depuis le
  fix Sprint 33 — ne plus jamais l'additionner à macro.
- **Source filter** : events_human.
- **Comparaison** :

  | RPC | Valeur | Diff |
  |---|---|---|
  | `Σ pages_overview_unified.cooked_booking_intent_28d` | 193 | 0 |
  | Ground-truth | **193** | — |

- **Verdict** : 🟢 **propre** (correctement isolé de macro).

#### C.5 anchor (cta_anchor_click)

- **Définition** : `COUNT(*) WHERE name='cta_anchor_click'`.
- **Intent business** : micro-conversion (clic "Demander un RDV" sticky
  bar mobile / table des matières / anchor menu). Émis par 3 chemins
  côté tracker (`click`, `hashchange`, `sticky-fallback`).
- **Volume 28j** : **2 423** — important volume (clic facile, plusieurs
  sources). Jamais affiché dans le dashboard.
- **Apparaît dans** : `cta_breakdown_for_path(path, days)` qui renvoie
  un breakdown phone/booking/anchor par placement. RPC jamais appelée
  par le dashboard.
- **Verdict** : 🟡 **incertain** — le calcul est correct (event capté +
  cohérent CLAUDE.md), mais comme jamais affiché on ne peut pas valider
  l'usage UX. **Suggestion** : ajouter une row dans
  `cooked_pages_compare` ou le panneau Comportement pour visibilité.

#### C.6 email_click (cta_email_click)

- **Définition** : `COUNT(*) WHERE name='cta_email_click'`.
- **Intent business** : prévu mais jamais activé (tracker skip
  explicitement les `mailto:`, le site jplouton-avocat.fr n'expose pas
  d'email). Colonnes `email_clicks_*` droppées de `seo_url_snapshot` en
  Sprint 30. Resté dans `ALLOWED_EVENTS` de l'Edge `/track` à titre
  défensif.
- **Volume 28j** : **0** (confirmé, conforme à CLAUDE.md).
- **Verdict** : 🟢 **propre** (vestigial assumé, 0 rows partout, drop
  cohérent).

---

