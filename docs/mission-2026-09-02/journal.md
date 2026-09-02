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
