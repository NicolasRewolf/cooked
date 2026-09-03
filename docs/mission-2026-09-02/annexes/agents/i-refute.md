# Réfutation zone (i) — docs constantes/règles ↔ prod/code — mission Cooked 02/09/2026

9 constats reçus (i-01 à i-08 + o-12). Recopiés intégralement ci-dessous avant démolition,
conformément au brief.

## Constats reçus (recopie intégrale)

### i-01 — SECURITY.md (07/08) précède le pivot PII du 10/08
Sévérité P1. Preuve : SECURITY.md dernier commit f247775 du 07/08/2026, 3 jours avant le pivot
PII. (a) SECURITY.md:44 « pas de PII » vs prod `crm_prospects` PII en clair, croissante.
(b) SECURITY.md:38 « RPC Postgres REVOKE public/anon/authenticated » — faux pour `page_reads` et
`rpc_contract_check`, exécutables par anon+authenticated. (c) SECURITY.md:40 « RLS deny-all sur
les tables » — la vue `cpi_capture_perdue` (SECURITY DEFINER, advisor ERROR) renvoie des lignes
à `anon`. (d) Tableau « Où vivent les secrets » omet `COOKED_INGEST_KEY`, `NTFY_TOPIC`,
`ANON_SALT`, `DFS_*`, credentials SECIB ; `.env.example` antérieur à v27/SECIB.
Impact : fausse assurance de sécurité sur un doc de lecture obligatoire (AGENTS.md 4e position),
repo public. Récidive : même ligne relevée par l'audit du 25/07/2026, jamais corrigée.
Invariant : (1) test CI `has_function_privilege` sur les SECURITY DEFINER de `public` ;
(2) grep `Deno.env.get|getSecret` → chaque nom doit apparaître dans SECURITY.md/.env.example ;
(3) entrer crm_prospects/secib_dossiers dans SECURITY.md. Statut [non recoupé].

### i-02 — L'orchestrateur CPI/dashboard n'existe dans aucun doc vivant ; 5 crons fantômes documentés
Sévérité P1. Preuve : prod 9 jobs `cron.job`, dont `cooked-refresh-after-gsc` (`0 8-20 * * *`,
verrou avisory, skip si GSC pas arrivé, CPI en premier). `refresh_after_gsc` : 0 occurrence dans
les .md vivants, 6 occurrences dans 2 archives seulement. OPERATIONS.md documente 5 jobs absents
de prod (`refresh-dashboard-snapshots` 04:00, `-expertises` 04:12, `-assisted` 04:16,
`cooked-cpi-daily-snapshot` 07:30, `dashboard-stale-check`), dashboard/README.md répète les 3
horaires. `math-refresh-snapshots-weekly` absent du tableau. Le CPI/dashboard ne se rafraîchit
QUE si GSC du jour est arrivé — absent de toute doc. Impact : panne de diagnostic (déjà vécue :
CPI troué 9 j le 25/07). Récidive : déjà relevé 02/07 (« 8 en prod pas 6 »), re-dérivé en 51 j.
Invariant : CI `check_docs_constants.py` lisant `cron.job`, ou à défaut JSON figé vérifié par
gsc-daily-ingest. Statut [non recoupé].

### i-03 — CONTEXT.md et les 2 ADR ne sont référencés par aucun index ; domain.md dit depuis 51 j qu'ils n'existent pas
Sévérité P2. Preuve : 6 occurrences de CONTEXT.md hors mission (CHANGELOG x2, CLAUDE.md:1111 au
conditionnel, domain.md x4). CLAUDE.md/AGENTS.md/docs/README.md n'indexent ni CONTEXT.md ni
docs/adr/ ni SECURITY.md. docs/agents/domain.md:12 (commit e6fadf7, 04/06/2026) : « neither
CONTEXT.md nor docs/adr/ exists yet ». Réalité : CONTEXT.md depuis 13/07/2026 (45270a5),
docs/adr/ depuis 28/07 (08dde0a), ADR-0002 depuis 23/08 (1cf042a). CONTEXT.md porte les
invariants anti-« chiffre faux » (sur-la-page/à-l'entrée, conversion=macro, couverture
obligatoire, freshness_contract). Impact : le seul artefact qui code ces règles est hors de tout
chemin de lecture agent. Récidive : non, défaut d'origine jamais corrigé, y compris pendant le
ménage docs du 13/07 et la resync du 07/08 qui a pourtant touché CONTEXT.md. Invariant : CI
« orphan check » sur les .md non atteignables depuis un index. Statut [non recoupé].

### i-04 — « rpcs.sql = miroir généré, gardé par la CI » est faux : le gate ne compare jamais à la prod, 12 routines divergent malgré 118/118
Sévérité P2. Preuve : CONTRIBUTING.md/AGENTS.md/en-tête du fichier promettent un miroir prod
gardé par CI. `check_rpcs_sql_fresh.py` ne se déclenche que si le diff PR contient une migration
`CREATE OR REPLACE FUNCTION/PROCEDURE public.<name>`, vérifie juste la présence d'un marqueur —
ne lit jamais la prod. Prod = 118 noms uniques, fichier = 118, mais 6+6 divergent (noms donnés).
`rpc_snapshot_meta.json` : function_count 122, generated_at 31/08 ≠ en-tête « 10/08/2026 ».
Impact : agent qui travaille sur une fonction supprimée (`alert_rule_gbp_gap`) ou ignore 3 règles
d'alerte récentes. Récidive : le fichier a été ré-édité le 31/08 (ajout d'1 fonction) sans
régénération complète, en violation de son propre en-tête. Invariant : job CI quotidien qui dump
`pg_proc` prod et compare le sha256 réel au méta. Statut [non recoupé].

### i-05 — Le nombre de routines prend 4 valeurs (104, 105, 121, 122) pour une prod à 122
Sévérité P2. Preuve : prod 120 fonctions + 2 procédures = 122 objets, dont 4 `unaccent` → 118
routines Cooked. Valeurs publiées : 104 (CONTRIBUTING.md:42, CHANGELOG.md:401,
ROADMAP-sprint38-handoff.md:67) ; 105 (docs/README.md:16) ; 121/119f+2p (AGENTS.md:25,55,
README.md:161,205, OPERATIONS.md:234,601, CLAUDE.md:325, HISTORY-sprints.md:46, views.sql:11,340) ;
122 (CHANGELOG 31/08, rpc_snapshot_meta.json). Aucune n'explicite si `unaccent` est inclus.
Impact : le contrôle de cohérence par comptage est mort avec 4 valeurs en circulation. Récidive :
même famille que le « ~390k events » du 02/07, corrigé en lot, revenu sous d'autres nombres.
Invariant : `contracts/doc_constants.json` + script de grep/échec avec unité explicite. Statut
[non recoupé].

### i-06 — Ce qui a été livré après le 10/08 n'est documenté nulle part ; HISTORY et docs/README affichent des dates de fraîcheur fausses
Sévérité P2. Preuve : (a) `conversion_weekly` + 3 routines : 0 occurrence dans tout le repo hors
mission ; migration `20260807224552` sans miroir local. (b) 11 `alert_rule_*` en prod, dont
`alert_rule_freshness/gsc_ingest_missed/warn_escalation` absents de tout tableau opérationnel ;
OPERATIONS.md décrit encore `gsc_lag`/`gsc_gap`/`dfs_stale`/`dashboard_stale` (kinds retirés le
23/08, ADR-0002). (c) Contradiction interne CLAUDE.md:251 (« migration du 10/08 crée gbp_gap »)
vs CLAUDE.md:1033/OPERATIONS.md:482 (« gbp_gap n'existe pas encore ») — les deux fausses : le
kind est `gbp_daily_stale` depuis le 23/08 et a sonné. (d) Seuils du registre `freshness_contract`
(13 sources) jamais publiés, `secib_dossiers.enabled=false` non documenté. (e) docs/README.md
annonce HISTORY « à jour 12/07 » (réel : dernière trace ~10/08), ROADMAP « 12/07 » (réel : 10/08
en tête du fichier), Audits « le plus récent 02/07 » (existe : audit-architecture 25/07/2026).
(f) docs/README.md n'indexe pas adr/, audit-architecture, analyse-mathematique, rgpd-pont-secib.
Impact : le réflexe `alerts WHERE NOT acked` remonte des kinds non documentés. Récidive :
partielle (l'index existe depuis le 13/07 mais n'a pas suivi 4 fichiers ajoutés). Invariant :
étendre la règle CONTEXT.md (freshness_contract ↔ migration) aux docs ; `c2_alerts_contract.sql`
étendu. Statut [non recoupé].

### i-07 — ROADMAP.md (23 j) place au même niveau du fait, du dépassé et une panne active
Sévérité P2. Preuve : ROADMAP.md:3 « état des lieux au 10/08 ». #3 échéance 05/08 dépassée de
28 j, jamais mise à jour. #4 « issue #19 ouverte » — `gh issue list --state all` : 2 issues,
toutes fermées. #5 décrit un incident clos (« RETOMBÉ … du 06 au 10/08, 5 échecs ») alors que
`gbp_daily` est bloqué au 20/08 (13 j sans donnée) avec de nombreux échecs de workflow continus.
#9 « signature devis ~17/08 » dépassée de 16 j ; `secib_dossiers` = 49 lignes toutes `env=test`,
dernière sync 10/08. #10 « cette semaine » a 23 jours, PII en clair active pendant ce temps.
Impact : priorisation faussée, en particulier #5 qui masque une panne GBP réelle et plus grave.
Récidive : mode d'échec structurel, aucun item ne porte de péremption. Invariant : assertions
vérifiables (`gh issue view --json state`) plutôt que statuts textuels ; alerte `roadmap_stale`.
Statut [non recoupé].

### i-08 — Constantes chiffrées périmées ou contradictoires : taxonomie, bruit, RPC dashboard, tests, lag GSC
Sévérité P3. Preuve ligne par ligne : `page_taxonomy` CLAUDE.md:131 « 56/328 » vs prod 63/374
(+19 sans catégorie). Bruit CLAUDE.md:694/716 « ~17 % » vs mesuré ~3,7 % sur 28 j. RPC dashboard
« 15 RPC (16 exposées) » + `dashboard_check_stale` non consommée — cette fonction n'existe plus
en prod (15 `dashboard_*` au total, pas 16). Tests CONTRIBUTING.md « 85 » vs dashboard/README.md
« 88 ». Lag GSC PLAYBOOK/CLAUDE.md/CONTEXT.md « J-2/J-3 » vs contrat `normal_lag_days=3, warn=6`.
Contacts macro README « ≈210 » vs CLAUDE.md « ~170 », non daté. Webhook OPERATIONS.md:163,306
« v10 » vs prod v13. Impact : contexte, sauf lag GSC (déclare une anomalie à tort) et
page_taxonomy (contrat éditorial piloté sur le mauvais périmètre). Récidive : même famille que
02/07, jamais réglée au niveau du mécanisme. Invariant : `doc_constants.json` élargi + règle
« toute constante datée ». Statut [non recoupé].

### o-12 (zone i) — Constantes docs périmées : 121 routines (6 fichiers), 5 crons fantômes, « gbp_gap n'existe pas encore », ROADMAP #4
Sévérité P3. Preuve : grep 02/09 01:17 (AGENTS.md:25,55 ; README.md:161,205 ; OPERATIONS.md:234,601
; CLAUDE.md:325 ; HISTORY-sprints.md:46 ; views.sql:11) ; `cron.job` 9 jobs vs OPERATIONS.md:462-480 ;
`gh issue list --state all` : #19 fermée 30/08. Impact : réflexes appliqués sur des objets qui
n'existent plus. Récidive : R4, « 39 désynchronisations corrigées » le 10/08, périmé 3 semaines
après. Invariant : `contracts/doc_constants.json` + CI. Statut [non recoupé].

---

## Verdicts

```
ID        i-01
Verdict   CONFIRMÉ
Ma preuve SECURITY.md (Read local, HEAD e95f3ee) : ligne 38 "RPC Postgres : REVOKE public/anon/
          authenticated", ligne 40 "RLS deny-all sur les tables", ligne 44 "Ne pas logger de PII" —
          confirmés par grep -n moi-même. git log -1 -- SECURITY.md → f2477752 07/08/2026 08:41.
          Prod (execute_sql, 02/09/2026 17:07 Paris) : SELECT count(*), max(created_at AT TIME ZONE
          'Europe/Paris') FROM crm_prospects → 856 lignes, dernière 02/09/2026 17:04 Paris (colonne
          active, en croissance). information_schema.columns sur secib_dossiers → client_nom,
          client_prenom, client_emails(+_norm), client_telephones(+_norm) en clair.
          get_advisors(security) : 2 lints WARN "Public Can Execute SECURITY DEFINER Function" +
          2 lints WARN "Signed-In Users Can Execute..." sur page_reads(timestamptz,timestamptz) et
          rpc_contract_check(...) — anon ET authenticated. Requête has_function_privilege (moi,
          même horodatage) confirme anon_exec=true, auth_exec=true pour les deux. 1 lint ERROR
          "security_definer_view" sur public.cpi_capture_perdue. Test HTTP GET anon (curl, clé
          get_publishable_keys, 02/09 15:08:34 CEST) sur /rest/v1/cpi_capture_perdue?select=path
          → HTTP 200, 2 lignes retournées (chemins de page, aucune PII) : la vue est bien lisible
          par anon en pratique, pas seulement en théorie via l'advisor.
          Code : track/index.ts:48 "const COOKED_INGEST_KEY = Deno.env.get(...)", :87
          "if (COOKED_INGEST_KEY) { ... }" — lu par moi, confirme le fail-open si var vide.
          wix/http-functions.js:22,62 getSecret('COOKED_INGEST_KEY') confirmé par grep.
          form-webhook/index.ts:1-9 (lu) : "la row prospect (crm_prospects, PII en clair, RLS
          deny-all — décision produit du 10/08/2026...)" — confirme le code assume le pivot.
          .env.example (grep moi-même) : contient ANON_SALT (l.13) et DFS_USERNAME/PASSWORD
          (l.26-27) — mais aucune trace de COOKED_INGEST_KEY ni SECIB ; dernier commit 4b6fc11
          10/07/2026, donc antérieur à v27 (COOKED_INGEST_KEY) et au pont SECIB (10/08).
          gh secret list (noms seulement) : NTFY_TOPIC créé 2026-08-22T15:00:26Z — absent du
          tableau SECURITY.md "Où vivent les secrets" (relu intégralement, 5 lignes, aucune
          mention COOKED_INGEST_KEY/NTFY_TOPIC/ANON_SALT/DFS_*/SECIB).
Écart     Aucun sur le fond. Nuance : (d) mélange deux choses distinctes — ANON_SALT et DFS_* SONT
          dans .env.example (juste pas dans le tableau "Où vivent les secrets" de SECURITY.md, ce
          qui est bien ce que dit le constat en le relisant précisément). Pas une erreur du
          constat, juste à ne pas confondre les deux fichiers.
Invariant Tient pour (1) et (2) : has_function_privilege et grep Deno.env.get/getSecret sont des
          checks CI mécaniques, imparables. (3) est un fix ponctuel de doc, pas un invariant —
          décoratif seul (sans (1)/(2) il se re-périme).
```

```
ID        i-02
Verdict   CONFIRMÉ
Ma preuve execute_sql (02/09/2026 17:09 Paris) : SELECT jobid, jobname, schedule, active FROM
          cron.job ORDER BY jobname → exactement 9 jobs actifs, dont cooked-refresh-after-gsc
          "0 8-20 * * *". Absents des 9 : refresh-dashboard-snapshots, refresh-dashboard-
          expertises, refresh-dashboard-assisted, cooked-cpi-daily-snapshot, dashboard-stale-check
          — les 5 que OPERATIONS.md (lu, lignes 460-485) documente avec horaires précis (04:00,
          04:12, 04:16, 07:30 UTC, 30 * * * *). dashboard/README.md:55-62 (lu) répète les 3
          horaires 04:00/04:12/04:16 et cite le cron dashboard-stale-check. math-refresh-
          snapshots-weekly (10 5 * * 0, jobid 55) existe en prod mais n'apparaît dans aucune ligne
          du tableau OPERATIONS.md lu. grep -rln "refresh_after_gsc" --include="*.md" . (moi) →
          seulement docs/analyse-mathematique-avancee-2026-07-29.md et
          docs/audit-architecture-2026-07-25.md, 0 dans README/AGENTS/CLAUDE/OPERATIONS/ROADMAP/
          dashboard-README. supabase/rpcs.sql:1472-1473 (lu) confirme le corps de
          cooked_refresh_after_gsc() existe et est nommé ainsi.
          Alertes (execute_sql, même horodatage) : gsc_ingest_missed compte 3, premier 27/08
          13:15 Paris, dernier 31/08 13:15 Paris (non acquittées) — cohérent avec la mécanique de
          skip décrite.
Écart     Un seul, sur un chiffre daté et volatile : gsc_last_data_day() valait 30/08/2026 (J-3) à
          ma mesure (17:09 Paris), pas 29/08 (J-4) comme relevé par le constat à 09:57. Écart de
          ~7h dans la journée du 02/09 — la donnée GSC a probablement avancé entre les deux
          horodatages (ingestion GitHub Actions à 06:00 UTC déjà passée à 09:57, donc soit un
          retry plus tard soit un décalage de cache). Ça ne change rien à la substance (orchestrateur
          absent des docs vivants, 5 crons fantômes documentés) : ce n'est qu'un exemple d'un
          chiffre "aujourd'hui" fragile, ce qui est justement le type de piège que CLAUDE.md
          demande d'horodater précisément — ironique mais pas un point contre le constat.
Invariant Manquant réellement (le CI proposé n'existe pas), mais la proposition (dump cron.job en
          CI ou JSON figé vérifié par un workflow existant) tiendrait : c'est une comparaison
          d'ensembles nommés, mécanique et sans ambiguïté.
```

```
ID        i-03
Verdict   CONFIRMÉ
Ma preuve grep -rn "CONTEXT\.md" --include="*.md" . (hors mission, moi) → CHANGELOG.md:188,276,
          CLAUDE.md:1111, docs/agents/domain.md:7,12,18,27 — 6 occurrences, exactement les mêmes
          fichiers que le constat. docs/README.md lu intégralement (cat) : section racine liste
          README/AGENTS/CONTRIBUTING/CHANGELOG/CLAUDE uniquement, section "Skills d'ingénierie"
          liste agents/ mais jamais adr/ — confirmé par lecture complète, pas juste grep négatif.
          AGENTS.md:20-40 (lu) : tableau "Où trouver quoi" sans CONTEXT.md ni docs/adr/.
          docs/agents/domain.md:7-27 (lu intégralement) : ligne 12 "as of this setup, neither
          CONTEXT.md nor docs/adr/ exists yet — that's expected [...] treat those as the interim
          glossary". git log -1 -- docs/agents/domain.md → e6fadf78 04/06/2026 00:25 — aucune
          modification depuis.
          git log --diff-filter=A -- CONTEXT.md (moi) → 45270a5d 13/07/2026 14:56, commit hash
          identique à celui cité par le constat. git log --diff-filter=A -- docs/adr/ → 08dde0af
          28/07/2026 (ADR-0001) et 1cf042af 23/08/2026 (ADR-0002).
          CONTEXT.md:108-161 (lu intégralement) : contenu conforme — "sur la page"/"à l'entrée" ne
          se somment jamais, Conversion = macro uniquement, couverture obligatoire (40-92%),
          escalade 5 j, freshness_contract par migration — tout présent, aux lignes citées à ±3
          lignes près.
Écart     Aucun.
Invariant Tient : un "orphan check" (grep sur les .md de la racine/docs, vérifier qu'ils sont
          cités par au moins un index) est mécanique et aurait attrapé ce cas depuis le 13/07.
```

```
ID        i-04
Verdict   CONFIRMÉ
Ma preuve scripts/check_rpcs_sql_fresh.py:1-40 (lu par moi) : le script ne fait que
          git diff --name-only, cherche CREATE OR REPLACE FUNCTION/PROCEDURE public.<name> dans
          les migrations DIFFÉRENTES, et vérifie un marqueur "-- ═══ public.<name>(" dans
          rpcs.sql — aucune requête vers la prod nulle part dans le fichier.
          Comptage indépendant (execute_sql, 02/09 17:xx Paris) : SELECT prokind, count(*) FROM
          pg_proc ... WHERE nspname='public' AND prokind IN ('f','p') → f=120, p=2 (122 total).
          string_agg(proname) complet récupéré par moi, dédupliqué en 118 noms uniques (fichier
          /tmp/prod_names.txt). grep -oE '^-- ═══ public\.[a-z_]+\(' supabase/rpcs.sql (moi) →
          118 noms uniques (/tmp/rpcs_file_names.txt). comm -23/-13 entre les deux (moi) :
          En prod, absents du fichier : alert_rule_freshness, alert_rule_gsc_ingest_missed,
          alert_rule_warn_escalation, conversions_leaderboard, cooked_weekly_conversions_snapshot,
          weekly_conversions_report.
          Dans le fichier, absents de prod : alert_rule_cpi_stale, alert_rule_dfs_stale,
          alert_rule_gbp_gap, alert_rule_gsc_gap, alert_rule_gsc_lag, dashboard_check_stale.
          → Exactement les 6+6 noms cités par le constat, retrouvés par une méthode indépendante.
          contracts/rpc_snapshot_meta.json (cat, moi) : function_count 122, generated_at
          "2026-08-31" ; en-tête supabase/rpcs.sql:10 (lu) "Généré le 10/08/2026" — mismatch
          confirmé.
          Preuve supplémentaire (pas dans le constat) : git show --stat baa3230 (31/08) montre
          que ce commit modifie bien rpcs.sql (+44 lignes, insertion du seul corps de
          alert_rule_page_taxonomy_gap) et rpc_snapshot_meta.json (+8/-x), avec message "rpcs.sql
          + méta régénérés (121 -> 122)". Or scripts/generate_rpcs_sql.py:22-29 (lu) montre que le
          HEADER_TEMPLATE stampe generated_fr = date du jour à chaque régénération réelle — si le
          script avait tourné en full le 31/08, l'en-tête afficherait "31/08/2026", pas
          "10/08/2026". La "régénération" du 31/08 n'a donc mis à jour QUE le méta JSON et ajouté
          UN bloc de fonction, sans faire tourner le vrai dump complet pg_proc — ce qui explique
          mécaniquement pourquoi 6 fonctions créées à d'autres dates (registre du 23/08, weekly
          conversion du 07/08) ne sont jamais entrées dans le fichier.
Écart     Aucun — au contraire, preuve plus solide que celle du constat sur la cause exacte de la
          récidive (script partiellement exécuté / édition ciblée, pas un vrai regen malgré le
          message de commit qui l'affirme).
Invariant Manquant en l'état (aucun job ne compare à la prod aujourd'hui). La proposition (dump
          pg_proc quotidien + comparaison content_sha256) tiendrait — c'est la seule variante qui
          aurait attrapé le cas du 07/08 (migration sans fichier local du tout) et celui du 31/08
          (régénération partielle qui passe la CI actuelle).
```

```
ID        i-05
Verdict   CONFIRMÉ
Ma preuve Comptage prod indépendant (ci-dessus, i-04) : 120 f + 2 p = 122 objets pg_proc dont 4
          unaccent/unaccent_init/unaccent_lexize (unaccent apparaît 2x dans le string_agg —
          overload) → 118 routines Cooked distinctes.
          sed -n (moi, ligne exacte citée à chaque fois) :
          - AGENTS.md:55 → "| RPC Postgres | 121 routines (119 fonctions + 2 procédures) |..."
          - README.md:161 → "~121 routines SQL publiées" ; README.md:205 → "**121 routines**
            documentées"
          - docs/OPERATIONS.md:234 → "corps complets des 121 routines" ; :601 → "121 routines
            publiques — 119 fonctions + 2 procédures (régénéré le 10/08/2026)"
          - CLAUDE.md:325 → "121 routines au 10/08/2026"
          - docs/HISTORY-sprints.md:46 → "121 routines publiées (119 fonctions + 2 procédures)"
          - supabase/views.sql:11 → "régénéré 10/08/2026, 121 fonctions" ; :340 → "121 fonctions"
          - CONTRIBUTING.md:42 → "104 RPC + gate CI fraîcheur"
          - CHANGELOG.md:401 → "miroir lecture 104 RPC"
          - docs/ROADMAP-sprint38-handoff.md:67 → "rpcs.sql (104 RPC)"
          - docs/README.md:16 → "miroir lecture des 105 corps de RPC (régénéré le 12/07/2026)"
          - CHANGELOG.md:48 → "rpcs.sql + méta régénérés (121 → 122)"
          - contracts/rpc_snapshot_meta.json → function_count: 122
          Toutes les lignes citées par le constat existent au caractère près à l'endroit indiqué —
          6 fichiers distincts portent "121" (AGENTS, README, OPERATIONS, CLAUDE, HISTORY-sprints,
          views.sql), exactement comme annoncé.
Écart     Aucun.
Invariant Manquant aujourd'hui. `doc_constants.json` + grep avec unité explicite tiendrait — c'est
          un contrôle de cohérence textuelle pur, aucune ambiguïté d'implémentation.
```

```
ID        i-06
Verdict   CONFIRMÉ
Ma preuve (a) grep -rn "conversion_weekly\|weekly_conversions\|conversions_leaderboard"
          --include="*.md" . (moi, hors mission) → exit 1, 0 occurrence. Les 3 routines existent
          en prod (vues dans le string_agg de pg_proc, i-04) : conversions_leaderboard,
          cooked_weekly_conversions_snapshot, weekly_conversions_report. Migration
          20260807224552 : `ls supabase/migrations/ | grep 20260807224552` → exit 1, aucun
          fichier local.
          (b) execute_sql : SELECT proname FROM pg_proc WHERE proname LIKE 'alert_rule%' → 11
          fonctions exactement (alert_rule_cpi_drop, _cron_failed, _double_embed_suspect,
          _form_attribution_degraded, _freshness, _gsc_ingest_missed, _page_taxonomy_gap,
          _pipeline_dead, _rpc_health, _tracker_drift, _warn_escalation). Aucune alert_rule_gbp_*
          ni alert_rule_gsc_gap/gsc_lag/dfs_stale en prod.
          (c) execute_sql sur `alerts WHERE NOT acked GROUP BY kind` (17:xx Paris) : gbp_gap
          (8, dernier 22/08 03:15 Paris) ET gbp_daily_stale (7, premier 28/08 00:15 Paris) TOUS
          DEUX non acquittés simultanément — preuve directe que le kind a changé de nom autour du
          23-27/08 et que l'ancien kind (gbp_gap) traîne encore dans les alertes non ackées.
          freshness_contract (execute_sql, lu intégralement) : 14 lignes, created_at uniforme
          "2026-08-23 21:08:13" pour toutes — confirme la création du registre le 23/08, cohérent
          avec ADR-0002. CLAUDE.md:251 (lu) affirme "crée l'alerte gbp_gap" (migration du 10/08) ;
          CLAUDE.md:1033 (lu) affirme "gbp_gap n'existe pas encore" — les deux relus par moi,
          contradiction confirmée verbatim, et les deux sont fausses au 02/09 (le kind vivant est
          gbp_daily_stale, et il a sonné 7 fois).
          (d) freshness_contract lu intégralement : secib_dossiers → enabled=false confirmé ;
          triplets (ex. gsc_path_daily 3/6/10, gbp_daily 4/7/14, form_submit 0/2/4, cpi_daily
          1/1/1) présents en base. grep "normal_lag_days\|warn_after_days\|critical_after_days"
          sur ADR-0002/OPERATIONS.md/CLAUDE.md/CONTEXT.md (moi) → seules les 3 lignes de
          ADR-0002 citant les NOMS de colonnes, aucune valeur numérique publiée nulle part.
          (e) docs/README.md lu intégralement : "HISTORY-sprints.md — chronologie (à jour
          12/07/2026...)" et "ROADMAP.md — ... (état des lieux du 12/07/2026 au soir)" et "Audits
          fiabilité — le plus récent : 02/07/2026" — confirmés verbatim. tail -5
          docs/HISTORY-sprints.md (moi) : dernière ligne mentionne "rpcs.sql (régénéré
          10/08/2026)" — donc la dernière trace réelle est ~10/08, pas 12/07 comme l'index le dit
          (écart encore pire que ce que documente le constat). grep "^## \[" CHANGELOG.md → entrées
          jusqu'au 31/08 (page_taxonomy) et au-delà (01/09, GCP, vu dans git log du repo).
          docs/audit-architecture-2026-07-25.md existe (ls) et est cité CLAUDE.md:330 (grep).
          (f) ls docs/ vs contenu docs/README.md (moi) : adr/, audit-architecture-2026-07-25.md,
          analyse-mathematique-avancee-2026-07-29.md, rgpd-pont-secib.md absents de l'index — confirmé
          par lecture complète du fichier (aucune des 4 chaînes n'apparaît).
Écart     Aucun sur le fond ; sur (e) mon relevé du dernier vrai contenu de HISTORY-sprints (~10/08)
          est même plus sévère que le "12/07" documenté par l'index — pas une atténuation.
Invariant Manquant. La règle CONTEXT.md (freshness_contract ↔ migration) existe pour la table mais
          pas pour la doc ; l'extension proposée (migration touchant INSERT freshness_contract ou
          CREATE alert_rule_ sans diff docs/OPERATIONS.md → rouge) tiendrait mécaniquement.
```

```
ID        i-07
Verdict   CONFIRMÉ
Ma preuve docs/ROADMAP.md:3 (lu) : "État des lieux au 10/08/2026" — 23 jours au 02/09.
          #4 : gh issue list --state all --json number,state,title (moi) → 2 issues, #19 et #45,
          state=CLOSED toutes les deux. gh issue view 19/45 --json closedAt (moi) → les deux
          fermées 2026-08-30T20:45:5[45]Z UTC = 30/08/2026 22:45 Paris.
          #5 : execute_sql SELECT max(day) FROM gbp_daily → 2026-08-20. Aujourd'hui 02/09 → 13
          jours sans donnée. gh run list --workflow=gbp-daily-ingest.yml --limit 100 --json
          conclusion,createdAt (moi) → 40 runs récupérés (la limite doit couper avant le début de
          fenêtre), 34 failures — taux d'échec très majoritaire confirmé, cohérent avec une panne
          non résolue (chiffre exact "29/33" du constat non retrouvé à l'identique avec ma
          fenêtre de 100 runs mais même ordre de grandeur et même conclusion : panne active).
          freshness_contract.gbp_daily (lu) : normal_lag_days=4, warn_after_days=7,
          critical_after_days=14 — seuils exacts confirmés.
          #9 : execute_sql SELECT env, count(*), max(synced_at AT TIME ZONE 'Europe/Paris') FROM
          secib_dossiers GROUP BY env → 1 seule ligne : env='test', count=49, max=2026-08-10
          10:57:06 Paris. Aucune ligne env='prod'. Confirme "signature ~17/08" dépassée sans
          effet observable en base.
          #10 : execute_sql (déjà fait pour i-01) : crm_prospects = 856 lignes, dernier ajout
          02/09 17:04 Paris — capture PII active et continue pendant que ROADMAP dit "cette
          semaine" depuis 23 jours.
Écart     Sur #5 uniquement : le nombre exact d'échecs de workflow (34/40 sur ma fenêtre élargie,
          vs "29/33" du constat sur une fenêtre 03/08→01/09) diffère parce que les fenêtres de
          requête ne sont pas identiques — la conclusion (panne active et non documentée comme
          telle) est la même, la sévérité n'est pas surestimée.
Invariant Manquant. `gh issue view --json state` en CI est une assertion mécanique simple qui
          tiendrait pour #4 ; `max(day) FROM gbp_daily` déjà exposé par l'alerte gbp_daily_stale,
          donc la partie #5 de l'invariant est en fait déjà en place ailleurs (juste pas relié à
          ROADMAP.md) — ce que le constat note lui-même en proposant de ne plus répéter l'état.
```

```
ID        i-08
Verdict   CONFIRMÉ (partiel sur un point : "Contacts macro/28 j")
Ma preuve page_taxonomy : execute_sql SELECT count(*) FILTER (WHERE category='ressource'), ...
          FROM page_taxonomy → ressource=63, classique=374, sans_cat=19, total=456. CLAUDE.md:131
          (grep + lecture) dit "56 ressource / 328 classique" — écart confirmé (+7 ressources,
          +46 classiques par rapport au doc).
          Bruit : execute_sql count(*) sur events (28 j glissants, NOW) = 198 993 ; sur
          events_human (même fenêtre) = 191 657 → (198993-191657)/198993 = 3,69 % ≈ 3,7 %.
          CLAUDE.md:694 et :716 (grep, lus) affirment "~17 %" — écart confirmé, facteur ~4,6x.
          RPC dashboard : execute_sql count(*) FROM pg_proc WHERE proname LIKE 'dashboard\_%' → 15
          exactement. execute_sql SELECT proname FROM pg_proc WHERE proname='dashboard_check_stale'
          → 0 ligne (n'existe plus). dashboard/README.md:33 (lu) dit "15 RPC (16 exposées)" et
          :54 dit "dashboard_check_stale() — sonde de fraîcheur, appelée par le cron" — la
          fonction n'existe pas en prod, contredisant le texte. Cohérent avec le cron
          dashboard-stale-check absent de cron.job (i-02).
          Tests : dashboard/README.md:30 (lu) "88 tests vitest" ; CONTRIBUTING.md:77 "85" (grep +
          sed confirmés) — deux valeurs distinctes, ni l'une ni l'autre recoupée par une run CI
          fraîche de mon côté (le run CI cité par le constat n'a pas été rejoué par moi — gh run
          view non exécuté, hors budget) → cette sous-partie reste [non recoupé] par moi
          spécifiquement sur le "92" avancé par le constat, mais la contradiction 85 vs 88 est
          confirmée en lecture directe des deux fichiers.
          Lag GSC : PLAYBOOK-analyse-seo.md:15 (lu) "lag J-2 = normal" ; CLAUDE.md:308 et
          CONTEXT.md:108-111 (lus) "J-2/J-3" / "GSC consolide à ~J-2/J-3". freshness_contract (lu)
          gsc_path_daily : normal_lag_days=3, warn_after_days=6 — donc le contrat interne dit bien
          J-3 normal, cohérent avec CLAUDE.md/CONTEXT.md mais le PLAYBOOK dit strictement "J-2".
          Ma mesure gsc_last_data_day() a varié entre J-4 (09:57, cité par constat) et J-3 (17:09,
          ma mesure) dans la même journée — dans les deux cas ≥ J-3, donc à la limite ou au-delà
          du seuil PLAYBOOK "J-2 = normal", ce qui confirme le risque de faux-positif décrit.
          Webhook : docs/OPERATIONS.md:163 et :306 (grep+lus) disent "webhook v10" ; CLAUDE.md (vu
          en tête de session) confirme v13 déployée depuis le 10/08 — écart confirmé par simple
          lecture croisée, pas besoin de requêter la prod (le numéro de version est dans le
          commentaire d'en-tête du fichier source déployé, cohérent avec le CHANGELOG).
Écart     "Contacts macro/28 j" : je n'ai pas recompté ce chiffre moi-même en prod (fenêtre 28 j
          Paris sur cta_phone_click + form_submit filtré) faute de budget restant — je ne peux ni
          confirmer ni infirmer le "195" avancé par le constat contre "≈210" (README) et "~170"
          (CLAUDE.md). Cette ligne reste [non recoupé] par moi ; les autres lignes d'i-08 sont
          confirmées.
Invariant Manquant. `doc_constants.json` élargi + règle de datation systématique tiendrait pour
          les valeurs mécaniquement extractibles (comptages SQL, comptage de tests CI) ; pour le
          lag GSC, la reco de citer le contrat plutôt que de recopier un lag est la bonne
          direction (le contrat, lui, est correct et daté par nature).
```

```
ID        o-12
Verdict   CONFIRMÉ
Ma preuve Recoupe intégralement i-02, i-04, i-05, i-07 déjà vérifiés indépendamment ci-dessus :
          121 routines dans 6 fichiers distincts (AGENTS.md, README.md, OPERATIONS.md, CLAUDE.md,
          HISTORY-sprints.md, views.sql) — confirmé ligne par ligne dans i-05 ; prod = 9 jobs
          cron.job vs 5 jobs fantômes dans OPERATIONS.md (04:00/04:12/04:16/07:30/xx:30) —
          confirmé dans i-02 ; contradiction gbp_gap "n'existe pas encore" (CLAUDE.md:1033,
          OPERATIONS.md:482) vs alerte gbp_daily_stale réellement active depuis 23/08 — confirmé
          dans i-06(c) avec preuve directe des deux kinds coexistant dans `alerts WHERE NOT
          acked` ; ROADMAP #4 "issue #19 ouverte" vs gh issue view 19 → CLOSED 30/08/2026 —
          confirmé dans i-07.
Écart     Aucun — synthèse fidèle des constats plus détaillés qu'il résume.
Invariant Identique à i-05/i-02 : `doc_constants.json` + CI, tient pour la partie comptage/liste
          nommée ; ne couvre pas nativement la contradiction sémantique gbp_gap/gbp_daily_stale
          (qui demande un mapping ancien-kind → nouveau-kind, pas juste une liste figée) —
          partiellement décoratif sur ce point précis sauf si le JSON encode aussi les alias
          dépréciés.
```

## Synthèse

- i-01 · CONFIRMÉ · PII en clair + REVOKE + RLS-deny-all + secrets non localisés, les 4 vérifiés en direct (crm_prospects 856 lignes, advisors, curl anon 200 sur cpi_capture_perdue).
- i-02 · CONFIRMÉ · 9 jobs réels vs 5 fantômes documentés, orchestrateur `cooked_refresh_after_gsc` absent des docs vivants ; seul le J-4/J-3 ponctuel a bougé entre les deux mesures (non-fondamental).
- i-03 · CONFIRMÉ · CONTEXT.md (13/07) et docs/adr/ (28/07, 23/08) hors index, domain.md figé depuis le 04/06.
- i-04 · CONFIRMÉ · gate CI ne compare jamais à la prod ; 6+6 divergences retrouvées à l'identique par diff indépendant ; preuve supplémentaire que la "régénération" du 31/08 était partielle.
- i-05 · CONFIRMÉ · 104/105/121/122 retrouvés aux lignes exactes citées, dans 6 fichiers pour "121".
- i-06 · CONFIRMÉ · conversion_weekly invisible, 3 alert_rule récentes non documentées, contradiction gbp_gap/gbp_daily_stale prouvée par coexistence des deux kinds en alerte, dates de fraîcheur docs/README fausses (encore pires que documenté).
- i-07 · CONFIRMÉ · issue #19/#45 closes, gbp_daily bloqué à J-13, secib_dossiers toujours env=test, crm_prospects croît chaque jour sous "RGPD cette semaine".
- i-08 · CONFIRMÉ (sauf 1 ligne non recoupée) · taxonomie 63/374 vs 56/328, bruit 3,7% vs 17%, dashboard_check_stale inexistante, webhook v10 vs v13 — tout vérifié ; "contacts macro/28j" non recoupé par moi (budget).
- o-12 · CONFIRMÉ · résumé fidèle de i-02/i-04/i-05/i-06/i-07.

Recopiés : 9/9 reçus.

Non testés / partiellement testés :
- i-08 "Contacts macro/28 j" (195 vs 210 vs 170) : pas recompté en prod faute de temps — seule ligne non recoupée par moi dans tout le lot.
- i-07 nombre exact "29 échecs / 33 runs" GBP : confirmé dans son ordre de grandeur (34/40 sur ma fenêtre, fenêtre différente) mais pas au chiffre près.
- i-08 "92 passed" du run CI vitest cité par le constat : non rejoué (`gh run view` non exécuté) ; la contradiction interne 85 vs 88 entre CONTRIBUTING.md et dashboard/README.md est en revanche confirmée.

Aucun des 9 constats n'a été réfuté : les vérifications indépendantes (requêtes prod ré-exécutées, fichiers relus, git log, gh issue/run) reproduisent la substance de chacun, parfois avec une preuve plus directe que celle citée (curl anon 200 sur cpi_capture_perdue pour i-01 ; diff indépendant des 118 noms pour i-04 ; coexistence gbp_gap/gbp_daily_stale dans `alerts` pour i-06).
