# 00 — Baseline « avant » — mission Cooked 02/09/2026

> Photo de l'état du système au **02/09/2026 entre 01:12 et 01:32 (Paris)**,
> prise en **lecture seule** (MCP Supabase `execute_sql`, `gh`, repo local à
> `e95f3ee` = `main`). Aucune interprétation ici : chaque ligne porte sa
> requête (annexe A, `Q‑nn`) ou sa source, et sa sortie brute. Les mêmes
> requêtes, sur les mêmes fenêtres, produiront `02-apres.md`.
>
> Conventions : dates JJ/MM/AAAA, heures Paris, `[non vérifié]` = affirmation
> sans ancrage prod/repo, « 28 j » = `occurred_at >= now() - interval '28 days'`
> au moment de la mesure sauf mention contraire.

---

## 0. Réflexes de démarrage (mission §4 Phase 0 étape 2)

| Réflexe | Sortie (02/09/2026 01:12–01:15 Paris) | Req. |
|---|---|---|
| `alerts WHERE NOT acked` | **48 alertes non acquittées** : `cpi_drop` 22 warn + 9 critical (escalades « warn ≥ 5 j sans acquittement », du 23/08 au 01/09) ; `gbp_gap` 7 warn + 1 critical (15→22/08) ; `gbp_daily_stale` 5 warn (28/08→01/09, dernier jour GBP = 20/08) ; `gsc_ingest_missed` 3 warn (27/08, 28/08, 31/08) ; `pipeline_dead` 1 critical (22/08 04:15 Paris) | Q‑01 |
| `refresh_pipeline_health()` | `status=healthy`, `issues=[]` ; snapshot SEO 01/09 05:00 (âge 20,25 h) ; dernier event 01/09 23:14 UTC (0,1 min) ; 176 events/60 min ; GSC dernier jour **29/08** (âge 4 j), dernière ingestion 01/09 13:55 Paris ; DFS 814 lignes, sync 31/08 16:29 Paris | Q‑02 |
| `gsc_last_data_day()` | **29/08/2026** (J‑4 au 02/09) | Q‑02 |
| `latest_rpc_health()` | 12 RPC, **12 `ok`**, dernier passage 01/09 05:30 Paris (contract tests) et 02/09 00:15 (règle horaire). Durées : `tracker_first_seen_global` **20 288 ms**, `site_context_export` 4 490 ms, `page_reads` 4 386 ms, `behavior_pages_for_period` 4 119 ms | Q‑03 |
| `cron.job_run_details` 30 j | **9 jobs, 1 894 runs, 0 échec** (détail §3.4) | Q‑04 |

Une alerte active s'instruit avant tout chiffre : les 48 alertes sont
instruites dans `01-audit.md` (zone h). Résumé factuel ici : `gbp_*` = panne
attendue du cron GBP (migration GCP `rewolf-507310`, demande d'accès API
déposée le 01/09, verdict attendu 10‑15/09 — mémoire de session) ;
`gsc_ingest_missed` = 3 ingestions arrivées après 13:15 Paris ;
`pipeline_dead` 22/08 = 0 event reçu entre 03:15 et 04:15 Paris (seul tick
à zéro sur 721 en 30 j, Q‑27) ; `cpi_drop` = 31 alertes sur 9 pages en 23 jours.

## 1. Ce que le repo prétend, confronté à la prod (Phase 0 étape 3)

| Affirmation du repo | Prod | Verdict | Req. |
|---|---|---|---|
| Tracker `sprint41` déployé (AGENTS.md:50, CLAUDE.md) | `props->>'_v'` sur 7 j (events_human) : `sprint41` 48 007 events / 3 070 sessions (**99,96 %**) ; `NULL` 18 events (= 18 `form_submit`, insérés serveur, sans `_v` : attendu) ; `sprint30` 3 `engagement_tick` d'une session le 27/08 11:33 (page en cache navigateur) ; 24 h : 6 894 events, 100 % `sprint41` | ✅ | Q‑05, Q‑06 |
| Edge `track` **v27** déployée (AGENTS.md:51) | `list_edge_functions` : `track` version Supabase 35, `updated_at` = **25/07/2026 21:15 Paris**, `verify_jwt=false` ; en‑tête du code déployé : « v27 — 25/07/2026 : x-cooked-key ingest gate » = en‑tête de `supabase/functions/track/index.ts:1`. Dernier commit touchant `track/` + `_shared/{track_row,canonical_path,events_row}.ts` : `f8b42c1` 25/07 21:16 (même minute que le déploiement). Hash du bundle non reproductible localement → **égalité au hash [non vérifié]**, égalité d'en‑tête + absence de commit ultérieur vérifiées | ✅ (en‑tête) | Q‑07, `git log` |
| Edge `form-webhook` **v13** déployée (AGENTS.md:52) | version Supabase 19, `updated_at` = **10/08/2026 18:32 Paris** ; en‑tête déployé « v13 — 10/08/2026 : Pont SECIB » = `form-webhook/index.ts:1` ; aucun commit ultérieur sur `form-webhook/`, `_shared/form_row.ts`, `_shared/events_row.ts` | ✅ (en‑tête) | Q‑07, `git log` |
| `supabase/migrations/` = miroir prod (CONTRIBUTING.md « miroir exact, timestamp réel ») | Prod : **212** versions dans `supabase_migrations.schema_migrations` ; local : **162** fichiers. **104 versions prod sans fichier local de même timestamp** ; **54 fichiers locaux dont le timestamp n'existe pas en prod** (mai–juin re‑datés, + 7 de juillet‑août : `20260710121500_c8_cpi_compose` ↔ prod `20260710102132`, `20260728002000_page_reads_module` ↔ `20260727222319`, `20260728102500_rpc_contract_check_helper` ↔ `20260728081943`, `20260728103000`/`104500`/`110000`/`113000` ↔ `20260728083232`/`083532`/`090355`/`105744`, `20260823120000_freshness_contract…` ↔ `20260823210813`). **1 migration prod sans aucun fichier local, même renommé : `20260807224552_weekly_conversion_pages_routine`** (table `conversion_weekly`, fonctions `cooked_weekly_conversions_snapshot`, `weekly_conversions_report`, `conversions_leaderboard`). `scripts/check_schema_migrations.py` ne compare à la prod qu'avec `DATABASE_URL`, absent en CI → il ne vérifie que l'unicité locale | ❌ | Q‑08, `comm` |
| `supabase/rpcs.sql` = corps des 122 routines prod (CHANGELOG 31/08 « rpcs.sql + méta régénérés (121 → 122) ») | `contracts/rpc_snapshot_meta.json` : `content_sha256 = a3d69c7d…` = sha256 du corps local ✅ (fichier cohérent avec son méta). **Prod : sha256 du même dump = `179ed9cc…` ≠**. Par fonction (md5 de `pg_get_functiondef`) : 114 identiques, **2 différentes** (`cooked_alerts_refresh`, `raise_cooked_alert`), **6 en prod absentes du fichier** (`alert_rule_freshness`, `alert_rule_gsc_ingest_missed`, `alert_rule_warn_escalation`, `conversions_leaderboard`, `cooked_weekly_conversions_snapshot`, `weekly_conversions_report`), **6 dans le fichier absentes de prod** (`alert_rule_cpi_stale`, `alert_rule_dfs_stale`, `alert_rule_gbp_gap`, `alert_rule_gsc_gap`, `alert_rule_gsc_lag`, `dashboard_check_stale`). L'en‑tête du fichier dit « Généré le 10/08/2026 » alors que le méta dit `generated_at: 2026-08-31` : le fichier a été **édité à la main** le 31/08 (ajout de `alert_rule_page_taxonomy_gap`), pas régénéré depuis la prod. Les 122 « routines » incluent 4 fonctions de l'extension `unaccent` : **118 routines Cooked** | ❌ | Q‑09 (+ comparaison locale) |
| `supabase/views.sql` = 11 vues prod (« régénéré 10/08/2026, 121 fonctions ») | 11 vues en prod, 11 dans le fichier (mêmes noms). Le fichier est **reformaté à la main** (colonnes regroupées, commentaires) : aucune des 11 n'est identique au `md5(pg_get_viewdef(oid,true))` prod. `events_human` et `events_main` : **sémantiquement identiques** à la prod (lecture ligne à ligne, Q‑10) ; `cpi_gisement` local `SELECT *` = prod (liste de colonnes développée). 8 autres vues : identité sémantique **[non vérifié]** (zone i) | ⚠️ | Q‑10 |
| `paris_date` / `paris_today` : `proconfig IS NULL` (contrat d'inlining, migration `20260725045430`) | `paris_date(ts)` : `proconfig = NULL` ; `paris_today()` : `proconfig = NULL` | ✅ | Q‑11 |
| SECURITY.md:36 « `REVOKE` public/anon/authenticated sur toute RPC » | Fonctions **SECURITY DEFINER** exécutables par `anon` **et** `authenticated` : **2** — `rpc_contract_check(p_name, p_sql, p_min_rows, p_exact_rows)` (corps : `EXECUTE p_sql INTO v_rows`, `LANGUAGE plpgsql`) et `page_reads(p_from timestamptz, p_to timestamptz)`. ACL des deux : `{=X/postgres,…,anon=X/postgres,authenticated=X/postgres}` (privilège par défaut PUBLIC jamais révoqué ; créées par les migrations du 27‑28/07). Fonctions SECURITY INVOKER exécutables par `anon` : 17 (`canonical_path`, `cooked_is_chrome_anchor`, `cooked_is_main_site`, `cooked_is_spam_referrer`, `cooked_normalize_email`, `cooked_normalize_phone_fr`, `cooked_page_index`, `cooked_page_type`, `cooked_paris_ts_start`, `cooked_paris_ts_end_exclusive`, `cooked_site_scope`, `cpi_compose`, `page_reads(p_days)`, `paris_date`, `paris_today`, `unaccent`×2 + `unaccent_init`, `unaccent_lexize`) ; `cooked_cpi_snapshot()` exécutable par `authenticated` seulement | ❌ | Q‑11, Q‑28 |
| Vues : `security_invoker` partout | `reloptions` : `security_invoker=true` sur 8 vues ; **absent sur `cpi_capture_perdue`, `cpi_movers`, `events_no_bots`**. `cpi_capture_perdue` a en plus `GRANT SELECT` à `anon`/`authenticated` (advisor **ERROR** `security_definer_view`) | ❌ | Q‑12 |
| Exposition PostgREST réelle (clé `anon` legacy, lecture seule, 02/09 01:29 Paris) | `GET /rest/v1/cpi_capture_perdue?select=path,grade&limit=1` → **HTTP 200, 1 ligne** ; `GET /rest/v1/rpc/page_reads?p_from=…&p_to=…` (Range 0‑0) → **HTTP 200, 1 ligne** (session×path×dwell) ; `GET /rest/v1/cpi_daily?limit=1` → 200 `[]` (RLS deny‑all efficace) ; `GET /rest/v1/crm_prospects?limit=1` → **401 permission denied** (aucun grant, RLS) ; `rpc_contract_check` : **non appelé** (tout appel écrit dans `rpc_health`) — exposition déduite de l'ACL + advisor 0028 (« can be executed by the anon role … via /rest/v1/rpc/rpc_contract_check ») | ❌ | curl (annexe B) |
| Advisors Supabase | **Security : 1 ERROR** (`security_definer_view` sur `cpi_capture_perdue`), **13 WARN** : `function_search_path_mutable` ×8 (`paris_date`, `paris_today` — voulu ; `cooked_paris_ts_start`, `cooked_paris_ts_end_exclusive`, `cooked_is_main_site`, `cooked_site_scope`, `cooked_normalize_email`, `cooked_normalize_phone_fr` — justification à produire, zone h), `extension_in_public` ×2 (`unaccent`, `pg_net`), `anon_security_definer_function_executable` ×2 + `authenticated_…` ×2 (`page_reads`, `rpc_contract_check`), `auth_leaked_password_protection` ×1 (sans objet : magic‑link) ; 33 INFO `rls_enabled_no_policy` (deny‑all voulu). **Performance : 0 WARN**, 13 INFO (5 tables sans PK — snapshots et `math_*` ; 7 index jamais utilisés dont `crm_prospects_email_norm_idx`, `_tel_norm_idx`, `secib_dossiers_*` ; auth connections) | ⚠️ | `get_advisors` |
| Constantes docs : « 121 routines » (AGENTS.md:25,55 ; README.md:161,205 ; OPERATIONS.md:234,601 ; CLAUDE.md:325 ; HISTORY‑sprints.md:46 ; views.sql:11) vs CHANGELOG 31/08 « 121 → 122 » | Prod : 122 (dont 4 `unaccent`) | ❌ (6 fichiers à 121) | `grep` |
| Crons documentés (OPERATIONS.md:462‑480 : 12 jobs) | **9 jobs** en prod : `cooked-alerts-hourly`, `cooked-purge-noise-weekly`, `cooked-refresh-after-gsc`, `math-refresh-snapshots-weekly`, `purge_old_events_monthly`, `refresh_noise_filters_hourly`, `refresh_seo_url_snapshot`, `refresh-identity-stitch`, `run_rpc_contract_tests`. Listés dans la doc mais absents de prod : `refresh-dashboard-snapshots`, `refresh-dashboard-expertises`, `refresh-dashboard-assisted`, `cooked-cpi-daily-snapshot`, `dashboard-stale-check` | ❌ | Q‑04 |
| Issue GitHub #19 « ouverte » (ROADMAP.md #4, mission §5) | `gh issue list --state all` : **2 issues au total, toutes fermées** (#19 et #45 fermées le 30/08/2026). 0 issue ouverte | ❌ (ROADMAP périmée) | `gh` |
| Dépôt GitHub | `NicolasRewolf/cooked` : **visibilité PUBLIC**, branche par défaut `main` | ℹ️ | `gh repo view` |

---

## 2. Table §1 — indicateurs « avant »

### 2.1 Précision du tracking

| Indicateur | Valeur (fenêtre, date de mesure) | Req. |
|---|---|---|
| % sessions coupées (rotation aid/sid) | **0,04 %** (4 / 10 693 sessions recousues, 28 j au 02/09 01:26) — définition : nouveau `session_id` d'un même `visitor_key` moins de 30 min après sa pageview précédente. Même requête sur 13/06→11/07 (avant `sprint41`) : **5,53 %** (1 024 / 18 509) | Q‑13 |
| Proxy simple : sessions dont la 1re pageview a un referrer interne | 1,2 % (138 / 11 069, 28 j) vs 3,9 % (720 / 18 510) sur 13/06→11/07 | Q‑14 |
| % `cta_phone_click` avec amont visible | **100 %** : 128 / 128 clics (28 j) ont une pageview antérieure dans la même session (128/128 sur le même path) ; 103 sessions | Q‑15 |
| % paires (session×path) pageview avec `page_exit` apparié | **75,4 %** (9 308 / 12 348, 28 j) — desktop 60,3 % (3 156 / 5 237), mobile 86,5 % (6 119 / 7 070), tablette 80,5 % (33 / 41) | Q‑16 |
| Taux de doublons même‑seconde (session, path, seconde, clé discriminante) | pageview **0,421 %** (58 / 13 769) ; page_exit 0,578 % (87 / 15 055) ; engagement_tick 0,498 % (585 / 117 503) ; web_vitals 0,239 % (77 / 32 217, clé `metric`) ; scroll_depth 0,046 % (5 / 10 977, clé `percent`) ; click_internal, cta_booking_click, cta_phone_click **0** | Q‑17 |
| % events `clock_clamped` | **1 / 191 447** (0,0005 %, un `web_vitals`), 28 j | Q‑17b |
| Drops à l'ingestion par raison (`ingest_drops`, 28 j) | `bot_ua` : **3 607 927** events droppés (05/08→02/09) ; `missing_fields` / `disallowed_name` : **aucune ligne** | Q‑18 |
| Distribution `props->>'_v'` 7 j | `sprint41` 48 007 (99,96 %), `NULL` 18 (form_submit), `sprint30` 3 | Q‑05 |
| Chars du tracker minifié | **14 760 / 15 000** (98,4 %) — `python3 scripts/minify-tracker.py` sur `wix/tracker.html` (48 936 chars source), 02/09 01:19 | shell |
| aid 32‑hex (fallback serveur) dans `events_human` 28 j | **0,0 %** sur tous les events | Q‑19 |

### 2.2 Précision des analyses

| Indicateur | Valeur (fenêtre, date) | Req. |
|---|---|---|
| `attribution_method` (`form_submits_attributed(28)`) | **hidden_field 57** (54 macro + 3 hors‑macro), **temporal_unique 7**, **unresolved 6** → 70 forms, résolus 64/70 = **91,4 %**, hidden_field 81,4 % | Q‑20 |
| % `form_submit` avec `cooked_aid` (28 j) | **57 / 70 = 81,4 %** ; 22 forms issus du backfill du 23/08 (`capture_source='wix-backfill'`) dans la fenêtre ; 3 hors macro (recrutement) ; 6 avec `path` NULL | Q‑17b |
| Contacts macro avec canal / avec entrée connue (`conversion_journeys(28)`) | 195 contacts (128 phone + 67 form) ; `entry_channel` non NULL : **193 / 195 = 99,0 %** ; `entry_path` non NULL : **189 / 195 = 96,9 %** (6 forms `unresolved`). Canaux : paid 90, organic_google 56, gmb 17, direct 21, organic_ai 2, organic_other 1, referral 1, social 1, NULL 2 | Q‑20 |
| Écart macro site vs Σ par page (même fenêtre `paris_today()-28 → paris_today()`) | `site_macro_counts` = 195 (128 + 67) ; Σ `macro_contacts_by_path(dates)` = **195** (128 + 67, 90 paths dont `(non rattaché)` = 6 forms) → **écart 0**. `macro_contacts_by_path(28)` (overload `days_back`, fenêtre 28 j au lieu de 29) = 182 : les deux overloads n'ont pas la même fenêtre | Q‑20 |
| Écart entre implémentations « contacts assistés » | `dashboard_assisted_quarter()` et `refresh_dashboard_resources_assisted` appellent toutes deux `assisted_contacts_by_entry_path` (rpcs.sql:1789, :495) → une seule implémentation. **Mais `dashboard_assisted_quarter()` dépasse son `statement_timeout=30s`** (EXPLAIN ANALYZE 02/09 01:31 : « canceling statement due to statement timeout » dans `CREATE TEMP TABLE _pvk`, fenêtre T3 = 01/07→02/09) ; le dashboard masque alors la ligne objectif (`dashboard/src/app/page.tsx:61`) | Q‑21 |
| Filtre spam Baidu | `cooked_is_spam_referrer()` utilisé dans 8 corps RPC ; **3 copies littérales** `referrer_hostname IS DISTINCT FROM 'm.baidu.com'` subsistent (rpcs.sql:1765, :3779, :3985) | `grep` |
| `bounce_rate` : unités | non re‑mesuré en Phase 0 → zone d [non vérifié] | — |
| Restatements historiques sans ligne dans `annotations` | Table `annotations` : 7 lignes (02/07 refonte traumatisme‑crânien ; 12/07 restatement CPI conversion recousue ; 13/07 ×2 ; 23/08 backfill 22 forms ; 25/07 Baidu centralisé ; 27/07 restatement GMB). **Sans annotation** : restatement CPI **02/07** (grain lectures, ±7 pts — la ligne du 02/07 concerne un article, pas le CPI), `classify_channel` v2 IA du 02/07 (~35 % du canal `organic_ai`), enrichissement `page_taxonomy` du 31/08 (+5 ressources dans l'onglet Articles) | Q‑22 |

### 2.3 Qualité des données (28 j, `events_human`, 191 447 events)

| Indicateur | Valeur | Req. |
|---|---|---|
| NULL‑rate colonnes par event | `title` NULL : **pageview 98,9 %**, web_vitals 38,0 %, engagement_tick 0,4 %, page_exit 0,7 % ; `referrer` NULL : pageview 12,9 %, engagement_tick 8,7 %, page_exit 15,1 % ; `utm_source` NULL : pageview 81,5 %, cta_phone_click 49,2 % ; `browser` unknown/NULL : **pageview 16,0 %**, engagement_tick 17,9 %, **page_exit 2,1 %**, web_vitals 7,4 % ; `os` unknown/NULL : pageview 14,3 %, engagement_tick 16,6 %, page_exit 0,4 % ; `country` NULL : **100 % partout** ; `path`, `url`, `hostname`, `device_type`, `viewport` : 0 % (sauf form_submit : path/url/hostname 8,6 %, title/referrer/utm/browser/os/viewport 100 % — serveur) | Q‑23 |
| Clés de `props` par event (dérive de schéma) | Une seule version tracker dans la fenêtre → pas de dérive inter‑version mesurable. Clés : pageview {`_v`} ; page_exit {`_v`,`duration_seconds`,`max_scroll`} ; engagement_tick {`_v`,`active_ms`} ; scroll_depth {`_v`,`percent`} ; web_vitals {`_v`,`metric`,`value`} (+`clock_clamped` ×1) ; click_internal {`_v`,`anchor`,`href`,`placement`,`target_path`} ; click_outbound {`_v`,`anchor`,`href`,`hostname`} ; cta_anchor_click {`_v`,`anchor`,`placement`,`source`,`target_section`, `data_anchor` 56,2 %} ; cta_booking_click {`_v`,`anchor`,`href`,`placement`,`target_path`} ; cta_phone_click {`_v`,`anchor`,`phone`,`placement`} ; form_submit {`form_id`,`submission_id`,`page_source` (null JSON 8,6 %),`objet_de_ma_demande` (8,6 %),`counts_as_macro`,`cooked_aid` (18,6 %),`cooked_sid` (18,6 %),`capture_source`,`payload_meta`} — toutes présentes à 100 % sauf mention | Q‑24 |
| Part de bruit dans `events` brut | 7 j : 48 443 brut vs 48 026 human → **0,9 %** ; 28 j : 198 798 vs 191 459 → **3,7 %** (bots filtrés à l'ingestion depuis v26 ; purge hebdo > 28 j) | Q‑25 |
| Taille de `events` et rétention | `pg_total_relation_size` **1 410 MB** (heap 1 032 MB), 1 101 562 tuples vivants, 1 180 morts ; plus ancien event **06/05/2026** ; base **2 379 MB**. Politique : `purge_old_events` mensuel (> 400 j, 1er run utile ≈ 06/2027), `purge_cooked_noise(28)` hebdo (dernier run 30/08 06:30, 83,5 s). Autres tailles : `gsc_query_page_daily` 471 MB, `gsc_query_daily` 199 MB, `identity_stitch` **136 MB**, `gsc_path_daily` 68 MB, `noise_sessions` **63 MB** (401 901 lignes) | Q‑25, Q‑12 |
| Colonne `country` | Peuplée à 100 % du 06/05 au **02/06/2026 19:37**, puis **0 %** sans exception (0 / 3 578 pageviews la semaine du 17/08). Le code déployé de `track_row.ts` ne renseigne jamais `country` (`CookedEventRow.country?` optionnel, jamais assigné) | Q‑26, `get_edge_function` |

### 2.4 Fiabilité

| Indicateur | Valeur | Req. |
|---|---|---|
| Taux de succès par job pg_cron (30 j) | `cooked-alerts-hourly` 690/690 ; `refresh_noise_filters_hourly` 715/715 ; `cooked-refresh-after-gsc` 390/390 ; `refresh_seo_url_snapshot` 30/30 ; `run_rpc_contract_tests` 30/30 ; `refresh-identity-stitch` 30/30 ; `cooked-purge-noise-weekly` 4/4 ; `math-refresh-snapshots-weekly` 4/4 ; `purge_old_events_monthly` 1/1 → **100 %** | Q‑04 |
| Durées (30 j) | `cooked-refresh-after-gsc` : p50 0,1 s (ticks « skip »), **30 runs > 20 min**, **max 2 166 s le 05/08 11:00** pour un budget `statement_timeout=2400s` (90 %) ; 01/09 14:00 = 1 596 s. `refresh_seo_url_snapshot` p50 96 s (max 102,5 s / 600 s) ; `run_rpc_contract_tests` p50 77 s (max 95 s) ; `refresh-identity-stitch` p50 23 s ; `cooked-alerts-hourly` p50 9,9 s (max 40 s / 300 s) ; `refresh_noise_filters_hourly` p50 1,7 s | Q‑29 |
| Couverture d'alerte (règles `alert_rule_*` en prod : 11) | `cpi_drop`, `cron_failed` (dernier run de chaque job actif, 7 j), `double_embed_suspect`, `form_attribution_degraded`, **`freshness`** (registre `freshness_contract` : 13 sources, dont `secib_dossiers` désactivée ; kinds `<source>_stale` / `<source>_gap`), `gsc_ingest_missed`, `page_taxonomy_gap`, `pipeline_dead` (0 event reçu en 60 min), `rpc_health`, `tracker_drift`, `warn_escalation` (warn ≥ 5 j sans ack → critical). Sources du registre : cpi_daily, crm_prospects, cta_phone_click, dashboard_resources_snapshot, dfs_keyword_volume, form_submit, gbp_daily, gsc_path_daily (gap 90 j), gsc_query_daily, gsc_query_page_daily, math_visit_sequences_snapshot, secib_dossiers (off), seo_url_snapshot. **Non couverts par une règle nommée** : `identity_stitch` (pas de colonne de date), `conversion_weekly` (routine hors cron), `page_taxonomy` hors `/post/` | Q‑11, Q‑30 |
| Canal ntfy de bout en bout | `net._http_response` (TTL pg_net 6 h) : **1 réponse HTTP 200** à 01/09 20:15 Paris (= escalade `cpi_drop` critical de 18:15 UTC). Réception côté téléphone **[non vérifiable]**. `raise_cooked_alert` prod : dédup (kind, severity) 24 h, push seulement si le dernier épisode du kind n'est pas acquitté | Q‑31 |
| `latest_rpc_health()` à jour | oui (01/09 05:30 + 02/09 00:15) ; `rpc_health` : **0 ligne ≠ `ok`** en 30 j, 690 passages | Q‑03, Q‑32 |
| Statement timeouts 30 j | 0 échec cron ; 0 `rpc_health` failed ; alertes `refresh_step_failed_*` : 0 depuis le 28/07 ; **1 timeout constaté en Phase 0** : `dashboard_assisted_quarter()` (30 s) | Q‑04, Q‑21 |
| Workflows GitHub Actions rouges (30 j, `gh run list`) | **GBP Daily Ingest : 29 échecs / 33** (03/08→01/09, panne attendue depuis la migration GCP + reauth ADC avant) ; GSC Daily Ingest 1 échec / 31 (01/09 10:59, réussi 11:54 après le nouveau SA) ; SQL contracts 2 échecs / 11 (10/08 et 23/08, sur PR, corrigés dans la PR) ; DFS 5/5 ok ; Dashboard contracts 4/4 ; Edge shared helpers 2/2 ; `backup-weekly` : aucun run (schedule retiré le 13/07) | `gh` |

### 2.5 Hygiène

| Indicateur | Valeur | Req. |
|---|---|---|
| Parité `schema_migrations` vs `supabase/migrations/` | 212 prod / 162 local ; 108 versions communes ; 104 prod sans fichier au même timestamp ; 54 fichiers re‑datés ; **1 migration prod sans aucun miroir** (`20260807224552`) | Q‑08 |
| Sha `rpcs.sql` | fichier = méta ✅ ; **prod ≠ fichier** (2 diff, 6 manquantes, 6 en trop) | Q‑09 |
| `views.sql` vs prod | 11/11 noms ; formatage manuel ; 2 vues vérifiées sémantiquement, 9 [non vérifié] | Q‑10 |
| Advisors | 1 ERROR, 13 WARN (liste §1) | — |
| `has_function_privilege(anon/authenticated, EXECUTE)` sur SECURITY DEFINER | **2 fonctions = true** (`rpc_contract_check`, `page_reads(tstz,tstz)`) | Q‑11 |
| `proconfig IS NULL` sur `paris_date` / `paris_today` | ✅ NULL / NULL | Q‑11 |
| Constantes docs | 121 vs 122 (6 fichiers) ; 5 crons fantômes dans OPERATIONS.md ; `CLAUDE.md` et `OPERATIONS.md:482` disent encore « aucune alerte `gbp_gap` n'existe » (créée le 10/08, renommée `gbp_daily_stale` le 23/08) ; ROADMAP #4 « issue #19 ouverte » (fermée 30/08) ; `CLAUDE.md` = 1 112 lignes | `grep` |
| Inventaire d'usage des 118 routines Cooked (repo + cron + dashboard + appels inter‑RPC, hors docs) | **Sans aucun consommateur détecté : 3** — `conversions_leaderboard`, `cooked_weekly_conversions_snapshot`, `weekly_conversions_report` (routine hebdo hors repo, 705 lignes dans `conversion_weekly`, 17 semaines 04/05→24/08, dernier snapshot 31/08 09:23 Paris). **Consommées uniquement par les contract‑tests** : `behavior_pages_for_period`, `cta_breakdown_for_path`, `engagement_density_for_path`, `outbound_destinations_for_path`, `page_reads`, `site_context_export`, `snapshot_pages_export`. **Consommées uniquement par la doc / l'ad‑hoc (0 code, 0 cron)** : `gsc_top_queries_for_path` ×2, `site_kpis_compare`, `site_gsc_kpis_compare`, `site_pulse`, `site_seo_funnel`, `seo_to_contact_funnel`, `top_contact_pages`, `tracker_version_distribution`, `cooked_pages_snapshot`, `form_submits_per_path`, `dfs_keywords_to_sync` (scripts ✅). Table complète : annexe C (`routine_usage.md`) | script Python (annexe C) |

---

## Annexe A — requêtes (toutes en lecture seule, MCP `execute_sql`, projet `mxycmjkeotrycyneacje`)

Les requêtes sont reproduites telles qu'exécutées (l'horodatage Paris est
inclus dans la sortie quand il compte). `Q‑nn` renvoie aux tables ci‑dessus.

```sql
-- Q-01 alertes actives
SELECT to_char(now() AT TIME ZONE 'Europe/Paris','DD/MM/YYYY HH24:MI:SS') AS now_paris, a.* FROM alerts a WHERE NOT acked ORDER BY 1;

-- Q-02 réflexes fraîcheur
SELECT * FROM refresh_pipeline_health();
SELECT gsc_last_data_day(), (SELECT max(day) FROM gbp_daily), (SELECT max(last_synced_at) FROM dfs_keyword_volume), (SELECT max(day) FROM cpi_daily);

-- Q-03 santé RPC
SELECT * FROM latest_rpc_health() ORDER BY 1;

-- Q-04 crons 30 j
SELECT j.jobname, j.schedule, j.active, count(d.runid) AS runs_30j,
       count(*) FILTER (WHERE d.status='succeeded') AS ok, count(*) FILTER (WHERE d.status='failed') AS ko,
       to_char(max(d.start_time) AT TIME ZONE 'Europe/Paris','DD/MM HH24:MI') AS dernier_run,
       round(extract(epoch FROM max(d.end_time-d.start_time))::numeric,1) AS max_s, j.command
FROM cron.job j LEFT JOIN cron.job_run_details d ON d.jobid=j.jobid AND d.start_time > now() - interval '30 days'
GROUP BY j.jobid, j.jobname, j.schedule, j.active, j.command ORDER BY j.jobname;

-- Q-05 versions tracker 7 j / 24 h
SELECT props->>'_v' AS v, count(*) FILTER (WHERE occurred_at > now() - interval '24 hours') AS n_24h, count(*) AS n_7j,
       count(DISTINCT session_id) AS sessions_7j, count(*) FILTER (WHERE name='pageview') AS pv_7j
FROM events_human WHERE occurred_at > now() - interval '7 days' GROUP BY 1 ORDER BY 3 DESC;

-- Q-06 events sans _v / sprint30 (7 j)
SELECT name, count(*) FROM events_human WHERE occurred_at > now() - interval '7 days' AND props->>'_v' IS NULL GROUP BY 1;
SELECT name, path, count(*), max(occurred_at) FROM events_human WHERE occurred_at > now() - interval '7 days' AND props->>'_v'='sprint30' GROUP BY 1,2;

-- Q-07 Edge déployées : outils MCP list_edge_functions + get_edge_function('track' | 'form-webhook')

-- Q-08 migrations prod
SELECT count(*), string_agg(version, ' ' ORDER BY version) FROM supabase_migrations.schema_migrations;
--   puis : ls supabase/migrations | grep -oE '^[0-9]{14}' ; comm -23 / comm -13

-- Q-09 rpcs.sql vs prod (même DUMP_SQL que scripts/generate_rpcs_sql.py)
WITH d AS (SELECT coalesce(string_agg(format(E'-- ═══ public.%s(%s) ═══\n%s', p.proname,
  pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid)), E'\n\n'
  ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)), '') AS dump, count(*) AS n
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.prokind IN ('f','p'))
SELECT n, encode(sha256(convert_to(dump,'UTF8')),'hex') AS content_sha256,
  (SELECT string_agg(p.proname||'|'||pg_get_function_identity_arguments(p.oid)||'|'||md5(pg_get_functiondef(p.oid)), E'\n'
     ORDER BY p.proname, pg_get_function_identity_arguments(p.oid))
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind IN ('f','p')) AS per_fn
FROM d;
--   comparé localement au md5 de chaque section de supabase/rpcs.sql (script Python, journal 01:22)

-- Q-10 vues prod
SELECT c.relname, c.reloptions, md5(pg_get_viewdef(c.oid, true)), length(pg_get_viewdef(c.oid, true))
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='v' ORDER BY 1;
SELECT c.relname, pg_get_viewdef(c.oid, true) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN ('events_human','events_main','cpi_gisement');

-- Q-11 routines : sécurité, proconfig, privilèges, md5
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.prokind, p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       CASE WHEN p.prokind IN ('f','p') THEN md5(pg_get_functiondef(p.oid)) END AS def_md5, l.lanname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
WHERE n.nspname='public' ORDER BY 1,2;

-- Q-12 tables/vues : RLS, reloptions, grants anon/authenticated, taille
SELECT c.relkind, c.relname, c.relrowsecurity, c.reloptions,
       (SELECT string_agg(grantee||':'||privilege_type, ',') FROM information_schema.role_table_grants g
         WHERE g.table_schema='public' AND g.table_name=c.relname AND g.grantee IN ('anon','authenticated')),
       CASE WHEN c.relkind='r' THEN pg_size_pretty(pg_total_relation_size(c.oid)) END
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','v','m') ORDER BY 1,2;

-- Q-13 sessions coupées (visiteur recousu), deux fenêtres
WITH w AS (SELECT 'courant_28j' AS fenetre, now() - interval '28 days' AS d0, now() AS d1
           UNION ALL SELECT 'avant_sprint41_13/06-11/07', '2026-06-13'::timestamptz, '2026-07-11 23:59:59+02'::timestamptz),
pv AS (SELECT w.fenetre, s.visitor_key, e.session_id, e.occurred_at
       FROM w JOIN events_human e ON e.name='pageview' AND e.occurred_at >= w.d0 AND e.occurred_at < w.d1
       JOIN identity_stitch s ON s.kind='sid' AND s.key=e.session_id),
seq AS (SELECT fenetre, visitor_key, session_id, occurred_at,
        lag(session_id) OVER (PARTITION BY fenetre, visitor_key ORDER BY occurred_at) AS prev_sid,
        lag(occurred_at) OVER (PARTITION BY fenetre, visitor_key ORDER BY occurred_at) AS prev_t FROM pv)
SELECT fenetre, count(DISTINCT session_id) AS sessions_stitchees,
       count(DISTINCT session_id) FILTER (WHERE prev_sid IS NOT NULL AND prev_sid <> session_id AND occurred_at - prev_t < interval '30 minutes') AS sessions_coupees
FROM seq GROUP BY 1;

-- Q-14 proxy referrer interne en 1re pageview (mêmes fenêtres que Q-13)
WITH w AS (...), pv AS (SELECT w.fenetre, e.session_id, e.referrer_hostname,
   row_number() OVER (PARTITION BY w.fenetre, e.session_id ORDER BY e.occurred_at) AS rn
   FROM w JOIN events_human e ON e.name='pageview' AND e.occurred_at >= w.d0 AND e.occurred_at < w.d1)
SELECT fenetre, count(*), count(*) FILTER (WHERE referrer_hostname IN ('www.jplouton-avocat.fr','jplouton-avocat.fr')) FROM pv WHERE rn=1 GROUP BY 1;

-- Q-15 amont des cta_phone_click (28 j)
WITH ph AS (SELECT id, session_id, occurred_at, path FROM events_human WHERE name='cta_phone_click' AND occurred_at >= now() - interval '28 days')
SELECT count(*), count(*) FILTER (WHERE EXISTS (SELECT 1 FROM events_human p WHERE p.name='pageview' AND p.session_id=ph.session_id AND p.occurred_at <= ph.occurred_at)),
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM events_human p WHERE p.name='pageview' AND p.session_id=ph.session_id AND p.path=ph.path AND p.occurred_at <= ph.occurred_at)),
       count(DISTINCT session_id) FROM ph;

-- Q-16 page_exit apparié par device (28 j)
WITH pv AS (SELECT session_id, path, min(device_type) AS device_type FROM events_human WHERE name='pageview' AND occurred_at >= now() - interval '28 days' GROUP BY 1,2),
px AS (SELECT DISTINCT session_id, path FROM events_human WHERE name='page_exit' AND occurred_at >= now() - interval '28 days')
SELECT coalesce(pv.device_type,'(total)'), count(*), count(px.session_id) FROM pv LEFT JOIN px USING (session_id, path) GROUP BY ROLLUP(pv.device_type);

-- Q-17 doublons même-seconde affinés (28 j)
SELECT name, count(*), count(*) - count(DISTINCT (session_id, path, date_trunc('second', occurred_at),
  CASE name WHEN 'web_vitals' THEN props->>'metric' WHEN 'scroll_depth' THEN props->>'percent' WHEN 'click_internal' THEN props->>'target_path' ELSE '' END)) AS doublons
FROM events_human WHERE occurred_at >= now() - interval '28 days'
  AND name IN ('pageview','page_exit','web_vitals','scroll_depth','engagement_tick','cta_phone_click','cta_booking_click','click_internal') GROUP BY 1;

-- Q-17b clock_clamped, forms (28 j)
SELECT name, count(*), count(*) FILTER (WHERE (props->>'clock_clamped')::boolean),
  count(*) FILTER (WHERE name='form_submit' AND props->>'cooked_aid' IS NOT NULL),
  count(*) FILTER (WHERE name='form_submit' AND props->>'capture_source'='wix-backfill'),
  count(*) FILTER (WHERE name='form_submit' AND NOT form_submit_counts_as_macro(props))
FROM events_human WHERE occurred_at >= now() - interval '28 days' GROUP BY ROLLUP(name);

-- Q-18 drops ingestion
SELECT reason, sum(n), min(day), max(day) FROM ingest_drops WHERE day > current_date - 28 GROUP BY reason;

-- Q-19 / Q-23 NULL-rate par event × colonne (28 j) — colonnes path,url,title,referrer,referrer_hostname,utm_source,device_type,browser,os,viewport_width,country,hostname,props ; aid ~ '^[0-9a-f]{32}$'
SELECT name, count(*), round(100.0*count(*) FILTER (WHERE title IS NULL)/count(*),1) AS null_title, /* … idem par colonne … */
       round(100.0*count(*) FILTER (WHERE anonymous_id ~ '^[0-9a-f]{32}$')/count(*),1) AS aid_32hex
FROM events_human WHERE occurred_at >= now() - interval '28 days' GROUP BY name ORDER BY 2 DESC;

-- Q-20 attribution, journeys, équivalences macro
SELECT attribution_method, counts_as_macro, count(*) FROM form_submits_attributed(28) GROUP BY 1,2;
SELECT contact_kind, entry_channel, entry_path IS NULL, attribution_method, count(*) FROM conversion_journeys(28) GROUP BY 1,2,3,4;
SELECT * FROM site_macro_counts(paris_today()-28, paris_today());
SELECT sum(phone_clicks), sum(form_submits), sum(contacts), sum(booking_intent), count(*) FROM macro_contacts_by_path(paris_today()-28, paris_today());
SELECT sum(phone_clicks), sum(form_submits), sum(contacts), sum(booking_intent), count(*) FROM macro_contacts_by_path(28);
SELECT count(*) FILTER (WHERE name='cta_phone_click'), count(*) FILTER (WHERE name='form_submit' AND form_submit_counts_as_macro(props)),
       count(*) FILTER (WHERE name='form_submit' AND form_submit_counts_as_macro(props) AND path IS NULL)
FROM events_human WHERE occurred_at >= now() - interval '28 days' AND name IN ('cta_phone_click','form_submit');

-- Q-21 dashboard_assisted_quarter (timeout observé)
EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON) SELECT public.dashboard_assisted_quarter();
--   → ERROR 57014 canceling statement due to statement timeout (CREATE TEMP TABLE _pvk … assisted_contacts_by_entry_path(q_start, q_end))

-- Q-22 annotations
SELECT day, kind, label, paths FROM annotations ORDER BY day;

-- Q-24 clés de props par event (28 j)
WITH base AS (SELECT name, props FROM events_human WHERE occurred_at >= now() - interval '28 days'), tot AS (SELECT name, count(*) AS n FROM base GROUP BY name)
SELECT b.name, k, count(*), round(100.0*count(*)/t.n,1), round(100.0*count(*) FILTER (WHERE jsonb_typeof(b.props->k)='null')/t.n,1)
FROM base b CROSS JOIN LATERAL jsonb_object_keys(b.props) k JOIN tot t USING (name) GROUP BY b.name, k, t.n ORDER BY 1, 3 DESC;

-- Q-25 taille / bruit / rétention
SELECT pg_size_pretty(pg_total_relation_size('public.events')), pg_size_pretty(pg_relation_size('public.events')),
  (SELECT n_live_tup FROM pg_stat_user_tables WHERE relname='events'), (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname='events'),
  (SELECT min(occurred_at) FROM events),
  (SELECT count(*) FROM events WHERE occurred_at > now() - interval '7 days'), (SELECT count(*) FROM events_human WHERE occurred_at > now() - interval '7 days'),
  (SELECT count(*) FROM events WHERE occurred_at > now() - interval '28 days'), (SELECT count(*) FROM events_human WHERE occurred_at > now() - interval '28 days'),
  pg_size_pretty(pg_database_size(current_database()));

-- Q-26 colonne country (events brut — diagnostic d'ingestion)
SELECT date_trunc('week', occurred_at AT TIME ZONE 'Europe/Paris')::date, count(*), count(country),
       max(occurred_at) FILTER (WHERE country IS NOT NULL)
FROM events WHERE name='pageview' AND occurred_at > '2026-05-04' GROUP BY 1 ORDER BY 1;

-- Q-27 fenêtres 60 min sans event aux ticks hh:15 (events brut — diagnostic)
WITH ticks AS (SELECT generate_series(date_trunc('hour', now() - interval '30 days') + interval '15 min', now(), interval '1 hour') AS t)
SELECT count(*), count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM events e WHERE e.received_at > t - interval '60 minutes' AND e.received_at <= t)) FROM ticks;
SELECT count(*) FROM events WHERE received_at > '2026-08-22 01:15:00+00' AND received_at <= '2026-08-22 02:15:00+00';  -- 0

-- Q-28 ACL brutes
SELECT proname, proacl FROM pg_proc WHERE proname IN ('rpc_contract_check','page_reads');

-- Q-29 durées crons (30 j)
SELECT j.jobname, count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM d.end_time-d.start_time)),
       max(extract(epoch FROM d.end_time-d.start_time)), count(*) FILTER (WHERE d.end_time-d.start_time > interval '20 minutes')
FROM cron.job j JOIN cron.job_run_details d ON d.jobid=j.jobid AND d.start_time > now() - interval '30 days' GROUP BY 1;

-- Q-30 registre de fraîcheur
SELECT source, label, cadence, normal_lag_days, warn_after_days, critical_after_days, gap_relation, gap_window_days, enabled, last_point_sql FROM freshness_contract ORDER BY 1;

-- Q-31 alertes par kind + réponses pg_net
SELECT kind, severity, acked, count(*), min(created_at), max(created_at) FROM alerts GROUP BY 1,2,3;
SELECT status_code, count(*), min(created), max(created) FROM net._http_response GROUP BY 1;

-- Q-32 rpc_health 30 j
SELECT rpc_name, count(*) FROM rpc_health WHERE checked_at > now() - interval '30 days' AND status <> 'ok' GROUP BY 1;

-- Q-33 identity_stitch : composantes
WITH comp AS (SELECT visitor_key, count(*) FILTER (WHERE kind='sid') AS n_sid, count(*) FILTER (WHERE kind='aid') AS n_aid FROM identity_stitch GROUP BY 1)
SELECT count(*), count(*) FILTER (WHERE n_aid > 1), count(*) FILTER (WHERE n_aid > 2), max(n_aid), max(n_sid),
       percentile_cont(0.99) WITHIN GROUP (ORDER BY n_sid), count(*) FILTER (WHERE n_sid >= 20),
       (SELECT count(*) FROM identity_stitch WHERE kind='aid' AND key ~ '^[0-9a-f]{32}$') FROM comp;
--   → 51 372 composantes ; 1 589 avec > 1 aid (16 avec > 2, max 4) ; max 109 sid ; p99 = 4 sid ; 18 composantes ≥ 20 sid ; 0 aid 32-hex

-- Q-34 trous de séries
--   cpi_daily (90 j) : 03→09/06 (avant la naissance du 10/06), 22→28/06, 20/07, 21/07, 24/07 ; aucun depuis le 25/07 ; 26/08→01/09 : 164→177 pages/jour
--   gsc_path_daily (120 j) : 0 jour manquant ; gbp_daily (60 j jusqu'au 20/08) : 0
```

## Annexe B — tests PostgREST (clé `anon` legacy ; 02/09/2026 01:29 Paris)

```bash
U=https://mxycmjkeotrycyneacje.supabase.co ; K=<clé anon legacy, obtenue via get_publishable_keys>
curl -s -H "apikey: $K" -H "Authorization: Bearer $K" "$U/rest/v1/cpi_capture_perdue?select=path,grade&limit=1"
#  → [{"path":"/","grade":"A"}]  http=200
curl -s -H "apikey: $K" -H "Authorization: Bearer $K" -H "Range: 0-0" \
  "$U/rest/v1/rpc/page_reads?p_from=2026-09-01T10:00:00Z&p_to=2026-09-01T11:00:00Z&select=path,dwell_s,retained"
#  → [{"path":"/indemnisation-des-victimes/droit-et-accidents-du-travail","dwell_s":136,"retained":true}]  http=200
curl … "$U/rest/v1/cpi_daily?select=day&limit=1"        #  → []  http=200   (RLS deny-all)
curl … "$U/rest/v1/crm_prospects?select=id&limit=1"     #  → 42501 permission denied  http=401
# rpc_contract_check : volontairement NON appelé (écrit dans rpc_health).
```

## Annexe C — inventaire d'usage des routines

Script Python (journal 01:27) : pour chacune des 122 routines prod, compte
les références `name(` ou `'name'` dans `dashboard/src`, `scripts/` + `tests/`,
`.github/workflows`, `supabase/functions`, les commandes `cron.job`, les
corps des autres RPC (`supabase/rpcs.sql`) et `views.sql` ; les `alert_rule_*`
sont découvertes dynamiquement par `cooked_alerts_refresh()` (`pg_proc LIKE
'alert\_rule\_%'`). Fichier complet : `docs/mission-2026-09-02/annexes/routine_usage.md`.
