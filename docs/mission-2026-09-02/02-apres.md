# 02 — Photo « après » — mission Cooked 02/09/2026

> Mêmes requêtes que `00-baseline.md` (annexe A, `Q‑nn`), rejouées le
> **04/09/2026 entre 08:44 et 09:20 (Paris)** en lecture seule (MCP Supabase
> `execute_sql`, `gh`, repo local sur la branche `claude/t20-restatements-cpi-version`
> = `main` + T-20). Une ligne par indicateur : avant (02/09 01:12–01:32), après,
> et **une explication par ligne qui bouge** — un chiffre qui change sans cause
> nommée est un chiffre à instruire, pas un progrès.
>
> Conventions identiques : dates JJ/MM/AAAA, heures Paris, « 28 j » =
> `occurred_at >= now() - interval '28 days'` au moment de la mesure sauf
> mention. Les fenêtres « closes » (T-05 / T-09) sont indiquées quand la RPC a
> changé de définition entre les deux photos.

---

## 0. Réflexes de démarrage

| Réflexe | Avant (02/09) | Après (04/09 08:48) | Explication |
|---|---|---|---|
| `alerts WHERE NOT acked` | **48** (cpi_drop 31, gbp 13, gsc_ingest_missed 3, pipeline_dead 1) | **2** : `form_fields_missing` warn (04/09 — attendu, T-18 : champs cachés absents de formulaires Wix, action Nicolas), `gbp_daily_stale` critical (série GBP arrêtée au 20/08, verdict Google ~10-15/09) | T-07 (alertes v4, stock acquitté, `cpi_drop` recalibré, `warn_escalation` hors kinds éditoriaux). Un **faux positif `gsc_ingest_missed`** (03/09 22:15 UTC) a été trouvé ce matin : bug de ma règle T-11 (jour Paris vs garde UTC), corrigé `20260904064833` et acquitté |
| `refresh_pipeline_health()` | healthy, GSC 29/08 (J‑4), snapshot 01/09 05:00 | healthy, `issues=[]`, snapshot 04/09 05:00 (âge 3,8 h), 142 events/60 min, GSC **31/08** (J‑4 au 04/09), dernière ingestion 03/09 12:35, DFS 814 lignes (31/08 16:29) | inchangé (lag GSC J‑4 normal ; l'ingestion du 04/09 part à ~10:30 UTC — dérive GitHub connue) |
| `gsc_last_data_day()` | 29/08 | 31/08 | 2 jours ingérés (02/09, 03/09) |
| `latest_rpc_health()` | 12 RPC, 12 ok | **51 tests, 51 ok**, dernier passage 04/09 08:46 (règle horaire) ; plus lents : `units_cooked_bounce_rate_range` 58,2 s, `units_cooked_bounce_rate_unit` 20,2 s, `tracker_first_seen_global` 20,0 s | +39 contract‑tests (I4 T-09, I5 T-03 `units_*`, I9 T-11, I12 T-16, dashboard T-13). Les deux tests `units_*` à 20-58 s scannent `events_human` sur 28 j : budget nocturne 131 s max (Q‑29), pas de timeout |
| `cron.job_run_details` 30 j | 9 jobs, 1 894 runs, 0 échec | **10 jobs, 1 509 runs, 0 échec** (Q‑04) | +`cpi-calibration-monthly` (T-20, 0 run avant le 01/10). `cooked-refresh-after-gsc` : 8 runs depuis sa re‑planification du 03/09 (T-11, nouveau `jobid` → l'historique de l'ancien job n'est plus joint), plus 382 ticks « skip » comptés avant |

## 1. Ce que le repo prétend, confronté à la prod

| Affirmation | Avant | Après | Explication |
|---|---|---|---|
| Tracker déployé | `sprint41` 99,96 % | `sprint41` **42 671 events / 7 j (99,96 %)**, 2 668 sessions ; `NULL` 17 = 17 `form_submit` ; `sprint30` disparu ; 24 h : 6 623 events 100 % sprint41 | `sprint42` (T-17) est sur `main` mais **pas collé dans Wix** (Nicolas) ; `cooked_config.expected_tracker_version = sprint41`, donc pas de `tracker_drift` — à basculer le jour du collage |
| Edge `track` / `form-webhook` | v27 (35) / v13 (19) | **v30** (Supabase 40) / **v15** (22), en‑têtes = repo, sondes 405/401 relues le 04/09 00:35 | T-04 (v28), T-18 (v29 / v15), T-19 (v30) ; v14 (T-07) |
| `supabase/migrations/` = miroir prod | 212 prod / 162 local ; 104 sans fichier ; 54 re‑datés ; **1 sans aucun miroir** (`20260807224552`) | **258 prod / 209 local / 162 communes ; 96 prod sans fichier au même timestamp ; 47 fichiers re‑datés** ; `20260807224552` a son fichier ; **0 version ≥ 02/09/2026 sans miroir** (46 migrations de la mission, toutes au timestamp prod) | Gate `schema-migrations-local` + prod‑drift (T-12). Le stock mai–juillet re‑daté reste tel quel (décision T-14 : on ne réécrit pas l'historique, la CI ne juge que le présent) |
| `supabase/rpcs.sql` = corps prod | fichier ≠ prod (2 diff, 6 manquantes, 6 en trop), édité à la main | **sha256 prod `250f6ed7…` = `contracts/rpc_snapshot_meta.json`** ; 138 routines `pg_proc` (134 Cooked + 4 `unaccent`) | régénéré depuis la prod par le workflow `rpcs-regenerate` à chaque PR touchant une RPC ; gate `rpcs-sql-fresh` |
| `supabase/views.sql` = 11 vues prod | 11/11 noms, formatage manuel, 2 vérifiées | 11/11 noms ; retouché à la main au T-19 (`country`) ; **parité sémantique toujours [non vérifiée] automatiquement** | reste ouvert (zone i) — pas dans le périmètre des tickets |
| `paris_date` / `paris_today` `proconfig IS NULL` | ✅ | ✅ NULL / NULL | contrat d'inlining préservé (C6 + prod‑drift) |
| SECURITY.md « REVOKE sur toute RPC » | 2 SECURITY DEFINER exécutables par `anon` + `authenticated` ; 17 INVOKER par `anon` | **0 / 0** SECURITY DEFINER exposées ; 18 INVOKER exécutables par `anon` (helpers purs + `cooked_page_index` / `cooked_cpi_snapshot`, sans grant sur les tables donc inertes) ; `alert_rule_exposure()` = 0 ; default privileges **fonctions** déjà restreints (T-01) ; **tables/séquences : 22 tables gardaient ALL pour `anon`/`authenticated` (dont TRUNCATE sur `events`, hors RLS) → révoqué le 04/09 (`20260904073237`) + default privileges tables/séquences/fonctions révoqués** | T-01 (25/07 ⇒ 02/09) + T-01 ter (04/09, trouvé par cette re‑mesure, Q‑12) |
| Vues `security_invoker` | absent sur 3 vues ; `cpi_capture_perdue` lisible par `anon` | **11 / 11** `security_invoker=true` (la dernière, `cpi_opportunite_contact`, posée le 04/09) ; **0 GRANT `anon`/`authenticated`** sur toute relation de `public` | T-01, T-19 (5 vues `events_*` recréées), T-01 ter |
| Exposition PostgREST réelle | `cpi_capture_perdue` 200 / `page_reads` 200 | non rejoué (la clé `anon` legacy est à désactiver — **T-02, décision Nicolas**) ; par construction : 0 grant, 0 fonction DEFINER exposée, `page_reads` supprimée (T-19) | à rejouer après T-02 |
| Advisors Supabase | Security **1 ERROR** + 13 WARN ; Perf 0 WARN / 13 INFO | Security **0 ERROR**, **12 WARN** : `function_search_path_mutable` ×8 (6 justifiées zone h + `paris_date`/`paris_today` voulus ; `page_taxonomy_theme_from_slug` créée sans `search_path` au T-15 → corrigée 04/09), `extension_in_public` ×2, `auth_leaked_password_protection` ×1 (sans objet) ; les 4 `*_security_definer_function_executable` ont disparu ; INFO `rls_enabled_no_policy` 36 (deny‑all voulu). Perf : 0 WARN, INFO : 6 tables sans PK (+`cpi_pre_restatement_20260903`, à supprimer après J+1), 5 index inutilisés (les 2 de `crm_prospects` sont désormais utilisés — T-16) | T-01, T-15/T-01 ter, T-16 |
| Constantes docs | 121 vs 122 (6 fichiers) ; 12 crons documentés vs 9 ; ROADMAP périmée | `contracts/doc_constants.json` = prod (138 routines, 19 règles, 15 sources, 10 crons, versions) ; gate I13 verte ; ROADMAP à jour (T-14, T-20) | T-14 |
| Issues GitHub | 0 ouverte (ROADMAP disait #19 ouverte) | 9 ouvertes : #103 (T-02, Nicolas) + 8 tickets `ready-for-agent` livrés à fermer à la clôture (#111, #114→#121) | mission |
| Dépôt | public | public, `main` | ℹ️ |

---

## 2. Table §1 — indicateurs « après »

### 2.1 Précision du tracking

| Indicateur | Avant | Après (04/09) | Explication |
|---|---|---|---|
| % sessions coupées (rotation aid/sid) | **0,04 %** (4 / 10 693, 28 j) | **0,04 %** (4 / 9 248 sessions recousues, 28 j) | stable — le correctif `sprint41` du 12/07 tient ; le dénominateur baisse de 13,5 % parce que T-04 a sorti le bot Baidu (`pc`) d'`events_human` |
| Proxy referrer interne en 1re pageview | 1,2 % (138 / 11 069) | 1,5 % (136 / 9 281) | même numérateur, dénominateur épuré (T-04) |
| % `cta_phone_click` avec amont visible | **100 %** (128 / 128) | **100 %** (128 / 128, 103 sessions) | = |
| % paires session×path avec `page_exit` | **75,4 %** — desktop **60,3 %**, mobile 86,5 %, tablette 80,5 % | **89,1 %** (9 439 / 10 597) — desktop **94,6 %** (3 166 / 3 346), mobile 86,5 % (6 233 / 7 204), tablette 85,1 % | **T-04** : le bot Baidu (UA littéral « pc », 13,8 % des pageviews, desktop, jamais de `page_exit`) est sorti d'`events_human` — le « trou desktop » du baseline était lui. Mobile inchangé = preuve que rien d'autre n'a bougé |
| Doublons même‑seconde (28 j) | pageview 0,421 %, page_exit 0,578 %, tick 0,498 %, vitals 0,239 %, scroll 0,046 %, clics 0 | pageview 0,473 % (57 / 12 063), page_exit 0,570 %, tick 0,343 %, vitals 0,247 %, scroll 0,045 %, clics **0** | même ordre de grandeur (artefact double‑embed résiduel documenté S39) ; aucun ticket ne visait ce point |
| % events `clock_clamped` | 1 / 191 447 | 1 / 170 220 (le même `web_vitals`) | = |
| Drops à l'ingestion (28 j) | `bot_ua` 3 607 927 | `bot_ua` **3 826 131** (08/08 → 04/09) ; `missing_fields` / `disallowed_name` : aucune ligne | T-19 : les drops sont désormais **agrégés côté Edge** (v30 : 1 appel / 100 drops ou / minute) — même compte, 100× moins d'appels RPC |
| Distribution `_v` 7 j | sprint41 99,96 % | sprint41 99,96 % ; NULL 17 (forms) | sprint42 pas encore collé (Nicolas) |
| Chars du tracker minifié | 14 760 / 15 000 | **14 820** / 15 000 (script), 14 824 octets fichier | T-17 (CLS explicite +60 chars) ; cliquet CI : aucun ajout net au‑dessus de 14 500 sans le loader |
| aid 32‑hex dans `events_human` 28 j | 0,0 % | 0,0 % | = |

### 2.2 Précision des analyses

| Indicateur | Avant | Après (04/09) | Explication |
|---|---|---|---|
| `attribution_method` (`form_submits_attributed(28)`) | hidden_field 57, temporal 7, unresolved 6 → 64/70 = 91,4 % ; fenêtre `now()-28 j` | hidden_field **56** (53 macro + 3 hors‑macro), temporal_unique **7**, unresolved **5** → **63/68 = 92,6 %**, hidden_field 82,4 % ; **fenêtre close 07/08 → 03/09** (`window_start`/`window_end` en sortie) | T-09 : la RPC lit 28 jours Paris clos à J‑1 (plus `now()`), d'où 68 forms au lieu de 70 (2 forms du 04/09 matin et du 07/08 avant 00:00 sortent) |
| % `form_submit` avec `cooked_aid` | 57 / 70 = 81,4 % | 56 / 68 = 82,4 % ; 22 du backfill ; 3 hors macro ; 6 sans `path` ni `page_source` | = (les 6 sans `page_source` alimentent `form_fields_missing`, T-18) |
| Contacts macro avec canal / entrée | 195 ; canal 193/195 = 99,0 % ; entrée 189/195 = 96,9 % ; paid 90, organic_google 56, gmb 17, direct 21, organic_ai 2, other 1, referral 1, social 1, NULL 2 | **193** (128 phone + 65 form), fenêtre 07/08 → 03/09 ; canal **191/193 = 99,0 %** ; entrée **188/193 = 97,4 %** ; **paid 98**, organic_google 56, gmb 17, **direct 15**, organic_ai 2, other 1, referral 1, social 1, NULL 2 | T-09 : `classify_channel` v5 — un `gclid`/`gbraid`/`wbraid` dans `url` ⇒ `paid` (avant : `direct`) : paid 90 → 98 et direct 21 → 15, gmb inchangé (17) ; le solde (−2) et 195 → 193 = fenêtre close à J‑1 (T-09), plus `now()` |
| Écart macro site vs Σ par page | `site_macro_counts` 195 = Σ `macro_contacts_by_path(dates)` 195 ; **`macro_contacts_by_path(28)` = 182** (fenêtre 28 j au lieu de 29) | `site_macro_counts` **193** = Σ `macro_contacts_by_path(dates)` **193** (87 paths, 1 `(non rattaché)`) = **`macro_contacts_by_path(28)` 193** = `conversion_journeys(28)` 193 = Σ `assisted_contacts_by_entry_path` **193** (dont **12 `(non attribuable)`**) | **I4** (T-08/T-09) : une seule fenêtre pour tous les compteurs de contacts — contract‑tests `contacts_28j_une_fenetre`, `assisted_sum_equals_site` verts |
| Écart entre implémentations « assistés » | une seule implémentation, mais **`dashboard_assisted_quarter()` en timeout 30 s** | `dashboard_assisted_quarter()` répond en < 1 s : `{value: 94, target: null, quarter: T3 2026}` — lit un **snapshot nocturne** (5ᵉ étape de `cooked_refresh_after_gsc`, 226 s le 03/09) ; `target = null` = pas d'objectif trimestriel (décision Nicolas 03/09) | T-08 |
| Funnel SEO → contacts | (non mesuré au baseline) | `seo_to_contact_funnel(28)` : 315 landings, 5 380 clics GSC, 5 852 entrées organiques recousues, **60 contacts**, fenêtre **04/08 → 31/08** (close à `gsc_last_data_day()`) ; Σ = `conversion_journeys` organiques sur la même fenêtre (contract‑test `funnel_meme_total_que_journeys` ok le 04/09 05:30) | T-09. Ne pas comparer aux 193 : autre fenêtre (recul de 3 jours GSC), autre canal |
| Filtre spam Baidu | 3 copies littérales dans les corps RPC | 5 occurrences de `m.baidu.com` dans `rpcs.sql` : 1 dans `cooked_is_spam_referrer` (source), 1 dans un contract‑test, **3 copies littérales subsistent** (`rpcs.sql:2426`, `:4640`, `:4846`) | **non traité** — hors tickets (constat de zone i, pas de défaut de chiffre : la fonction et les copies filtrent la même chaîne) → ROADMAP |
| `bounce_rate` : unités | [non vérifié] → défaut d‑01 (×100 pendant 38 j) | `behavior_pages_for_period` en 0‑100 (T-03, restatement annoté) ; 4 contract‑tests `units_*` verts (I5) | T-03 |
| Restatements sans annotation | 7 annotations ; 02/07 CPI, `classify_channel` v2, 31/08 taxonomie sans ligne | **16 annotations** : 02/07 (CPI grain lectures + v2), 25/07 (momentum requêtes révélées + `convertit`), 31/08 (taxonomie), 03/09 ×6 (T-03→T-09) posées ; `cpi_daily.cpi_version` 2.2.0 → 2.2.5 (0 NULL) | T-20 (I10) |

### 2.3 Qualité des données (28 j, `events_human`, 170 220 events — 191 447 avant)

| Indicateur | Avant | Après (04/09) | Explication |
|---|---|---|---|
| NULL‑rate | `title` pageview 98,9 % ; `browser` unknown **pageview 16,0 %**, tick 17,9 % ; `os` unknown pageview 14,3 % ; `country` 100 % NULL ; `referrer` pageview 12,9 % ; `utm_source` pageview 81,5 % | `title` pageview **99,0 %** (et **100 %** depuis `track` v30 le 04/09 00:35 : 72 pageviews, 137 vitals, 67 exits) ; `browser` unknown **pageview 2,2 %**, tick 1,7 % ; `os` unknown pageview **0,2 %** ; **`country` : colonne supprimée** ; `referrer` pageview 14,7 % ; `utm_source` pageview 77,5 % ; `url` avec `?` : pageview 32,2 % sur 28 j, **43,1 % depuis v30 et 100 % de ces query strings ne contiennent que des paramètres de campagne/attribution** (`utm_*`, `gclid`, `cooked_aid/sid`) | `browser`/`os` unknown = le bot Baidu (UA « pc ») : T-04 le sort. `title` : T-19 (v30 n'écrit plus). `country` : T-19. `url` : T-19 (liste blanche) |
| Clés de `props` par event | stables | stables : mêmes ensembles ; `cta_anchor_click.data_anchor` 55,1 % ; `form_submit` : `cooked_aid`/`cooked_sid` null 17,6 %, `page_source`/`objet` null 8,8 % ; `web_vitals.clock_clamped` 1 event | = |
| Part de bruit dans `events` brut | 7 j 0,9 % ; 28 j 3,7 % | 7 j **11,1 %** (48 008 vs 42 688) ; 28 j **15,1 %** (200 507 vs 170 220) | **attendu et documenté** (CLAUDE.md) : T-04 classe rétroactivement le bot Baidu en `noise_sessions` (miroir SQL) ; la purge hebdomadaire du **dimanche 06/09 06:30** (validée par Nicolas) évacue ce stock. Un chiffre lu sur `events` brut d'ici là est faux de 15 % — d'où la règle « toujours `events_human` » |
| Taille `events` / rétention | 1 410 MB (heap 1 032), 1 101 562 vivants ; base 2 379 MB ; `identity_stitch` **136 MB** ; `gsc_query_page_daily` 471 MB | 1 414 MB (heap 1 032), 1 117 945 vivants, 1 180 morts, plus ancien 06/05 ; base **2 297 MB** ; `identity_stitch` **44 MB** (index 124 → 10 MB) ; `gsc_query_page_daily` 472 MB ; `noise_sessions` 63 MB ; `cpi_daily` 7,7 MB ; `ingest_drops` 120 kB | T-19 (REINDEX CONCURRENTLY, autovacuum GSC resserré). Politique de rétention inchangée : 400 j (**CNIL 13 mois à confirmer par Nicolas**) |
| Colonne `country` | 0 % depuis le 02/06, jamais renseignée par le code | **supprimée** (`20260903220532`, 5 vues recréées) | T-19, décision Nicolas (#120) |

### 2.4 Fiabilité

| Indicateur | Avant | Après (04/09) | Explication |
|---|---|---|---|
| Succès par job pg_cron (30 j) | 9 jobs, 100 % | **10 jobs, 100 %** : alerts 689/689, noise 713/713, contract‑tests 30/30, seo snapshot 30/30, identity 30/30, refresh‑after‑gsc 8/8 (depuis le 03/09), purge noise 4/4, math 4/4, purge events 1/1, calibration 0 (1er run le 01/10) | T-11 (re‑planification), T-20 |
| Durées (30 j) | refresh‑after‑gsc max 2 166 s / 2 400 ; seo snapshot p50 96 s ; contract‑tests p50 77 s (12 tests) | refresh‑after‑gsc **max 1 619,8 s** (03/09 17:00, 5 étapes tracées dans `refresh_runs`, budget 2 400 s, alerte `refresh_budget` à 80 %) ; seo snapshot p50 95,9 s (max 102,5) ; contract‑tests **p50 62,6 s, max 131,5 s** (51 tests) ; identity 22,9 s ; alerts p50 10,0 s (max 40,2) ; noise 1,7 s | T-11 (durées mesurées par étape), T-03/T-09/T-13/T-16 (+39 tests dans le même budget) |
| Couverture d'alerte | 11 règles ; registre 13 sources ; non couverts : `identity_stitch`, `page_taxonomy` hors `/post/` | **19 règles** `alert_rule_*` : contact_sans_amont, **cpi_calibration** (T-20), cpi_drop, cron_failed, double_embed_suspect, **exposure** (I1), form_attribution_degraded, freshness (**15 sources** dont `cpi_calibration_checks`, `page_taxonomy` warn 21 j ; `secib_dossiers` off), gsc_ingest_missed (corrigée 04/09), **identity_stitch** (vide / stale / couverture, T-10), page_taxonomy_gap (seuil 1, T-15), pipeline_dead, **refresh_after_gsc_stale**, **refresh_budget** (T-11), rpc_health, **spam_in_events_human** (T-04), tracker_drift, **volume_floor** (T-07), warn_escalation | T-04, T-07, T-10, T-11, T-15, T-20 |
| Canal ntfy | 1 réponse 200 (01/09) ; réception téléphone [non vérifiable] | `net._http_response` : 2 × HTTP 200, dernier 03/09 03:15 (escalade `gbp_daily_stale` critical) ; réception téléphone toujours **[non vérifiable]** depuis la base | = |
| `latest_rpc_health()` | 12 RPC ok ; 0 ≠ ok / 30 j, 690 passages | **51 tests ok** ; **0 ≠ ok / 30 j, 733 passages** | I4, I5, I9, I12 sous contract‑test |
| Statement timeouts 30 j | 0 cron, 0 rpc_health ; 1 constaté (`dashboard_assisted_quarter` 30 s) | 0 cron, 0 rpc_health ; `dashboard_assisted_quarter` lit un snapshot (T-08) ; 2 requêtes ad‑hoc de cette re‑mesure ont dépassé le budget MCP (Q‑13 + Q‑14 + Q‑15…18 en un seul appel) et ont été rejouées séparément — sans incidence prod | T-08 |
| Workflows GitHub rouges | GBP 29/33 (attendu) ; GSC 1/31 ; SQL contracts 2/11 | sur les 200 derniers runs (03‑04/09, PRs de la mission) : GBP 1 échec (attendu jusqu'au verdict Google), GSC 1/1 ok, régénération rpcs.sql 10/10 ok ; les échecs des gates (prod‑drift 21/42, SQL contracts 17/54, docs 5/28, Edge 5/13, dashboard 3/18, tracker 3/21, python 3/12) sont **tous des itérations de PR corrigées avant merge** — `main` est vert à chaque merge (#124 → #145) | mission |

### 2.5 Hygiène

| Indicateur | Avant | Après (04/09) | Explication |
|---|---|---|---|
| Parité `schema_migrations` | 212 / 162 ; 1 sans miroir | 258 / 209 ; 162 communes ; **0 version depuis le 02/09 sans miroir** ; `20260807224552` mirrorée ; le stock re‑daté (mai–juillet : 96 / 47) est historique et hors gate | T-12, T-14 |
| Sha `rpcs.sql` | prod ≠ fichier | **prod = fichier** (`250f6ed7…`) | Arch #5 + T-12 |
| `views.sql` vs prod | 2 vérifiées, 9 [non vérifié] | 11/11 noms ; parité sémantique **[non vérifiée]** (zone i, hors tickets) | — |
| Advisors | 1 ERROR, 13 WARN | **0 ERROR, 12 WARN** (détail §1) | T-01, T-15, T-01 ter |
| SECURITY DEFINER exécutables par `anon`/`authenticated` | 2 | **0** ; `alert_rule_exposure()` = 0 ; 0 GRANT relation ; default privileges tables/séquences/fonctions révoqués | T-01, T-01 ter |
| `proconfig IS NULL` sur `paris_date`/`paris_today` | ✅ | ✅ | — |
| Constantes docs | 121 vs 122 ; 5 crons fantômes ; `gbp_gap` « n'existe pas » ; ROADMAP #19 | I13 vert ; 0 fantôme ; `CLAUDE.md` **1 252 lignes** (1 112 avant : +3 règles absolues I5/I1‑I13/I10, notes T-xx) | T-14, T-20 — la longueur de `CLAUDE.md` reste un point ouvert (§ ROADMAP) |
| Inventaire d'usage des routines | 3 sans consommateur ; 7 sous contract‑test seulement | annexe C mise à jour au T-19 (`annexes/routine_usage.md`) : `page_reads` ×2 supprimées ; les 3 routines `conversion_weekly` conservées (routine hebdo de Nicolas, hors repo) | T-19 |

---

## 3. Photo métier du 04/09/2026 (pour lire la suite sans se tromper)

- **Contacts macro 28 j (07/08 → 03/09, clos J‑1)** : **193** = 128 appels + 65 formulaires — même chiffre dans toutes les RPC (I4).
- **CPI du 03/09** : 177 pages scorées, CPI pondéré trafic **46,5**, `clics_perdus` 1 281, version de définition **2.2.5**. Le snapshot du 04/09 n'est pas encore écrit à 09:00 (ingestion GSC du jour attendue vers 12:30 Paris) : **la vérification J+1 (condition de Nicolas pour le DROP de `cpi_pre_restatement_20260903`) se lit après**.
- **Calibration CTR (T-20, premier point)** : R² **0,913**, pente −1,259, 20 buckets, médiane |écart| 25,5 %, CTR position 1 = 8,20 %. Critère liant (≥ 0,85) respecté.
- `page_taxonomy` : 457 lignes, **63 ressources / 375 classiques / 1 post sans catégorie** (T-15 ; la synchro hebdo attend le secret `WIX_API_KEY`).
- Pont SECIB (bac à sable) : 858 prospects / 49 dossiers — **comptes uniquement**, aucune donnée nominative dans ce rapport (règle §2).

---

## 4. Invariants posés par la mission (un par défaut corrigé, tous sous gate)

| # | Invariant | Défaut d'origine | Gardien |
|---|---|---|---|
| I1 | Aucune fonction ni vue de `public` lisible ou exécutable par `anon`/`authenticated` ; aucun GRANT relation ; default privileges révoqués | 2 SECURITY DEFINER exposées (récidives 25/07, 31/08) ; TRUNCATE `events` pour `anon` | `alert_rule_exposure()` (horaire), `check_prod_drift.py` (CI), migrations `20260904073237` + `…_view_invoker` |
| I2 | Tracker : garde d'exécution, wipe de storage, `page_exit` ré‑armé, chrome Cookiebot exclu, CLS = 0 explicite — chacun a son test | correctifs prod sans assertion | `tests/tracker.test.js` (source + minifié), cliquet de taille |
| I3 | Aucun event de bot dans `events_human` (UA littéral, SEBot, referrer spam) — filtre à l'ingestion ET miroir SQL | bot Baidu 13,8 % des pageviews pendant 4 mois | Edge v28 + `refresh_noise_sessions` + `alert_rule_spam_in_events_human` |
| I4 | « Contacts macro N jours » = **un seul chiffre**, fenêtre Paris close à J‑1, identique dans `site_macro_counts`, `macro_contacts_by_path`, `conversion_journeys`, `form_submits_attributed`, `assisted_contacts_by_entry_path` ; funnel = journeys organiques sur sa fenêtre | 183 / 189 / 195 selon la RPC | contract‑tests `contacts_28j_une_fenetre`, `assisted_sum_equals_site`, `funnel_meme_total_que_journeys` ; règle CI C6c |
| I5 | `*_pct` = 0‑100, `*_rate` = 0‑1, un nom = une unité partout | rebond ×100 pendant 38 j | 4 contract‑tests `units_*` |
| I6 | Une alerte = un seuil mesuré sur sa distribution ; critical ⇒ ntfy ; warn ≥ 5 j ⇒ escalade (hors kinds éditoriaux) | 48 alertes muettes, 31 `cpi_drop` sur volatilité | `cooked_alerts_refresh()` v4, `ack_alerts()` |
| I7 | Fraîcheur mesurée sur la **donnée** (`cooked_end`, `refreshed_at`), jamais sur l'heure du run ; couture horodatée | dashboard « frais » avec des données J‑2 | registre `freshness_contract` (15 sources), `alert_rule_identity_stitch` |
| I8 | Aucune constante chiffrée de doc écrite à la main (I13) | 4 valeurs pour « nombre de routines », 5 crons fantômes | `contracts/doc_constants.json`, `check_docs_constants.py`, prod‑drift |
| I9 | L'aval de l'ingestion GSC (CPI + 4 snapshots dashboard) suit l'ingestion quelle que soit son heure ; durée par étape tracée ; retard ⇒ alerte | séquence muette, CPI gelé | `cooked_refresh_after_gsc()`, `refresh_runs`, `refresh_after_gsc_stale` / `refresh_budget` / `gsc_ingest_missed` (jour UTC) |
| I10 | Un restatement CPI = bump de `cpi_definition_version` + annotation + ligne de doc, dans la même migration | 6 définitions indiscernables, 3 restatements sans annotation | `cpi_daily.cpi_version`, `annotations`, règle absolue CLAUDE.md |
| I11 | La catégorie d'un article vient de l'API Wix, jamais du slug ; un article publié non vu est **absent**, pas `NULL` ⇒ synchro hebdo + alerte dès 1 | 12 articles invisibles 2 mois | `wix_taxonomy_sync.py` (cron lundi), `page_taxonomy_gap` seuil 1 |
| I12 | Normalisation email/téléphone : **miroir strict** SQL ↔ Python, vecteurs partagés ; aucun taux du pont sans `pont_couverture` | pont non instruit | `contracts/normalize_vectors.json` (CI des deux côtés), vue `pont_couverture` |
| I13 | La CI compare la prod à la prod (rôle `cooked_ci_ro`) : routines, crons, règles, registre, contrats dashboard, échantillons | repo ≠ prod pendant des semaines | `check_prod_drift.py` (quotidien + PR) |
| I14 | Toute ligne écrite en prod par un agent est journalisée (`journal.md`), toute migration a son miroir au timestamp prod, `rpcs.sql` est régénéré depuis la prod | 1 migration sans miroir, `rpcs.sql` édité à la main | `schema-migrations-local`, `rpcs-sql-fresh`, `rpcs-regenerate` |

---

## Annexe — ce qui n'a pas pu être rejoué à l'identique

- **Q‑13 / Q‑14 fenêtre « avant sprint41 » (13/06 → 11/07)** : non rejouée (données figées, valeurs du baseline 5,53 % / 3,9 % toujours valables).
- **Annexe B (curl PostgREST avec la clé `anon` legacy)** : non rejouée — la clé est à désactiver (T-02, Nicolas) ; l'exposition est jugée sur l'ACL (0 grant, 0 DEFINER exposée).
- **Q‑07 hash du bundle Edge** : égalité au hash toujours [non vérifiée] ; égalité d'en‑tête + déploiement par la CLI le 04/09 00:35 + sondes.
- **Q‑26** : sans objet (colonne supprimée).
