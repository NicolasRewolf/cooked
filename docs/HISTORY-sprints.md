# Chronologie des sprints — Cooked

Une ligne par jalon. Sources : CLAUDE.md, README.md, migrations,
docs/audits. Les sprints non listés n'ont pas laissé de trace durable.

| Quand | Sprint | Quoi |
|---|---|---|
| 05-06/05/2026 | bootstrap | Tracker live (première ingestion réelle 06/05 19:14 Paris) ; schéma `events` ; proxy Velo same-origin |
| ~08-10/05 | 12-13 | Retex fondateur : critères de validation explicites, math nudge, mode itératif ; canonicalPath (decode+NFC+slash) ; `tracker_first_seen_global()` |
| ~12/05 | 17 | Bot filtering : `bot_fingerprints` + vue `events_human` (= events − bots − noise) |
| ~13/05 | 18 | `form_submit` server-side : Edge Function `form-webhook` + Wix Automations |
| ~14/05 | 19 | `cta_anchor_click` |
| 15/05 | 20-22 | Filtres prefetch + noise_sessions ; `anonymous_id` en localStorage `_ckd_aid` |
| 16-17/05 | 23-27 | anchor dans cta_breakdown ; invariants identité webhook (S24) ; pipeline_health ; dédup form_submit ; revokes anon ; layer1 bots + `cta_anchor_label_map` ; contract tests nocturnes → `rpc_health` (S27) ; rétention 400j |
| 18-21/05 | 28-30 | `classify_channel` ; session 30 min localStorage ; noise refresh horaire ; clock-skew guard ; drop zombies ; hardening + perf ; tracker sprint30 (21/05 21:19) |
| 21-22/05 | 31-32 | **GSC dans Cooked** : 3 tables (`gsc_path_daily`, `gsc_query_daily`, `gsc_query_page_daily`), backfill 16 mois, Service Account |
| 22-25/05 | 33 | Daily ingest GSC (Actions 06:00 UTC, --months 1 auto-cicatrisant) ; DataForSEO hebdo ; RPCs cross-source (period_bounds, kpis_compare, pages_overview_unified, pulse, funnel, opportunities) ; dashboard Next.js créé PUIS supprimé (25/05) → Q&A ad-hoc via Claude Code + MCP |
| 27-31/05 | 34 | form_submit hors « Nous rejoindre » ; macro dry ; data lens ; perf indexes |
| 03/06 | 35 | Fix anchor chrome UI : ~90 % des `cta_anchor_click` étaient du Cookiebot/burger/nav — corrigé tracker + rétroactif (`cooked_is_chrome_anchor`) |
| ~05/06 | 36 | `click_internal` (attribution élément → page cible) |
| 04-07/06 | — | Paris date seam ; session restitch MPA ghosts |
| 09-10/06 | **37** | Tracker sprint37 : execution guard `__cookedLoaded` (neutralise le double-embed Wix), batching {events:[…]} (−57 % POST), seeding champs cachés `cooked_aid`/`cooked_sid` ; webhook v10 ; dédup rétroactive double-embed (**restatement : phone 28j 110→95, +13,6 % corrigé**) ; `page_taxonomy` + `cooked_page_type` ; attribution lecture (`form_submits_attributed`, `conversion_journeys`, `content_performance`) ; `seo_to_contact_funnel` ; table `alerts` + cron horaire ; purge vestiges ; suite tests tracker (jsdom, source + minifié) ; audit qualité données (verdict : sain) |
| 10/06 | **38** | **CPI v2.1** : `cooked_page_index(days)` + `cpi_daily` + cron 07:30 UTC. Conçu, validé en live (3 bugs de calibration trouvés et corrigés : couverture GSC scalée, λ_pos 0,08, cpi borné + badge), premier snapshot 192 pages / CPI pondéré 32 / 446 clics perdus. Reste P1 : validation prédictive à J+28 (Spearman CPI→Δcontacts > 0,3) |
| 15-18/06 | **39** | **Consolidation & passage en prod opérationnelle.** Edge `track` v22 (`click_internal.target_path` décodé + backfill 143 lignes — bug P1 résolu) ; `snapshot_pages_export` réparée (colonnes email_clicks droppées S30 → 0) ; **CPI v2.2** (momentum transition continue + empirical Bayes dynamique par type) ; alertes recalibrées (`double_embed_suspect` = sessions pageview/web_vitals dupliquées même-seconde, seuil 30 ; `cpi_drop` = vrai decay momentum/capture, exclut la volatilité conversion) ; vue `cpi_gisement` (pilotage conversion : potentiel vs conversion réalisée) ; 3 revues d'experts du CPI → verdict « outil suffisant, complexité refusée, levier = action sur le gisement » ; croisement export Wix ↔ `form_submit` (comptage fiable, aucun raté) |
| 01-03/07 | **audit Fable 5** | **Audit complet + plan de correction T-01→T-19 exécuté à 100 %** (Fable 5 pilote, Opus 4.8 exécute — docs/audit-fable5-2026-07-02.md + plan-correction). Justesse : trou GSC fin de mois réparé + backfillé (31/05, 30/06) + alerte `gsc_gap` (a sonné et s'est résolue en réel) ; canal IA fiabilisé (`classify_channel` v2 utm_source, ~35 % du canal récupéré, restatement) ; clamp horloge Edge **v23** + webhook **v11** (drop → alerte) ; tracker **sprint40** (page_exit ré-armé après retour d'onglet — ~10 % des lectures sous-comptées) + grain session×path dans CPI/dashboard → **restatement CPI léger (±7 pts, 4 pages A/B ; gate avant/après + plancher de bruit ; 8 pages C sorties du scoring)** ; `target_path` unaccent (8 backfills). Fiabilité : filtres bruit incrémentaux 48 h (**155 s → 4 s**) ; purge hebdo bruit > 28 j (`purge_cooked_noise`, 41 589 lignes au 1er run) + TTL 90 j `noise_sessions` ; **alertes push ntfy** (critical → téléphone, testé de bout en bout) ; retries GSC, dfs hard-fail, alerte `tracker_drift` (grâce 48 h), sécurité `cpi_gisement` (security_invoker + revoke anon — advisor ERROR fermé). **Protocole validation CPI J+28 corrigé avant le 08/07** (Δcontacts anti-corrélé par régression vers la moyenne → cible niveau futur + comparaison par tiers ; dual-ratio dry-run : complet 3,18 / sans conversion 0,00). Taxonomie : seed sitemap (+46 posts) + purge 9 paths poubelle + garde-fous heuristique (T-19) ; **scope officiel des 14 pages expertise** (T-20fix — 2 pages 301 sorties, droit-penal/proces-criminel entrés). Dashboard : onglet **Expertises** channel-aware (~71 % paid ; droit-penal 21 %) ; **Vague A** : drill-down `/article/[slug]`, filtres (recherche/thème/santé), colonne **« contacts assistés »** (attribution page d'entrée — 12/90 j, recoupé). Swarm de bots ~20/06→ (bruts ×5, `events_human` stable) documenté + trigger de réouverture du guard. **Backup externe décliné** (décision Nicolas 02/07 — workflow inerte dans le repo). |
| 29-30/06 | **dashboard V1 + fiabilité** | **Dashboard V1 lecture-seule** (Next 16 + Supabase, sous-app `dashboard/`, articles ressources) live sur data.rewolf.studio ; RPC `dashboard_*` sur snapshots quotidiens ; auto-analyse multi-agents → fixes (allowlist fail-closed, garde de fraîcheur, KPI SEO calculés SQL). **Incidents pipeline résolus** : cron CPI gelé depuis le 21/06 (timeout, `cpi_daily` figé 8 j) réparé + rattrapé ; filtres bruit durcis (`TRUNCATE`→`DELETE`, fin des deadlocks) ; snapshot SEO stopgap 1500 s ; `refresh_pipeline_health()` ne crashe plus en incident. **Ménage repo** (audit multi-agents) : scaffold/doublons SQL morts supprimés, CI tracker câblée, doc resynchronisée. |

## Constantes du projet

- Projet Supabase : `mxycmjkeotrycyneacje` — site : `https://www.jplouton-avocat.fr`
- Tracker navigateur en prod : **sprint40** depuis le 02/07/2026 ~20:00 Paris
  (page_exit ré-armé ; limite Wix Custom Code : 15 000 caractères, minifié
  14 068). Edge Function `track` en **v23** (clamp horloge ±48 h),
  `form-webhook` en **v11** (submissionTime validé, drop → alerte)
- 11 crons pg_cron + 3 GitHub Actions (cf. docs/OPERATIONS.md) ; GSC ingéré
  à 06:00 UTC, fenêtre `--months 2` ; lag J-2/J-3
- Le client final des chiffres : Me Plouton (+ Adrien, Nomad Marketing)
