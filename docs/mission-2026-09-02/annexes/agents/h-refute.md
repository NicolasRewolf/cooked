# Réfutation — zone (h) ops : crons, alertes, ntfy, CI, advisors, privilèges
Mission Cooked du 02/09/2026 — Phase 1, passe de réfutation fail-closed, LECTURE SEULE.
Repo `main` e95f3ee · prod `mxycmjkeotrycyneacje` · toutes mes mesures du **02/09/2026 entre 15:03 et 15:35 Paris**.

**Constats reçus : 12. Constats recopiés : 12.** (h-01…h-08, o-02, o-03, o-04, o-05)

Rien n'a été écrit en prod. `rpc_contract_check` n'a **jamais** été appelé. Aucun POST vers une RPC
(le seul POST tenté — une sonde d'exposition à paramètre bidon, qui n'aurait pas atteint le corps —
a été refusé par le garde-fou de l'environnement ; l'exposition est donc établie par l'ACL, pas par appel).
La valeur de `cooked_config.ntfy_topic` n'a pas été lue. Aucune PII, aucune clé dans ce document.

---

# PARTIE 1 — RECOPIE DES 12 CONSTATS REÇUS

### h-01
- **Titre** — `rpc_contract_check` : exécution de SQL arbitraire en SECURITY DEFINER (owner postgres) ouverte à `anon` — et la cause n'est PAS celle supposée
- **Sévérité** — P0 (perte/exfiltration de données possible — PII en clair)
- **Preuve** — `pg_proc` + `has_function_privilege` 02/09 09:41 : `prosecdef=true`, owner postgres, `proconfig={search_path=public, pg_catalog}`, `proacl = {=X/postgres, postgres=X, anon=X, authenticated=X, service_role=X}`, `anon_exec=true`. Advisors lints 0028/0029 (« can be executed by the `anon` role … via /rest/v1/rpc/rpc_contract_check »). Corps : `EXECUTE p_sql INTO v_rows`. Exposition réelle prouvée par le jumeau `page_reads(timestamptz,timestamptz)`, même ACL, HTTP 200 en GET. Cause racine : `pg_default_acl` porte DEUX lignes pour les fonctions de `public` (grantors `postgres` et `supabase_admin`) accordant X à anon/authenticated/service_role ; mergées avec `acldefault('f', owner)` qui contient `=X/owner` (PUBLIC). Fichier fautif `supabase/migrations/20260728102500_rpc_contract_check_helper.sql` : aucune ligne REVOKE/GRANT.
- **Impact** — appel `POST /rest/v1/rpc/rpc_contract_check` avec la clé anon → `p_sql` exécuté avec les droits de `postgres` : lecture de `crm_prospects`/`secib_dossiers` (PII en clair, 795 prospects) malgré RLS deny-all ; écriture/suppression via CTE ; exfiltration via `net.http_post` (`pg_net` installé dans `public`). Violation du secret professionnel et du RGPD. Fenêtre : 36 jours depuis le 28/07/2026. Objets secondaires : `page_reads(tstz,tstz)`, vue `cpi_capture_perdue`.

### h-02
- **Titre** — `alert_rule_pipeline_dead` mesure la PHASE du trou, pas la santé du pipeline : un trou de 68,9 min n'a pas alerté, un trou de 63,3 min a alerté
- **Sévérité** — P1 (panne silencieuse dans un sens, faux positif dans l'autre)
- **Preuve** — corps prod : `count(*) FROM events WHERE received_at > now() - interval '60 minutes'`, `IF v_n = 0 THEN` ; fenêtre glissante fixe 60 min évaluée une fois par heure (cron `cooked-alerts-hourly`, `15 * * * *`, jobid 5). Trous mesurés sur 30 j : 10/08 02:05→03:14 = 68,9 min / 0 tick ; 22/08 03:12→04:16 = 63,3 min / 1 tick (seule alerte) ; 28/08 05:41→06:37 = 56,0 min / 0 ; 07/08 06:53→07:48 = 54,5 min / 0 ; …15 trous ≥ 40 min, dont 2 ≥ 60 min.
- **Impact** — FAUX POSITIF : l'unique `pipeline_dead` des 30 j (22/08 04:15, critical, non acquittée) est un creux nocturne naturel reparti seul à 04:16. ANGLE MORT : la règle n'est garantie de se déclencher que si la panne dure ≥ 120 min ; une panne réelle < 2 h peut passer inaperçue selon l'heure de début (~1 700 events/jour ouvré, 2 h diurnes ≈ 140 events et plusieurs contacts macro perdus).

### h-03
- **Titre** — Le gate CI anti-dérive (Arch #5 / Arch #10) est structurellement aveugle au mode de défaillance réel du projet : la migration appliquée en prod sans fichier
- **Sévérité** — P1 (l'invariant censé empêcher la récidive est inerte ; dérive mesurée en cours)
- **Preuve** — `check_rpcs_sql_fresh.py` : la liste vient de `git diff --name-only` ; `if not migrations: print("Arch #5 OK — aucune migration modifiée"); return 0` → une migration appliquée via MCP `apply_migration` sans fichier ne déclenche rien. Contrôle de fraîcheur = présence d'un marqueur textuel `-- ═══ public.<nom>(` + présence du fichier dans le diff ; aucun hash, aucune connexion prod. `check_schema_migrations.py` : `db_url = os.environ.get("DATABASE_URL","")` puis sortie « OK … (pas de DATABASE_URL) ». `.github/workflows/sql-contracts.yml` : le job n'a aucun bloc `env:` → `DATABASE_URL` absent en CI. `generate_rpcs_sql.py` exige lui aussi `DATABASE_URL`.
- **Impact** — dérive constatée non détectée : 212 versions prod vs 162 fichiers locaux, 104 versions prod sans fichier, 54 fichiers re-datés, 1 migration prod sans miroir (`20260807224552`, table `conversion_weekly` + 3 routines) ; `rpcs.sql` ≠ prod (2 corps différents — `cooked_alerts_refresh`, `raise_cooked_alert` —, 6 routines manquantes, 6 en trop). La documentation de référence n'est plus fiable sur l'organe qui protège tout le reste.

### h-04
- **Titre** — Canal ntfy : escalade non bornée + échec CI quotidien sur le même topic — ~19 pushs critical en 10 jours, tous connus, aucun acquittable sans SQL
- **Sévérité** — P1 (fatigue d'alerte)
- **Preuve** — `alert_rule_warn_escalation` re-émet un `critical` pour tout kind dont un warn existe depuis ≥ 5 j, s'il n'y a ni critical < 26 h ni ack sur 5 j ; aucune borne de répétition. `raise_cooked_alert` : dédup `(kind, severity)` 24 h puis push ntfy priorité 5 si `critical` et dernier épisode non acquitté. Table `alerts` 30 j : cpi_drop critical 9 (23/08 23:15 → 01/09 20:15, 0 ackée), cpi_drop warn 30, gbp_daily_stale critical 1 + warn 6, gbp_gap critical 1 + warn 8, gsc_ingest_missed warn 3, pipeline_dead critical 1 → 12 criticals en 30 j. Second flux même topic : GBP Daily Ingest en échec les 24→31/08 et 01/09 = 9 échecs consécutifs, step `notify-failure` fonctionnel. ~21 notifications en 10 jours. `alerts.acked` = booléen mis à jour par SQL, aucune UI.
- **Impact** — aucun chiffre faux ; la perte est la capacité de détection : le canal critical délivre ~2 notifications/jour de bruit connu, et sur 12 criticals la proportion exigeant une action humaine sous 24 h est nulle.

### h-05
- **Titre** — `cooked_refresh_after_gsc` tourne à 90 % de son budget sans aucune trace de durée par étape : on saura qu'il a cassé, pas pourquoi
- **Sévérité** — P2 (dette qui mordra à l'échelle — la marge se referme avec la croissance des données)
- **Preuve** — `cron.job` jobid 46 : `0 8-20 * * *`, `SET statement_timeout='2400s'; SELECT public.cooked_refresh_after_gsc();`. Baseline : 30 runs > 20 min sur 30 j ; max 2 166 s le 05/08/2026 = 90,3 % du budget ; 1 596 s le 01/09 = 66,5 % ; marge résiduelle au pic 234 s. `cooked_config` ne contient que 4 clés dont `last_full_refresh_after_gsc_at` (horodatage de FIN, pas de ventilation) ; aucune table de log de durée par étape. Budgets par étape (non re-vérifiés) : cpi 600 + dashboard 600 + expertises 600 + assisted 300 = 2 100 s.
- **Impact** — le plafond global 2 400 s est inférieur à la somme des budgets d'étape + le hors-étapes ; `events` croît (~48 600 events/7 j) et `gsc_query_page_daily` atteint 1,18 M lignes. Quand le plafond sautera, l'échec tombera arbitrairement sur l'étape en cours et le diagnostic partira de zéro. Retex projet : « les jobs pg_cron lourds tapent leur statement_timeout en silence » (CPI gelé 8 j).

### h-06
- **Titre** — `freshness_contract.repair_hint` : le runbook embarqué dans l'alerte renvoie vers 5 jobs pg_cron qui n'existent pas
- **Sévérité** — P2
- **Preuve** — `freshness_contract` (13 sources) : `cpi_daily` → « Vérifier le job pg_cron cooked-cpi-daily-snapshot (07:30 UTC) et cooked_cpi_snapshot(). » ; `dashboard_resources_snapshot` → « Vérifier les jobs pg_cron refresh-dashboard-* (04:00-04:16 UTC) et cooked-refresh-after-gsc. ». Or `cron.job` renvoie 9 jobs et aucun de ces noms (run_rpc_contract_tests, purge_old_events_monthly, refresh_noise_filters_hourly, cooked-alerts-hourly, refresh_seo_url_snapshot, cooked-purge-noise-weekly, refresh-identity-stitch, cooked-refresh-after-gsc, math-refresh-snapshots-weekly). Les 5 jobs fantômes sont les mêmes que ceux listés à tort dans `docs/OPERATIONS.md:462-480`.
- **Impact** — les seuils du registre sont corrects et les alertes se déclenchent bien ; le défaut porte sur la consigne de réparation, la seule partie de l'alerte qui a de la valeur à 3 h du matin. Aggravant : la constante périmée n'est pas dans un Markdown, elle est dans une TABLE de production récitée à l'opérateur pendant l'incident.

### h-07
- **Titre** — Bloat structurel non surveillé : `identity_stitch` porte 123 MB d'index pour 24 MB de données, et les 3 tables GSC vivent en permanence à 10-13 % de tuples morts
- **Sévérité** — P2
- **Preuve** — (a) `identity_stitch` : 122 133 lignes vivantes, 0 morte, 41 autovacuums ; pkey 81 MB (8 026 271 scans), visitor_idx 42 MB, heap 24 MB → 123 MB d'index (84 % du total), ~695 o/ligne ; `n_tup_del` cumulé 12 228 906 ≈ 100 reconstructions (`refresh_identity_stitch(90)`, cron jobid 42, vide et réinsère chaque nuit). (b) GSC : `gsc_query_page_daily` 1 176 664 vivants / 132 411 morts (11,3 %, 1 seul autovacuum le 17/08), `gsc_query_daily` 13,0 %, `gsc_path_daily` 10,4 % ; `n_tup_upd` 3,10 M / 2,90 M / 0,54 M ; scale_factor 0,2 → seuil ~235 k. (c) `ingest_drops` : 41 vivants / 71 morts (173 %), `n_tup_upd` 1 087 879, 16 612 autovacuums.
- **Impact** — ~110 MB récupérables sur `identity_stitch` (4,6 % d'une base de 2 379 MB) ; ~282 k tuples morts sur les 3 tables GSC ; l'index primaire sert 8 M de scans sur un btree ~5× trop gros. Aucun chiffre livré n'est faux — c'est un coût, pas un biais. Ni la volumétrie ni le bloat ne sont couverts par `refresh_pipeline_health()`.

### h-08
- **Titre** — Hygiène : un vestige de VACUUM désarmé, 4 contrats SQL jamais exécutés, et un `updated_at` non maintenu qui rend inerte le garde-fou de `tracker_drift`
- **Sévérité** — P3 (hygiène)
- **Preuve** — (a) `cooked_config.events_vacuum_full_scheduled` = « 26/07/2026 04:00 Paris », `updated_at` 25/07 23:50, alors que le VACUUM FULL annuel a été désarmé le 10/08/2026 (migration `20260810093206`) ; aucun job `oneshot-*` dans `cron.job`. (b) 4 fichiers de contrat SQL dans `scripts/` référencés par aucun workflow (`c2_alerts_contract`, `cooked_events_window_contract`, `validate_gsc_is_branded`, `cpi_validation_j28`) ; `sql-contracts.yml:5-6` assume le statut « contrat MANUEL, exécuté hors CI ». (c) `expected_tracker_version` = « sprint41 » avec `updated_at` = 02/07/2026 19:22, alors que sprint41 n'a été déployé que le 12/07/2026 → valeur modifiée sans bump. Or `alert_rule_tracker_drift` fait `AND (now() - v_expected_since) > interval '48 hours'` avec `v_expected_since = updated_at` : le délai de grâce de 48 h ne s'applique jamais.
- **Impact** — aucun chiffre faux, aucune panne actuelle. (c) est un piège armé pour le prochain déploiement de tracker : alerte immédiate et trompeuse au moment précis où le signal doit être fiable. (b) prive le sous-système d'alertes de son propre filet.

### o-02 (zone h)
- **Titre** — `page_reads(p_from timestamptz, p_to timestamptz)` — SECURITY DEFINER exécutable par `anon`, répond en GET avec les données session×path×dwell ; orpheline (consommée uniquement par les contract-tests)
- **Sévérité** — P1
- **Preuve** — curl 02/09 01:29 : `GET /rest/v1/rpc/page_reads?p_from=…&p_to=…&select=path,dwell_s,retained` (clé anon) → HTTP 200 avec un row réel ; ACL `{=X/postgres,…anon=X…}` ; seul appelant = `run_rpc_contract_tests`.
- **Impact** — données comportementales de tout le site lisibles sans auth (pas de PII) ; surface d'API inutile.

### o-03 (zone h / f)
- **Titre** — Vue `cpi_capture_perdue` sans `security_invoker` et avec `GRANT SELECT` à anon/authenticated → lisible sans auth (advisor ERROR)
- **Sévérité** — P1
- **Preuve** — `pg_class.reloptions` = NULL (02/09 01:15) ; `role_table_grants` : anon:SELECT, authenticated:SELECT ; curl 01:29 : `GET /rest/v1/cpi_capture_perdue?select=path,grade&limit=1` → HTTP 200 ; advisor `security_definer_view` level ERROR.
- **Impact** — scores CPI / clics perdus par page = intelligence business exposée publiquement depuis le 28/07 (migration `20260728090355`).

### o-04 (zone h / i)
- **Titre** — `supabase/rpcs.sql` n'est plus le miroir de la prod : 2 fonctions différentes, 6 manquantes, 6 en trop ; édité à la main le 31/08
- **Sévérité** — P2
- **Preuve** — sha256 du dump prod `179ed9cc…` vs méta `a3d69c7d…` (02/09 01:22) ; corps différents : `cooked_alerts_refresh`, `raise_cooked_alert` ; manquantes : `alert_rule_freshness`, `alert_rule_gsc_ingest_missed`, `alert_rule_warn_escalation`, `conversions_leaderboard`, `cooked_weekly_conversions_snapshot`, `weekly_conversions_report` ; en trop : `alert_rule_{cpi_stale,dfs_stale,gbp_gap,gsc_gap,gsc_lag}`, `dashboard_check_stale` ; `supabase/rpcs.sql:10` « Généré le 10/08/2026 » vs `contracts/rpc_snapshot_meta.json` `generated_at 2026-08-31`.
- **Impact** — un agent qui lit `rpcs.sql` raisonne sur une dédup d'alertes et des règles qui n'existent plus (kinds remplacés le 23/08 par le registre `freshness_contract`).

### o-05 (zone h / i)
- **Titre** — Migrations : 1 migration prod sans aucun fichier miroir (`20260807224552_weekly_conversion_pages_routine`) + 54 fichiers locaux re-datés ; `check_schema_migrations.py` ne compare jamais à la prod en CI
- **Sévérité** — P2
- **Preuve** — `schema_migrations` : 212 versions ; `ls supabase/migrations` : 162 ; `comm` : 104 versions prod sans fichier au même timestamp, 54 fichiers absents de prod ; `20260807224552` sans équivalent même renommé ; `check_schema_migrations.py:33-40` (`if not db_url: … return 0`) ; `sql-contracts.yml` sans `DATABASE_URL`.
- **Impact** — table `conversion_weekly` (705 lignes), 3 fonctions et une routine hebdo existent en prod et nulle part dans le repo ni les docs ; `supabase db push` ne les recrée pas.

---

# PARTIE 2 — VERDICTS

```
ID        h-01
Verdict   CONFIRMÉ (P0 tenu) — avec deux justifications secondaires fausses et un écart de PÉRIMÈTRE
```
**Ma preuve.** Requête `pg_proc` / `has_function_privilege` ré-exécutée le **02/09/2026 à 15:03 Paris** :

| proname | prosecdef | owner | proacl | anon_x |
|---|---|---|---|---|
| rpc_contract_check | true | postgres | `{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}` | true |

Corps relu par moi via `pg_get_functiondef` (15:04 Paris) — la ligne décisive est bien
`EXECUTE p_sql INTO v_rows;`, en `LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_catalog'`,
sans aucun garde-fou lecture seule.

Cause racine ré-exécutée (15:05 Paris) — `pg_default_acl` filtré sur `defaclobjtype='f'` et `nspname='public'` :
```
grantor=postgres        acl={postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
grantor=supabase_admin  acl={postgres=X/supabase_admin,anon=X/supabase_admin,authenticated=X/supabase_admin,service_role=X/supabase_admin}
```
Ces deux lignes ne contiennent PAS d'entrée PUBLIC ; l'entrée `=X/postgres` observée sur la fonction vient
donc bien de `acldefault('f', owner)`. La mécanique à deux sources décrite par le constat est exacte.

Fichier relu par moi : `supabase/migrations/20260728102500_rpc_contract_check_helper.sql` —
`grep -nE "REVOKE|GRANT"` → **aucune ligne**. Idem pour `supabase/migrations/20260728002000_page_reads_module.sql`
(le jumeau o-02) → aucune ligne. Règle écrite : `SECURITY.md:38` « **RPC Postgres** : `REVOKE` public/anon/authenticated ».
Discipline manuelle : `ls supabase/migrations/*.sql | wc -l` → **162**, `grep -rl "REVOKE" supabase/migrations/ | wc -l` → **64**.

**Écart.** Trois, dont deux qui affaiblissent le raisonnement sans sauver le constat, et un qui le corrige :

1. **`pg_net` n'est PAS dans `public`.** Ma requête (15:05 Paris) place `http_post`, `http_get`, `http_delete`,
   `http_collect_response` dans le schéma **`net`**, pas `public` — l'argument « `search_path=public` donc
   `net.http_post` est atteignable » est faux. Il est sans conséquence : `p_sql` est du texte libre, l'attaquant
   qualifie `net.http_post(...)` lui-même. Pire pour la posture générale : `has_function_privilege('anon', …)`
   = **true** sur `net.http_post` — `anon` peut appeler la sortie réseau **directement**, sans passer par
   `rpc_contract_check`.
2. **Pas de canal de lecture directe.** La fonction est `RETURNS void` : `p_sql` doit rendre une valeur
   castable en `bigint`, et le résultat n'est jamais renvoyé à l'appelant. Le message d'erreur part dans
   `rpc_health.detail`, mais `pg_class.relacl` de `rpc_health` (15:05 Paris) = `{postgres=arwdDxtm/postgres,
   anon=awdDxtm/postgres, authenticated=awdDxtm/postgres, service_role=arwdDxtm/postgres}` — **anon n'a pas
   `r` (SELECT)**. L'exfiltration n'est donc pas un « lire `crm_prospects` d'un appel » : elle passe par
   `net.http_post` (canal hors-bande) ou par de l'inférence booléenne. L'écriture et la suppression, elles,
   sont bien immédiates et sans obstacle — et `anon` a en prime `awd` sur `rpc_health`, donc peut falsifier
   le journal de santé du harnais de contrat.
3. **Périmètre : 2 fonctions, pas un schéma ouvert.** Mon décompte (15:06 Paris) sur les 120 fonctions de
   `public` : **21** exécutables par `anon`, dont **2 seulement** en SECURITY DEFINER — `rpc_contract_check`
   et `page_reads(timestamptz,timestamptz)`. Les 19 autres sont des helpers purs (`canonical_path`,
   `paris_date`, `unaccent`…) sans accès privilégié. La discipline `REVOKE` a donc tenu sur 118 objets /120 ;
   le cadrage « default privileges = trou structurel » est juste sur la CAUSE, mais l'AMPLEUR annoncée
   (« toute fonction neuve naît ouverte ») ne s'est matérialisée que deux fois, les deux le 28/07/2026,
   dans deux migrations écrites le même jour. Cela ne change pas la sévérité P0 de l'objet
   `rpc_contract_check` : un seul exécuteur de SQL arbitraire suffit.

**Invariant.** **Tient**, et le constat a raison de corriger le brief : le volet 1 seul est insuffisant,
puisque la source (b) est un `GRANT` explicite en double. Deux précisions issues de mes mesures :
le volet 1 doit couvrir `net.*` aussi (anon y a EXECUTE, indépendamment des fonctions de `public`) ;
et le volet 2 doit ajouter les **tables** (anon détient `awd` sur `rpc_health` — un objet écrivable
sans auth que ni le constat ni le brief ne mentionnent). Le volet 3 (supprimer le paramètre `p_sql`)
est le seul des trois qui ferme le trou définitivement plutôt que de le refermer par convention.

---
```
ID        h-02
Verdict   CONFIRMÉ — mécanisme reproduit à l'identique ; un chiffre de dénombrement à corriger
```
**Ma preuve.** Corps prod relu via `pg_get_functiondef` le **02/09/2026 à 15:07 Paris** — la fenêtre est bien
fixe et absolue :
```sql
SELECT count(*) INTO v_n FROM public.events WHERE received_at > now() - interval '60 minutes';
IF v_n = 0 THEN RETURN QUERY SELECT 'pipeline_dead','critical', …
```
(lecture sur `events` brut assumée : c'est la table que la règle interroge elle-même — diagnostic d'ingestion.)

Cadence relue par moi dans `cron.job` (15:08 Paris) : jobid **5**, `cooked-alerts-hourly`, `15 * * * *`,
`SET statement_timeout='300s'; SELECT public.cooked_alerts_refresh();`.

Trous ré-mesurés par moi sur 30 j (`lead()` sur `received_at`, 15:07 Paris), avec pour chacun le nombre de
ticks `:15` capables de déclencher, c'est-à-dire les ticks `t ∈ [début+60 min, fin[` :

| début (Paris) | fin (Paris) | durée | ticks déclencheurs |
|---|---|---|---|
| 10/08/2026 02:05 | 10/08/2026 03:14 | 68,9 min | **0** |
| 22/08/2026 03:12 | 22/08/2026 04:16 | 63,3 min | **1** |
| 28/08/2026 05:41 | 28/08/2026 06:37 | 56,0 min | 0 |
| 07/08/2026 06:53 | 07/08/2026 07:48 | 54,5 min | 0 |

La démonstration tient exactement : le trou **le plus long** des 30 jours n'a rien déclenché, le deuxième
plus long a déclenché. Recoupement dans `alerts` (15:08 Paris) : un seul `pipeline_dead` sur 30 j,
**22/08/2026 04:15**, severity critical, non acquittée, detail « Aucun event reçu depuis 60 min… » —
il correspond au tick de 04:15 tombé dans `[04:12, 04:16[`, alors que le trafic est reparti seul à 04:16.

**Écart.** Un seul, sur un dénombrement : le constat annonce « 15 trous ≥ 40 min sur 30 j » ;
ma requête en trouve **22** (dont 2 ≥ 60 min — ce chiffre-là est exact). L'écart va dans le sens
de l'aggravation. Précision utile que le constat ne fait pas : sur ces 22 trous, **21 sont nocturnes**
(01h–07h Paris) et un seul est en soirée (16/08 19:46→20:29) — donc le régime normal du site produit
bien des creux d'une heure la nuit, ce qui condamne définitivement un seuil absolu.

**Preuve additionnelle qui renforce l'angle mort** (la mienne, absente du constat) : j'ai vérifié si un
autre filet rattrape une panne courte. `freshness_contract` (13 sources, 15:32 Paris) **ne contient
aucune entrée pour `events` ni pour les pageviews**. Les deux entrées les plus proches sont
`cta_phone_click` et `form_submit`, toutes deux en `warn_after_days = 2`. Autrement dit : sous 48 heures
de panne, `alert_rule_pipeline_dead` est le **seul** détecteur, et il est aveugle sous 2 h.
L'angle mort n'est donc couvert par rien entre 0 et 48 h.

**Invariant.** **Tient**, et la deuxième branche proposée (mesurer `now() - max(received_at)`) est la bonne :
elle est continue, sans phase, et son coût est nul. La première branche (médiane de la même heure sur 7 j)
tient aussi mais est superflue si l'âge est mesuré à un pas plus fin que la fenêtre. Le test de
non-régression proposé est réellement discriminant : rejoué sur mes 22 trous, il rejette la règle actuelle
(elle déclenche sur un trou nocturne de 63 min et rate un trou nocturne de 69 min).

---
```
ID        h-03
Verdict   CONFIRMÉ — inertie des deux gates vérifiée ligne à ligne, dérive re-mesurée par moi
```
**Ma preuve — inertie.** Fichiers relus par moi le **02/09/2026 à 15:20 Paris** :

- `scripts/check_rpcs_sql_fresh.py:41` `def changed_migration_files()` → la liste vient bien de
  `git_diff_paths("HEAD~1 HEAD")` (push) ou `origin/<base>...HEAD` (PR).
- `scripts/check_rpcs_sql_fresh.py:71` → `print("Arch #5 OK — aucune migration modifiée"); return 0`.
  Une migration appliquée en prod sans fichier commité ne modifie aucun chemin sous `supabase/migrations/`
  → sortie 0 sans le moindre contrôle. C'est exactement le mode opératoire du projet.
- `scripts/check_rpcs_sql_fresh.py:25` → `MARKER = re.compile(r"^-- ═══ public\.(\w+)\(", re.MULTILINE)` :
  le contrôle de fraîcheur se réduit à la présence d'un **marqueur textuel** et au fait que
  `supabase/rpcs.sql` figure dans le diff. Aucun hash, aucune connexion prod.
- `scripts/check_schema_migrations.py:41-43` →
  `db_url = os.environ.get("DATABASE_URL","").strip()` puis
  `if not db_url: print(f"Arch #10 OK — {len(versions)} migration(s) locales, versions uniques (pas de DATABASE_URL)"); return 0`.
- `.github/workflows/sql-contracts.yml` : `grep -n "env:|DATABASE_URL|schedule"` → **aucune occurrence**.
  Les steps sont `python3 scripts/check_migration_paris_date.py` (:36), `check_rpcs_sql_fresh.py` (:45),
  `check_dashboard_contracts.py` (:52), `check_schema_migrations.py` (:59) — aucun bloc `env:`, aucun
  déclencheur `schedule`. `DATABASE_URL` n'est donc jamais défini : la branche de comparaison prod est
  du code mort en CI. `scripts/generate_rpcs_sql.py:102` exige la même variable.

**Ma preuve — dérive re-mesurée (le constat la reprenait de la baseline).**
`SELECT count(*) FROM supabase_migrations.schema_migrations` (15:17 Paris) → **212**.
`ls supabase/migrations/*.sql | wc -l` → **162**. Diff des jeux de timestamps (Python, 15:19 Paris) :
**104** versions prod sans fichier de même timestamp, **54** fichiers absents de prod,
`20260807224552` **présent en prod, absent en local**. Côté `rpcs.sql`, sha256 recalculé sur la prod :
`179ed9cc…` ≠ méta `a3d69c7d…` (détail en o-04). Les deux chiffres du constat sont donc exacts,
et je les ai obtenus indépendamment.

**Écart.** Aucun sur le fond. Une nuance de formulation : le constat écrit « 1 migration prod sans AUCUN
miroir » — c'est vrai au sens du contenu (`grep -rl "conversion_weekly\|weekly_conversion"` dans
`supabase/migrations/` et `docs/` ne renvoie que les fichiers de la mission d'audit en cours), mais
104 versions prod n'ont pas de fichier de même timestamp : la majorité sont des re-datages, une seule
est une disparition de contenu. Le constat le dit correctement ; je le confirme.

**Invariant.** **Tient**, à une condition que le constat identifie lui-même et qu'il faut lire comme
bloquante : sans secret de connexion lecture seule en CI, les deux premières branches sont irréalisables
et les scripts continueront d'imprimer « OK ». La troisième branche (comparaison en alerte SQL horaire,
kind `repair_drift`) est la seule qui soit exécutable **aujourd'hui** avec l'outillage existant — c'est
elle qu'il faut retenir en priorité, pas la CI. Le gate actuel, lui, est décoratif au sens strict :
il vérifie une corrélation dans le diff Git là où la vérité vit en prod.

---
```
ID        h-04
Verdict   CONFIRMÉ — au chiffre près, et légèrement sous-estimé
```
**Ma preuve.** Corps prod relus par moi (`pg_get_functiondef`, **02/09/2026 15:09 Paris**) :

- `alert_rule_warn_escalation` : re-émet un `critical` pour tout kind dont un warn existe dans la fenêtre
  `[now()-6j, now()-5j]`, s'il n'y a **ni** critical `> now() - interval '26 hours'` **ni** alerte acquittée
  sur 5 j. **Aucun compteur d'épisodes, aucune borne de répétition** — le cycle recommence indéfiniment.
- `raise_cooked_alert` : dédup `(kind, severity)` sur 24 h ; puis
  `if p_sev = 'critical' and coalesce(v_last_acked,false) = false then … perform net.http_post(url := 'https://ntfy.sh/', … 'priority', 5 …)`.
  Le topic est lu depuis `cooked_config` (**valeur non lue par moi**).

Table `alerts` sur 30 j, requête à moi (15:10 Paris) — identique au constat ligne à ligne :
cpi_drop critical **9** (23/08 23:15 → 01/09 20:15, **0 ackée**) ; cpi_drop warn 30 (7 ackées) ;
gbp_daily_stale critical 1 + warn 6 ; gbp_gap critical 1 + warn 8 ; gsc_ingest_missed warn 3 ;
pipeline_dead critical 1. **12 criticals sur 30 j.**

**Preuve que le constat ne fournissait pas, et qui tranche la cause** : j'ai listé les 12 criticals avec
leur `detail` (15:11 Paris). **10 sur 12 commencent par « Escalade : warn actif depuis ≥ 5 jours »** —
les 9 `cpi_drop` **et** le `gbp_daily_stale` du 02/09 01:15. Leur cadence est un métronome :
23/08 23:15 → 25/08 02:15 → 26/08 04:15 → 27/08 07:15 → 28/08 09:15 → 29/08 12:15 → 30/08 15:15 →
31/08 18:15 → 01/09 20:15, soit un pas de ~26-27 h. C'est bien l'escalade générique, et non la règle
`cpi_drop` recalibrée au Sprint 39, qui produit le bruit — le constat l'affirmait, je le prouve.

Second flux, vérifié par moi (`gh run list`, 15:13 Paris) : GBP Daily Ingest a échoué les **24, 25, 26,
27, 28, 29, 30, 31/08, 01/09 et 02/09** = **10 échecs consécutifs** ; sur 30 j, **22 échecs sur 25 runs**.
Le push est effectif : sur le run du 02/09 (id 33616034547), `gh run view --json jobs` donne
`Run ingest => failure` puis **`notify-failure => success`**, et le step (`.github/workflows/gbp-daily-ingest.yml`,
lignes 84-96 relues par moi) fait un `curl` vers `https://ntfy.sh/${{ secrets.NTFY_TOPIC }}` avec
`Priority: high`. Aucun autre workflow ne pollue : GSC 1 échec/24, SQL contracts 1/6, DFS 0/3, Dashboard 0/2.

**Écart.** Deux, tous deux **aggravants** : (i) l'escalade a une condition supplémentaire que le constat
omet — `count(warn sur 5 j) >= 4` — sans effet sur la répétition non bornée ; (ii) le constat compte
9 échecs CI et « ~21 notifications en 10 jours » : au 02/09 c'est **10** échecs consécutifs et
**10 criticals d'escalade**, soit ≥ 20 pushs sur 11 jours en ne comptant que les runs quotidiens,
davantage si l'on inclut les relances (22 échecs sur 30 j pour 25 runs). Le chiffre du titre (« ~19 »)
est donc un plancher.

**Invariant.** **Tient**, avec une hiérarchie que je précise : la borne d'escalade (branche 1) est le
correctif à effet immédiat — elle éteint 10 des 12 criticals. La séparation des kinds (branche 2) est
juste mais secondaire. La branche 3 (rendre l'ack atteignable) est la seule qui traite la cause
structurelle : la condition de push est `v_last_acked = false`, donc **un seul ack suffit à éteindre
un kind** — le stock d'alertes non acquittées n'est pas un symptôme, c'est le carburant. La branche 4
(mesure de contrôle) est décorative tant que personne ne la regarde : elle n'empêche aucune récidive,
elle la constate.

---
```
ID        h-05
Verdict   PARTIEL — le défaut d'observabilité est réel et je le prouve plus durement que le constat ;
          mais le titre, la sévérité et la cause annoncée (« 90 % du budget », « la marge se referme »)
          sont FAUX au présent : la tendance est descendante depuis le 17/08/2026.
```
**Ce qui tient — et que je durcis.** Corps prod de `cooked_refresh_after_gsc` analysé par moi
(**02/09/2026 15:33 Paris**) : sur 4 154 caractères, **0 occurrence** de `clock_timestamp|duration|duree|elapsed`,
**1 seul `INSERT INTO`**, cible `public.cooked_config`. Aucune ventilation de durée n'est écrite nulle part.
`cooked_config` (15:15 Paris) ne contient que **4 clés** : `events_vacuum_full_scheduled` (maj 25/07/2026 23:50),
`expected_tracker_version` (maj 02/07/2026 19:22), `last_full_refresh_after_gsc_at`
(valeur 02/09/2026 13:00 Paris, maj 02/09/2026 13:00) et `ntfy_topic` (valeur **non lue**).
`last_full_refresh_after_gsc_at` est bien un horodatage de fin de séquence. **Le constat a raison :
il n'existe aucune trace de durée par étape.**

**Ce qui ne tient pas — la mesure.** J'ai ré-interrogé `cron.job_run_details` pour le jobid 46 sur 30 j
(15:14 Paris) : **390 runs, 0 échec**, 30 runs > 20 min, max **2 166 s**. Jusque-là le constat est exact.
Mais j'ai ensuite sorti la **série**, ce qu'il n'a pas fait :

| jour | durée | % du budget 2 400 s |
|---|---|---|
| 04/08 | 2 017 s | 84,0 % |
| **05/08** | **2 166 s** | **90,2 %** ← le pic cité |
| 07/08 | 2 110 s | 87,9 % |
| 10/08 | 1 891 s | 78,8 % |
| 13/08 | 1 971 s | 82,1 % |
| 17/08 | 1 543 s | 64,3 % ← rupture |
| 20/08 | 1 333 s | 55,6 % |
| 25/08 | 1 619 s | 67,5 % |
| 01/09 | 1 596 s | 66,5 % |
| **02/09** | **1 621 s** | **67,6 %** |

Le pic de 90,2 % date du **05/08/2026, il y a 28 jours**. Une rupture de régime s'est produite autour du
17/08 et la série est depuis **stable entre 55,6 % et 71,8 %**, sans jamais dépasser 72 % sur les
16 derniers jours. Le titre « tourne à 90 % de son budget » décrit un état révolu, et la sévérité —
justifiée par « la marge se referme avec la croissance des données » — est **contredite par la
direction même de la série**, qui est descendante d'environ 25 points en un mois. C'est précisément le
piège que la règle absolue de CLAUDE.md vise : un agrégat (le max sur 30 j) lu comme un état courant,
sans décomposition par jour.

**Second point faux : les « budgets par étape ».** Le constat écrit « cpi 600 s + dashboard 600 s +
expertises 600 s + assisted 300 s = 2 100 s, sous le plafond global », en signalant lui-même ne pas
l'avoir revérifié. Ma recherche dans le corps prod (15:34 Paris) ne trouve **ni `set_config(...)` ni
`SET LOCAL`** : il n'y a **aucun budget par étape** dans la fonction, seulement le plafond global de
2 400 s posé dans la commande cron. Les quatre budgets cités sont ceux des anciens jobs autonomes —
c'est-à-dire les **jobs fantômes de h-06**, dont le travail a été absorbé par le jobid 46. L'alerte
`refresh_step_failed_*` existe bien (le corps la lève via `PERFORM public.raise_cooked_alert`), mais
elle ne repose sur aucun minuteur d'étape.

**Écart (résumé).** Défaut d'observabilité : **confirmé et aggravé**. Chiffre du titre : **périmé de
28 jours**. Cause annoncée (« la marge se referme avec la croissance ») : **réfutée par la série**.
Sévérité : P2 → **P3** au vu de la marge courante (≈ 780 s de coussin, soit 48 %). Nuance de lecture
supplémentaire : la médiane des 390 runs est **0 s** — le job est un no-op 360 fois sur 390 et ne fait
un travail réel qu'une fois par jour ; parler d'un « budget consommé à 90 % » sans le dire donne une
image de saturation permanente qui n'existe pas.

**Invariant.** Branche 1 (une ligne de log par run × étape) : **tient**, c'est le seul correctif qui
répond au défaut réellement établi. Branche 2 (warn à 80 % du budget global) : **tient**, mais son
argument de vente est faux — elle n'aurait pas sonné « 28 jours avant que quiconque ne regarde », elle
aurait sonné du 04/08 au 15/08 puis se serait tue toute seule, ce qui en fait un détecteur de pic, pas
de tendance. Branche 3 (somme des budgets d'étape ≤ budget global) : **décorative** — il n'existe aucun
budget d'étape à sommer ; le test proposé porterait sur des constantes qui ne sont nulle part dans le code.

---
```
ID        h-06
Verdict   PARTIEL — le défaut existe (2 repair_hint sur 13 renvoient vers des jobs absents),
          mais « 5 jobs pg_cron » appartient à OPERATIONS.md, pas à la table ; sévérité surévaluée.
```
**Ma preuve.** `cron.job` ré-interrogé le **02/09/2026 à 15:08 Paris** — **9 jobs**, tous actifs :
`run_rpc_contract_tests` (30 3 * * *), `purge_old_events_monthly` (0 4 1 * *),
`refresh_noise_filters_hourly` (5 * * * *), `cooked-alerts-hourly` (15 * * * *),
`refresh_seo_url_snapshot` (0 3 * * *), `cooked-purge-noise-weekly` (30 4 * * 0),
`refresh-identity-stitch` (40 3 * * *), `cooked-refresh-after-gsc` (0 8-20 * * *),
`math-refresh-snapshots-weekly` (10 5 * * 0). Aucun `cooked-cpi-daily-snapshot`, aucun `refresh-dashboard-*`,
aucun `dashboard-stale-check`.

J'ai ensuite croisé **automatiquement** les `repair_hint` avec `cron.job.jobname` (15:12 Paris) plutôt que
de les lire à l'œil. Résultat sur les 4 hints qui nomment un job :

| source | jeton de type nom-de-job sans job correspondant |
|---|---|
| `cpi_daily` | `cooked-cpi-daily-snapshot` |
| `dashboard_resources_snapshot` | `refresh-dashboard` (glob `refresh-dashboard-*`) |
| `math_visit_sequences_snapshot` | — (aucun) |
| `seo_url_snapshot` | — (aucun) |

Le défaut est donc réel : **2 hints sur 13 sources** dirigent l'opérateur vers un ordonnanceur où le job
n'existe pas. Registre créé le **23/08/2026 à 23:08 Paris** (`min(created_at)` sur les 13 lignes, 15:15 Paris),
soit le livrable « chantier 1 » — la consigne est née fausse.

**Écart.** Deux, tous deux **atténuants** :

1. **Le « 5 jobs » n'est pas dans la table.** Le registre ne nomme explicitement **qu'un seul** job absent
   (`cooked-cpi-daily-snapshot`) ; le second hint utilise un **glob** (`refresh-dashboard-*`). Les cinq noms
   énumérés par le constat viennent de `docs/OPERATIONS.md`, que j'ai relu : lignes **472, 474, 475, 477, 480**
   listent bien `refresh-dashboard-snapshots`, `refresh-dashboard-expertises`, `refresh-dashboard-assisted`,
   `cooked-cpi-daily-snapshot` et `dashboard-stale-check`. Ce sont deux artefacts distincts et le constat
   les fusionne. Or c'est précisément sur cette fusion que repose son argument aggravant (« cette fois la
   constante périmée est dans une TABLE, pas dans un Markdown ») : la table contient **une** constante
   fausse et un glob, le Markdown en contient cinq.
2. **Le second hint n'est pas un cul-de-sac.** Il nomme aussi `cooked-refresh-after-gsc`, qui **existe**
   (jobid 46) et qui est effectivement l'organe qui a absorbé le travail des jobs dashboard. Un opérateur
   qui suit ce hint arrive donc au bon endroit par sa seconde moitié. Seul le hint `cpi_daily` laisse
   réellement l'opérateur sans issue.

Compte tenu de ces deux points, la sévérité P2 est surévaluée : **P3 (hygiène de runbook)**, du même
ordre que h-08. Le fond — une consigne de réparation périmée récitée pendant l'incident — reste juste.

**Invariant.** Branche 1 (contrôle « tout nom de job cité existe dans `cron.job` ») : **tient**, et je l'ai
exécutée en une seule requête ci-dessus, ce qui prouve son coût nul ; à brancher en règle d'alerte plutôt
qu'en CI (la CI n'a pas d'accès prod — cf. h-03). Branche 2 (colonne `owner_job` en clé étrangère logique) :
**tient et est supérieure**, car elle rend l'erreur inécrivable au lieu de la rendre détectable ; sa limite
est qu'un hint peut légitimement citer plusieurs jobs (c'est le cas de `dashboard_resources_snapshot`), donc
la colonne doit être un tableau, pas un scalaire.

---
```
ID        h-07
Verdict   CONFIRMÉ — bloat reproduit et quantifié plus finement ; un chiffre secondaire volatile diffère
```
**Ma preuve.** `pg_stat_user_tables` + `pg_stat_user_indexes`, requêtes à moi du **02/09/2026 à 15:35 Paris** :

| relation | vivants | morts | % morts | n_tup_upd | n_tup_del | autovacuums | dernier autovacuum | heap+toast | index |
|---|---|---|---|---|---|---|---|---|---|
| `identity_stitch` | 122 133 | 0 | 0,0 % | 0 | 12 228 906 | 41 | 02/09 05:40 | **24 MB** | **124 MB** |
| `gsc_query_page_daily` | 1 178 389 | 137 809 | **11,7 %** | 3 158 817 | 0 | **1** | 17/08 08:45 | 198 MB | 273 MB |
| `gsc_query_daily` | 1 034 048 | 134 519 | **13,0 %** | 2 954 244 | 0 | 2 | 23/08 08:33 | 105 MB | 94 MB |
| `gsc_path_daily` | 151 505 | 16 570 | **10,9 %** | 548 137 | 0 | 2 | 22/08 08:32 | 24 MB | 45 MB |
| `ingest_drops` | 41 | 17 | 41,5 % | 1 098 428 | 0 | **16 762** | 02/09 15:31 | 104 kB | 16 kB |
| `events` (repère) | 1 105 889 | 1 180 | 0,1 % | 0 | 1 572 688 | 3 | 23/08 06:32 | 1 032 MB | 379 MB |

Détail des index de `identity_stitch` (15:35 Paris) — le constat ne donnait pas les définitions, qui sont
ce qui rend le verdict incontestable :
```
identity_stitch_pkey        81 MB   8 126 017 scans   UNIQUE btree (kind, key)
identity_stitch_visitor_idx 42 MB      90 959 scans   btree (visitor_key)
```
Un btree unique sur `(kind, key)` — un discriminant court plus une clé de session — coûte de l'ordre de
60 octets par entrée ; pour 122 133 lignes cela donne **~7 MB attendus contre 81 MB observés, soit ~11×**.
Même ordre pour `visitor_key` (~5 MB attendus, 42 MB observés). Le bloat n'est donc pas une hypothèse
tirée d'un ratio : il est établi par comparaison à la taille théorique de la clé. L'estimation de
~110 MB récupérables du constat est correcte (je trouve ~112 MB).

Le mécanisme est confirmé par les compteurs : `n_tup_del = 12 228 906` pour une table de 122 133 lignes
= **~100 cycles de vidage/réinsertion complets**, cohérents avec `refresh_identity_stitch(90)` (cron jobid 42,
`40 3 * * *`, vérifié dans ma lecture de `cron.job`). `n_dead_tup = 0` et 41 autovacuums récents confirment
que VACUUM passe : il récupère l'espace du heap mais ne compacte pas les pages btree — d'où un index en
régime permanent à moitié vide, et un surcoût payé sur les 8,13 M de scans de la clé primaire.

**Écart.** Un seul, sur un compteur volatile : le constat donne `ingest_drops` à 41 vivants / **71 morts
(173 %)** ; je mesure **17 morts (41,5 %)** à 15:35, avec un autovacuum passé à 15:31 — l'écart est
l'oscillation normale d'une ligne chaude entre deux passages du démon, pas une erreur. Le fait saillant
est identique et je le confirme : **16 762 autovacuums** sur une table de 104 kB, soit un worker mobilisé
toutes les deux à trois minutes, pendant que `gsc_query_page_daily` (198 MB de heap, 137 809 tuples morts)
n'a été autovacuumée **qu'une seule fois**, le 17/08. Les autres chiffres du constat sont reproduits à
la dérive naturelle près (137 809 vs 132 411 morts, etc. : la journée a avancé).

**Invariant.** Branche 1 (`alert_rule_bloat`) : **tient** — le canal (`alerts` + cron horaire) existe déjà,
le seuil doit porter sur le **ratio index/heap** plutôt que sur `n_dead_tup`, car `identity_stitch` affiche
`n_dead_tup = 0` et serait invisible à un seuil de tuples morts. Branche 2 (`autovacuum_vacuum_scale_factor`
par table) : **tient**, c'est le réglage standard pour une table upsertée en masse. Branche 3 (rafraîchissement
différentiel de `identity_stitch`) : **tient**, et c'est la seule qui supprime la cause ; un REINDEX
périodique traiterait le symptôme sans empêcher sa reformation nocturne.

---
```
ID        h-08
Verdict   CONFIRMÉ — et je ferme les deux trous de preuve que le constat déclarait ouverts ;
          le volet (b) était sous-estimé de moitié.
```
**(a) Vestige — confirmé.** `cooked_config` relu par moi (**02/09/2026 15:15 Paris**) : clé
`events_vacuum_full_scheduled`, valeur « 26/07/2026 04:00 Paris », `updated_at` **25/07/2026 23:50**.
`cron.job` (15:08 Paris) ne contient aucun job `oneshot-*` — rien ne traîne côté ordonnanceur. La clé
annonce une opération passée, et désarmée depuis par `20260810093206_rangement_post_pivot_secib`.

**(b) Contrats non câblés — confirmé, et le chiffre est un plancher.** Le constat annonce 4 fichiers ;
j'en compte **8** dans `scripts/*.sql` (15:29 Paris) : `c2_alerts_contract`, `canonical_path_contract`,
`cooked_events_window_contract`, `cpi_validation_j28`, `test_refresh_dashboard_rolling28`,
`test_refresh_expertises_rolling28`, `validate_gsc_is_branded`, `validate_period_bounds_live_j1`.
J'ai vérifié chacun contre `.github/workflows/` :

- `cooked_events_window_contract` ressort dans `sql-contracts.yml` — mais aux **lignes 5-6**, dans un
  **commentaire** : « (Le contrat cooked_events_window … est un contrat MANUEL, exécuté hors CI …) ».
- `canonical_path_contract` ressort dans `canonical-path-contract.yml` — mais le workflow exécute
  `python3 -m pytest tests/test_canonical_path_contract.py` (ligne 35) et référence
  `tests/test_canonical_path_contract.py` (ligne 13) : c'est un **test Python homonyme**, pas le fichier
  `scripts/canonical_path_contract.sql`.
- Les six autres : **aucun workflow**.

Conclusion corrigée : **0 des 8 contrats SQL de `scripts/` n'est exécuté par un workflow**, et la seule
occurrence de `.sql` dans les workflows est `supabase/rpcs.sql` en filtre de `paths`. Le point du constat
sur `c2_alerts_contract.sql` — le contrat du sous-système d'alertes, celui-là même dont ce rapport
démontre les défauts, n'est joué nulle part — tient intégralement.

**(c) `updated_at` non maintenu — confirmé, et je remplace la déduction par une preuve.** Le constat
signalait deux trous : la conclusion « la valeur a changé sans bump » était une déduction, et l'absence
de déclencheur n'avait pas été vérifiée. Je ferme les deux.

- **Preuve directe du changement sans bump** : le fichier `supabase/migrations/20260713000733_expected_tracker_version_sprint41.sql`,
  que j'ai relu intégralement (15:24 Paris), contient exactement :
  ```sql
  UPDATE public.cooked_config
  SET value = 'sprint41'
  WHERE key = 'expected_tracker_version';
  ```
  Aucune mise à jour de `updated_at`. Alors que la migration de création
  (`20260702122347_cooked_config_and_ingestion_alerts.sql:14`) prenait bien soin de l'écrire :
  `on conflict (key) do update set value = excluded.value, updated_at = now();`. Ce n'est donc plus une
  déduction à partir des dates de déploiement : c'est le `UPDATE` fautif, daté, dans le repo.
- **Absence de déclencheur vérifiée** : `pg_trigger` joint à `pg_class` sur `public.cooked_config`,
  `NOT tgisinternal` (15:26 Paris) → **aucune ligne**. Rien ne garantit la colonne.
- **Mécanisme de la grâce relu par moi** dans `alert_rule_tracker_drift` (15:26 Paris) :
  `IF v_majv IS NOT NULL AND v_majv IS DISTINCT FROM v_expected AND (now() - v_expected_since) > interval '48 hours'`
  avec `v_expected_since` = `updated_at`. Le délai de grâce est donc bien annulé de façon permanente.
- Contre-exemple confirmant que la colonne EST maintenue ailleurs : `last_full_refresh_after_gsc_at`
  affiche `updated_at` = 02/09/2026 13:00 Paris. Le maintien dépend de chaque écrivain, exactement comme
  le dit le constat.

**Écart.** Un seul, **aggravant** : (b) porte sur 8 fichiers et non 4, dont zéro câblé — le constat compte
moins de la moitié du problème et attribue à tort une exécution CI au contrat `canonical_path`.
Sévérité P3 : **appropriée** pour (a), mais (c) mérite d'être remontée — c'est un piège armé dont
la date de déclenchement est connue (le prochain déploiement de tracker).

**Invariant.** Branche (a) : **tient**, sans urgence. Branche (b) : **tient**, et la formulation
« soit câbler, soit supprimer » est la bonne — mais le câblage suppose l'accès lecture de h-03, donc
la suppression est la seule option actionnable aujourd'hui. Branche (c) : **tient et est la seule
non décorative des trois** — un déclencheur `BEFORE UPDATE` est exactement la forme qui résiste au mode
d'écriture réel de cette table (un `UPDATE` nu dans une migration, comme celui de 20260713000733 que
j'ai relu). Une consigne écrite n'aurait rien empêché : la règle existait déjà implicitement et la
migration du 13/07 l'a enfreinte.

---
```
ID        o-02
Verdict   CONFIRMÉ — reproduit par mon propre appel HTTP
```
**Ma preuve.** ACL et signature ré-interrogées le **02/09/2026 à 15:03 Paris** : `public.page_reads` existe
en **deux surcharges**, et c'est bien celle à deux `timestamptz` qui est `prosecdef = true`, owner postgres,
`proacl = {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`,
`has_function_privilege('anon', …, 'EXECUTE') = true`. La surcharge `page_reads(p_days integer)` est
exposée à `anon` elle aussi, mais **non** SECURITY DEFINER.

Mon `curl` en GET, clé anon publiable, en-tête `Range: 0-0`, **02/09/2026 à 15:04 Paris** :
```
GET /rest/v1/rpc/page_reads?p_from=2026-09-01T10:00:00Z&p_to=2026-09-01T11:00:00Z&select=path,dwell_s,retained
→ HTTP 200
[{"path":"/indemnisation-des-victimes/droit-et-accidents-du-travail","dwell_s":136,"retained":true}]
```
Lecture confirmée sans authentification. Comportemental, aucune PII.

**Écart.** Aucun sur le fond. Deux précisions : la fonction est SECURITY DEFINER **et** `STABLE`, ce qui
est la raison pour laquelle PostgREST accepte le **GET** (les fonctions volatiles n'y répondent qu'en POST) —
c'est ce qui rend l'endpoint trivialement testable depuis un navigateur, sans même un client HTTP.
Et le fichier qui la crée, `supabase/migrations/20260728002000_page_reads_module.sql`, ne contient
**aucune ligne REVOKE/GRANT** (grep à moi, 15:29 Paris) : c'est le même oubli que h-01, le même jour.

**Invariant.** **Tient.** La dépréciation proposée est le bon geste : la fonction est orpheline (son
consommateur `content_performance_via_page_reads` a été reverté par `20260728104500`, présent dans le repo),
donc supprimer coûte moins que révoquer. Un `REVOKE` seul laisserait un objet inutile dont la prochaine
redéfinition ré-hériterait des default privileges de h-01.

---
```
ID        o-03
Verdict   CONFIRMÉ — et sous-estimé : anon n'a pas SELECT, il a TOUS les droits sur la vue
```
**Ma preuve.** Requête à moi sur `pg_class` croisée avec `has_table_privilege`, **02/09/2026 15:06 Paris**,
balayant **toutes** les vues et vues matérialisées de `public` : une seule vue est lisible par `anon` sans
`security_invoker = true` —
```
cpi_capture_perdue | reloptions = (aucune) | owner = postgres
```
Le périmètre du constat est donc exact au singulier : c'est la **seule** vue dans ce cas sur tout le schéma.

Mon `curl` en GET, clé anon, **02/09/2026 à 15:04 Paris** :
```
GET /rest/v1/cpi_capture_perdue?select=path,grade&limit=1
→ HTTP 200
[{"path":"/","grade":"A"}]
```

**Écart.** Un, **aggravant**. Le constat lit `role_table_grants` et conclut « anon:SELECT, authenticated:SELECT ».
La `relacl` réelle (15:05 Paris) est :
```
{postgres=arwdDxtm/postgres, anon=arwdDxtm/postgres, authenticated=arwdDxtm/postgres, service_role=arwdDxtm/postgres}
```
`anon` détient **a, r, w, d, D, x, t, m** — soit INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES,
TRIGGER et MAINTAIN, pas seulement SELECT. La vue agrège (donc n'est pas auto-modifiable et les écritures
échoueraient en pratique), mais le **grant** posé est un `ALL`, pas un `SELECT` : la migration fautive a
accordé bien plus que ce que le constat rapporte, et c'est le même symptôme que `rpc_health` en h-01.
Sévérité P1 : maintenue.

**Invariant.** **Tient.** La règle proposée (`WITH (security_invoker = true)` + `REVOKE ALL FROM anon,
authenticated` à toute `CREATE VIEW`) couvre bien les deux moitiés du défaut. À une condition : le test
de contrôle doit être écrit comme je l'ai écrit — un balayage de **toutes** les vues avec
`has_table_privilege('anon', …)`, et non une allowlist de noms —, sinon il ne verra pas la prochaine vue.
Sous cette forme il est exécutable en une requête et son coût est nul.

---
```
ID        o-04
Verdict   CONFIRMÉ — sha256 recalculé par moi sur la prod, diff des noms reproduit à l'identique
```
**Ma preuve.** J'ai relu le générateur pour reproduire **exactement** son périmètre
(`scripts/generate_rpcs_sql.py`, `DUMP_SQL` : `pg_get_functiondef` de toutes les routines de `public`,
`prokind IN ('f','p')`, triées par nom puis arguments, jointes par `\n\n`, chacune précédée du marqueur
`-- ═══ public.<nom>(<args>) ═══`). J'ai ensuite exécuté ce dump en prod et haché le résultat côté
serveur, le **02/09/2026 à 15:09 Paris** :
```
function_count_prod  = 122
content_sha256_prod  = 179ed9cc379c8235a239c0a00bdf3e5edce607dec86d59f395b5e5d837758427
```
contre `contracts/rpc_snapshot_meta.json` (relu par moi) :
```
"generated_at": "2026-08-31", "function_count": 122,
"content_sha256": "a3d69c7d06a3889491777758547db92005ff696a7a4fc912363e26827dd2b4de"
```
Les hachages diffèrent alors que le **compte est identique (122)** — c'est-à-dire le cas exact où un
contrôle par comptage passerait et où seul un contrôle par contenu échoue.

Diff des noms, fait par moi (marqueurs extraits de `supabase/rpcs.sql` par `grep -oE '^-- ═══ public\.[a-z0-9_]+\('`
vs noms distincts de la prod ; 118 de chaque côté ; 15:12 Paris) :

| en prod, absentes du fichier | dans le fichier, absentes de prod |
|---|---|
| `alert_rule_freshness` | `alert_rule_cpi_stale` |
| `alert_rule_gsc_ingest_missed` | `alert_rule_dfs_stale` |
| `alert_rule_warn_escalation` | `alert_rule_gbp_gap` |
| `conversions_leaderboard` | `alert_rule_gsc_gap` |
| `cooked_weekly_conversions_snapshot` | `alert_rule_gsc_lag` |
| `weekly_conversions_report` | `dashboard_check_stale` |

**6 et 6, noms pour noms identiques au constat.**

Preuve des **2 corps divergents**, faite en comparant les textes plutôt qu'en croyant les md5 :
- `raise_cooked_alert` — prod : `where kind = p_kind and severity = p_sev and created_at > now() - interval '24 hours'`
  (dédup par couple, avec le commentaire « et non plus par kind seul »). Fichier local : `where kind = p_kind`
  puis `and created_at > now() - interval '24 hours'`, **sans `severity`**. Le fichier décrit donc l'ancienne
  sémantique, celle où un warn bloque le critical du même kind pendant 24 h — l'inverse du comportement réel.
- `cooked_alerts_refresh` — le fichier appelle 12 règles dont **5 qui n'existent plus**
  (`alert_rule_cpi_stale`, `_dfs_stale`, `_gbp_gap`, `_gsc_gap`, `_gsc_lag`) et **n'appelle pas**
  `alert_rule_freshness`, `alert_rule_gsc_ingest_missed`, `alert_rule_warn_escalation` ni
  `alert_rule_page_taxonomy_gap`. L'impact annoncé par le constat est donc littéral : un agent qui lit
  `rpcs.sql` pour raisonner sur les alertes ne verra **pas** l'escalade — c'est-à-dire précisément
  le mécanisme responsable de 10 des 12 criticals de h-04.

**Écart.** Aucun. L'en-tête `supabase/rpcs.sql:10` dit bien « Généré le 10/08/2026 » alors que le méta
porte `2026-08-31` : les deux artefacts que le générateur écrit **ensemble** portent des dates différentes,
ce qui est la signature d'une édition manuelle.

**Invariant.** **Tient**, et c'est le bon contrôle : comparer le `content_sha256` recalculé en prod au méta.
Ma manipulation en est la démonstration — le hachage se calcule côté serveur en une requête, sans rapatrier
le dump. Réserve identique à h-03 : la branche « job CI » suppose un secret de connexion qui n'existe pas ;
la version alerte SQL horaire est immédiatement réalisable. Point à ajouter que le constat n'a pas : le
contrôle doit porter sur le hachage **et** la date d'en-tête, sinon une régénération partielle continuera
de produire deux artefacts désynchronisés.

---
```
ID        o-05
Verdict   CONFIRMÉ — chiffres re-mesurés par moi, à l'unité près
```
**Ma preuve.** `SELECT count(*) FROM supabase_migrations.schema_migrations` (**02/09/2026 15:17 Paris**)
→ **212**, dernière version `20260831090702`. `ls supabase/migrations/*.sql | wc -l` → **162**.
Diff des deux ensembles de timestamps, calculé par moi en Python (15:19 Paris) :
```
prod: 212   local: 162
prod sans fichier de meme timestamp: 104
fichiers absents de prod: 54
20260807224552 en prod: True | fichier local: False
```
Les quatre chiffres du constat sont exacts.

Objet orphelin vérifié dans la même requête (15:17 Paris) : `SELECT count(*) FROM public.conversion_weekly`
→ **705 lignes**. Et `grep -rl "conversion_weekly\|weekly_conversion" supabase/migrations/ docs/` (15:19 Paris)
ne renvoie **que** les trois fichiers de la mission d'audit en cours (`docs/mission-2026-09-02/journal.md`,
`annexes/routine_usage.md`, `00-baseline.md`) — **aucun** fichier de migration, **aucune** documentation
antérieure. La table, ses trois routines et sa routine hebdomadaire n'existent donc nulle part hors de la prod :
un `supabase db push` depuis le repo ne les recrée pas, et une restauration depuis le repo les perdrait.

Inertie du contrôle, relue par moi : `scripts/check_schema_migrations.py:41-43` — `db_url = os.environ.get("DATABASE_URL","").strip()`
puis sortie 0 avec le message « (pas de DATABASE_URL) » ; `.github/workflows/sql-contracts.yml` sans bloc
`env:` ni `schedule:` (cf. h-03). La seule chose que le script vérifie réellement en CI est l'**unicité**
des versions locales.

**Écart.** Aucun.

**Invariant.** **Tient** sur le principe, avec la même réserve bloquante que h-03 et o-04 : sans rôle
lecture seule accessible depuis GitHub Actions, le « CI quotidien » ne peut pas exister et le script
continuera d'imprimer « OK ». La seconde branche (« règle timestamp réel vérifiée automatiquement ») est
en revanche **décorative telle qu'écrite** : rien ne permet de distinguer, depuis le repo seul, un fichier
légitimement re-daté d'un fichier fabriqué après coup — c'est justement la comparaison à
`schema_migrations` qui fournit l'information, donc la seconde branche n'ajoute rien à la première et
n'existe pas sans elle.

---

# PARTIE 3 — SYNTHÈSE

**12 constats reçus, 12 recopiés, 12 testés.** Aucun n'est resté hors de portée.

| ID | Verdict | En une ligne |
|---|---|---|
| h-01 | **CONFIRMÉ** | SQL arbitraire en SECURITY DEFINER owner postgres ouvert à `anon` : ACL et corps revérifiés ; mais `pg_net` est dans `net` (pas `public`), `rpc_health` n'est pas lisible par anon, et seules **2** fonctions sur 120 sont concernées. |
| h-02 | **CONFIRMÉ** | Trous reproduits à l'identique (68,9 min → 0 tick ; 63,3 min → 1 tick) ; **22** trous ≥ 40 min sur 30 j et non 15 ; aucun autre filet ne couvre `events` sous 48 h. |
| h-03 | **CONFIRMÉ** | Les deux gates sortent « OK » sans rien vérifier (`return 0` avant tout contrôle, `DATABASE_URL` absent) ; dérive 212/162/104/54 re-mesurée par moi. |
| h-04 | **CONFIRMÉ** | 12 criticals/30 j dont **10 portent « Escalade : »** — la cause est bien l'escalade non bornée ; CI GBP à **10** échecs consécutifs, `notify-failure => success` vérifié. |
| h-05 | **PARTIEL** | Aucune trace de durée : confirmé et durci (0 mention de chrono, aucun budget d'étape dans le corps). Mais « 90 % du budget » date du **05/08** : la série est à **62-68 % depuis le 17/08**, tendance descendante — la cause annoncée est réfutée. |
| h-06 | **PARTIEL** | 2 `repair_hint` sur 13 pointent vers des jobs absents : réel. Mais les « 5 jobs » sont dans `OPERATIONS.md`, pas dans la table (1 nom + 1 glob), et le second hint cite aussi un job qui existe → P3, pas P2. |
| h-07 | **CONFIRMÉ** | `identity_stitch` : 24 MB de heap, **124 MB** d'index, pkey à 81 MB pour 122 133 lignes ≈ **11×** la taille théorique ; GSC à 10,9-13,0 % de morts ; `ingest_drops` à 16 762 autovacuums. |
| h-08 | **CONFIRMÉ** | (c) passe de déduction à **preuve** : `20260713000733` fait un `UPDATE` sans `updated_at`, et aucun trigger n'existe sur `cooked_config`. (b) sous-estimé : **8** contrats SQL, **0** exécuté par un workflow. |
| o-02 | **CONFIRMÉ** | Mon GET anon à 15:04 renvoie HTTP 200 avec un row réel ; la fonction est SECURITY DEFINER **et** STABLE, d'où la réponse en GET ; migration créatrice sans REVOKE. |
| o-03 | **CONFIRMÉ** | Mon GET anon à 15:04 renvoie HTTP 200 ; seule vue du schéma dans ce cas ; **aggravant** : `anon` détient `arwdDxtm` (ALL), pas seulement SELECT. |
| o-04 | **CONFIRMÉ** | sha256 prod recalculé par moi `179ed9cc…` ≠ méta `a3d69c7d…` à compte de fonctions **identique** (122) ; 6 manquantes / 6 en trop ; dédup locale sur `kind` seul vs `(kind, severity)` en prod. |
| o-05 | **CONFIRMÉ** | 212/162, 104 sans fichier, 54 re-datés, `20260807224552` absent du repo, `conversion_weekly` = 705 lignes introuvable hors prod. |

**Bilan : 10 CONFIRMÉ, 2 PARTIEL, 0 RÉFUTÉ.** Constats non testables : **aucun**.

**Les deux corrections qui changent une décision.**
1. **h-05** est le seul constat dont le chiffre porteur est périmé. Un lecteur pressé retiendrait « le
   refresh est à 90 % de son budget et la marge se referme » et arbitrerait un chantier de performance.
   La série quotidienne dit l'inverse : rupture à la baisse le 17/08, plateau à 62-68 % depuis 16 jours,
   coussin courant ≈ 780 s. Le défaut à corriger est l'**observabilité** (réellement absente), pas la marge.
   Le troisième volet de son invariant est décoratif : les « budgets d'étape » qu'il propose de sommer
   sont ceux des jobs fantômes de h-06 et n'existent plus dans le code.
2. **h-06** confond une table de production et un fichier Markdown, et c'est sur cette confusion que
   repose son argument d'aggravation. La table contient **une** constante fausse et un glob ; les cinq
   noms sont dans `OPERATIONS.md:472-480`.

**Deux objets que les constats n'ont pas vus, découverts en les vérifiant.**
- `anon` possède `awd` (INSERT/UPDATE/DELETE) sur **`rpc_health`** — la table où le harnais de contrat
  écrit son verdict de santé — et `arwdDxtm` (ALL) sur la vue `cpi_capture_perdue`. Le défaut de h-01/o-03
  n'est donc pas seulement un droit d'EXECUTE ou de SELECT de trop : des `GRANT ALL` ont été posés sur
  des **tables**, ce qu'aucun des deux invariants proposés ne couvre en l'état.
- `anon` a EXECUTE sur `net.http_post`, `net.http_get` et `net.http_delete` : la sortie réseau de la base
  est atteignable sans authentification, indépendamment de `rpc_contract_check`. Le volet 1 de l'invariant
  h-01 doit couvrir le schéma `net`, pas seulement `public`.

**Réserve transversale.** Trois invariants (h-03, o-04, o-05) reposent tous sur le même prérequis absent :
un secret de connexion lecture seule utilisable en CI. Tant qu'il n'existe pas, ces trois-là sont
inapplicables sous leur forme « job CI » et ne sont réalisables que sous leur forme « règle d'alerte SQL
horaire » — canal que le projet possède déjà et n'utilise pas pour ça.

**Limites de cette passe.** Lecture seule stricte : `rpc_contract_check` n'a jamais été appelé et son
exposition PostgREST reste établie par l'ACL, le corps et le jumeau vérifié en HTTP, non par exploitation
(une sonde POST à paramètre bidon, qui n'aurait pas atteint le corps, a été refusée par le garde-fou de
l'environnement). L'outil `get_advisors` a également été refusé : j'ai reconstruit la substance des lints
0028/0029 et `security_definer_view` par requêtes directes sur `pg_proc`, `pg_class` et
`has_table_privilege`, ce qui constitue une preuve plus forte qu'un libellé d'advisor. La réception
effective des pushs ntfy sur le téléphone de Nicolas reste invérifiable ; la valeur de `ntfy_topic`
n'a pas été lue. Le bloat de h-07 est établi par comparaison à la taille théorique des clés et par
l'historique de suppressions, non par `pgstattuple`.
