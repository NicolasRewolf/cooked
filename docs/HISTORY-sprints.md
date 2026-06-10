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
| 09-10/06 | **37** | Tracker sprint37 : execution guard `__cookedLoaded` (neutralise le double-embed Wix), batching {events:[…]} (−57 % POST), seeding champs cachés `cooked_aid`/`cooked_sid` ; webhook v10 ; dédup rétroactive double-embed (**restatement : phone 28j 110→95, +13,6 % corrigé**) ; `page_taxonomy` + `cooked_page_type` ; attribution lecture (`form_submits_attributed`, `conversion_journeys`, `content_performance`) ; `seo_to_contact_funnel` ; table `alerts` + cron horaire ; purge vestiges ; suite tests tracker (28 asserts) ; audit qualité données (verdict : sain) |
| 10/06 | **38** | **CPI v2.1** : `cooked_page_index(days)` + `cpi_daily` + cron 07:30 UTC. Conçu, validé en live (3 bugs de calibration trouvés et corrigés : couverture GSC scalée, λ_pos 0,08, cpi borné + badge), premier snapshot 192 pages / CPI pondéré 32 / 446 clics perdus. Reste P1 : validation prédictive à J+28 (Spearman CPI→Δcontacts > 0,3) |

## Constantes du projet

- Projet Supabase : `mxycmjkeotrycyneacje` — site : `https://www.jplouton-avocat.fr`
- Tracker en prod : **sprint37** depuis le 10/06/2026 ~01:00 Paris
  (limite Wix Custom Code : 15 000 caractères — minifié à 14 649)
- 6 crons pg_cron actifs (cf. README) ; GSC ingéré à 06:00 UTC ; lag J-2
- Le client final des chiffres : Me Plouton (+ Adrien, Nomad Marketing)
