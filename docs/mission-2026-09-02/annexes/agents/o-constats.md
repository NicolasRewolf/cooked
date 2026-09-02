# Constats de l'orchestrateur (Phase 0, 02/09/2026 01:12-01:32 Paris) — à soumettre à la réfutation avec ceux des zones

ID            o-01 (zone h)
Titre         `rpc_contract_check(p_name, p_sql, …)` — SECURITY DEFINER, `EXECUTE p_sql`, exécutable par `anon` et `authenticated` via PostgREST
Sévérité      P0 (exécution SQL arbitraire en tant que `postgres` par quiconque détient la clé publishable : lecture de `crm_prospects` (PII en clair), écriture/suppression via CTE `RETURNING`, exfiltration via `net.http_post`)
Preuve        `pg_proc.proacl` = `{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}` (02/09 01:30) ; `has_function_privilege('anon', …, 'EXECUTE')` = true (01:15) ; corps `supabase/rpcs.sql` section `rpc_contract_check` : `SECURITY DEFINER` + `EXECUTE p_sql INTO v_rows` ; advisor `anon_security_definer_function_executable` (observed_at 2026-09-01T23:14Z) ; mécanisme démontré sur `page_reads(tstz,tstz)` (même ACL) : `GET /rest/v1/rpc/page_reads?...` avec la clé anon → HTTP 200 + données (01:29). `rpc_contract_check` volontairement non appelée.
Impact        toute la base (PII incluse) lisible et modifiable sans authentification depuis le 28/07/2026 (migration prod `20260728081943_rpc_contract_check_helper`, fichier local `20260728102500`) — 36 jours. Aucune trace d'exploitation cherchée (hors périmètre lecture seule).
Récidive      R5 (audit 25/07 : 4 SECURITY DEFINER exécutables par anon, corrigées le 25/07) ; récidive le 28/07 (cette fonction + `page_reads`) ; nouvelle récidive le 31/08 (`alert_rule_page_taxonomy_gap`, corrigée le jour même). Cause : privilège EXECUTE accordé à PUBLIC par défaut à la création, `REVOKE` manuel jamais systématique.
Invariant     (1) `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` ; (2) test CI/contrat (`scripts/check_exposure.py` ou règle `alert_rule_exposure`) qui échoue si une fonction SECURITY DEFINER est exécutable par anon/authenticated ou si une vue sans `security_invoker` a un GRANT anon/authenticated ; (3) `rpc_contract_check` retirée de l'API (schéma non exposé ou `REVOKE … FROM anon, authenticated, PUBLIC`).
Statut        [non recoupé]

ID            o-02 (zone h)
Titre         `page_reads(p_from timestamptz, p_to timestamptz)` — SECURITY DEFINER exécutable par `anon`, répond en GET avec les données session×path×dwell ; orpheline (consommée uniquement par les contract-tests)
Sévérité      P1
Preuve        curl 02/09 01:29 Paris : `GET /rest/v1/rpc/page_reads?p_from=2026-09-01T10:00:00Z&p_to=2026-09-01T11:00:00Z&select=path,dwell_s,retained` (clé anon, Range 0-0) → HTTP 200 `[{"path":"/indemnisation-des-victimes/droit-et-accidents-du-travail","dwell_s":136,"retained":true}]` ; ACL `{=X/postgres,…anon=X…}` ; inventaire d'usage : seul appelant = `run_rpc_contract_tests`.
Impact        données comportementales de tout le site lisibles sans auth (pas de PII) ; surface d'API inutile.
Récidive      idem o-01 (28/07).
Invariant     idem o-01 + dépréciation (page_reads a été créée puis son consommateur `content_performance_via_page_reads` reverté le 28/07).
Statut        [non recoupé]

ID            o-03 (zone h / f)
Titre         Vue `cpi_capture_perdue` sans `security_invoker` et avec `GRANT SELECT` à anon/authenticated → lisible sans auth (advisor ERROR)
Sévérité      P1
Preuve        `pg_class.reloptions` = NULL pour `cpi_capture_perdue` (02/09 01:15) ; `role_table_grants` : anon:SELECT, authenticated:SELECT ; curl 01:29 : `GET /rest/v1/cpi_capture_perdue?select=path,grade&limit=1` → HTTP 200 `[{"path":"/","grade":"A"}]` ; advisor `security_definer_view` level ERROR.
Impact        scores CPI / clics perdus par page = intelligence business exposée publiquement depuis le 28/07 (migration `20260728090355`, fichier local `20260728110000`).
Récidive      exactement le P0-2 de l'audit du 02/07 (`cpi_gisement`, corrigé par `20260702074025_cpi_gisement_security_invoker`).
Invariant     idem o-01 (2) ; règle : toute `CREATE VIEW` porte `WITH (security_invoker = true)` + `REVOKE ALL FROM anon, authenticated` — vérifiable par le même test.
Statut        [non recoupé]

ID            o-04 (zone h / i)
Titre         `supabase/rpcs.sql` n'est plus le miroir de la prod : 2 fonctions différentes, 6 manquantes, 6 en trop ; édité à la main le 31/08 (en-tête « Généré le 10/08 », méta `2026-08-31`)
Sévérité      P2
Preuve        sha256 du dump prod (DUMP_SQL du générateur) = `179ed9cc…` vs méta `a3d69c7d…` = sha256 du corps local (02/09 01:22) ; md5 par fonction : diff `cooked_alerts_refresh`, `raise_cooked_alert` ; manquantes `alert_rule_freshness`, `alert_rule_gsc_ingest_missed`, `alert_rule_warn_escalation`, `conversions_leaderboard`, `cooked_weekly_conversions_snapshot`, `weekly_conversions_report` ; en trop `alert_rule_{cpi_stale,dfs_stale,gbp_gap,gsc_gap,gsc_lag}`, `dashboard_check_stale` ; `supabase/rpcs.sql:10` « Généré le 10/08/2026 » ; `contracts/rpc_snapshot_meta.json` `generated_at 2026-08-31`.
Impact        un agent qui lit `rpcs.sql` raisonne sur une dédup d'alertes et des règles qui n'existent plus (les kinds `gsc_lag`, `cpi_stale`, `gbp_gap`… ont été remplacés le 23/08 par le registre `freshness_contract`).
Récidive      R4 (25/07) : le gate `check_rpcs_sql_fresh.py` ne compare aucun hash à la prod ; il exige seulement que `rpcs.sql` change dans la PR.
Invariant     job CI (quotidien + sur PR) qui recalcule le `content_sha256` en prod (rôle lecture seule) et échoue s'il diffère du méta ; générateur seul autorisé à écrire le fichier (en-tête daté par le générateur).
Statut        [non recoupé]

ID            o-05 (zone h / i)
Titre         Migrations : 1 migration prod sans aucun fichier miroir (`20260807224552_weekly_conversion_pages_routine`) + 54 fichiers locaux re-datés ; `check_schema_migrations.py` ne compare jamais à la prod en CI
Sévérité      P2
Preuve        `supabase_migrations.schema_migrations` : 212 versions ; `ls supabase/migrations` : 162 ; `comm` (02/09 01:20) : 104 versions prod sans fichier au même timestamp, 54 fichiers absents de prod ; `20260807224552` sans équivalent même renommé (grep `weekly_conversion` = 0 fichier) ; `scripts/check_schema_migrations.py:33-40` (`if not db_url: … return 0`) ; `.github/workflows/sql-contracts.yml` sans `DATABASE_URL`.
Impact        table `conversion_weekly` (705 lignes), 3 fonctions et une routine hebdo (dernier snapshot 31/08 09:23) existent en prod et nulle part dans le repo ni les docs ; `supabase db push` depuis le repo ne les recrée pas.
Récidive      R4 (25/07 : « 21 migrations non committées »).
Invariant     CI quotidien `schema_migrations` vs fichiers (rôle lecture seule) ; règle « timestamp réel » vérifiée automatiquement.
Statut        [non recoupé]

ID            o-06 (zone c / g)
Titre         `dashboard_assisted_quarter()` dépasse son `statement_timeout=30s` sur le trimestre en cours ; la ligne objectif du dashboard est masquée en silence
Sévérité      P1
Preuve        `EXPLAIN (ANALYZE) SELECT public.dashboard_assisted_quarter()` 02/09 01:31 Paris → `ERROR 57014 canceling statement due to statement timeout` dans `CREATE TEMP TABLE _pvk` de `assisted_contacts_by_entry_path(q_start=01/07, q_end=02/09)` ; `pg_proc.proconfig` = `statement_timeout=30s` ; `dashboard/src/app/page.tsx:61` `console.error("dashboard_assisted_quarter KO — ligne objectif masquée")`.
Impact        tuile/ligne objectif trimestriel absente sans alerte (aucun contract-test ne couvre les `dashboard_*`) ; la fenêtre grandit chaque jour jusqu'au 30/09.
Récidive      `fix_assisted_quarter_perf_et_timeout` (03/07) puis unification 25/07 (`assisted_contacts_by_entry_path`) — la fonction unifiée est plus lourde que le calcul session brute qu'elle remplace.
Invariant     contract-test des 16 `dashboard_*` (rows ≥ 1, durée < timeout) dans `run_rpc_contract_tests` + alerte `rpc_health`.
Statut        [non recoupé]

ID            o-07 (zone h)
Titre         Canal d'alerte saturé : 48 alertes non acquittées, 9 pushs ntfy « critical » en 9 jours pour des `cpi_drop` escaladés, escalade re-poussée toutes les 26 h
Sévérité      P2
Preuve        Q-01/Q-31 (02/09 01:12) : `cpi_drop` 22 warn + 9 critical non acquittés (23/08→01/09) ; corps prod `alert_rule_warn_escalation` (26 h, ≥ 4 warns/5 j, pas d'ack) ; `net._http_response` 200 à 01/09 20:15 = escalade.
Impact        le canal conçu pour « le système ne sait pas qu'il est en panne » pousse quotidiennement de la volatilité éditoriale ; acquitter exige une écriture SQL manuelle.
Récidive      25/07 (23 alertes en stock, dédup punitive) → corrigé par PR #78 ; l'escalade générique du 23/08 recrée la saturation par un autre chemin.
Invariant     (design) escalade plafonnée / kinds éditoriaux non escaladés / canal séparé ; test que `count(*) WHERE NOT acked` reste < N.
Statut        [non recoupé]

ID            o-08 (zone h)
Titre         `alert_rule_pipeline_dead` (0 event reçu en 60 min) sonne sur un creux nocturne légitime
Sévérité      P2
Preuve        alerte id 104 du 22/08 02:15 UTC (04:15 Paris) ; Q-27 : 0 event entre 03:15 et 04:15 Paris le 22/08, 459 events_human entre 02:00 et 06:00 ; sur 721 ticks/30 j : 1 seul à zéro ; minimum horaire = 2 events.
Impact        faux positif critical (push ntfy nocturne) ; le seuil n'est pas robuste au trafic de nuit.
Récidive      règle inchangée depuis Sprint 37.
Invariant     seuil dépendant de l'heure ou comparaison à l'historique ; test de la règle sur les 30 derniers jours (0 faux positif).
Statut        [non recoupé]

ID            o-09 (zone h)
Titre         `cooked_refresh_after_gsc` consomme jusqu'à 90 % de son budget (2 166 s / 2 400 s) sans mesure par étape
Sévérité      P2
Preuve        Q-29 (02/09 01:20) : 30 runs > 20 min en 30 j, max 2 165,9 s le 05/08 11:00 ; `cron.job` `SET statement_timeout='2400s'` ; corps prod : 4 étapes à `statement_timeout` propres (600/600/600/300 s) ; aucune table de durées.
Impact        au-delà de 2 400 s l'étape en cours est annulée (57014), alerte `refresh_step_failed_*`, rejeu à l'heure suivante ; la marge se réduit avec `events`/`identity_stitch`.
Récidive      timeouts nocturnes silencieux (juin), `fix_refresh_after_gsc_timeout` 22/07.
Invariant     durée par étape journalisée + alerte à 80 % du budget.
Statut        [non recoupé]

ID            o-10 (zone b)
Titre         `events.country` mort depuis le 02/06/2026 19:37 — capture perdue sans décision
Sévérité      P2
Preuve        Q-26 (events brut, diagnostic) : 100 % renseigné jusqu'à la semaine du 25/05, 35,8 % semaine du 01/06 (dernier 02/06 19:37), 0 % depuis ; `track_row.ts` déployé : `country` jamais assigné.
Impact        toute RPC/vue qui lit `country` est vide ; décision Nicolas (§7.2).
Récidive      signalé audit 02/07 (P2 docs) — non tranché.
Invariant     scorecard NULL-rate en contract-test (une colonne qui passe de 100 % à 0 % déclenche une alerte).
Statut        [non recoupé]

ID            o-11 (zone f)
Titre         Restatements sans annotation : CPI 02/07 (grain lectures), `classify_channel` v2 IA 02/07, `page_taxonomy` +12 articles 31/08
Sévérité      P3
Preuve        Q-22 : 7 lignes dans `annotations` — aucune ne mentionne le 02/07 CPI (la ligne 02/07 = refonte d'un article), ni la v2 IA, ni le 31/08 ; `docs/cpi-cooked-page-index.md` « Annotations posées dans la table annotations » pour les trois restatements CPI.
Impact        un « avant/après 02/07 » ou « 31/08 » dans les séries est lu comme un mouvement réel.
Récidive      règle §2.10 de la mission ; CLAUDE.md « table annotations à remplir ».
Invariant     checklist PR : toute migration étiquetée « restatement » exige une ligne `annotations` (test CI sur le nom de migration).
Statut        [non recoupé]

ID            o-12 (zone i)
Titre         Constantes docs périmées : 121 routines (6 fichiers), 5 crons fantômes dans OPERATIONS.md, « gbp_gap n'existe pas encore » (CLAUDE.md, OPERATIONS.md:482), ROADMAP #4 « issue #19 ouverte »
Sévérité      P3
Preuve        `grep` 02/09 01:17 (AGENTS.md:25,55 ; README.md:161,205 ; OPERATIONS.md:234,601 ; CLAUDE.md:325 ; HISTORY-sprints.md:46 ; views.sql:11) ; `cron.job` 9 jobs vs OPERATIONS.md:462-480 ; `gh issue list --state all` : #19 fermée 30/08.
Impact        un agent applique des réflexes sur des objets qui n'existent plus (cron CPI 07:30, alerte gbp_gap « à créer »).
Récidive      R4 ; « 39 désynchronisations corrigées » le 10/08, à nouveau périmé 3 semaines après.
Invariant     `contracts/doc_constants.json` + `scripts/check_docs_constants.py` en CI.
Statut        [non recoupé]

ID            o-13 (zone a)
Titre         Tracker minifié à 14 760 / 15 000 chars (98,4 %)
Sévérité      P2
Preuve        `python3 scripts/minify-tracker.py` 02/09 01:19 : « Minified : 14,760 chars (98.4 % of Wix's 15,000 limit) ».
Impact        240 chars de marge : tout correctif tracker (ré-armement, anti-forge, loader) est bloqué ; décision loader (§7.1).
Récidive      14 048 le 02/07 (93,7 %), sprint41 a consommé 700 chars.
Invariant     test CI `tracker-test` qui échoue au-dessus de 14 500 chars (marge de 500) — ou loader.
Statut        [non recoupé]

ID            o-14 (zone d)
Titre         `classify_channel` ignore `gclid`/`gbraid`/`wbraid` : 18 entrées sur 28 j portent un `gclid` et sont classées hors `paid`
Sévérité      P3
Preuve        Q-35 (02/09 09:54 Paris, `events_human`, 1re pageview de session, 05/08→01/09) : `paid` = 1 472, dont 1 185 avec `gclid` ; `non_paid_avec_gclid` = 18 ; corps `classify_channel` (rpcs.sql) : aucun test sur `url`/`gclid`.
Impact        1,2 % des clics Ads classés direct/organique — négligeable aujourd'hui, mais c'est la même famille de défaut que le GMB (27/07) et l'IA (02/07) : le canal dépend du seul `utm_*`.
Récidive      pattern `classify_channel` v2 (02/07, utm_source IA) et v3 (27/07, GMB).
Invariant     vecteurs de test `contracts/channel_vectors.json` (referrer, utm, url → canal) rejoués en contract-test.
Statut        [non recoupé]
