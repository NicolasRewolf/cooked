# 02 — Plan de correction — mission Cooked 02/09/2026

> ⛔ **ARRÊT 1.** Ce plan attend la **validation écrite de Nicolas**, ticket par ticket ou en bloc, citée mot pour
> mot dans la session avant toute exécution. Les Phases 3‑4 se feront dans des sessions ultérieures (une par ticket
> lourd), chacune commençant par relire `journal.md` et le ticket validé.
>
> ✅ T‑01 exécuté le 02/09/2026 20:23 Paris (vérifié 03/09 07:04) ; T‑12 livré par la session Cursor du 02/09 23:00→00:08 (PR #124, #102 et #113 fermées).
>
> Format : `docs/plan-correction-audit-2026-07-02.md`. Source des constats : `01-audit.md` (IDs `x‑nn`). Priorité :
> **P0 → P1 → invariants anti‑récidive → P2 → P3.** Règle de valeur : une correction vaut par la part de chiffres
> métier qu'elle change ou par la panne qu'elle empêche ; l'hygiène passe après et reste petite.
> Chaque ticket porte : objet · problème (constat source) · changement précis · **validation avant/après** (requête,
> fenêtre, valeur attendue) · restatement ? · **qui** · estimation · **invariant livré avec**.
>
> Règles de Phase 3 rappelées : une branche `claude/<sujet>` et une PR par ticket ; migration appliquée en prod =
> miroir exact (timestamp réel) + `rpcs.sql` régénéré **par le script depuis la prod** + méta dans la même PR ;
> CI verte ; effet vérifié en prod par une requête montrée ; CHANGELOG + doc concernée ; restatement ⇒ ligne
> `annotations` + phrase pour Me Plouton avant merge. DELETE de masse, DROP, purge, changement de rétention :
> validation explicite citée (⛔ ARRÊT 2).

---

## 0. Périmètre proposé

| Vague | Tickets | Nature | Quand |
|---|---|---|---|
| **0 — Fermer les portes** (< 1 h, jour 1) | T‑01, T‑02 | sécurité | dès validation |
| **1 — Chiffres faux livrés** | T‑03, T‑04, T‑05, T‑06, T‑08, T‑09 | P0/P1 de chiffre | sessions suivantes, dans cet ordre |
| **2 — Invariants anti‑récidive** | T‑12, T‑07, T‑10, T‑11, T‑13, T‑14 | I1…I13 | après la vague 1 (T‑12 peut passer avant : il conditionne les autres) |
| **3 — P2 à valeur** | T‑15, T‑16, T‑17, T‑18 | dette qui mordra | ensuite |
| **4 — Hygiène et décisions** | T‑19, T‑20, T‑21, T‑22 | P3 + arbitrages | quand Nicolas a tranché §7 |

**Ce que je propose de NE PAS faire** (et pourquoi) : réécrire le tracker en loader (décision §7.1, pas un chantier
d'audit) ; toucher la cadence `engagement_tick` (aucun constat) ; une CPI v2.3 (décision prise) ; corriger la
« duplication » d'events (0,4 %, sans clé d'idempotence — arbitrage du 25/07 maintenu, seule l'alerte de plancher
est proposée) ; un backup externe (décision du 02/07) ; l'ingestion SECIB prod (devis non signé).

---

# VAGUE 0 — Fermer les portes

## T‑01 · Révoquer l'exposition `anon` : `rpc_contract_check`, `page_reads`, `cpi_capture_perdue` + privilèges par défaut ⚠️ P0 — **FAIT 02/09 20:23, vérifié 03/09 07:04** (journal)

- **Problème** : h‑01 (P0), o‑02 (P1), o‑03 (P1). Deux fonctions SECURITY DEFINER et une vue répondent au rôle
  `anon` ; `rpc_contract_check` exécute le SQL qu'on lui passe. Cause : `pg_default_acl` (rôles `postgres` et
  `supabase_admin`) accorde EXECUTE à `anon`/`authenticated` sur toute nouvelle fonction ; aucun `REVOKE` dans les
  migrations du 28/07. Récidive R5 ×3.
- **Changement** : migration `YYYYMMDDHHMMSS_revoke_exposition_anon_et_default_privileges.sql` :
  1. `REVOKE ALL ON FUNCTION public.rpc_contract_check(text,text,integer,integer) FROM PUBLIC, anon, authenticated;`
     idem `public.page_reads(timestamptz,timestamptz)` et `public.page_reads(integer)` ;
  2. `ALTER VIEW public.cpi_capture_perdue SET (security_invoker = true); REVOKE ALL ON public.cpi_capture_perdue FROM anon, authenticated;`
     idem `cpi_movers`, `events_no_bots` (sans grant aujourd'hui : uniformisation) ;
  3. `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;`
     — pour le rôle `supabase_admin`, vérifier si `postgres` a le droit de le faire ; sinon, documenter et compenser
     par l'invariant ;
  4. **Invariant I1** : `alert_rule_exposure()` (règle SQL découverte par `cooked_alerts_refresh`, `critical`) qui
     liste toute fonction `public` SECURITY DEFINER avec `has_function_privilege('anon'|'authenticated', …, 'EXECUTE')`
     et toute vue sans `security_invoker=true` ayant un grant `anon`/`authenticated` ; + `scripts/check_exposure.sql`
     rejoué par `run_rpc_contract_tests` (0 ligne attendue).
- **Validation** : avant = 2 fonctions, 1 vue (Q‑11/Q‑12 baseline) ; après = `has_function_privilege` false sur les 3,
  `curl GET /rest/v1/cpi_capture_perdue` → 401/permission denied, `GET /rest/v1/rpc/page_reads` → 401 ; advisors
  security : 0 ERROR, 0 lint 0028/0029 ; `alert_rule_exposure()` → 0 ligne ; contract‑tests verts (le dashboard
  n'utilise aucun de ces objets : zone g).
- **Restatement** : non. **Qui** : moi (migration) ; Nicolas : rien côté Wix. **Estimation** : 45 min.
- **À ne pas oublier** : régénérer `rpcs.sql` depuis la prod (T‑12 partiel), `SECURITY.md` (T‑14).

## T‑02 · Forensique légère et rotation — décision Nicolas ⚠️

- **Problème** : l'exposition a duré 36 j ; 24 h de logs et `rpc_health` ne montrent aucun appel étranger, mais ce
  n'est pas une preuve d'absence.
- **Changement** : (a) lire les `edge_logs` disponibles sur la rétention maximale du plan (Supabase Studio, action
  Nicolas) pour tout `POST /rest/v1/rpc/rpc_contract_check` hors curl de l'audit (02/09 09:52) ; (b) **décision** :
  faire tourner la clé publishable/anon (le dashboard la lit via Vercel : `NEXT_PUBLIC_SUPABASE_*`) — coût faible,
  bénéfice : invalide toute clé copiée. Aucune donnée n'a besoin d'être restaurée sauf preuve contraire.
- **Validation** : liste des appels (0 attendu) consignée dans `03-passation.md`. **Qui** : Nicolas (Studio +
  Vercel) ; moi (procédure). **Estimation** : 20 min.

# VAGUE 1 — Chiffres faux livrés

## T‑03 · `bounce_rate` : réparer la division par 100 et poser le contrat d'unités

- **Problème** : d‑01 (P0), d‑04 (P1). `behavior_pages_for_period` divise une fraction 0‑1 par 100 (`rpcs.sql`
  section `behavior_pages_for_period`, `round(b.bounce_rate / 100.0, 4)`) et met la fraction dans `_pct` ;
  `cooked_bounce_rate` vaut 0,23 dans `gsc_page_performance` et 34,43 dans `pages_overview_unified` ; l'écart résiduel
  22,98 → 34,43 n'est expliqué ni par la fenêtre ni par la définition (à instruire ici).
- **Changement** : migration : `behavior_pages_for_period` → `bounce_rate = b.bounce_rate` (0‑1), `bounce_rate_pct
  = b.bounce_rate_pct` ; `gsc_page_performance.cooked_bounce_rate` publié en pourcentage comme les autres (ou renommé
  `cooked_bounce_rate_pct` — contrat de sortie : décision, je propose le renommage avec alias 1 sprint) ; instruction
  de l'écart résiduel (grain session×path vs session, dénominateur entrées vs sessions) et alignement.
  **Invariant I5** : contract‑test « `*_pct` ∈ [0,100], `*_rate` ∈ [0,1] » sur toutes les RPC publiées.
- **Validation** : `SELECT max(bounce_rate), max(bounce_rate_pct) FROM behavior_pages_for_period(J‑28, J)` avant =
  0,0100 / ~1 ; après = ~0,62 / ~62 ; `/honoraires-rendez-vous` : même valeur dans les 3 sources (fenêtre alignée).
- **Restatement** : oui pour tout lecteur de `behavior_pages_for_period` (contract‑tests et ad‑hoc ; le dashboard
  ne l'utilise pas) → annotation « correction d'unité, pas un changement de comportement ». **Qui** : moi.
  **Estimation** : 1 h 30.

## T‑04 · Tarir le bot Baidu à la source et sortir le spam de `events_human`

- **Problème** : a‑01 (P0), a‑02, c‑06, d‑05. UA `pc` + referrer `m.baidu.com` = 13,8 % des pageviews de
  `events_human` ; ni l'Edge ni `refresh_noise_sessions` ne le voient ; `classify_channel` le classe `referral`.
- **Changement** : (1) Edge `track` **v28** : motif `^pc$` (UA littéral) dans `BOT_UA_RE` de `_shared/track_row.ts`
  + drop comptés `bot_ua` ; (2) migration : même motif dans la taxonomie `ua_bot` de `refresh_noise_sessions` +
  règle « referrer spam » dans `refresh_noise_sessions` (sessions dont la 1re pageview a `cooked_is_spam_referrer`) ;
  (3) `classify_channel` v4 : renvoie `'spam'` si `cooked_is_spam_referrer(ref)` ; (4) **purge** des lignes
  existantes du bot dans `events` (> 20 600 lignes/28 j) : ⛔ DELETE de masse → validation Nicolas citée, sinon on
  laisse `noise_sessions` les masquer ; (5) **Invariant I3** : contract‑test + alerte « part de sessions spam dans
  `events_human` < 1 % ».
- **Validation** : avant = 1 899 pageviews `user_agent='pc'` sur 28 j (Q a‑01) ; après = 0 dans `events_human`,
  `ingest_drops` `bot_ua` augmente d'autant ; couverture `page_exit` mesurée à ~89 % ; `classify_channel` : 0 ligne
  `referral` avec `cooked_is_spam_referrer`.
- **Restatement** : oui — sessions/visiteurs 28 j en ad‑hoc −16 % ; les RPC publiées et le CPI ne bougent pas
  (déjà filtrés). Phrase : « correction de mesure (retrait d'un robot), pas une baisse de trafic ». **Qui** : moi
  (Edge deploy + migration) ; Nicolas : rien. **Estimation** : 2 h.

## T‑05 · Aligner « 28 jours » GSC : `gsc_pages_overview` et la capture du CPI

- **Problème** : d‑03 (P1 : 25 j, −12,5 % de clics), d‑07 (P2 : capture 24‑25 j vs comportement 28 × 24 h),
  l'overload `period_kind` documenté n'existe pas.
- **Changement** : `gsc_pages_overview` bornée par `cooked_period_bounds('rolling_28','gsc')` (28 jours clos à
  `gsc_last_data_day()`) ; CPI : fenêtre GSC = 28 jours clos à `gsc_last_data_day()` **et** fenêtre Cooked alignée
  sur les mêmes jours Paris (ce qui traite aussi f‑04 : bornes sur `now()`) — c'est un **restatement CPI**
  (décision §7.7) ; documenter les fenêtres dans `cpi-cooked-page-index.md`. **Invariant I4** (test « 28 j = 28
  jours »).
- **Validation** : Σ `gsc_pages_overview.gsc_clicks_28d` = Σ `gsc_path_daily` sur 28 j alignés (4 689 → 5 358 le
  02/09) ; CPI : `cpi_daily` J vs J‑1 recalculé, delta moyen et grades déplacés consignés.
- **Restatement** : oui (annotation + phrase). **Qui** : moi. **Estimation** : 2 h (+ validation restatement).

## T‑06 · Momentum du CPI : revenir à une source complète — décision §7.7

- **Problème** : f‑01 (P1) : momentum sur 16‑28 % des clics ; f‑07 : `potentiel` multiplié par momentum × gate.
- **Options** (à trancher par Nicolas) : (a) `gsc_path_daily` total (état d'avant le 25/07 : brandé inclus, biais
  borné à `/notre-cabinet`) ; (b) `gsc_path_daily` total moins les clics brandés révélés par qpd (≈ total non brandé,
  proposée) ; (c) qpd non brandé corrigé par la couverture (fragile sous 20 %). Je recommande **(b)**.
  `potentiel` = `cpi_compose(zc,zr,zl,0,1,1,true)` (identité exacte, coût nul). **Invariant I4/I10** : test de
  couverture du momentum ≥ plancher par grade ; `cpi_drop` refuse une page dont les clics `gsc_path_daily` montent.
- **Validation** : contrefactuel du réfuteur f rejoué : 0 page fiable en direction inverse ; `cpi_daily` restaté
  consigné (delta, grades, movers).
- **Restatement** : oui. **Qui** : moi après décision. **Estimation** : 2 h.

## T‑08 · Contacts assistés : compter ce qu'on ne rattache pas, et sortir le trimestre du chemin critique

- **Problème** : c‑03 (P1 : −6,5 %, bucket mort), g‑02 (P1 : timeout 30 s, ligne objectif masquée, `Promise.all`
  bloqué), c‑04 (jour en cours hors couture).
- **Changement** : `assisted_contacts_by_entry_path` : `LEFT JOIN LATERAL` + ligne `(non attribuable)` ;
  `dashboard_assisted_quarter` lit un snapshot rafraîchi par `cooked_refresh_after_gsc` (fenêtre close J‑1, `live_j1`)
  au lieu de calculer à l'affichage ; `page.tsx` rend « objectif indisponible » plutôt que rien ; clé
  `objectif_assistes_trimestre` : **à poser par Nicolas** (valeur). **Invariant I4** : `Σ assistés + non attribuables
  = site_macro_counts` en contract‑test ; **I8** : les 15 `dashboard_*` sous `run_rpc_contract_tests` avec budget.
- **Validation** : avant = 174 vs 186 ; après = 174 + 12 = 186 ; `dashboard_assisted_quarter()` < 1 s ;
  `pg_stat_statements` : appels = chargements de la home.
- **Restatement** : oui, sur l'objectif trimestre (+6,5 %) — phrase : « les formulaires sans identifiant sont
  désormais comptés à part ». **Qui** : moi + Nicolas (valeur de l'objectif). **Estimation** : 3 h.

## T‑09 · Une seule fenêtre « 28 jours » et un seul grain par ratio

- **Problème** : d‑02/c‑05 (183/189/195), d‑06/c‑01 (`seo_to_contact_funnel` grains mixtes + `current_date` UTC),
  o‑14 (gclid : chevauchement paid/GMB).
- **Changement** : `conversion_journeys`, `form_submits_attributed`, `seo_to_contact_funnel` passent par
  `cooked_period_bounds` (dates Paris closes) ; `seo_to_contact_funnel` : dénominateur en visiteur recousu, GSC bornée
  à `gsc_last_data_day()` ; grep CI interdisant `current_date` et `now() - make_interval` dans les migrations (règle
  C6 étendue) ; `classify_channel` : `utm_source=gmb` **et** `gclid` → règle explicite (décision : `paid` prime).
  **Invariant I4** : contract‑test « même étiquette de fenêtre ⇒ même total de contacts » entre les 3 RPC.
- **Validation** : les trois RPC renvoient 195 (ou la valeur du jour) sur `rolling_28` à toute heure ;
  `contact_rate_pct` recalculé et consigné.
- **Restatement** : `contact_rate_pct` remonte (dénominateur −8 %) → annotation. **Qui** : moi. **Estimation** : 2 h.

# VAGUE 2 — Invariants anti‑récidive

## T‑12 · La CI compare la prod à la prod (prérequis de six invariants) — **FAIT par la session Cursor du 02/09 23:00 (PR #124)** ; reste : les contrats dashboard depuis la prod (→ T‑13) et `views.sql`

- **Problème** : h‑03, o‑04, o‑05, i‑04, g‑01, i‑02, h‑06.
- **Changement** : (1) **secret `DATABASE_URL_RO`** : rôle Postgres `cooked_ci_ro` (`SELECT` sur `pg_catalog`,
  `supabase_migrations`, `cron.job`, `public.freshness_contract`) — action Nicolas (création du secret GitHub, mot de
  passe fourni par la migration) ; (2) workflow `prod-drift.yml` planifié quotidien + sur PR : `content_sha256` prod =
  méta, ensemble `schema_migrations` = fichiers, `pg_get_function_result` des `dashboard_*` = JSON régénéré
  (`scripts/generate_dashboard_contracts.py`, nouveau), `cron.job` = liste dans `contracts/doc_constants.json`,
  `repair_hint` nomme un job existant ; (3) **immédiatement** : régénérer `rpcs.sql` + `views.sql` par les scripts
  (plus jamais à la main), committer le miroir de `20260807224552_weekly_conversion_pages_routine` (SQL depuis
  `schema_migrations.statements`), corriger les 7 timestamps re‑datés de juillet‑août ; (4) à défaut de secret :
  règle `alert_rule_repo_drift` interne qui compare le sha stocké dans `cooked_config` par la CI au sha prod.
- **Validation** : job vert un jour, rouge sur une migration MCP sans fichier (test à blanc sur une branche).
- **Restatement** : non. **Qui** : moi + Nicolas (secret). **Estimation** : 3 h.

## T‑07 · Alertes : seuils calibrés, escalade bornée, `pipeline_dead` sur l'âge, acquittement

- **Problème** : f‑02, f‑03, h‑02, h‑04, b‑03, b‑04, o‑08.
- **Changement** : migration « alertes v4 » : `pipeline_dead` = `now() - max(received_at) > 90 min` (âge, continu)
  ou relatif à la médiane de la même heure sur 7 j ; `cpi_drop` : garde sur le **niveau** du momentum (< 0,90) et
  `fiable` = S/A pour le push (B consultatif) — après T‑06 ; `warn_escalation` : ≤ 2 pushs par épisode puis silence
  jusqu'à ack ; kinds éditoriaux (`cpi_drop`) jamais `critical` ; `form_submit_dropped` via `raise_cooked_alert` ;
  alerte de plancher de volume (−50 % vs même créneau 7 j) ; test de rejeu des 30 derniers jours (0 faux positif
  nocturne, 1 détection sur trou diurne > 45 min) ; **acquittement** : RPC `ack_alerts(kinds[])` + bouton dans le
  dashboard (ou commande documentée) ; purge/ack des 51 alertes en stock ⛔ (écriture, validation citée).
  **Invariant I6** : chaque seuil documenté avec sa distribution (`docs/OPERATIONS.md` § alertes).
- **Validation** : `alerts WHERE NOT acked` → 0 après ack ; sur 7 j : ≤ 1 push critical hors incident réel.
- **Restatement** : non. **Qui** : moi ; Nicolas : ack initial. **Estimation** : 3 h.

## T‑10 · Fraîcheur mesurée sur la donnée, couture horodatée — **FAIT 03/09 23:15** (migration `20260903205820`, journal)

- **Problème** : g‑03, c‑02, c‑04, e‑06 (partie registre).
- **Changement** : `freshness_contract` : `last_point_sql` de `dashboard_resources_snapshot` → `max(cooked_end)` ;
  `identity_stitch` : colonne `refreshed_at` (ou `cooked_config`) + ligne au registre (warn 30 h) + contrat « 100 %
  des sessions J‑1 cousues » ; `page_taxonomy` au registre ; `FreshnessBanner` : `paris_today() - cooked_end >= 2` ⇒
  orange ; RPC incluant le jour en cours : drapeau `grain_partiel` ou `live_j1`. **Invariant I7.**
- **Validation** : le 28/08 rejoué → bandeau orange dès 00:00 ; `alert_rule_freshness` sonne si la couture a 30 h.
- **Qui** : moi. **Estimation** : 2 h.

## T‑11 · Refresh aval robuste à la dérive du cron GitHub + durée par étape

- **Problème** : e‑02 (P1), h‑05 (P2).
- **Changement** : `cooked_refresh_after_gsc` : garde « `max(ingested_at) > last_full_refresh_after_gsc_at` » (le
  marqueur existe) au lieu de « ingestion du jour » ; cron `0 6-23 * * *` ; table `refresh_runs(run_id, step,
  started_at, duration_ms, ok)` + alerte à 80 % du budget global ; alerte « ingestion GSC après 12:00 UTC ».
  **Invariant I9.**
- **Validation** : simulation : ingestion à 21:00 UTC → séquence à 22:00 ; `refresh_runs` renseignée à chaque run.
- **Qui** : moi. **Estimation** : 1 h 30.

## T‑13 · Dashboard : contrats depuis la prod, RPC sous contract‑test, Zod nullable, OTP — **FAIT 03/09 23:20** (migration `20260903211121`, journal)

- **Problème** : g‑01, g‑04, g‑06, g‑08.
- **Changement** : `generate_dashboard_contracts.py` (15 RPC, depuis la prod) + check en CI (T‑12) ; les 15
  `dashboard_*` dans `run_rpc_contract_tests` avec budget (5 s ; 20 s pour `article_detail`) ; `NOT NULL DEFAULT 0`
  sur les compteurs snapshot **et** `.nullable()` côté Zod pour les champs de taxonomie ; `shouldCreateUser:false` +
  test ; `dashboard_article_detail` : matérialiser la partie lourde ou baisser `rolling_90` — après mesure.
  **Invariant I8.**
- **Validation** : `latest_rpc_health()` liste 27 RPC ; page `/seo` cassée artificiellement sur une branche →
  CI rouge.
- **Qui** : moi. **Estimation** : 3 h.

## T‑14 · Docs : constantes vérifiées, SECURITY.md vrai, ROADMAP à jour, CLAUDE.md sans récit — **FAIT 03/09 23:55** (PR, journal)

- **Problème** : i‑01…i‑08, f‑06, h‑06, g‑05, g‑07, o‑12.
- **Changement** : `contracts/doc_constants.json` + `scripts/check_docs_constants.py` (routines, versions, crons,
  seuils, comptes, dates de mesure) ; orphan‑check des `.md` ; `SECURITY.md` réécrit (PII confinée, tableau des
  secrets complet, I1) ; `OPERATIONS.md` (crons réels, orchestrateur, kinds d'alerte, registre) ; `ROADMAP.md` ;
  `docs/cpi-modele-mathematique.md` (annexe SQL pointant `rpcs.sql`) ; `dashboard/README.md` ; fermeture propre de
  #45 (commentaire) ; `CLAUDE.md` : **règles nouvelles seulement** (I1, I5, C6 étendue, fenêtres). **Invariant I13.**
- **Validation** : CI docs verte ; `grep` « 121 routines » → 0.
- **Qui** : moi. **Estimation** : 3 h.

# VAGUE 3 — P2 à valeur

## T‑15 · `page_taxonomy` : synchro Wix automatisée, filtres de l'alerte — **FAIT 04/09 00:15** (migration `20260903213503`, secret Wix = Nicolas)
- **Problème** : e‑06, e‑07. **Changement** : `scripts/wix_taxonomy_sync.py` (patron gsc) + cron GitHub
  hebdomadaire, source = liste publiée de l'API Wix ; exclusion `fp_[0-9.]+_[0-9.]+/` et règle « slug d'article »
  dans `alert_rule_page_taxonomy_gap` ; `page_taxonomy` au registre (T‑10) ; correction du path tronqué (105 chars).
  **Validation** : 0 `/post/` publié sans ligne (recoupement API). **Qui** : moi (script), Nicolas (secret Wix API
  si nécessaire). **Estimation** : 2 h.

## T‑16 · Pont SECIB : garde‑fous avant le premier chiffre
- **Problème** : e‑01, e‑03, e‑04, e‑05/c‑07, c‑08, e‑08. **Changement** : vue avec `env` paramétré, statut
  `non_rapprochable`, `personne_key` + rang pour dédupliquer, priorité email > tél implémentée, borne haute sur
  `converti`, indicateur de couverture publié ; normalisation téléphone (`(0)` après indicatif) + vecteurs JSON
  partagés SQL/Python ; index unique fonctionnel `crm_prospects(email_norm, occurred_at tronquée)` ; tests
  `test_secib_ingest.py`, `test_wix_forms_import.py`, `test_gbp_ingest.py` + `paths:` élargi. **Invariant I12.**
  **Validation** : vecteurs verts des deux côtés ; `pont` sur `env='test'` = 0 ligne quand `env='prod'` demandé.
  **Qui** : moi. **Estimation** : 4 h. Aucune préparation de credentials prod (devis non signé).

## T‑17 · Tracker : filet CI, tests des correctifs, CLS explicite, debug off — puis décision loader
- **Problème** : a‑03, a‑04, a‑05, a‑07, a‑08. **Changement** : CI rouge sous 14 500 chars ; 3 assertions jsdom
  (session cut, page_exit ré‑armé, anchor chrome) ; CLS = 0 émis (coûte des chars → dépend de §7.1) ;
  `COOKED_DEBUG=false` + grep CI ; alerte « contact sans amont » (a‑08) et plancher de volume (T‑07) en attendant une
  reprise sur échec (nécessite le loader). **Invariant I11.** **Qui** : moi (code, tests) ; **Nicolas** : collage Wix
  du tracker et de `masterpage-cooked.js`. **Estimation** : 2 h + collage.

## T‑18 · Edge / formulaires : `page_source` partout, alertes routées, gate fail‑fast
- **Problème** : b‑01, b‑02, b‑04, b‑05, b‑06 (réfutation en cours). **Changement** : Nicolas ajoute
  `page_source` (+ `objet`) aux formulaires « Divorce » et « Demande dossier en cours » (bloc à coller fourni) ;
  `form_row.ts` : `canonicalPath` sur `page_source` ; `alert_rule_form_attribution_degraded` surveille aussi
  `path IS NULL` ; `form_submit_dropped` via `raise_cooked_alert` ; `COOKED_INGEST_KEY` vide ⇒ `throw` au boot +
  test ; `canonical_path(NULL)` aligné SQL/TS. Edge `form-webhook` **v14**, `track` v28 (avec T‑04).
  **Validation** : `form_submit` `path` NULL sur 28 j → 0 hors formulaires sans page. **Qui** : moi + Nicolas (Wix).
  **Estimation** : 2 h.

# VAGUE 4 — Hygiène et décisions

## T‑19 · Budget de complexité : dépréciations, bloat, vestiges
- **Problème** : d‑08, h‑07, h‑08, b‑07. **Changement** (⛔ DROP = validation citée) : `DROP` `page_reads` ×2 (après
  T‑01), `gsc_path_metrics_28d`, overload `macro_contacts_by_path(days_back)` remplacé par `period_kind` (avec
  période de grâce), `gsc_top_queries_for_path(days_back)` idem ; `REINDEX` `identity_stitch` + `autovacuum` réglé
  sur les tables GSC ; purge de `cooked_config.events_vacuum_full_scheduled` ; `record_ingest_drop` : agrégation
  côté Edge (1 appel/minute) ; contrats SQL manuels câblés dans le job T‑12. Compte cible : 122 → ~114 routines.
  **Qui** : moi après §7.4. **Estimation** : 2 h.

## T‑20 · Restatements passés : annotations et version du CPI
- **Problème** : f‑05, o‑11, f‑08. **Changement** : 3 lignes `annotations` (02/07 CPI grain lectures, 25/07
  momentum/zv, 31/08 périmètre taxonomie) ; colonne `cpi_version` alimentée par `cooked_cpi_snapshot` ; check §3
  planifié (R² + médiane dans une table, au registre) ; re‑test 56 j lancé (t0 10/06) en signalant les 4 ruptures.
  **Invariant I10.** **Qui** : moi ; Nicolas valide les phrases. **Estimation** : 1 h 30.

## T‑21 · Colonne `country` — décision (§7.2)
## T‑22 · Rétention `url`/`title` — décision (§7.3)

---

## 7. Décisions qui appartiennent à Nicolas (à poser en bloc)

1. **Loader tracker first‑party** (~200 chars + fichier versionné). Avis : **oui, mais après la vague 1** — le
   monolithe est à 14 760/15 000, aucun correctif tracker (reprise sur échec, CLS explicite) ne rentre ; le loader
   libère ~14 500 chars et rend le tracker déployable par CI. Coût : 1 session + collage Wix + un domaine ou un
   chemin `/_functions` pour servir le fichier. Non : rester bloqué sur le tracker actuel (T‑17 réduit).
2. **Colonne `country`** : suppression délibérée le 03/06 (commit `3ba987d`), 0 consommateur. Avis : **amputer**
   (drop de la colonne dans `events` = migration + `CookedEventRow`), pas peupler — aucun besoin identifié.
3. **Rétention `events.url`/`title`** : ≈ 213 + 60 MB re‑mesurés, jamais lus ; `url` transporte les ids et les
   `gclid`. Avis : cesser d'écrire `title` (mort à 98,8 % sur pageview) et tronquer `url` à la partie utile
   (query string des campagnes seulement) ; garder 400 j ; politique CNIL 13 mois : à confirmer par Nicolas.
4. **Consolidation de l'API SQL** : cible ~110 routines à court terme (T‑19), ~90 à moyen terme (regrouper les 7
   RPC « contract‑tests only » et les 12 « ad‑hoc only »). Avis : **autoriser les dépréciations de T‑19 maintenant**,
   le reste ticket par ticket.
5. **Anti‑forge `cta_phone_click`** : garde d'origine forgeable, pas de rate‑limit. Avis : **détection maintenant**
   (alerte contact sans amont + plancher de volume, T‑07/T‑17), verrou (HMAC par event) avec le loader.
6. **Cadence `engagement_tick`** : aucun constat — **inchangée**.
7. **Restatements proposés** (chacun = annotation + phrase pour Me Plouton) : T‑03 unités bounce (« correction
   d'unité ») ; T‑04 bot Baidu (« retrait d'un robot : les visites ad‑hoc baissent de ~16 %, les chiffres publiés ne
   bougent pas ») ; T‑05 fenêtres CPI/GSC (« alignement des fenêtres, +12 % de clics affichés sur 28 j ») ; T‑06
   momentum (« correction de la source du momentum, X pages changent de badge ») ; T‑08 assistés (+6,5 %) ; T‑09
   `contact_rate_pct`.
8. **GBP / SECIB** : GBP — rien à préparer côté Cooked au‑delà de T‑07 (l'alerte fait son travail) ; le client OAuth
   dédié reste l'action Nicolas après le verdict Google (~10‑15/09). SECIB — devis non signé, rien côté prod ; le
   défaut qui coûterait cher au branchement est T‑16 (pont sans garde‑fous) : à faire **avant** la signature.

## 8. Issues GitHub

Une issue par ticket (T‑01…T‑22), labels `docs/agents/triage-labels.md` : `ready-for-agent` (moi), `ready-for-human`
(Nicolas), `needs-info` (décision). **T‑01 et T‑02 sont publiées sans détail technique** (dépôt public,
`SECURITY.md`) : le détail vit ici. Créées le 02/09/2026 à 20:15 Paris (#102 → #123) :

| Ticket | Issue |
|---|---|
| T-01 | https://github.com/NicolasRewolf/cooked/issues/102 |
| T-02 | https://github.com/NicolasRewolf/cooked/issues/103 |
| T-03 | https://github.com/NicolasRewolf/cooked/issues/104 |
| T-04 | https://github.com/NicolasRewolf/cooked/issues/105 |
| T-05 | https://github.com/NicolasRewolf/cooked/issues/106 |
| T-06 | https://github.com/NicolasRewolf/cooked/issues/107 |
| T-07 | https://github.com/NicolasRewolf/cooked/issues/108 |
| T-08 | https://github.com/NicolasRewolf/cooked/issues/109 |
| T-09 | https://github.com/NicolasRewolf/cooked/issues/110 |
| T-10 | https://github.com/NicolasRewolf/cooked/issues/111 |
| T-11 | https://github.com/NicolasRewolf/cooked/issues/112 |
| T-12 | https://github.com/NicolasRewolf/cooked/issues/113 |
| T-13 | https://github.com/NicolasRewolf/cooked/issues/114 |
| T-14 | https://github.com/NicolasRewolf/cooked/issues/115 |
| T-15 | https://github.com/NicolasRewolf/cooked/issues/116 |
| T-16 | https://github.com/NicolasRewolf/cooked/issues/117 |
| T-17 | https://github.com/NicolasRewolf/cooked/issues/118 |
| T-18 | https://github.com/NicolasRewolf/cooked/issues/119 |
| T-19 | https://github.com/NicolasRewolf/cooked/issues/120 |
| T-20 | https://github.com/NicolasRewolf/cooked/issues/121 |
| T-21 | https://github.com/NicolasRewolf/cooked/issues/122 |
| T-22 | https://github.com/NicolasRewolf/cooked/issues/123 |

