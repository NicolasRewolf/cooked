# Journal — mission Cooked 02/09/2026 (précision, fiabilité, hygiène)

> Une ligne par requête prod, écriture, décision. Heures **Paris**.
> Session Claude Code (Claude Fable 5.1), worktree
> `.claude/worktrees/cooked-architecture-review-c22b77`, branche
> `claude/prompt-mission-cooked-fable-a06565`, base `main` = `e95f3ee`
> (PR #101). Phases autorisées : 0-2 (annexe A du prompt de mission).

## Conventions

- `[R]` lecture prod (MCP Supabase, `execute_sql` SELECT uniquement)
- `[F]` lecture fichier / repo
- `[W]` écriture (fichier repo, jamais prod en Phases 0-2)
- `[D]` décision / arbitrage de l'orchestrateur
- `[A]` sous-agent lancé / livrable reçu

## Phase 0 — Ancrage

- 02/09/2026 01:11 `[F]` Ouverture de session. `git status` propre, HEAD `e95f3ee`.
  `.mcp.json` du repo : serveur `supabase` HTTP **read_only=true**
  (`features=docs,account,database,debugging,development,functions,branching`).
  Ce serveur demande une authentification non disponible dans cette session ;
  le connecteur Supabase claude.ai (`mcp__5e27b44c-…`) est celui utilisé.
- 02/09/2026 01:12 `[W]` Création de `docs/mission-2026-09-02/journal.md`.
- 02/09/2026 01:12 `[F]` Lecture dans l'ordre : AGENTS.md, CLAUDE.md (déjà en contexte), CONTRIBUTING.md,
  SECURITY.md, docs/OPERATIONS.md, docs/ROADMAP.md, CHANGELOG.md (depuis 01/07), audit-architecture-2026-07-25.md,
  audit-fable5-2026-07-02.md, plan-correction-audit-2026-07-02.md (format ticket), PLAYBOOK, cpi doc, dashboard/CLAUDE.md.
  `gh issue list --state open` → 0 issue ouverte (#19 et #45 fermées le 30/08). `gh repo view` → dépôt **PUBLIC**.
- 02/09/2026 01:12 `[R]` Réflexes prod : `alerts WHERE NOT acked` (48), `latest_rpc_health()` (12 ok),
  `cron.job` × `job_run_details` 30 j (9 jobs, 0 échec). `refresh_pipeline_health()` lancée après relecture de son
  corps (lecture seule : agrégats + `cron.job_run_details`) → healthy.
- 02/09/2026 01:14 `[R]` `list_migrations` (212), `list_edge_functions` (track v35 Supabase / form-webhook v19),
  `get_edge_function` ×2 (code déployé : en-têtes v27 / v13), `get_advisors` security (1 ERROR, 13 WARN) + performance (0 WARN).
- 02/09/2026 01:15 `[R]` Q-05 versions tracker 7 j ; Q-11 inventaire pg_proc (prosecdef, proconfig, privilèges, md5) ;
  Q-12 tables/vues (RLS, grants, tailles) ; Q-22 annotations ; Q-31 alerts par kind + net._http_response ; Q-25 tailles/bruit.
- 02/09/2026 01:19 `[F]` `python3 scripts/minify-tracker.py` → 14 760 / 15 000 chars (écrit `wix/tracker.min.html`, gitignoré).
- 02/09/2026 01:20 `[R]` Q-08 versions `schema_migrations` (212) ; Q-09 dump rpcs (sha prod `179ed9cc…` ≠ méta `a3d69c7d…`)
  + md5 par fonction ; Q-30 `freshness_contract` ; Q-29 durées crons ; Q-18 ingest_drops ; cooked_config (clés + longueurs,
  valeurs non lues) ; Q-26 country par semaine (events brut, diagnostic d'ingestion annoncé).
- 02/09/2026 01:22 `[F]` Comparaison locale md5 par fonction : 114 identiques, 2 différentes, 6 manquantes, 6 en trop
  (`rpcs.sql` édité à la main le 31/08, non régénéré). `comm` migrations : 104 prod sans fichier au même timestamp,
  54 fichiers re-datés, 1 migration prod sans miroir (`20260807224552`).
- 02/09/2026 01:23 `[R]` Q-13/Q-14 sessions coupées (0,04 % vs 5,53 %), Q-15 amont phone (128/128), Q-16 page_exit
  apparié (75,4 %), Q-17 doublons, Q-17b clock_clamped/forms, conversion_weekly (705 lignes), vues prod (11), pgrst.
- 02/09/2026 01:26 `[R]` Q-23 NULL-rate colonnes, Q-24 clés props, Q-20 attribution/journeys/équivalences macro (195 = 195),
  corps prod de 6 fonctions absentes/différentes de rpcs.sql (raise_cooked_alert, alert_rule_freshness, warn_escalation,
  pipeline_dead, cron_failed, cooked_alerts_refresh).
- 02/09/2026 01:27 `[F]` Script d'inventaire d'usage des 122 routines (repo + cron + dashboard + appels inter-RPC).
- 02/09/2026 01:29 `[R]` `get_publishable_keys` (clé anon legacy) puis **curl lecture seule** PostgREST :
  `cpi_capture_perdue` → 200 + données ; `rpc/page_reads` → 200 + données ; `cpi_daily` → [] ; `crm_prospects` → 401.
  `rpc_contract_check` **volontairement non appelé** (tout appel écrit dans `rpc_health`).
- 02/09/2026 01:30 `[R]` Q-27 fenêtres 60 min à zéro (1/721 : 22/08 04:15) ; Q-28 ACL ; Q-32 rpc_health KO (0) ;
  résultats `pg_get_function_result` des 16 `dashboard_*` ; Q-17 doublons affinés ; Q-10 md5 des vues ;
  `EXPLAIN ANALYZE dashboard_assisted_quarter()` → **timeout 30 s** (57014).
- 02/09/2026 01:31 `[R]` Q-34 trous cpi_daily/gsc/gbp ; Q-33 composantes identity_stitch ; viewdef prod events_human /
  events_main / cpi_gisement (comparés à views.sql : sémantique identique, formatage manuel).
- 02/09/2026 01:35 `[W]` `docs/mission-2026-09-02/00-baseline.md` (336 lignes) + `annexes/routine_usage.md`.
- 02/09/2026 01:35 `[D]` Aucune écriture prod. Aucune alerte acquittée (acquitter = écriture ; à proposer en Phase 2).

## Phase 1 — Audit multi-agents (lecture seule)

- 02/09/2026 01:35→09:50 `[D]` **Pause de session** (~8 h, reprise sur « Réessayer » de Nicolas à 09:50). Aucune action entre-temps ; le temps actif cumulé reste ~40 min.
- 02/09/2026 09:50 `[A]` Briefs auditeurs écrits (`scratchpad/briefs/{a..i}.md`, ~80 lignes chacun : périmètre, interdits,
  outils, règles, garde-fous §3, faits Phase 0, pistes, format, fichier de sortie). **9 auditeurs lancés en parallèle**
  (modèle Opus, arrière-plan, lecture seule, un seul fichier de sortie chacun dans `scratchpad/agents/<zone>-audit.md`) :
  (a) tracker/Velo, (b) Edge, (c) identité/attribution, (d) sémantique RPC, (e) ingestions, (f) CPI, (g) dashboard,
  (h) ops/sécurité, (i) docs.
- 02/09/2026 09:51 `[R]` curl lecture seule PostgREST OpenAPI root (apikey + Bearer anon) pour lister les RPC exposées
  au rôle `anon` — preuve d'exposition de `rpc_contract_check` sans l'appeler.
  → root réservé à `service_role` (401 « Only the service_role API key can be used for this endpoint »). OPTIONS et
  POST à paramètre inexistant (PGRST202) ne discriminent pas l'exposition (même réponse pour `purge_old_events`, non
  exposée). Preuve retenue pour `rpc_contract_check` : ACL identique à `page_reads(tstz,tstz)` qui, elle, répond en GET à
  la clé anon (01:29). **Jamais exécutée.**
- 02/09/2026 09:52 `[R]` Contrôle horloge : `now()` prod = 09:52:29 Paris = horloge locale. `rpc_health` 9 h : 36 lignes
  (contract-tests nocturnes 05:30 + règle horaire) — aucune écriture de ma part.
- 02/09/2026 09:54 `[R]` Recoupement canal paid (annexe A) : **MCP Google Ads inutilisable dans cette session**
  (`GOOGLE_ADS_DEVELOPER_TOKEN environment variable not set` sur `customers_list_accessible_customers`) — garde-fou
  outil, signalé, non contourné. Côté Cooked (Q-35, `events_human`, entrées = 1re pageview de session, 05/08→01/09 Paris) :
  1 472 entrées `paid` / 11 070 (13,3 %) ; 1 185 avec `gclid` (80,5 %), 537 avec `gbraid`/`wbraid` ; utm `adwords/ppc` 1 223,
  `bing/cpc` 249 ; **18 entrées non-paid portent un `gclid`** (classify_channel ne lit pas gclid). Le côté Ads reste
  [non vérifié] tant que le MCP n'a pas son token.
- 02/09/2026 10:05→10:11 `[A]` Livrables reçus : (e) 431 lignes / 8 constats (10:05), (h) 636 / 8 (10:06). Réfuteur (e)
  lancé 10:08.
- 02/09/2026 ~10:10 `[D]` **Incident quota** : « session limit » Opus atteinte (HTTP 429, réinitialisation 14:40 Paris).
  7 auditeurs (a, b, c, d, f, g, i) et le réfuteur (e) terminés en erreur par l'API — pas par un garde-fou du projet.
  Aucune écriture prod par les agents (vérifié : seuls des SELECT). Fichiers écrits AVANT la coupure : a (521 lignes, 8
  constats, complet), c (498, 8, complet), f (608, 8, complet), g (539, 8, complet), i (710, 8, complet), b (323, **4
  constats, sans sections Écarté/Non vérifiable — partiel**), d (**absent**). Effets de bord tolérés dans le scratchpad :
  `jsdomtest/node_modules` (zone a a installé jsdom pour rejouer `tests/tracker.test.js`), `prod_names.txt`,
  `file_names.txt` (zone i). Repo intact (`git status` : seul `docs/mission-2026-09-02/` non suivi).
- 02/09/2026 14:56 `[D]` Reprise sur message de Nicolas (« Tu as été coupé […] reprendre ton travail sans casse »).
  Plan : reprendre les agents (b) et (d) avec leur contexte, lancer les réfuteurs par lots (pas 9 en parallèle) pour ne
  pas retomber sur la limite, Opus pour les zones à P0/P1, Sonnet pour (a) et (i).
- 02/09/2026 15:00 `[A]` Briefs réfuteurs construits (`briefs/refute-{a,c,f,g,h,i}.md` : section « Constats » de chaque
  livrable + constats d'orchestrateur rattachés — h : o-02, o-03, o-04, o-05 ; g : o-06 ; f : o-11 ; i : o-12 ; o-01/07/08/09/13
  doublonnent h-01/h-04/h-02/h-05/a-05 et ne sont pas re-soumis ; o-10 → (b), o-14 → (d) quand leurs livrables seront
  complets). Auditeurs (b) et (d) repris avec leur contexte (SendMessage). **Lot 1 de réfutation lancé** : (e), (h), (c) —
  Opus, arrière-plan. Lots suivants (f, g, a, i, puis b, d) après retour du lot 1, pour rester sous la limite de quota.
- 02/09/2026 15:04 `[R]` Contre-vérification manuelle de a-01 (bot UA `pc` / referrer Baidu dans `events_human`),
  28 j Paris clos à J-1 : 1 899 / 13 772 pageviews (13,79 %) ont `user_agent='pc'` ; ces 1 899 sont exactement les
  pageviews à referrer spam (`cooked_is_spam_referrer`) ; 1 900 sessions ; 0 `page_exit`, 0 contact, 0 ligne dans
  `noise_sessions`. **CONFIRMÉ.** Conséquence : les mesures de Phase 0 faites sur `events_human` sans filtre spam
  (couverture page_exit 75,4 %, `browser`/`os` unknown ~16 % des pageviews, sessions 28 j) sont contaminées —
  erratum à porter dans `01-audit.md`, baseline conservée telle quelle (photo « avant »).
- 02/09/2026 15:05 `[A]` Lot 2 de réfutation lancé : (f), (g) en Opus ; (a), (i) en Sonnet (zones sans P0/P1 de chiffre,
  contre-vérifiées à la main par ailleurs). Livrable (b) complété par l'agent repris (594 lignes, 8 constats).
- 02/09/2026 15:07 `[R]` Contre-vérifications manuelles (mes requêtes, résultats bruts) :
  · c-03 : `assisted_contacts_by_entry_path(J-27, J)` = 174 sur 48 paths, bucket `(non rattaché)` = NULL (0 ligne) ;
    `macro_contacts_by_path(28)` = 186 ; écart 12 = 12 forms macro sans `cooked_sid`/`cooked_aid` → **CONFIRMÉ**.
  · h-02 : trous entre events consécutifs (events brut, 30 j) : 10/08 02:05→03:14 (68,9 min, aucun tick :15 dans
    [début+60, fin]) non alerté ; 22/08 03:12→04:16 (63,3 min) alerté → **CONFIRMÉ** (la règle mesure la phase).
  · g-02 : `pg_stat_statements` — 68 appels pour les 5 RPC de la home, 10 pour `dashboard_assisted_quarter`
    (moy. 444 ms, max 1 088 ms) → cohérent avec « annulée par timeout non comptée » ; **CONFIRMÉ** au chiffre.
  · c-01 : corps `seo_to_contact_funnel` (rpcs.sql = prod, md5 identique) : `distinct on (e.session_id)` +
    `now() - make_interval` (entrées, session brute) vs `conversion_journeys` (recousu) vs `current_date - days_back`
    (GSC) → **CONFIRMÉ**.
  · g-03 : `FreshnessBanner.tsx:33` `ageHours > 36`, `cookedEnd` absent de tout test de sévérité → **CONFIRMÉ**.
  · i-01 : `SECURITY.md:38-40` (« REVOKE … », « RLS deny-all ») vs 2 SECURITY DEFINER exposées + vue exposée ;
    dernier commit 07/08 → **CONFIRMÉ**.
  · e-02 : `gh run list gsc-daily-ingest` : départs 27/08 17:15 UTC, 28/08 18:07, 29/08 12:11, 30/08 11:07,
    31/08 12:31, 02/09 10:29 pour un schedule `0 6 * * *` → dérive de +4 à +12 h **CONFIRMÉE** ; le refresh aval
    (0 8-20 UTC) garde 1 h 50 de marge le 28/08 → **CONFIRMÉ**.
  · f-01 : couverture des clics vus par le momentum (`gsc_query_page_daily` non brandé / `gsc_path_daily`, 28 j clos
    au 29/08, par grade du `cpi_daily` du 01/09) : S 347/1 226 = 28,3 % (médiane page 26,0 %), A 146/731 = 20,0 %
    (17,9 %), B 302/1 831 = 16,5 % (10,4 %), C 166/1 269 = 13,1 % (0,0 %) → **CONFIRMÉ** au chiffre (la source du
    momentum reste à relire dans le corps prod par le réfuteur f).
- 02/09/2026 15:09 `[A]` Réfuteur (b) lancé (Sonnet, 9 constats dont o-10).
- 02/09/2026 15:09 `[A]` Livrable (d) reçu de l'agent repris (8 constats, dont **d-01 P0** : `behavior_pages_for_period`
  bounce_rate ÷100 depuis le 26/07). Brief réfuteur (d) construit (+ o-14) ; réfuteur (d) lancé (Opus).
- 02/09/2026 15:10 `[R]` Contre-vérifications manuelles :
  · d-01 : `max(bounce_rate)` de `behavior_pages_for_period(J-28, J)` = **0,0100** (423 lignes) vs
    `max(bounce_rate_28d)` de `seo_url_snapshot` = 100,00 → facteur 100 **CONFIRMÉ**.
  · d-03 : Σ `gsc_pages_overview(500).gsc_clicks_28d` = 4 689 vs Σ `gsc_path_daily` 28 j clos au 30/08 = 5 357
    (24 j = 4 474) ; 318/404 pages égales à la somme 24 j, 252 à la somme 28 j → fenêtre plus courte que 28 j
    **CONFIRMÉE** ; l'écart exact (−12,5 % vs −15,3 % annoncé) dépend de la borne : `gsc_last_data_day()` est passé
    de 29/08 à 30/08 vers 12:30 (ingestion du jour) → PARTIEL sur le chiffre, à trancher par le réfuteur.
- 02/09/2026 15:35 `[A]` Réfutation (a) reçue : 8/8 recopiés, **8 CONFIRMÉS** (a-07 : date de commit corrigée 25/07 au
  lieu de 28/07, sans effet ; a-08 : 125/125 sur sa fenêtre vs 128/128). Aucun réfuté.
- 02/09/2026 15:40 `[A]` Réfutation (c) reçue : 8/8 recopiés — **6 CONFIRMÉS** (c-02, c-03 [174 vs 186 = −6,5 %],
  c-04 [sous-estimé : 77,4 % des sessions du jour hors couture à 15 h], c-06, c-07, c-08), **2 PARTIELS** (c-01 : grain
  mixte et 3 fenêtres confirmés, mais le dénominateur n'est gonflé que de 8,3 %, pas « 52 % » ; c-05 : 2 définitions de
  fenêtre, pas 3, dérive horaire de sens inverse). Invariants jugés décoratifs pour c-01, c-04, c-07.
- 02/09/2026 15:41 `[A]` Réfutation (e) reçue : 8/8 recopiés — **6 CONFIRMÉS** (e-01 [0 rapprochement sur 856], e-02
  [dérive non résorbée au 02/09 10:29 UTC], e-04, e-05, e-06 [2 articles invisibles, path tronqué à 105 chars en base],
  e-08), **2 PARTIELS** (e-03 : défaut réel, ampleur chiffrable = 20,2 % d'emails dupliqués ; e-07 : 10 non-articles,
  pas 11). Signalé hors constats : `gbp_daily_stale` critical du 02/09 01:15 non acquitté.
- 02/09/2026 15:33 `[R]` Contre-vérifications manuelles (suite) :
  · a-03 : paires session×path avec LCP → avec CLS (28 j, hors bot) : Chrome 3 175/4 436 = 71,6 % (p75 0,160 observé,
    0,120 zéros implicites, 827 CLS = 0), Safari 8/2 362 = 0,3 %, Firefox 0/610, Edge 87,7 % → **CONFIRMÉ**.
  · a-04 : `wix/tracker.html` — `queue.splice(0, 50)` avant `transmit(...)` ; `fetch(... keepalive)` sans `.then`/`.catch` ;
    events CRITICAL → `flushQ()` immédiat sans reprise → **CONFIRMÉ**.
  · a-08 : `masterpage-cooked.js:22` `COOKED_DEBUG = true` ; `http-functions.js` garde `!origin || !startsWith` (fail-closed
    depuis le 25/07, forgeable par en-tête) → **CONFIRMÉ**.
  · b-01 : `form_submit` 180 j par `form_id` : « Prise de contact site-web » 17/228 + 1/22 `path` NULL, « Formulaire
    Divorce » 3/3 NULL (2/3 avec `cooked_aid`), « Demande dossier en cours » 1/1 NULL → 22/254 = 8,7 % → **CONFIRMÉ**.
  · c-04 : sessions du jour (pageview, hors bot) hors `identity_stitch` : 02/09 **213/229 = 93,0 %** à 15:33 ; 30/08,
    31/08, 01/09 : 0 % → **CONFIRMÉ** (le réfuteur mesurait 77,4 % à 15:0x ; la part croît dans la journée).
  · d-04 : `/honoraires-rendez-vous` : `gsc_page_performance` 0,2298 vs `pages_overview_unified` 34,43 vs snapshot 34,43
    → **CONFIRMÉ** (unité ×100 + fenêtre : 22,98 % ≠ 34,43 %).
  · e-01 / c-08 : `secib_dossiers` 49 (100 % `env='test'`), 41 sans aucune clé ; `pont_prospects_dossiers` 856 lignes,
    100 % `non_converti` ; `crm_prospects` 856, 93 emails dupliqués, 153 avec `cooked_aid` → **CONFIRMÉS** (agrégats seuls).
  · f-02 : Δmomentum 7 j (01/08→01/09, S/A/B aux deux dates) : 1 350 paires / 53 pages, σ = 0,199, p10 −0,210 ;
    305 (22,6 %) sous −0,10 dont 93 avec momentum courant ≥ 1,0 ; 150 chutes ≤ −15 → **CONFIRMÉ** au chiffre près.
- 02/09/2026 ~15:50 `[D]` **Second incident quota** (429, réinitialisation 19:50) : réfuteurs (h), (g), (i), (b), (d) terminés
  en erreur par l'API. Fichiers écrits AVANT la coupure et complets : h-refute (12 verdicts : 10 CONFIRMÉS, 2 PARTIELS),
  g-refute (9 : 8/1), i-refute (9 : 9/0), d-refute (9 : 7/2), f-refute (9 : 8/1, reçu 15:47). **b-refute absent.**
  Aucune écriture prod par les agents (SELECT seulement).
- 02/09/2026 19:55 `[D]` Reprise sur message de Nicolas (« J'ai atteint ma limite d'utilisation […] continuer »).
  Réfuteur (b) relancé (Sonnet). Extraction des verdicts des 8 livrables de réfutation pour la synthèse.
- 02/09/2026 19:57 `[R]` Forensique P0 (lecture seule) : `rpc_health` depuis le 28/07 ne contient que les 12 `rpc_name`
  connus (aucun nom étranger) ; lignes hors créneaux cron : 1 par RPC le 28/07 10:19 (création du helper) et 3 pour le
  trio horaire — compatibles avec des exécutions manuelles de Nicolas. Aucune trace d'appel externe par ce canal
  (un attaquant réutilisant un nom connu resterait invisible ici).
- 02/09/2026 19:58 `[R]` `query_logs` (edge_logs, 24 h max) : les seuls appels à `rpc/page_reads`, `cpi_capture_perdue`
  et `rpc/rpc_contract_check` sont les miens (curl 01:29, 09:52) et ceux des réfuteurs (15:04, 15:08). Aucun appel
  tiers dans la fenêtre observable ; avant 24 h : [non vérifiable].
- 02/09/2026 20:00 `[W]` Rédaction de `01-audit.md` (synthèse) — réfutation (b) toujours en cours, statuts b-nn provisoires.
- 02/09/2026 20:05 `[A]` Réfutation (b) reçue : 9/9 recopiés — **8 CONFIRMÉS** (b-01, b-02, b-04…b-08, o-10), **1 PARTIEL**
  (b-03 : la seconde alerte `pipeline_dead` du 01/08, 2 h 46 en journée, était un vrai signal). Bilan réfutation :
  81 verdicts, 70 CONFIRMÉS, 11 PARTIELS, 0 RÉFUTÉ. `01-audit.md` mis à jour.
- 02/09/2026 20:10 `[W]` `02-plan.md` écrit (22 tickets T-01…T-22, 4 vagues, §7 décisions). Création des issues GitHub
  (Phase 2, autorisée par l'annexe A) — T-01/T-02 sans détail technique (dépôt public, SECURITY.md).
- 02/09/2026 20:15 `[W]` **22 issues créées** : #102 (T-01) → #123 (T-22), labels `mission-2026-09-02` + triage
  (`ready-for-agent` / `ready-for-human` / `needs-info`, créés — le repo n'en avait pas) ; T-01/T-02 sans détail
  technique. Liste : `annexes/issues.txt`, `02-plan.md` §8.
- 02/09/2026 20:18 `[W]` Livrables des agents et briefs copiés dans `annexes/agents/` et `annexes/briefs/` (scan PII :
  aucun email/téléphone réel ; les seules valeurs sont les vecteurs fictifs des tests de normalisation).
- 02/09/2026 20:20 `[D]` **⛔ ARRÊT 1.** Aucune écriture prod pendant toute la session. Aucun push : le dossier de
  mission contient le détail d'une exposition non corrigée (T-01) — commit **local** sur la branche de mission
  seulement, publication après T-01. Prochaine session : relire `journal.md` + le ticket validé, puis Phase 3.
- 02/09/2026 20:23 `[W-PROD]` **T-01 appliqué** (`apply_migration`, version prod `20260902182316`) : REVOKE sur
  `rpc_contract_check`, `page_reads` ×2 ; `security_invoker` + REVOKE sur `cpi_capture_perdue`, `cpi_movers`,
  `events_no_bots` ; `ALTER DEFAULT PRIVILEGES FOR ROLE postgres … REVOKE EXECUTE … FROM PUBLIC, anon, authenticated` ;
  celui de `supabase_admin` refusé (notice) ; nouvelle règle `alert_rule_exposure()` (invariant I1).
- 02/09/2026 20:30 `[W]` Réponses aux trois questions de Nicolas dans `01-audit.md` §8 (routine hebdo lancée à la
  main via MCP le lundi matin ; Q-14 = expirations légitimes, Q-13 = signature du bug ; composantes multi-aid =
  traces pré-sprint41, 4 multi-device sur 1 547, sortie de fenêtre ~10/10).
- 02/09/2026 20:35→03/09 07:00 `[D]` Session inactive (nuit).
- 03/09/2026 07:04 `[R]` **Vérification T-01** : `has_function_privilege(anon|authenticated)` = false sur les 3
  fonctions ; 3 vues `security_invoker=true`, SELECT anon false ; `pg_default_acl` postgres = `{postgres=X,
  service_role=X}` (supabase_admin inchangé) ; `alert_rule_exposure()` → 0 ligne ; 0 SECURITY DEFINER exposée ;
  curl anon → **401** sur `cpi_capture_perdue`, `rpc/page_reads`, `cpi_movers` ; advisors security : **0 ERROR**,
  lints 0028/0029 disparus (restent 8 `search_path` justifiés, 2 extensions, 1 auth). **T-01 terminé au sens §3.9**
  sauf le miroir/rpcs.sql — voir ci-dessous.
- 03/09/2026 07:07 `[W-PROD]` `apply_migration` `t12_role_lecture_seule_ci` (version `20260903050701`) : rôle
  `cooked_ci_ro` (IF NOT EXISTS), settings read-only, grants, policy SELECT sur `freshness_contract`.
- 03/09/2026 07:10 `[R]` Miroir de `20260807224552` (routine hebdo) et de T-01 écrits localement ; 9 corps de fonction
  prod transcrits et **vérifiés au md5** ; `rpcs.sql` reconstruit (124 sections) : sha256 corps = `0e06add6…` =
  dump prod — reconstruction exacte. Découverte d'une fonction inattendue `cooked_ci_cron_jobs()` (migration prod
  `20260902220012`, que je n'ai pas appliquée).
- 03/09/2026 07:15 `[D]` **Travail parallèle constaté** : `origin/main` = `d205ff9` (PR #124 « t12-ci-prod-drift »,
  session **Cursor** de Nicolas, 02/09 23:00→03/09 00:08) : rôle `cooked_ci_ro` (`20260902212045`), no-op
  (`20260902215946`), `cooked_ci_cron_jobs()` (`20260902220012`), workflow `prod-drift.yml` + `check_prod_drift.py`,
  `contracts/doc_constants.json`, 7 migrations re-datées, miroir weekly, **miroir T-01** (identique au mien),
  `rpcs.sql` régénéré (124, sha `0e06add6…`). Issues **#102 et #113 fermées** par la PR. Gate `prod-drift` verte
  (run 02/09 22:08 UTC). Conséquence : mes miroirs T-01/weekly sont abandonnés (identiques), ma migration
  `20260903050701` est **redondante** (rôle déjà créé) mais appliquée → miroir ajouté pour la parité, sinon la gate
  quotidienne (06:20 UTC) serait rouge. Point de vigilance : deux sessions ont écrit en prod la même nuit sans se
  voir (mémoire « canal de travail unique ») — à signaler à Nicolas, pas à re-litiger.
- 03/09/2026 07:20 `[W]` Rebase de la branche de mission sur `origin/main` ; bandeaux « ne pas publier » remplacés
  par l'état vérifié de T-01 ; PR ouverte.
- 03/09/2026 07:35 `[W]` PR #125 (dossier de mission + miroir `20260903050701`) : CI verte (prod-drift, paris-date,
  rpcs-sql-fresh, dashboard-rpc-columns, schema-migrations) → **mergée sur main**, branche supprimée. Fin de session.

### T-03 (#104) — 03/09/2026
- 07:2x `[R]` Lecture des corps (rpcs.sql régénéré = prod) : `behavior_pages_for_period` (÷100 sur une fraction, pct
  reçoit la fraction), `seo_pages_overview` (`we` sans filtre spam → sessions du bot dans `ss`/`entry_exit`),
  `gsc_page_performance` (`cooked.bounce_rate` = fraction), `pages_overview_unified` (chemin lent = fraction, chemin
  rapide = snapshot en %). « Avant » 07:32 : `/honoraires-rendez-vous` rebond 21,71 % avec bot (99 entrées bot / 152)
  vs **32,08 % sans bot = snapshot 32,08** → l'écart résiduel de d-04 est le bot ; `bpfp` max 0,0100 / 1,00 ;
  `gsc_page_performance` 0,2298 ; chemin lent max 1,0000 (fraction) vs rapide 100,00.
- 07:38 `[W-PROD]` `apply_migration` `t03_bounce_rate_unites_et_contrat` (version `20260903053754`) : 5 fonctions
  (générées depuis les corps prod par substitutions ciblées, C6 vérifié : aucun cast Paris brut).
- 07:40 `[R]` « Après » : `bpfp` max **1,0000 / 100,00** ; `/honoraires-rendez-vous` **0,3208 / 32,08** = snapshot ;
  `gsc_page_performance` **36,92** (fenêtre GSC J‑3, en %) ; chemin lent max **44,44** (%) ; 4 contrats d'unités :
  **0 violation**. Sha du dump prod = `53c5ee52…` = `rpcs.sql` reconstruit depuis le fichier de migration (5 md5
  identiques). `apply_migration` `t03_annotation_restatement_bounce` : ligne `annotations` du 03/09/2026 posée.

### T-04 (#105) — 03/09/2026
- 09:40 `[D]` Validation citée : « Tu mets à jour et tu enchaines sur T-04 ok ? » (Nicolas, 03/09/2026 09:40). Périmètre
  = ticket #105 **sans purge** (validation du 02/09) : masquage par `noise_sessions`, aucun DELETE dans `events`.
- 09:41 `[F]` Clone local remis sur `origin/main` (`fbb37cf`) — le premier `git pull` avait tourné par erreur dans le
  worktree `.claude/worktrees/…` (cwd persistant) : branche `claude/t04-bot-baidu` recréée depuis le bon `main`,
  patch Edge (3 fichiers, worktree `claude/t04-bot-baidu-source`) ré-appliqué. Corps `refresh_noise_sessions`,
  `classify_channel`, `run_rpc_contract_tests` de `rpcs.sql` **= prod (3 md5 identiques)**.
- 09:42 `[R]` « Avant » (events_human, 28 j Paris 06/08→02/09) : 13 823 pageviews dont **1 875 `pc`** (13,6 %) =
  1 875 referrer Baidu (mêmes lignes) + 34 SEBot-WA ; 11 110 sessions dont 1 875 spam (16,9 %) ; canal `referral`
  1 995 dont **1 875 spam (94 %)**. Historique (events brut, annoncé) : `pc` = 85 985 lignes / 7 252 sessions,
  07/05/2026 → 03/09/2026, **0 ligne `pc` sans referrer Baidu et 0 ligne Baidu sans UA `pc`** ; SEBot-WA 554 lignes /
  113 sessions. Couverture `page_exit` 28 j : 75,6 % avec bot, **89,1 % hors bot**. Coût du rattrapage : 7 365 sessions
  (27 déjà dans `noise_sessions`), scan 6,7 s.
- 09:46 `[W]` Tests Deno (`npx deno@2 test track_row_test.ts`) : **42 verts** dont 3 T-04 (`pc`/`PC` = bot, SEBot-WA =
  bot, `pc` en sous-chaîne d'un UA Android = humain).
- 09:48 `[W]` Migration générée depuis les corps prod par substitutions ciblées (script /tmp, chaque motif matché
  exactement 1 fois ; C6 : 0 cast Paris brut) : taxonomie `ua_bot` + `pc`/`sebot`, règle `spam_referrer`, rattrapage
  `noise_sessions`, `classify_channel` v4 (`spam`), `alert_rule_spam_in_events_human`, 2 contract-tests I3, REVOKE.
- 09:50 `[W-PROD]` `apply_migration` `t04_bot_baidu_spam_referrer_invariant_i3` (version **`20260903075011`**).
- 09:50 `[R]` « Après » (même requête) : pageviews **11 914** (−1 909 = 1 875 + 34, exact), `pc` **0**, Baidu **0**,
  SEBot **0** ; sessions **9 201** (−1 909) ; `referral` **120**, spam dans referral **0**. `noise_sessions` :
  +7 252 `ua_bot: pc`, +86 `ua_bot: sebot` (113 − 27). `classify_channel` : baidu → `spam`, google → `organic_google`,
  null → `direct`, `gmb` intact. `alert_rule_spam_in_events_human()` → 0 ligne en 0,13 s ; contrats
  `spam_share_events_human` = 0, `classify_channel_spam` = 0 (0,65 s). ACL : anon/authenticated = false sur les 4
  fonctions ; `paris_date`/`paris_today` sans `proconfig` (C6b intact). Advisors security : 0 ERROR (inchangé).
  `page_exit` 28 j : **89,1 %** (mobile 86,5 / desktop 94,6 / tablet 82,9) — a-02 confirmé.
- 09:51 `[W-PROD]` `npx supabase functions deploy track --no-verify-jwt` → **Edge track v28 déployée** (version
  interne Supabase 38, 07:51 UTC). Ingestion vivante (76 events / 15 min, tracker `sprint41`). Le robot arrive par
  salves (41, 12, 66, 12, 45, 12, 17 lignes/h sur 24 h, dernière à 04:16 Paris) : la preuve « 0 ligne `pc` après
  déploiement » se lit à **J+1**, pas maintenant. `ingest_drops.bot_ua` ne l'isolera pas (106 004 drops déjà ce jour).
- 09:52 `[W]` `rpcs.sql` reconstruit sans `DATABASE_URL` (3 sections remplacées + 1 insérée) : **125 fonctions, sha256
  corps `52bf519a…` = dump prod**, méta régénéré par `write_outputs`.
- 09:55 `[W-PROD]` `apply_migration` `t04_annotation_restatement_bot_baidu` (version **`20260903075234`**) : annotation
  posée. Miroirs des deux migrations, CHANGELOG, AGENTS/CLAUDE/OPERATIONS (v28) écrits.
- 09:56 `[D]` **Point à signaler à Nicolas** : « sans purge » = aucun DELETE de ma main. Mais les sessions désormais
  classées bruit tombent sous la politique existante `cooked-purge-noise-weekly` (`purge_cooked_noise(28)`, dimanche
  04:30 UTC) : dimanche **06/09/2026 ~06:30 Paris**, les ~80 000 lignes du robot antérieures au 06/08 seront
  supprimées d'`events` comme tout bruit > 28 j. Cohérent avec la doctrine « supprimer du bruit ne change aucun
  résultat », mais c'est une conséquence, pas une décision prise ici — à confirmer ou à bloquer avant dimanche.
  Corollaire : si Nicolas veut les conserver, il faut aussi les sortir de `noise_sessions` (purgée à 90 j) et poser un
  filtre durable dans `events_human` — sinon le robot ressurgit dans la vue au bout de 90 jours.
- 09:58 `[W]` PR #127 ouverte (avant/après dans la description) ; CI verte (8 jobs) ; **mergée sur `main`** (`179fd7f`),
  branche supprimée, **#105 fermée**. T-04 terminé au sens §3.9 — reste la preuve J+1 « 0 ligne `pc` ingérée ».
- 10:02 `[D]` **Décision purge citée** : « si il faut purger : on purge, point. » (Nicolas, 03/09/2026 10:02). La purge
  hebdo `cooked-purge-noise-weekly` fera son travail dimanche 06/09 : rien à bloquer, rien à ajouter. Même message :
  « On s'en tient au prompt et on avance. » → Phase 3 poursuivie dans l'ordre de la vague 1 (`02-plan.md` §0) :
  **T-05** (#106) maintenant. T-06 (choix d'option), T-08 (valeur d'objectif) et T-02 restent des décisions à poser.

### T-05 (#106) — 03/09/2026
- 10:07→10:19 `[W-PROD]` (session précédente, même agent) Photo « avant » du CPI : table `cpi_pre_restatement_20260903`
  (LIKE `cpi_daily`, RLS sans policy, REVOKE) + job pg_cron one-shot auto-désarmé — `apply_migration` `t05_photo_avant_cpi`
  (version **`20260903081257`**) ; le job a échoué à 10:18 (`statement_timeout` 2 min : un `SET LOCAL` DANS le bloc DO ne
  réarme pas la commande en cours) → `t05_photo_avant_cpi_fix_timeout` (version **`20260903081927`**, SET séparé du DO,
  patron `cooked-refresh-after-gsc`). Brouillon de la migration principale écrit (`TMP_…`), docs OPERATIONS + CPI amorcées.
- 10:32 `[D]` Validation citée : « On s'en tient au prompt et on avance. » (Nicolas, 03/09/2026 10:32) et « Personne ne
  travaille sur T-05 ! Tu es le seul à bosser dessus » (10:40) — reprise du ticket #106 tel que validé, restatement compris
  (§7.7 du plan : « alignement des fenêtres, +12 % de clics affichés sur 28 j »).
- 10:45 `[R]` Photo « avant » **réussie** : job de 10:22:00 → 10:27:25, 175 pages (47 fiables), `cron.job` t05 = 0.
  Brouillon relu : diff ligne à ligne contre `rpcs.sql` = uniquement les bornes (11 / 39 / 16 lignes), aucun changement de
  contrat de sortie ; **md5 prod des 3 corps = `rpcs.sql`** (vérifié 10:52). « Avant » `gsc_pages_overview` : Σ
  `gsc_clicks_28d` **4 474** vs Σ `gsc_path_daily` 28 j alignés (03/08→30/08) **5 358** ; 24 jours de données sous la
  borne brute. `cpi_daily` du 03/09 : 0 ligne (l'orchestrateur `cooked_refresh_after_gsc` — cron 46, 8h-20h UTC — attend
  l'ingestion GSC du jour ; il n'y a pas de job `cooked-cpi-daily-snapshot` : la ligne d'OPERATIONS.md §crons est
  périmée → T-14). Alertes non acquittées : `cpi_drop` 2/jour depuis le 10/08 (warn + critical), `gbp_daily_stale`,
  `pipeline_dead` du 22/08 — bruit d'alerte, périmètre **T-07**, non traité ici.
- 10:53 `[W-PROD]` `apply_migration` `t05_fenetres_28j_gsc_cpi_invariant_i4` (version **`20260903085351`**) :
  `gsc_pages_overview` (bornes `cooked_period_bounds('rolling_28','gsc')`), `cooked_page_index` (CTE `w` :
  `g_end = gsc_last_data_day()`, `t0/t1 = cooked_paris_ts_start/_end_exclusive`, toutes les bornes GSC et Cooked
  réécrites, `c0` = 28 j pleins), `run_rpc_contract_tests` (+ `gsc_pages_overview_28d_alignes`, `cpi_sans_horloge`).
- 10:54 `[R]` « Après » : Σ `gsc_clicks_28d` **5 358 = 5 358** ; contrats I4 : **0 / 0** ; ACL anon/authenticated
  `gsc_pages_overview` false/false, `run_rpc_contract_tests` false/false ; `cooked_page_index` **true/true** — état
  antérieur préservé par CREATE OR REPLACE (fonction SECURITY INVOKER, hors périmètre de l'invariant I1 qui vise les
  SECURITY DEFINER ; à instruire au T-19 avec l'inventaire d'usage), `paris_date`/`paris_today` sans `proconfig`.
  Écart de miroir détecté : 2 lignes de `gsc_pages_overview` indentées 2 espaces en prod vs 4 dans le fichier (mon
  collage) → fichier réaligné sur la prod, **md5 prod = fichier** sur les 3 corps. `rpcs.sql` reconstruit (3 sections
  remplacées, `write_outputs`) : **125 fonctions, sha256 corps `e439762f…` = dump prod**.
- 10:57 `[W-PROD]` `apply_migration` `t05_photo_apres_cpi` (version **`20260903085657`**) : job one-shot 08:58 UTC →
  `cooked_cpi_snapshot()` (upsert `cpi_daily` du 03/09 avec la définition T-05, mêmes données GSC que la photo :
  dernier jour 30/08). Réussi **10:58:00 → 10:58:59** (59 s contre 5 min 25 s pour l'ancienne définition : les bornes
  fixes remplacent `now()` pour le planificateur). L'orchestrateur repassera après l'ingestion GSC (~13:00) et
  rafraîchira la ligne — comportement quotidien normal.
- 11:02 `[R]` **Comparaison avant/après** (`cpi_pre_restatement_20260903` vs `cpi_daily` 03/09) : 175 → 175 pages,
  169 communes, 6 entrées / 6 sorties (toutes grade C, `n_org` 5-7 : la fenêtre Cooked recule de 3-4 jours) ; delta CPI
  moyen **−1,30**, médiane |Δ| 3 ; composantes : Δzc +0,02, Δzr −0,04, Δzl −0,08, Δzv +0,06, Δmomentum −0,03, Δgate 0 ;
  18 movers ≥ 15 pts dont **1 fiable** (assurance-perte-exploitation 21→41 B→B, zv −2,5→−0,7 — terme conversion,
  hors fenêtre T-05, volatilité connue) ; 2 changements de grade (1 B→C, 1 C→B) ; 46 fiables S/A/B : delta moyen −1,28,
  médiane |Δ| 2, max 20 ; top pages : garde-à-vue 67→58, CIVI 70→66, home 74→79, sarvi 45→31, prestation
  compensatoire 87→93 ; `clics_perdus` 1 138 → 1 284 (+13 %) ; CPI pondéré trafic 48,5 → 45,6.
- 11:06 `[W-PROD]` `apply_migration` `t05_annotation_restatement_fenetres_28j` (version **`20260903090225`**) :
  annotation posée. Miroirs des 5 migrations écrits (versions prod), CHANGELOG, CLAUDE.md (bloc restatement 03/09),
  `cpi-cooked-page-index.md` (§Ruptures de série), OPERATIONS.md (ligne `gsc_pages_overview`).
- 11:10 `[D]` À reporter : le commentaire interne de `cooked_refresh_after_gsc` (« cooked_page_index lit now() ») est
  périmé — texte de commentaire seulement, pas de redéfinition de fonction pour ça (T-09/T-14) ; `cpi_drop` sonnera
  peut-être sur le 03/09 (Δ −19 sur /honoraires-rendez-vous, grade C donc hors `fiable`) — annotation posée, T-07.

### T-09 (#110) — 03/09/2026
- 11:10 `[D]` Validation citée : « Allez on poursuit on avance :) » (Nicolas, 03/09/2026 11:10). Vague 1 dans l'ordre du
  plan : T-06 (option a/b/c) et T-08 (valeur d'objectif) attendent une décision → **T-09** est le prochain ticket sans
  décision bloquante. Session unique (le ticket lourd est repris dans la même session, journal + #110 relus).
- 11:12 `[F]` Relecture d-02/c-05, d-06/c-01, o-14 (01-audit.md), §T-09 du plan, corps prod de `conversion_journeys`,
  `form_submits_attributed`, `seo_to_contact_funnel`, `macro_contacts_by_path` (×2), `classify_channel`,
  `cooked_period_bounds`, `gsc_pages_overview`, `cooked_page_index`, `run_rpc_contract_tests` (rpcs.sql = prod, sha vérifié).
- 11:15 `[R]` Mesure « avant » : contacts 28 j = 183 / 189 / 195 selon la RPC (lens live, live_j1, gsc : 100 % fenêtre) ;
  funnel : GSC 24 j (`current_date` UTC) face à 28 × 24 h d'entrées ; 16 entrées `gmb` + 3 `direct` portent un gclid.
- 11:22 `[W-PROD]` `apply_migration` `t09_photo_avant_cpi` (version **`20260903092218`**) : colonne `phase` sur
  `cpi_pre_restatement_20260903` (lignes T-05 → `t05_avant`), copie synchrone de `cpi_daily` du 03/09 (= après T-05,
  10:58) en `t09_avant` — 175 lignes.
- 11:25 `[W]` Migration principale générée par script (`/tmp/gen_t09.py`, hors repo) : corps de `gsc_pages_overview`,
  `cooked_page_index`, `run_rpc_contract_tests` extraits de `rpcs.sql` + substitutions ciblées ; les 5 autres réécrits.
  Dry-run en transaction : **timeout MCP** sur le funnel (`cross join w` → hash join sur 28 j) ; réécrit en sous-requêtes
  scalaires `(select d_start from w)` (InitPlan, bornes constantes pour le planificateur) : `explain analyze` du
  dénominateur ~5 s au lieu de > 60 s. Rollback vérifié, prod inchangée.
- 11:33 `[W-PROD]` `apply_migration` `t09_fenetre_unique_contacts_invariant_i4` (version **`20260903093320`**) :
  `classify_channel` v5 (DROP 4 args + CREATE 5 args, `url DEFAULT NULL`, gclid/gbraid/wbraid ⇒ paid avant gmb),
  `form_submits_attributed(days_back, p_end)`, `conversion_journeys(days_back, p_end)` (DROP + CREATE, `window_start`/
  `window_end` en sortie, `form_submit_counts_as_macro`), `macro_contacts_by_path(int)` ancrée J-1,
  `seo_to_contact_funnel(days_back, p_end)` (lens `cross`, entrées de visite recousue, FULL JOIN), `gsc_pages_overview`
  (contacts sur ses bornes GSC), `cooked_page_index` (zv sur `conversion_journeys(p_days, gsc_last_data_day())`, url passée
  à `classify_channel`), `run_rpc_contract_tests` (+ `contacts_28j_une_fenetre`, `funnel_meme_total_que_journeys`,
  `classify_channel_gclid_paid`). ACL réappliquées (REVOKE public/anon/authenticated, GRANT service_role).
- 11:34 `[R]` « Après » : fenêtre live_j1 06/08→02/09 : `site_macro_counts` **191** = Σ `macro_contacts_by_path(28)`
  **191** = `conversion_journeys(28)` **191** ; `form_submits_attributed(28)` 65 macro ; fenêtre cross 03/08→30/08 :
  site 195 = journeys 195, dont 55 organiques. Funnel(28) : 5 860 entrées organiques, 55 contacts, 0,94 %, 5 346 clics
  GSC, 308 lignes, 0 ligne sans entrée, fenêtre 03/08→30/08. Grain isolé sur la même fenêtre : 5 845 sessions brutes
  vs 5 860 entrées recousues (+0,3 %) — l'écart de +8,3 % de l'audit venait des fenêtres, pas du grain.
- 11:35 `[R]` Contract-tests I4 exécutés via `rpc_contract_check` : `classify_channel_gclid_paid` ok (1 ms),
  `contacts_28j_une_fenetre` ok (4,4 s), `funnel_meme_total_que_journeys` ok (6,5 s).
- 11:35 `[W-PROD]` `apply_migration` `t09_photo_apres_cpi` (version **`20260903093524`**) : job one-shot 09:37 UTC →
  `cooked_cpi_snapshot()`, auto-désarmé. Réussi 11:37:50, `cron.job` t09 = 0.
- 11:36 `[W]` `rpcs.sql` reconstruit (9 corps prod recollés, format d'origine préservé, `write_outputs`) : 125 fonctions,
  sha256 corps `a52e8007…` ; `check_rpcs_sql_fresh.py` OK. Règle CI **C6c** dans `check_migration_paris_date.py`
  (`current_date` / `now() - make_interval` interdits pour les migrations ≥ `20260903093320`, littéraux entre apostrophes
  et commentaires ignorés, `-- c6c:allow`) ; sonde /tmp : 2 violations détectées, 0 sur les migrations T-09.
- 11:40 `[R]` **Comparaison avant/après** (`cpi_pre_restatement_20260903` phase `t09_avant` vs `cpi_daily` 03/09) : 175 → 175
  pages, 175 appariées ; **seul zv bouge** (64 pages), zc/zr/zl/momentum/gate : 0 changement ; delta CPI moyen **+0,33**,
  max |Δ| 27 ; **0 changement de grade** ; 6 movers ≥ 15 pts (garde-à-vue-ou-audition-libre 50→23 B, cap-ferret-relaxe
  11→38 B, abus-de-confiance 62→81 A, sarvi 31→13 A, escroqueries-cryptomonnaies 34→52 C, DDSE 48→30 B) ; 3 badges
  `convertit` changent ; CPI pondéré trafic 45,6 → 45,7.
- 11:43 `[W-PROD]` `apply_migration` `t09_annotation_restatement_fenetre_contacts` (version **`20260903094241`**) :
  annotation posée (4 annotations au 03/09). ACL vérifiées : anon/authenticated false sur les 8 fonctions sauf
  `cooked_page_index` true/true (état antérieur, SECURITY INVOKER — T-19). Miroirs des 4 migrations (versions prod),
  CHANGELOG, CLAUDE.md (bloc restatement contacts 03/09 + signatures), OPERATIONS (RPC attribution, table restatements,
  arbre scripts), cpi doc (en-tête + §Ruptures), CONTRIBUTING (C6c), workflow `sql-contracts.yml`.
- 11:45 `[D]` À reporter : commentaire interne de `cooked_refresh_after_gsc` périmé (T-14) ; `cpi_drop` peut sonner sur
  les 6 movers du 03/09 — annotation posée, périmètre T-07 ; DROP de `cpi_pre_restatement_20260903` au T-19.

### Décisions Nicolas — 03/09/2026 12:0x
- 12:02 `[D]` **T-06** : option **(b)** retenue (momentum sur `gsc_path_daily` total moins les clics brandés révélés par
  qpd), question posée en clair (« sur quoi le momentum doit-il se baser ? »), réponse Nicolas 03/09/2026 ~12:02.
- 12:02 `[D]` **T-08** : **pas d'objectif trimestriel pour l'instant** — la ligne « Contacts nourris par les articles »
  affiche le compteur seul (clé `objectif_assistes_trimestre` laissée absente ; repères donnés : 110 / 90 j, 33 / 28 j).
  Le reste de T-08 (bucket « non attribuable », snapshot au lieu du calcul à l'affichage — `dashboard_assisted_quarter()`
  **dépasse les 30 s aujourd'hui** : ligne masquée, constaté 11:58) reste à faire, sans décision bloquante.

### T-06 — momentum du CPI sur la source complète (03/09/2026, 12:05 → 12:35)
- 12:05 `[R]` Relecture f-01/f-07, corps `cooked_page_index` (CTE `mom` sur `gsc_query_page_daily` non brandé), vue
  `cpi_opportunite_contact` (potentiel × momentum × gate), `alert_rule_cpi_drop`, `cpi_movers`.
- 12:08 `[M]` **Mesure avant** (cpi_daily du jour = après T-09, GSC clos au 30/08) : couverture du momentum (clics qpd non
  brandé / clics totaux) = 28 % (S), 19 % (A), 18 % (B), 12 % (C). Direction du momentum vs clics réels non brandés :
  **15 pages fiables sur 47 en direction inverse** (2 S, 1 A, 12 B) — le contrefactuel de l'audit se reproduit.
  Contrôle par semaine des clics GSC : **chute réelle de ~40 % fin juillet** (2 155 → 1 463 sem. du 27/07, ≈ 1 350/sem.
  depuis) — pas une double ingestion (7 jours × ~2 000 lignes chaque semaine). Non expliqué, hors périmètre T-06, noté.
- 12:12 `[A]` Migration `20260903101159_t06_photo_avant_cpi` : phase `t06_avant` (175 lignes).
- 12:14 `[A]` Migration `20260903101652_t06_momentum_source_complete` (1er essai refusé : `pg_get_functiondef` ne termine
  pas par `;` — générateur corrigé, rien d'appliqué, atomique). Contenu : `mom` = `momf` (gsc_path_daily) − `momb`
  (brandé révélé), position `momp` inchangée ; `cpi_opportunite_contact.potentiel = cpi_compose(zc,zr,zl,0,1,1,true)` ;
  `alert_rule_cpi_drop` + `NOT EXISTS` clics réels 7 j > 7 j précédents ; contract-tests `cpi_momentum_source_complete`
  (≥ 1) et `potentiel_sans_momentum_gate` (= 0) — **ok / ok** au premier run ; `alert_rule_cpi_drop()` s'exécute sans
  erreur (aucun cpi_drop à cet instant).
- 12:17 `[A]` Migration `20260903101736_t06_photo_apres_cpi` : cron one-shot 10:22 UTC → `succeeded` (12:22:00 →
  ~12:23:30 Paris), désarmé.
- 12:25 `[M]` **Mesure après** (même jour, mêmes données GSC) : 175 → 175 pages ; **seul le momentum bouge** (132 pages ;
  zc/zr/zl/zv/gate identiques sur les 175) ; delta CPI moyen **+3,7**, médiane |Δ| 4 ; **0 changement de grade** ;
  31 movers ≥ 15 dont **8 fiables** (notre-cabinet 62→100, accident-moto 52→87, interdiction-de-gérer 56→80,
  assurance-perte-exploitation 43→61, 5-8-millions-notaires 34→52, garde-à-vue-ou-audition-libre 23→40 ;
  abus-de-confiance 81→64, indemnisation-civi 80→60) ; CPI pondéré trafic 45,7 → 45,9 ; momentum moyen 1,065 → 1,139
  (le site baisse de 40 %, une page stable est « ↗ » — c'est le sens du momentum relatif).
  **Contrefactuel rejoué : 0 page fiable en direction inverse** (critère de validation du plan atteint).
  Limite documentée : `/notre-cabinet` (48 → 56 clics totaux, 2 clics non brandés révélés par fenêtre) — les clics brandés
  non révélés restent dans le total, biais de marque résiduel borné à cette page et à la home.
- 12:30 `[A]` Migration `20260903102532_t06_annotation_restatement_momentum` (annotation posée, I10).
- 12:33 `[R]` `rpcs.sql` resynchronisé (3 corps, md5 identiques à la prod), `views.sql`, méta ; CHANGELOG, CLAUDE.md,
  OPERATIONS (table des restatements), doc CPI (source du momentum + rupture de série).
- Reste (T-06) : PR + merge ; vérifier demain (04/09) que `cpi_drop` ne sonne pas sur une page dont les clics montent.

### T-08 — assistés non attribuables + snapshot trimestre (03/09/2026, 11:47 → 14:12)
- 11:47 `[M]` **Mesure avant** (06/08→02/09, live_j1) : `site_macro_counts` / `conversion_journeys` = **191** ;
  `assisted_contacts_by_entry_path` = **179**, bucket `(non rattaché)` = 0. Écart = **12 forms macro** sans
  `cooked_sid`/`cooked_aid`. `dashboard_assisted_quarter` timeout 30 s (recalcule le trimestre à l'affichage).
- 11:47 `[A]` Migrations `20260903114723` (no-op, appliquée par erreur — conservée pour parité) puis
  `20260903114751` (LEFT JOIN + ligne `(non attribuable)`, table snapshot, refresh 180 s, lecture 5 s) ;
  `20260903114815` (`cooked_refresh_after_gsc` 5ᵉ étape) ; `20260903114857` (I4 + 15 `dashboard_*`) ;
  `20260903114858` (one-shot 11:55 UTC).
- 11:53 `[M]` **I4 après** : 191 = 191, dont 12 `(non attribuable)`, écart 0. Contract-test
  `assistes_plus_non_attribuables_eq_site` **ok** (73 s).
- 13:55 `[W-PROD]` One-shot 11:55 UTC **failed 57014** à 180 s exact (CREATE TEMP `_pvk` sur 01/07→02/09).
  28 j = 73 s ; trimestre ≈ 2,3× → ~170 s, trop juste. Job encore actif (unschedule non atteint).
- 14:00 `[A]` Migration `20260903120048` : timeout refresh **600 s**, assisted **300 s** ; unschedule + retry
  12:06 UTC avec `SET statement_timeout='600s'` dans la commande cron (le SET fonction n'arme pas le timer
  pg_cron — retex 01/07).
- 14:06 `[M]` Retry **succeeded** 14:06:00→14:09:30 Paris (**210 s**), job désarmé. Snapshot T3 2026 :
  **94** (01/07→02/09, target NULL). `dashboard_assisted_quarter()` **3 ms**, status ok.
- 14:10 `[A]` Annotation I10 `20260903121037`. Advisors : 0 ERROR ; nouvelle table snapshot en RLS deny-all
  sans policy (même pattern que les autres `dashboard_*_snapshot`).
- Décision Nicolas 12:02 : **pas d'objectif** (`objectif_assistes_trimestre` absent). Le compteur ressources
  n'inclut pas les 12 `(non attribuable)` (JOIN `page_taxonomy`).

### T-07 — alertes v4 (03/09/2026, 14:27 →)
- 14:27 `[M]` **Mesure avant** : 55 non acquittées (34 `cpi_drop`, 9 `gbp_daily_stale`, 8 `gbp_gap`,
  3 `gsc_ingest_missed`, 1 `pipeline_dead` du 22/08) ; 11 critical / 10 j. GSC last day = 31/08.
  GBP last day = 20/08 (vrai retard). `cpi_drop` du jour : 3 pages (2 S/A momentum 1,01 et 1,09 ; 1 B).
- 14:28 `[R]` Replay 40 j `received_at` : trou 166 min le 01/08 13:16→16:02 (diurne, vrai) ; 68,9 min
  le 10/08 02:05 ; 63,3 min le 22/08 03:12 (FP) ; 60,8 min le 03/09 04:56. 0 trou > 90 min hors 01/08.
- 14:32 `[A]` Migration `20260903123218` : `pipeline_dead` âge 90 min + heure active ; `cpi_drop` S/A +
  momentum < 0,90 ; escalade hors `cpi_drop` ; cap 2 pushs ; `volume_floor` ; `ack_alerts` ; `cooked_paris_hour`.
- 14:33 `[M]` Règles à chaud : pipeline / cpi / volume / escalade = **0 ligne** (v4 silencieuse à 14:33).
- Reste : ack des 55 (décision Nicolas) ; deploy `form-webhook` v14 ; PR.

### T-11 — refresh aval robuste à la dérive du cron GitHub (03/09/2026, 16:30 →)
- 16:30 `[F]` Relecture #112, e-02/h-05 (annexes e-refute/h-refute), corps prod de `cooked_refresh_after_gsc`
  (garde « `paris_date(max(ingested_at)) < paris_today()` → skip » + marqueur), `cron.job` (46 : `0 8-20 * * *`,
  2400 s), `cooked_config` (4 clés), `alert_rule_gsc_ingest_missed` (juge après 13:00 Paris), registre
  `freshness_contract` (13 sources ; hints `cpi_daily` / `dashboard_resources_snapshot` citent des jobs fantômes).
- 16:35 `[R]` **Mesure avant.** `gsc_path_daily.ingested_at` : 01/09 11:55 UTC, 03/09 10:35 UTC (planifié 06:00).
  `cron.job_run_details` (jobid 46, runs > 60 s, 45 j) : la séquence part à l'heure qui suit l'ingestion —
  27/08 18:00, 28/08 **19:00** (dernier tick avant fermeture à 20:00), 29/08 13:00, 30/08 12:00, 31/08 13:00,
  01/09 12:00, 02/09 11:00, 03/09 11:00 UTC ; durées 1 343-1 621 s ces 8 jours, p50 ≈ 1 600 s / 30 j, max 2 166 s
  (05/08), **7 runs à 2 400 s le 26/07** (timeout). `return_message` = « 1 row » partout : aucune durée par étape.
  Alertes `gsc_ingest_missed` : 27/08, 28/08, 31/08 (= les 3 retards > 13:00 Paris).
- 16:40 `[D]` Fenêtre **`0 6-21`** et non `0 6-23` (plan) : `cooked_cpi_snapshot` date le snapshot avec
  `paris_today()` ; un tick à 22 ou 23 h UTC (00:00-01:00 Paris l'été) écrirait la ligne au lendemain et le jour
  courant manquerait. 21 h UTC = 23 h Paris = dernier tick sûr. L'ingestion la plus tardive observée : 18:07 UTC.
- 16:45 `[D]` Pas de nouvelle alerte « GSC après 12:00 UTC » : `gsc_ingest_missed` existait déjà (13:00 Paris) —
  recalée sur **12:00 UTC** (heure du cron), libellé « en retard » + commande de relance. Ajout de
  `refresh_after_gsc_stale` (critical : ingestion > 3 h non suivie, fenêtre 8-23 h UTC, muette si un
  `refresh_step_failed_*` a déjà sonné) et `refresh_budget` (warn ≥ 80 % de `refresh_after_gsc_budget_s`).
- 16:52 `[A]` `apply_migration` **`20260903145256_t11_refresh_after_gsc_robuste`** : table `refresh_runs`
  (RLS deny-all, service_role), clé `refresh_after_gsc_budget_s` = 2400, `cooked_refresh_after_gsc_pending()`,
  orchestrateur réécrit (garde par marqueur, une ligne `refresh_runs` par étape + `_total`, marqueur = `now()` début
  de transaction pour rejouer une ingestion arrivée pendant la séquence), cron `0 6-21 * * *`, 3 règles d'alerte,
  2 hints du registre, `run_rpc_contract_tests` + 2 contrats I9. C6/C6b/C6c OK en local.
- 16:53 `[R]` Vérifs à chaud : `pending()` = false (« séquence complète 13:00 après ingestion 12:35 » Paris) ;
  appel direct → `skip:` ; `cron.job` = `0 6-21 * * *` actif ; 3 règles → 0 ligne ; ACL anon/authenticated = false
  sur les 5 fonctions.
- 16:54 `[A]` `apply_migration` **`20260903145344_t11_validation_rerun`** : marqueur reculé à 10:00 UTC (< ingestion
  10:35) → `pending()` = **true** (« ingestion du 12:35 non suivie… dernier complet 12:00 » Paris). Attendu : le tick
  de 15:00 UTC (17:00 Paris) rejoue la séquence et remplit `refresh_runs` (6 lignes).
- 16:58 `[W]` Miroirs des 2 migrations, `doc_constants.json` (`0 6-21`), OPERATIONS (table crons : 5 jobs fantômes
  remplacés par l'orchestrateur ; § GSC ; table alertes +3), CLAUDE.md (réflexe n° 4 `pending()`, cron CPI),
  CHANGELOG, workflow **`rpcs-regenerate.yml`** (régénère `rpcs.sql` en CI avec `DATABASE_URL_RO` — une session
  locale ne l'a pas ; Cursor a dû l'avoir).
- 17:00 `[R]` Tick 15:00 UTC : la séquence est partie (pid actif, `CREATE TEMP TABLE _cooked_ev…`), preuve que la
  garde par marqueur déclenche hors de l'ancienne condition « ingestion du jour ». Rejeu ≈ 25 min, une seule
  transaction : `refresh_runs` ne se remplit qu'à la fin.
- 17:06 `[W]` PR #134 mergée par Nicolas (CI prod-drift + SQL contracts vertes) ; #133 (workflow `rpcs-regenerate`)
  mergée avant. `rpcs.sql` régénéré en CI : 132 fonctions, sha aligné prod.
- 17:15 `[D]` **Nicolas arrête l'attente** (« ça prend trop de temps »). Non lu à la main : les 6 lignes `refresh_runs`
  du rejeu et le marqueur ré-avancé. **Filet** : les contrats `refresh_runs_after_ingest` et
  `refresh_after_gsc_not_pending` tournent à 03:30 UTC (`run_rpc_contract_tests`) et l'alerte
  `refresh_after_gsc_stale` sonne à 15 h Paris si l'ingestion de demain n'est pas suivie. À lire demain 04/09 :
  `SELECT * FROM refresh_runs ORDER BY started_at DESC;` puis cocher la validation dans #134.
- 17:35 `[R]` **Rejeu lu** (une requête, après l'arrêt de l'attente) : `refresh_runs` = 6 lignes, run 17:00:00 Paris,
  `_total` **1 620 s** ok (cpi 60 s · dashboard 173 s · expertises 138 s · **assisted 1 021 s** · quarter 226 s) ;
  marqueur ré-avancé à 17:00 ; `pending()` = false ; 0 alerte ouverte. Contrats I9 passés à la main
  (`rpc_contract_check`) → `latest_rpc_health()`. **T-11 terminé au sens §3.9 du prompt** (PR #134 mergée, miroirs,
  `rpcs.sql` régénéré, effet montré, docs). Constat neuf pour T-10/T-13 : l'étape assistés = 63 % de la séquence.

## Phase 3 — suite (session du 03/09/2026 soir, Claude Fable 5.1, worktree `friendly-euler-39e8a2`)

- 22:47 `[D]` Reprise sur instruction de Nicolas (03/09/2026 22:47, message de session) : « Reprend le prompt et va
  au bout stp. » Lue comme la validation d'exécuter les tickets encore ouverts du plan (tous `ready-for-agent`
  depuis le tri du 03/09) puis de clore la Phase 4 ; les décisions et actions Nicolas (T-02, Wix, secrets, DROP)
  restent des arrêts. Ordre : T-10 → T-13 → T-14 → T-15 → T-16 → T-17 → T-18 → T-19 → T-20 → Phase 4.
- 22:48 `[R]` Réflexes : `alerts WHERE NOT acked` = **0** ; `gsc_last_data_day()` = 31/08 ; heure Paris 22:48.

### T-10 — fraîcheur mesurée sur la donnée, couture horodatée (03/09/2026, 22:50 → 23:20)
- 22:50 `[F]` Relecture #111, g-03/c-02/c-04/e-06 (01-audit.md:190-221), `FreshnessBanner.tsx` (`ageHours > 36`,
  `cookedGap` affiché mais jamais orange), `freshness_contract` (13 lignes : `dashboard_resources_snapshot` sur
  `paris_date(max(refreshed_at))`), corps prod `alert_rule_freshness`, `refresh_identity_stitch` (DELETE+INSERT, aucun
  horodatage), `cooked_alerts_refresh` (ramasse `alert_rule_%` à 0 argument), `run_rpc_contract_tests` (md5 disque =
  prod `62ea9362…`).
- 22:52 `[R]` **Mesure avant.** `cron.job_run_details` job 42 : 30 succès / 30 j, 17-25 s, « 1 row ». `cooked_config` :
  5 clés, aucune `identity_stitch_*`. Couverture : J-1 (02/09) **429/429** sessions humaines cousues ; J-2 **416/416**
  (0,5 s, index `idx_events_paris_date`). `dashboard_resources_snapshot` : `cooked_end` 02/09, `refreshed_at` 03/09
  17:00, `paris_today` 03/09. `page_taxonomy` : 456 lignes, 437 catégorisées, `max(updated_at)` 31/08 11:05.
  Consommateurs d'`identity_stitch` (rpcs.sql) : `assisted_contacts_by_entry_path`, `conversion_journeys`,
  `seo_to_contact_funnel` (fenêtres closes J-1 depuis T-08/T-09), `math_*` (hors périmètre). Lens `live` :
  `site_kpis_compare`, `cooked_pages_snapshot` — sessions brutes, sans couture.
- 22:58 `[D]` Écart au plan, assumé : « `paris_today() - cooked_end >= 2` ⇒ orange » sonnerait **chaque matin** (la
  séquence suit l'ingestion GSC, ~13-15 h Paris : J-2 de 00:00 à la séquence est l'état normal — g-03 le mesurait
  à 13,5 h/j). Règle retenue : orange si J-3 à toute heure, ou J-2 **après 16 h Paris** ; registre : warn > 2 j,
  critical > 4 j ; le grain horaire reste aux alertes T-11 (`gsc_ingest_missed` 12:00 UTC, `refresh_after_gsc_stale`).
  Rejeu du 28/08 : orange de 16:00 à 21:00 le 28/08 ; dès 00:00 le 29/08 si rien n'avait suivi (J-3).
  `identity_stitch` : pas de ligne au registre (grain jour) mais une règle dédiée à l'heure (30 h / 54 h), comme
  demandé par le plan ; page_taxonomy au registre (warn 21 j). Pas de drapeau `grain_partiel` : aucune RPC en
  périmètre ne mélange plus couture et jour en cours → `COMMENT ON FUNCTION` sur les deux RPC lens `live`.
- 23:05 `[W]` Migration `t10_fraicheur_donnee_couture_horodatee` écrite (registre, `refresh_identity_stitch` +
  horodatage `cooked_config`, amorce depuis le dernier succès cron, `alert_rule_identity_stitch`, 2 contrats I7,
  ACL, commentaires). C6/C6b/C6c OK (`-- c6c:allow` sur le `make_interval` d'origine de la couture).
  Dashboard : `lib/freshness.ts` (pur, `now` injecté) + 9 tests (rejeu 28/08 matin/après-midi, J-3, J-1, 36 h,
  GSC, live) ; `FreshnessBanner` rebranché ; vitest 121/121, tsc, eslint OK.
- 22:58 `[W-PROD]` `apply_migration` → version **`20260903205820`** (clés `cooked_config` écrites 22:58 Paris : `identity_stitch_refreshed_at` = 03/09 05:40:17, `identity_stitch_rows` = 121 237) ; fichier local renommé.
- 23:12 `[R]` **Après.** `alert_rule_identity_stitch()` = 0 ligne ; `alert_rule_freshness()` = `gbp_daily_stale`
  seul (20/08, retard GBP connu) ; registre : `dashboard_resources_snapshot` sur `max(cooked_end)` (1/2/4),
  `page_taxonomy` (7/21/—). Contrats via `rpc_contract_check` : `identity_stitch_couvre_j2` **ok** (0 ligne,
  123 ms), `identity_stitch_horodatee` **ok** (1). Routines : 134.
