# CLAUDE.md — instructions pour les sessions Claude Code travaillant sur ce repo

> Ce fichier est lu automatiquement au démarrage de chaque session
> Claude Code dans ce repo. Il définit le périmètre d'autonomie de
> l'agent et les règles dures à respecter.

---

## Identité du projet

`cooked` est un **système d'analytics first-party** (cookieless,
RGPD-exempt, non échantillonné) pour le site `jplouton-avocat.fr`
(Wix Studio). Depuis Sprint 31-32 (21-22/05/2026), Cooked ingère
**aussi Google Search Console** pour les analyses cross-source
acquisition × comportement on-page. Tout dans le même projet
Supabase, plus de pipeline séparé. Stack :

```
tracker.html (Wix Custom Code)
   ↓
Velo HTTP proxy (/_functions/track) — same-origin
   ↓
Supabase Edge Function `track` (Deno)
   ↓
events table (Supabase Postgres)
   ↓
events_human view (events MINUS bots MINUS noise)
   ↓
seo_url_snapshot (rebuilt nightly via pg_cron)
   ↓
RPCs internes consommées par les analyses

   +

scripts/gsc_ingest.py + gsc_common.py  (Service Account → API GSC)
   ↓
gsc_path_daily        — day × path        (~121k rows, 16 mois)
gsc_query_daily       — day × query       (~872k rows, 16 mois)
gsc_query_page_daily  — day × path × query (~1M rows, brique
                        d'attribution query → landing, Sprint 32)
```

**Dashboard de lecture (V1, depuis le 29/06/2026).** Après une période
sans UI (l'app `dashboard/` initiale supprimée le 25/05/2026), une
sous-app **Next.js 16 isolée** a été reconstruite dans `dashboard/` :
vue lecture-seule des **articles ressources** (comportement Cooked + SEO
par requête, volume DataForSEO en référence). Live sur
**data.rewolf.studio** (Vercel, rootDir=`dashboard`), lectures
server-side via clé service, auth Supabase magic-link + allowlist.
Détails : `dashboard/CLAUDE.md` + `dashboard/README.md`. Le mode
principal reste le **question/réponse ad-hoc** via Claude Code + MCP
Supabase ; les RPCs publiées restent l'API canonique — le dashboard en
consomme un sous-ensemble (`dashboard_*`).

Capture côté browser : pageview / scroll_depth / engagement_tick /
web_vitals / click_outbound / page_exit / cta_phone_click /
cta_booking_click / cta_anchor_click (Sprint 19) / click_internal
(Sprint 36 — nav interne : quel élément mène à quelle page, placement +
target_path). Plus `form_submit`
inséré directement par la deuxième Edge Function `form-webhook` qui
reçoit les webhooks Wix Automations (Sprint 18). Bot filtering via la
vue `events_human` (Sprint 17 ; Sprint 37 : dédup des clics dupliqués
même-seconde causés par le double-embed du snippet — phone +13,6 % corrigé
rétroactivement ; Sprint 39 : diagnostic complété — artefact de mesure +
comportement « tapeur », pas un bug systémique ; alerte `double_embed_suspect`
recalibrée sur les sessions réellement dupliquées, seuil 30).

**Sprint 37 (09/06/2026) — attribution & fiabilité :**
- Tracker `sprint37` : execution guard (`window.__cookedLoaded`), batching
  ({events:[…]} — flush 30 s / 10 events / pagehide ; events critiques
  immédiats) → −60/70 % de requêtes, et seeding des champs cachés Wix
  `cooked_aid`/`cooked_sid` dans les formulaires (⚠️ seeding DOM mort-né,
  remplacé au sprint38 — voir bloc Sprint 38).
- Webhook `form-webhook` v10 : lit les champs cachés → `props.cooked_aid`/
  `cooked_sid` (les colonnes identité restent `webhook-…`, invariants
  Sprint 24/29 préservés). L'attribution vit en LECTURE :
  - `form_submits_attributed(days)` — hidden_field > temporal_unique >
    unresolved (75 % résolu avant champs cachés, ~95 % attendu après).
  - `conversion_journeys(days)` — un row par contact macro avec entry_path,
    entry_channel, journey[] (séquence de pages), device.
  - `content_performance(days)` — perf par page_type × theme (sessions,
    dwell/scroll médians, booking_intents, contacts assistés).
- Taxonomie : `cooked_page_type(path)` (cabinet/hub/expertise/post/blog-nav)
  + table `page_taxonomy` (theme par heuristique slug, source tracée ;
  la catégorie Wix ressource/classique reste NULL — non déductible du slug,
  à enrichir via le hub).
- Vestiges purgés : events_stitched, session_canonical_id,
  sessions_corrected_daily ; views.sql resynchronisé avec la prod.
- Monitoring : table `alerts` + `cooked_alerts_refresh()` (cron horaire
  `15 * * * *`) — pipeline mort, récidive double-embed, santé RPCs S37,
  attribution dégradée, retard GSC. Réflexe : `SELECT * FROM alerts
  WHERE NOT acked`.
- `seo_to_contact_funnel(days)` — la boucle GSC → landing → contacts
  (entry_channel LIKE 'organic%' : classify_channel retourne
  organic_google / organic_other / organic_ai).

**Sprint 38 (10/06/2026) — CPI (Cooked Page Index) :**
- `cooked_page_index(days)` — score santé 0-100 par page : capture GSC
  (standardisation indirecte sur la courbe CTR propre du site, loi de
  puissance R²=0,917), rétention/lecture organiques (cascade orthogonale,
  empirical Bayes), conversion (direct + assists dilués 1/L +
  0,25×bookings), momentum log-symétrique **relatif au site**, gate LCP.
  Grades de confiance A/B/C. Spec complète et grille de lecture :
  `docs/cpi-cooked-page-index.md`.
- Snapshot quotidien `cpi_daily` (cron `30 7 * * *`, 90 min après
  l'ingest GSC) → trajectoire du score lui-même = alerte decay précoce.
- Premier snapshot 10/06/2026 : 192 pages, CPI pondéré trafic 32,
  446 clics perdus/28j.
- Reprise 10/06 après-midi : vue `cpi_movers` (dérivée ~7j du CPI, delta_z
  par composante, statuts present/nouveau/disparu — premier rendu ~17/06)
  + alerte `cpi_drop` (chute ≥15 pts d'une page grade A/B) dans
  `cooked_alerts_refresh()` ; harnais de validation J+28 committé
  (`scripts/cpi_validation_j28.sql`, à lancer dès le 08/07/2026 — dry-run :
  stabilité poids τ-b≥0,952 PASSE, calibration CTR R²=0,915 stable) ;
  idées v2.2 instruites dans la doc CPI (thèmes NO-GO, INP go-si-relatif,
  cannibales défer).
- Form attribution v2 (11/06) : Wix Forms V2 **ne rend pas les champs
  cachés dans le DOM** de la page publiée → le seeding DOM du S37 ne
  pouvait pas fonctionner (payloads sans `field:cooked_aid`). Remplacé :
  tracker `sprint38` expose les ids en query params (`replaceState`,
  jamais crawlé, paths Cooked sans query) ; `wix/masterpage-cooked.js`
  (Velo, collé dans masterPage.js) les lit via `wixLocation.query` et les
  pose par `setFieldValues()` — le rail du `page_source` de
  faq-system.js. Webhook v10 inchangé. **Première attribution
  `hidden_field` vérifiée le 11/06/2026 à 08:53** (form de test Nicolas,
  compte comme contact macro dans les chiffres du 11/06). Champs cachés
  ajoutés au « Formulaire Divorce » par Nicolas le 11/06 après-midi (à
  vérifier à la première soumission).
- Reprise 11/06 après-midi : table `annotations` (événements hors-site,
  migration `20260611201942`) ; **catégorie Wix Blog renseignée dans
  `page_taxonomy`** via l'API Wix MCP (56 `ressource` / 328 `classique`,
  migration `20260611202556`) ; constat P1 `click_internal.target_path`
  URL-encodé (101/391 sur 28j) — **RÉSOLU au Sprint 39** (voir ci-dessous).

**Sprint 39 (15-18/06/2026) — consolidation & passage en prod opérationnelle :**
- Edge Function `track` **v22** : `click_internal.target_path` décodé
  (`canonical_path(url_decode(...))`) + backfill rétroactif de 143 lignes
  (migration `20260615234052`) → le constat P1 du Sprint 38 est clos. Lire
  `target_path` est désormais direct (plus de décodage à la volée).
- `snapshot_pages_export` réparée (`20260615220500`) : elle référençait des
  colonnes `email_clicks_*` droppées au Sprint 30 → renvoie `0::bigint`,
  contrat de sortie préservé (cassée depuis le 21/05).
- **CPI v2.2** (`20260616142127`) : momentum à **transition continue** (fin
  de la bascule discrète à 20 clics) + lissage **empirical Bayes dynamique**
  (Beta-Binomial, κ estimé par type) pour rétention/lecture. corr 0,9855 avec
  v2.1, aucun verdict fiable A/B déplacé ≥5 pts. Sensibilité connue : la
  conversion porte ~65 % de la variance du score (point ouvert, à juger au J+28).
- Alertes recalibrées : `double_embed_suspect` (`20260616082041`) compte les
  **sessions distinctes** avec pageview/web_vitals dupliqués même-seconde
  (seuil 30) — fini les faux positifs sur un visiteur « tapeur » ; le
  double-embed est un artefact de mesure + comportement, pas un bug systémique.
  `cpi_drop` (`20260617215132`) n'alerte que sur un **vrai decay** (momentum
  ≤ −0,10 OU capture delta_zc ≤ −0,5), exclut la volatilité pure de la
  conversion (un contact qui sort de la fenêtre 28 j faisait plonger une page
  de ~50 pts sans déclin réel).
- Vue **`cpi_opportunite_contact`** (`20260723212008`, ex-`cpi_gisement`) : pilotage
  conversion. Relit le dernier `cpi_daily` et sépare le **potentiel**
  (capture+rétention+lecture, hors conversion, renormalisés) du badge
  **conversion réalisée** ; **ne complexifie PAS le CPI** (aucun nouveau calcul).
  Opportunité de contact = `grade IN ('S','A','B') AND NOT convertit ORDER BY
  potentiel DESC` = pages à fort trafic qui ne convertissent pas → où poser un
  pont vers le contact (croiser avec l'intention : indemnisation > pénal éducatif).
  Alias déprécié : `cpi_gisement`.
- Décision produit : 3 revues d'experts externes du CPI passées au crible
  (fenêtre zv étendue, attribution non conservée, MAD saturée, score 2-volets…).
  Verdict — **l'outil est suffisant, on ne le complexifie pas** : le benchmark
  a montré que « réparer » zv en continu est une impasse vu la rareté des
  contacts (~10/mois **attribuables par page en organique** — le site fait
  ~170 contacts macro/28 j toutes sources). Le levier est l'**action sur les
  opportunités de contact**, pas une
  v2.3. **On passe en prod opérationnelle : focus site (conversion), plus
  l'outil.**
- Croisement export Wix ↔ `form_submit` Cooked validé : Cooked ne rate aucun
  formulaire (comptage fiable).
- Bug **SITE** (hors Cooked) repéré : sur la home, les boutons d'ancre
  « Domaines d'expertises »/« Nos affaires » pointent vers `/` au lieu d'une
  ancre → rechargent la page si le JS Wix n'est pas prêt (≈ plusieurs clics
  nécessaires). À corriger côté Wix Studio.

**Audit 01-03/07/2026 (Fable 5 × Opus 4.8)** — audit complet puis plan
T-01→T-19 exécuté à 100 % (détail : docs/audit-fable5-2026-07-02.md +
docs/plan-correction-audit-2026-07-02.md, chronologie : HISTORY-sprints).
À retenir pour les sessions futures :
- **Tracker `sprint40`** (02/07 ~20:00, page_exit ré-armé) ; **Edge `track`
  v23** (clamp horloge ±48 h, `props.clock_clamped`) ; **webhook v11**
  (submissionTime validé, drop → alerte `form_submit_dropped`).
- **Restatement CPI du 02/07** (grain lectures session×path) : ±7 pts max,
  4 pages A/B (sarvi 52→45…), 8 pages C sorties du scoring (159 vs 167).
  Un « avant/après 02/07 » dans cpi_daily n'est PAS un decay.
- **`classify_channel` v2** : IA détectée aussi par utm_source (restatement
  canaux, ~35 % du canal organic_ai récupéré).
- **GSC : fenêtre `--months 2`** (la fenêtre mois-calendaire perdait les
  fins de mois — 31/05 et 30/06 backfillés) + alerte `gsc_gap`.
- **Purge hebdo du bruit > 28 j** (`purge_cooked_noise`) + filtres bruit
  incrémentaux : supprimer du bruit ne change aucun résultat.
- **Alertes critical poussées sur ntfy** (topic dans `cooked_config`).
- **Dashboard 3 onglets** (Articles Ressources / Expertises / SEO) +
  fiches `/article/[slug]` + colonne « contacts assistés » (attribution
  page d'entrée). Les 14 pages expertise = liste business explicite dans
  `refresh_dashboard_expertises_snapshots` (PAS d'énumération heuristique).
- **Backup externe : décliné par Nicolas le 02/07** (risque assumé) — ne
  plus le proposer avant ~juin 2027 (purge 400 j des events réels).

**Revue architecture 10/07/2026 (Arch #1–#5, PRs #60–#61)** — 2e passe
après C1–C9 ; tue les fuites SQL restantes :
- **`live_j1`** dans `cooked_period_bounds` : fenêtre dashboard ancrée J-1
  Paris (lens `live` inchangé pour `site_kpis_compare` « aujourd'hui ») ;
  fin des 11 blocs `v_shift` copiés.
- **`gsc_is_branded(query)`** : prédicat unique branded GSC (vecteur
  `contracts/branded_query_vectors.json`).
- **`cooked_snapshot_window(w, grain)`** : driver bornes `live_j1` + GSC +
  `cooked_events_window` pour les 3 refreshers dashboard.
- **`supabase/rpcs.sql`** : miroir lecture des 105 corps RPC (`pg_get_functiondef`) ;
  gate CI `check_rpcs_sql_fresh.py` si migration redéfinit une RPC.

**Revue architecture D4–D9 (10/07 soir, PRs #57–#65)** — chantiers opportunistes
mergés sur `main` :
- **D4** `_shared/track_row.ts` + `form_row.ts` — Edge track **v25**, webhook **v12**.
- **D7** `dashboard/src/data/view-models.ts` — pages → props UI testables.
- **D8** `lib/chart-geometry.ts` — géométrie SVG partagée.
- **D6** `metric-columns.tsx` — colonnes Resources / Expertises dédupliquées.
- **D9** helpers tracker (`labelOf`, `inStickyAncestor`…) — iso-comportement.

**12/07/2026 — couture d'identité (PRs #68–#69)** :
- Bug tracker : rotation aid/sid sur wipe de storage → ~22 % des sessions
  coupées, ~95 % des `cta_phone_click` sans amont visible.
- Fix : table **`identity_stitch`** (composantes connexes aid↔sid, cron
  03:40 UTC, 90 j) + `refresh_dashboard_resources_assisted` **v2** (assistés
  ressource 28 j : 16→37) + **`conversion_journeys` v2** recousue (migration
  `20260712203935` ; funnel + content_performance réparés par héritage).
- **Restatement CPI du 12/07 au soir** (voir avertissement plus bas) ;
  tracker **`sprint41`** déployé le 12/07 ~22:20 (vérif J+1 du 13/07 : OK).

⚠️ **Restatement CPI du 12/07/2026** (couture d'identité, `conversion_journeys`
v2) : le `cpi_daily` du 12/07 a été restaté — seule la composante conversion
zv bouge (zc/zr/zl/momentum/gate inchangés page par page), delta moyen
−0,1 pt, 0 changement de grade, 7 movers ≥15 pts (dont arnaque-en-ligne
41→100 et /nos-affaires 67→12 qui rend un crédit usurpé). Annotation posée
dans `annotations`. **Un « avant/après 12/07 » dans cpi_daily n'est PAS un
decay.**

⚠️ **Restatement CPI du 27/07/2026** (`classify_channel` v3 — GMB) : les clics
venant de la fiche Google (`utm_source=gmb`) sortent du canal `organic_google`,
donc du CPI, de `conversion_journeys` et de `seo_to_contact_funnel`. Sur la
home : n_org 305→164, grade S→A, zv en baisse. Annotation posée dans
`annotations`, photo dans `cpi_pre_restatement_20260727` (migration
`20260727215805`). **Un « avant/après 27/07 » sur la home n'est PAS un decay.**

Tables d'audit `cpi_pre_restatement_20260712` / `_20260727` : **supprimées le
10/08/2026** (migration `20260810093206_rangement_post_pivot_secib` — qui
désarme aussi le VACUUM FULL annuel du 26/07 et crée l'alerte `gbp_gap`).

**10/08/2026 — Pont SECIB (PIVOT — PII en clair)** :
- **Décision produit (Nicolas)** : Cooked rapproche les prospects web des
  dossiers SECIB **en clair** (nom/prénom/email/téléphone) — le hachage a été
  proposé et refusé. But : savoir si chaque prospect entrant a réellement
  ouvert un dossier (puis facturé), par matière et par canal d'acquisition.
- **Confinement PII** : `crm_prospects` (capture form-webhook v13 + backfill
  historique Wix : 795 prospects 03/2025→08/2026 via `scripts/wix_forms_import.py`,
  import idempotent) +
  `secib_dossiers` (ingest API SECIB) uniquement — RLS deny-all, service_role
  only. `events`/`events_human`/RPCs analytics restent SANS PII. Ne jamais
  faire transiter ces colonnes dans une vue analytics ou le dashboard sans
  décision explicite. Le texte libre des formulaires (message) reste exclu.
- **Lecture du pont** : vue `pont_prospects_dossiers` (email norm > tél E.164,
  statut converti / client_existant / non_converti, délai jours,
  `facture_total_ht`). Matching SQL via `cooked_normalize_email` /
  `cooked_normalize_phone_fr` — MIROIR STRICT dans `scripts/secib_ingest.py`.
- **API SECIB (étape 0 validée 10/08 sur bac à sable)** : token
  client_credentials (`~/.claude/secib-credentials.json`, JAMAIS committé) ;
  `Dossier/Get` en **POST** body `FiltreDossierApiDto` (le GET → 400) ;
  pagination `range=a-b` max 50 ; dates naïves = heure Paris ; lien
  facture→dossier UNIQUEMENT via `ExportComptable/ExportFinancier`
  (`DossierCode`, `DossierMatiereId`). `InfoComplementaire` : écrivable par
  l'API mais PAS lisible (question posée à Septeo) — le pont n'en dépend pas.
- **Prod en attente** : GUID reçu = cabinet de démo Septeo. Accès au cabinet
  Plouton réel conditionné à la **signature du devis SECIB+** (120 €HT/mois,
  12 mois min, devis du 07/08 valable ~10 j). Après signature : swap des
  credentials, `secib_ingest.py ingest --secib-env prod`, cron GitHub Actions
  à créer (patron gsc/gbp).
- **RGPD (action Nicolas, engagée)** : registre des traitements + politique de
  confidentialité du site à mettre à jour ; durée de conservation à fixer ;
  secret professionnel → périmètre validé avec Julien.

**29/07/2026 — framework d'analyse mathématique (PR #91)** :
- `scripts/advanced_math_analytics.py` (chaînes de Markov, graphe de navigation
  interne, Shapley, inférence causale, STL/Kalman) sur deux briques SQL : RPC
  `math_visit_sequences` / `math_internal_edges` + snapshots `math_*_snapshot`
  (refresh `math_refresh_snapshots`).
- EXECUTE public révoqué sur les RPC `math_*` (advisors 0028/0029).
- Rapport et **limites de conclusion** :
  `docs/analyse-mathematique-avancee-2026-07-29.md` — à lire avant d'invoquer
  ces méthodes, elles ne disent pas ce qu'on croit sur de petits volumes.

Cooked sert de remplaçant GA4 : des données comportementales fiables pour
Nicolas et Me Plouton, et les analyses Cooked × GSC (intent matching,
funnel SEO complet, pogo-stick × ranking) consommées en question/réponse.

---

## 🚨 Réflexes de démarrage de session

Avant toute analyse, dans cet ordre (30 secondes) :

```sql
SELECT * FROM alerts WHERE NOT acked;          -- 1. rien d'anormal ?
SELECT * FROM refresh_pipeline_health();       -- 2. pipeline healthy ?
SELECT gsc_last_data_day();                    -- 3. fraîcheur GSC (lag J-2/J-3 normal)
```

Si une alerte est active : la traiter ou l'expliquer AVANT de produire des
chiffres (un chiffre produit pendant un incident pipeline est un chiffre
faux). Pour prioriser le travail SEO/contenu :
`SELECT * FROM cooked_page_index(28) WHERE grade IN ('S','A','B') ORDER BY cpi ASC`.

**Carte de la documentation** (lire selon le besoin) :

| Besoin | Fichier |
|---|---|
| Point d'entrée agents (humain ou IA) | `AGENTS.md` |
| Workflow Git, CI, migrations | `CONTRIBUTING.md` |
| Versions & changements récents | `CHANGELOG.md` |
| Mener une analyse SEO sans tomber dans les pièges | `docs/PLAYBOOK-analyse-seo.md` |
| Comprendre/utiliser le score CPI | `docs/cpi-cooked-page-index.md` |
| Corps complets des RPC (121 routines au 10/08/2026 — régénéré par `scripts/generate_rpcs_sql.py`) | `supabase/rpcs.sql` |
| Ce qui reste à faire | `docs/ROADMAP.md` |
| RGPD du pont SECIB (textes à publier, registre, arbitrages ouverts) | `docs/rgpd-pont-secib.md` |
| État de fiabilité des données (audits) | `docs/audit-fable5-2026-07-02.md` (historique : `docs/data-quality-audit-2026-06-10.md`) |
| Revue d'architecture (48 constats, 25/07/2026 — lire l'avertissement de fiabilité en tête) | `docs/audit-architecture-2026-07-25.md` |
| Framework d'analyse mathématique (Markov, Shapley, causal…) | `docs/analyse-mathematique-avancee-2026-07-29.md` |
| Chronologie des sprints | `docs/HISTORY-sprints.md` |
| Ambition & vue d'ensemble du système | `README.md` |
| Architecture détaillée, déploiement, events, dépannage | `docs/OPERATIONS.md` |

---

## Périmètre d'autonomie de cet agent

L'agent `cooked` est **propriétaire de bout en bout** du système :

- Le tracker `wix/tracker.html` déployé en Custom Code
- Le proxy Velo `wix/http-functions.js`
- L'Edge Function `supabase/functions/track/index.ts` (Deno, tracker ingest)
- L'Edge Function `supabase/functions/form-webhook/index.ts` (Deno, Wix Automations webhook pour `form_submit`)
- Le schéma Cooked (`mxycmjkeotrycyneacje`) :
  `events`, `seo_url_snapshot`, vues, RPCs publiées
- Les 3 tables Google Search Console (Sprint 31-32) :
  `gsc_path_daily`, `gsc_query_daily`, `gsc_query_page_daily`
- Les migrations Supabase (`supabase/migrations/*.sql`,
  `supabase/views.sql`, `supabase/rpcs.sql` miroir lecture)
- Le pg_cron de rebuild nocturne `refresh_seo_url_snapshot()`
- Le contrat des RPCs publiées (signatures, types de retour,
  comportement)
- Le README du repo Cooked
- Les analyses, graphes, rapports produits depuis Cooked
- Le pont SECIB (`scripts/secib_ingest.py`, `scripts/wix_forms_import.py`,
  tables `crm_prospects`/`secib_dossiers`, vue `pont_prospects_dossiers` ;
  credentials `~/.claude/secib-credentials.json` JAMAIS committés)
- Les scripts d'outillage (`scripts/minify-tracker.py`,
  `scripts/gsc_ingest.py`, `scripts/gsc_common.py`,
  `npx supabase functions deploy`, etc.)
- Le workflow GitHub Actions GSC (`.github/workflows/gsc-daily-ingest.yml`)
- L'ingestion DataForSEO (`scripts/dfs_common.py`, `dfs_sync.py`,
  table `dfs_keyword_volume`, cron `dfs-weekly-sync.yml`)
- L'ingestion Google Business Profile (`scripts/gbp_ingest.py`, table
  `gbp_daily`, cron `gbp-daily-ingest.yml`) — les appels partis de la fiche
- L'auth Service Account GSC (`gsc-mcp-claude@plouton-472207...`)
  et le fichier `~/.claude/gsc-credentials.json` qui ne doit JAMAIS
  être committé

L'agent peut prendre toutes les décisions techniques sur ces objets.
Demander une validation explicite à Nicolas uniquement pour :

- Une décision business ou de produit (ex : multi-tenancy, nouveau client,
  re-création d'une UI visible par le client final)
- Une suppression de donnée irrécupérable (DROP TABLE, DELETE de masse)
- Un changement de coût significatif (ex : passer à un plan Supabase
  payant supérieur, activer une API tierce facturée)

---

## 🚨 RÈGLE ABSOLUE — Aucun chiffre orienté décision sans contre-vérification

Tout chiffre qui appuie une recommandation (« quick win », « page à
réécrire », « meilleure page du site », « scaler X ») doit avoir passé
**au moins une contre-vérification AVANT d'être livré** :

1. **Décomposition** : un agrégat (position moyenne, total d'impressions,
   dwell global) se décompose toujours une maille en dessous (par requête,
   par canal, par jour) avant d'être interprété.
2. **Croisement de sources** : quand deux systèmes mesurent la même chose
   (clics GSC vs visites Cooked, export Wix vs form_submit), comparer sur
   fenêtre alignée. Les divergences sont des informations, pas du bruit.
3. **Dire le statut** : si un chiffre n'a pas pu être contre-vérifié, la
   réponse doit le dire explicitement (« non recoupé »). Nicolas ne doit
   jamais avoir à se demander si un chiffre livré a été vérifié ou pas.

**Pourquoi cette règle existe :** le 11/06/2026, le rapport pages
expertise a présenté trois « quick wins SEO » comme meilleure action du
site. Challengé par Nicolas, le contrôle (10 minutes) a montré qu'un des
trois était un faux gisement (81 % d'impressions navigationnelles d'un
concurrent) et que les clics GSC sous-comptaient les visites réelles de
2,4×. Le piège était documenté dans le playbook depuis la veille — il n'a
pas été appliqué. La confiance se perd sur UN chiffre faux livré avec
aplomb ; aucune vitesse de livraison ne vaut ce coût.

---

## Méthodologie qui marche (retex Sprints 12-13)

À garder comme grille de qualité pour les sprints futurs :

1. **Critères de validation explicites avant exécution** — quand tu
   demandes à Nicolas de valider quelque chose, liste 3-5 critères
   concrets, vérifiables. Pas de "ça devrait marcher", on doit savoir
   que ça marche.

2. **Avant de valider, regarde concrètement le résultat** — ne signe
   pas "RAS" sans avoir lu le payload event, le retour de la RPC, le
   contenu de `seo_url_snapshot`. Les bugs subtils (URL-encoding du
   Sprint 13, 5 % capture rate du Sprint 12) se cachent dans ce qu'on
   n'a pas regardé.

3. **Le math nudge** — quand un verdict semble damning (capture rate
   5 %, scroll 0 %, etc.), refais les comptes avec les fenêtres
   temporelles avant de conclure à un bug. La plupart des "bugs" de
   bootstrap sont des artefacts d'amorçage (capture-N-jours vs source-
   externe-28-jours, par exemple).

4. **Mode itératif strict avant scale** — quand un changement touche
   au tracker ou à l'Edge Function, valide sur **1 type d'event** ou
   **1 page** avant d'élargir. C'est le pattern qui a évité de
   poursuivre la backfill URL-decode globale avec un bug subtil.

5. **Un fix = une migration nommée** — pas de UPDATE manuel non
 tracé sur la DB. Tout fix Cooked passe par une migration commitée
 dans `supabase/migrations/*.sql` ; si une **RPC** change, régénérer
 `supabase/rpcs.sql` (`scripts/generate_rpcs_sql.py`) — gate CI Arch #5.

---

## Architecture rapide (pour démarrer une session sans relire tout)

```
Browser (Wix Custom Code)               Wix Automations (server-side)
  └─ tracker.html                          └─ on Form Submitted
      ↓ POST /_functions/track                  ↓ POST /functions/v1/form-webhook
        (same-origin)                            ?token=<FORM_WEBHOOK_SECRET>
Velo proxy (http-functions.js)
  └─ Authorization: Bearer <secret_key>
      ↓
Edge Function /track (Deno)              Edge Function /form-webhook (Deno)
  ├─ hash IP+UA → anonymous_id              ├─ verify token query param (401 if KO)
  ├─ parse UA → device/browser/os           ├─ parse Wix payload (body.data.*)
  ├─ canonicalPath(path) (Sprint 13 + NFC)    ├─ strip PII events (Sprint 30)
  │                                           ├─ INSERT crm_prospects (identité
  │                                           │   en clair, v13 — RLS deny-all)
  └─ INSERT events                          └─ INSERT events (name=form_submit)
       ↓                                          ↓
events table (raw)
       ↓ refresh_bot_fingerprints() — Sprint 17
       ↓ events_human view (events MINUS bots MINUS noise)
       ↓ identity_stitch (couture aid↔sid → visitor_key,
       ↓   refresh_identity_stitch(90), cron 03:40 UTC — 12/07/2026)
       ↓ pg_cron nightly
refresh_seo_url_snapshot()
       ↓
seo_url_snapshot (70 colonnes post-Sprint-30 : 4 fenêtres × ~11
                  metrics + CWV + provenance + device + CTAs + pogo
                  + device CTA rate. Sprint 30 a dropé 4 colonnes
                  email_clicks_* qui étaient à 0 depuis le début)
       ↓
RPCs internes (interrogées en ad-hoc via MCP Supabase)
```

RPCs publiées — analyses historiques & snapshot :
- `snapshot_pages_export()` — top pages avec metrics 28d/90d
- `site_context_export()` — site-wide aggregates
- `outbound_destinations_for_path(path, days)` — top destinations
  outbound par page
- `cta_breakdown_for_path(path, days)` — répartition CTAs
  phone/booking/anchor par placement (Sprint 30 : `anchor_nav`
  ajouté pour ne plus masquer 42 % des clicks)
- `tracker_first_seen_global()` — première date de capture (Sprint
  13bis), avec guard ±2j contre les horloges clients cassées
  (Sprint 29). Pour pro-rater les fenêtres de comparaison quand la
  fenêtre demandée dépasse l'historique disponible.
- `behavior_pages_for_period(from, to)` — toutes les pages avec
  metrics + CWV pour une période donnée
- `pogo_rates_for_period(date_from, date_to)` — pogo-stick rate par
  page Google organique (Sprint 30 : LEFT JOIN dedup + NULL exit
  handling)
- `engagement_density_for_path(target_path, days)` — p25/p50/p75 du
  dwell + evenness_score par page (Sprint 30 : GROUP BY session_id)
- `classify_channel(ref, utm_source, utm_medium, self_host)` —
  taxonomie unifiée des canaux d'acquisition (Sprint 28)
- `refresh_pipeline_health()` — self-diagnostic 5 axes (snapshot, cron,
  ingestion, GSC, DataForSEO : dfs_last_synced_at, dfs_row_count)
- `latest_rpc_health()` — dernier état des contract tests par RPC

RPCs publiées — cross-source GSC × Cooked (Sprint 33+, migrations) :

- `gsc_last_data_day()` — dernier jour `gsc_path_daily` (lag Google)
- `cooked_period_bounds(period_kind, data_lens)` — `live` | `live_j1`
  (dashboard : fin J-1 Paris) | `gsc` | `cross` (cross = fin alignée GSC)
- `gsc_is_branded(query)` — prédicat branded GSC unique (exclut « plouton »)
- `cooked_snapshot_window(p_window, p_grain)` — driver refresh dashboard
  (bornes + temp `_cooked_ev`, grain `clean`|`human`)
- `site_kpis_compare(period_kind)` — KPIs Cooked (lens live)
- `site_gsc_kpis_compare(period_kind)` — KPIs GSC (lens gsc)
- `pages_overview_unified(max_rows)` — univers pages (~490 paths), contacts macro séparés de booking_intent
- `gsc_page_performance(target_path)` — fiche page complète
- `gsc_top_queries_for_path(path, period_kind, max_rows)` — requêtes → landing (overload `days_back` conservé)
- `site_macro_counts(start, end)` — contacts macro site-wide (phone + form filtré)
- `gsc_pages_overview(max_rows)` — top pages SEO (tri clics) ; v3 contacts macro
- `gsc_top_queries_global(period_kind, max_rows)` — top requêtes site (+ volume DFS)
- `site_pulse` / `pages_pulse` — quadrants GSC 28v28 × Cooked 7v7 (`pulse_quadrant` helper)
- `site_seo_funnel(period_kind)` — funnel impressions → contacts
- `gsc_page_daily_series` / `cooked_page_daily_series` — séries quotidiennes (sparklines)
- `dfs_keywords_to_sync(limit_n)` — liste keywords à syncer (union GSC 28j ∪ 90j)
- `gsc_x_dfs_opportunities(...)` — quick wins SEO (volume DFS + position 5–15)

RPCs attribution & santé (Sprint 37-38) :
- `form_submits_attributed(days)` — attribution des forms : hidden_field >
  temporal_unique > unresolved
- `conversion_journeys(days)` — un row par contact macro : entry_path,
  entry_channel, journey[] (séquence de pages), pages_count, device.
  **v2 recousue depuis le 12/07/2026** (migration `20260712203935`) : contrat
  de sortie inchangé, mais l'entrée/parcours se calcule sur le **visiteur
  recousu** via `identity_stitch` (priorité sid > aid > fallback session brute)
- `content_performance(days)` — perf par page_type × theme
- `seo_to_contact_funnel(days)` — GSC clics → entrées organiques → contacts
  par landing
- `cooked_page_index(days)` / `cooked_cpi_snapshot()` — score santé par page
  + snapshot quotidien `cpi_daily`
- `cpi_movers` (vue) — Δ CPI sur ~7j glissants depuis `cpi_daily` : statuts
  present/nouveau/disparu, `fiable` (grade A/B aux deux dates), delta_z par
  composante ; alimente l'alerte `cpi_drop` (chute ≥15 pts **+ vrai decay
  momentum/capture**, warn — recalibré S39, exclut la volatilité conversion)
- `cpi_opportunite_contact` (vue, ex-`cpi_gisement`) — pilotage conversion : relit le dernier
  `cpi_daily` et sépare le **potentiel** (capture+rétention+lecture, hors
  conversion, renormalisés) du badge **conversion réalisée** (`convertit`).
  Opportunité de contact = `grade IN ('S','A','B') AND NOT convertit ORDER BY potentiel DESC`.
  Ne recalcule rien, ne complexifie pas le CPI. Alias déprécié : `cpi_gisement`.
  Colonne `grade` = **Fiabilité** S/A/B/C (S≥200∧E≥40, A≥100∧≥20, B≥30∧≥5, C sinon).
- `cpi_capture_perdue` (vue, 28/07/2026) — pilotage capture : les pages en
  déficit de clics face à la courbe CTR du site, **avec la fiabilité du
  chiffre**. `clics_perdus` est extrapolé depuis la fraction de requêtes que
  Google révèle ; sous 20 % de couverture l'extrapolation domine.
  `fiabilite_capture` = directe (≥ 40 %) / partielle (20-39 %) / extrapolée
  (< 20 %), `interpretable` = grade S/A/B **ET** couverture ≥ 20 %.
  Ne plus lire `cpi_daily.clics_perdus` à la main.
- `cooked_alerts_refresh()` — recalcul des alertes (cron horaire) ; table
  `alerts` (acked boolean)
- `cooked_page_type(path)` — cabinet / hub / expertise / post / blog-nav ;
  table `page_taxonomy` (theme par heuristique slug)

**DataForSEO (agent Cooked)** : le MCP DataForSEO est connecté → lookups de
volume **en live** via `mcp__dataforseo__kw_data_google_ads_search_volume`
(location `France`, language `fr`). Pièges : max ~10 mots / 80 car. par keyword
(sinon le batch ENTIER est rejeté, code 40501) ; réponse MCP plafonnée à ~10
keywords → découper en lots de 8. La table `dfs_keyword_volume` reste la
**source durable**, alimentée par `scripts/dfs_sync.py` (env `DFS_USERNAME` /
`DFS_PASSWORD` / `SUPABASE_SECRET_KEY` — en GitHub Actions, **absents en local**
donc script non lançable depuis Cursor). Sanitize avant envoi (`sanitize_for_dfs`
dans `dfs_common.py`). Un lookup MCP live n'écrit PAS en base : pour persister,
upsert dans `dfs_keyword_volume` (clé `keyword, location_code` ; mapping
`competition = competition_index/100`, `competition_level = label`) ou laisser
le `dfs_sync.py` hebdo rattraper. Après changement RPC/script : relancer
`dfs_sync.py --limit 500`.

**Contacts (taxonomie)** : `cooked_contacts_*` = `cta_phone_click` + `form_submit` uniquement.
`cooked_booking_intent_*` = `cta_booking_click` (micro). Ne pas mélanger.
Source SQL unique : `macro_contacts_by_path(days_back)` — utilisée par
`pages_overview_unified`, `gsc_pages_overview`, `gsc_page_performance`.
Pour ajouter un signal macro futur (ex. SMS), ne modifier que cette fonction.

Pre-deployment date "tracker live" : 05/05/2026 → 06/05/2026 19:14
Paris (première ingestion réelle).

**Versions canoniques (repo `main`, 10/08/2026)** :
- Tracker : **`sprint41`** (ids auto-réparants — fin de la rotation aid/sid sur
  wipe de storage qui coupait ~22 % des sessions). **DÉPLOYÉ le 12/07/2026
  ~22:20 par Nicolas**, vérifié J+1 le 13/07/2026 (OK).
- Edge `track` : **v27** (25/07/2026 — gate `x-cooked-key` à l'ingestion,
  constat n°3 de la revue d'architecture ; v26 = filtre bots à l'ingestion,
  constat n°5/R2 — la taxonomie ua_bot est appliquée AVANT l'INSERT, drops
  comptés dans `ingest_drops` ; v25 = D4 `track_row` + C5 `events_row` ;
  clamp horloge v23). Détail des constats :
  `docs/audit-architecture-2026-07-25.md`.
- Edge `form-webhook` : **v13** (10/08/2026 — Pont SECIB : identité prospect
  en clair → `crm_prospects`, jamais bloquant pour l'event ; v12 = D4
  `form_row` ; v11 = submissionTime + drop alert).

Prod peut lagger : vérifier la version déployée avant d'annoncer un changement
Edge. Dernier contrôle le 10/08/2026 : `track` **v27** + `form-webhook`
**v13 déployées**, prod alignée
avec le repo.

**Couture d'identité (12/07/2026)** : table `identity_stitch` (sid|aid →
`visitor_key`, composantes connexes du graphe aid↔sid, cron nocturne 03:40 UTC,
90 j glissants). Répare rétroactivement les sessions coupées par le bug de
rotation d'ids (~22 % des sessions, ~95 % des phone clicks sans amont). Consommée
par `refresh_dashboard_resources_assisted` v2 (entrée = première pageview de la
**visite recousue**, segmentation 30 min). ⚠️ Ne JAMAIS coudre via un aid 32-hex
(fallback serveur hash IP|UA, partageable entre visiteurs).
**`conversion_journeys` v2 branchée** le 12/07 au soir (migration
`20260712203935`) : parcours sur le visiteur recousu, contrat de sortie
inchangé, ~1 s sur 28 j — `seo_to_contact_funnel` et `content_performance`
sont réparés par héritage (ils la consomment).

---

## 🚨 RÈGLE ABSOLUE — Timezone Paris partout, date affichée explicite

Le serveur Postgres stocke `occurred_at` en UTC. Le client (Nicolas, Me Plouton)
raisonne en Paris. Sans précaution, les events de 00:00–01:59 Paris (= 22:00–
23:59 UTC la veille) sont rattachés à la veille au lieu d'aujourd'hui — ce
qui fait disparaître silencieusement des conversions du compte du jour.

**Règles dures :**

1. **Filtrage par date côté SQL** : toujours `(occurred_at AT TIME ZONE
   'Europe/Paris')::date`, jamais `occurred_at::date`. Le bug s'appelle
   "fenêtre glissante UTC = perte de 2h chaque matin".

   ```sql
   -- CORRECT
   WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date = (now() AT TIME ZONE 'Europe/Paris')::date

   -- INTERDIT
   WHERE occurred_at::date = current_date
   ```

2. **Date couverte explicitée dans la réponse** : ne jamais écrire "aujourd'hui"
   tout court. Toujours préciser le jour calendaire (ex: "lundi 18/05/2026")
   pour qu'une réponse lue 6h après reste lisible.

3. **Heures affichées en Paris** : `to_char(occurred_at AT TIME ZONE
   'Europe/Paris', 'HH24:MI')` quand on liste des events. Jamais l'heure UTC
   sauf si explicitement demandé.

**Pourquoi cette règle existe :** le 18/05/2026 j'ai indiqué à Nicolas "1
formulaire aujourd'hui" alors qu'un 2e formulaire venait d'arriver à 08:58
Paris et que ma requête tournait encore en mode "aujourd'hui UTC = hier
Paris". Frustration justifiée.

---

## 🚨 RÈGLE ABSOLUE — Format de date FR partout : JJ/MM/AAAA

Nicolas est français. **Toutes les dates affichées dans les réponses texte,
tableaux markdown, récaps, commentaires doivent être en JJ/MM/AAAA** —
jamais YYYY-MM-DD (ISO) dans le texte présenté.

**Exemples corrects :**
- ✅ "Sprint 30 livré le **21/05/2026**"
- ✅ "Premier compare 7j vs 7j iso : à partir du **28/05/2026**"
- ✅ "Form_submit reçu le **21/05/2026** à 13:30 (Paris)"
- ✅ "jeudi 22/05/2026"

**Exemples interdits :**
- ❌ "Sprint 30 livré le 2026-05-21"
- ❌ "Compare possible à partir du 2026-05-28"

**Exception — SQL et code uniquement :**
- Les requêtes SQL Postgres gardent `'2026-05-28'` (syntaxe obligatoire)
- Les littéraux dans le code source restent ISO
- Les noms de migrations gardent leur timestamp natif (`20260521140914_xxx.sql`)
- Les commit messages git peuvent contenir ISO (cohérent avec `git log`)

→ Conversion à la frontière : SQL produit du ISO, on convertit en français
au moment d'afficher.

**Pour formatter directement en SQL** quand le résultat brut doit être lisible :
```sql
to_char((occurred_at AT TIME ZONE 'Europe/Paris'), 'DD/MM/YYYY HH24:MI') AS quand
```

**Pourquoi cette règle existe :** le 21/05/2026 Nicolas a recadré l'agent
après plusieurs récaps en format `2026-05-XX`. Lecture rapide en JJ/MM/AAAA
= friction réduite, jamais besoin de mentalement reconstituer "ah oui c'est
le 28 mai".

---

## 🚨 RÈGLE ABSOLUE — Toujours requêter `events_human`, jamais `events`

**Pour TOUTE requête ad-hoc demandée par Nicolas, je tape `FROM events_human`,
pas `FROM events`.**

- `events` (table brute) contient les bots et le bruit non filtré → comptes
  gonflés de ~17 % (parfois plus selon les périodes).
- `events_human` (vue) = `events` − `bot_fingerprints` − `noise_sessions`.
  C'est la base canonique de toutes les analyses business.
- Toutes les RPCs publiées (`snapshot_pages_export`, `cta_breakdown_for_path`,
  `site_context_export`, etc.) lisent déjà `events_human` — donc passer par
  une RPC est toujours sûr.

**Exceptions où `events` brut est acceptable (à expliciter dans la réponse) :**

1. Audit du système de filtrage lui-même (vérifier ce qui a été filtré, par
   exemple lors d'une investigation type Sprint 24).
2. Compter les `form_submit` : insérés server-side par `form-webhook`,
   `device_type='server'`, jamais classés bot ou bruit → comptes identiques
   sur `events` et `events_human`. Préférer quand même `events_human` par
   cohérence.
3. Debug d'ingestion (vérifier qu'un event vient bien d'arriver).

Si je tape `FROM events` sans annoncer pourquoi, c'est une erreur. Nicolas
peut me le rappeler avec un simple "events_human" et je dois corriger
immédiatement la requête.

**Pourquoi cette règle existe :** Nicolas remonte les chiffres à Me Plouton
(le client) et à Adrien (Nomad Marketing). Un chiffre gonflé de 17 % par
des bots = une décision business fausse. Le filet anti-bruit a été construit
exprès pour produire des chiffres propres ; il faut que je le respecte
systématiquement.

---

## 🚨 Leçons d'analyse SEO (retex 09-10/06/2026) — les 6 pièges

Détail et requêtes types : `docs/PLAYBOOK-analyse-seo.md`. Résumé dur :

1. **Toujours décomposer par canal avant de juger une page.** Un dwell
   médian global mélange social (1 s) et Google (45 s) → chiffre menteur.
   Les métriques de lecture se calculent sur les entrées **organiques
   uniquement** (`classify_channel(...) LIKE 'organic%'`).
2. **La position moyenne est un piège** (pondérée impressions, mélange des
   requêtes). Pour juger un CTR : attendu requête par requête via la courbe
   du site, puis somme (standardisation indirecte — cf. terme capture du CPI).
3. **`gsc_query_page_daily` ne couvre qu'une fraction du trafic** (Google
   anonymise jusqu'à ~94 % des requêtes d'une page). Les TOTAUX viennent de
   `gsc_path_daily` ; qpd sert au mix positionnel et à l'attribution.
4. **Marée vs ranking** : clics en baisse à position CONSTANTE = demande ou
   SERP qui bouge (pas la page). Clics en baisse + position qui glisse =
   vrai decay. Deux maladies, deux remèdes. Le momentum du CPI est relatif
   au site pour cette raison.
5. **Exclure le branded** (`query !~* 'plouton'`) de toute mesure de
   capture/CTR, sinon la home triche.
6. **Petits volumes = pas de verdict.** Empirical Bayes + grades de
   confiance (A/B/C). Un champion à 12 visites est une hypothèse, pas un
   résultat. Le CPI trie, les quatre z diagnostiquent — ne jamais livrer le
   nombre sans ses composantes.

---

## Définition des conversions (taxonomy macro / micro / engagement)

Trois niveaux de signaux à distinguer dans toute analyse Cooked.
**Ne jamais les mélanger** sous un seul label "conversion" — c'est
l'erreur faite dans l'audit du 15/05/2026 qui annonçait 157 "conversions"
alors qu'il n'y avait que 37 vraies actions business.

### 1. Macro-conversion (vrai contact établi)

Le visiteur a réellement essayé de joindre le cabinet.

- `cta_phone_click` — tap-to-call (composeur ouvert sur mobile, intent
  quasi-certain ; sur desktop, c'est un signal plus faible mais reste
  une action explicite)
- `form_submit` — soumission validée server-side par l'Edge Function
 `form-webhook` via Wix Automation (irréfutable). Hors contact macro si
 `props.objet_de_ma_demande` contient « Nous rejoindre » (candidatures).
 Typologie stockée dans `props.objet_de_ma_demande` (pas de PII).

**C'est la métrique business.** Si on doit choisir UN chiffre à
remonter à Me Plouton ou à Adrien (Nomad Marketing), c'est celui-ci.

### 2. Micro-conversion (intent déclaré, pas encore matérialisé)

Le visiteur a manifesté son intention mais n'est pas allé au bout.

- `cta_booking_click` — clic sur "Prendre rendez-vous" / "Je prends
  rendez-vous" qui mène vers `/honoraires-rendez-vous`
- `cta_anchor_click` — clic sur "Demander un RDV" / "Je prends
  rendez-vous — table des matières" qui scrolle vers le formulaire de
  la même page (sticky bar mobile expertise, table des matières, etc.)

⚠️ **Caveat `cta_anchor_click` (Sprint 35, 03/06/2026)** : avant le
Sprint 35, le sticky-fallback du tracker comptait **tout** clic dans un
conteneur sticky/fixed comme un anchor. Audit prod : **~90 % des
`cta_anchor_click` (6 629 / 7 318) étaient du chrome UI** — bandeau
Cookiebot (boutons + clics sur le corps du dialog), burger, liens de nav,
et dumps de texte (`<script>` inline, méga-menu, indicatifs tél captés
comme libellé). C'est corrigé côté tracker (sélecteur Cookiebot + cap de
longueur ≥ 80 + règle structurelle nav) ET rétroactivement dans
`events_human` (helper `cooked_is_chrome_anchor(props)`, migration
`anchor_click_exclude_chrome`) : `events_human` est passé de 7 318 à 689
`cta_anchor_click`. Donc : requêter `events_human` donne déjà des
`cta_anchor_click` propres ; les chiffres anchor d'avant le 03/06/2026
dans ce fichier (ex. le « 53 » du récap 06→15/05) sont **très gonflés** et
ne sont plus reproductibles tels quels. Reste ~343 libellés de nav courts
(Équipe, Affaires…) non filtrables rétroactivement par le libellé seul.
Pour auditer le chrome retiré : `events` brut + `cooked_is_chrome_anchor`.

À utiliser pour mesurer l'efficacité des CTAs et la qualité du funnel
intermédiaire, **pas** pour annoncer un taux de conversion business.

### 3. Engagement (signal de lecture)

Le visiteur consomme du contenu sans manifester d'intent explicite.

- `scroll_depth` (percent ≥ 75 %)
- `engagement_tick` cumul ≥ 2 min
- Session multi-page (≥ 2 pageviews)

Utile pour comprendre la qualité du contenu, pas la performance
commerciale.

### Piège SQL à connaître : `device_type='server'` et form_submit

Les `form_submit` sont insérés par l'Edge Function `form-webhook`
server-side, donc avec `device_type = 'server'` (cf
`supabase/functions/form-webhook/index.ts`).

La plupart des analyses "humaines" filtrent `device_type != 'server'`
pour exclure les bots Cooked détectés (UA suspects insérés par la
fonction `track`). **Ce filtre jette par erreur tous les form_submit**
et donne l'impression qu'il n'y en a aucun.

Règles correctes :

```sql
-- Compter les macro-conversions (ne PAS filtrer device_type)
SELECT COUNT(*) FROM events_human
WHERE name IN ('cta_phone_click','form_submit');

-- Compter les micro-conversions (exclure bots, garder humains)
SELECT COUNT(*) FROM events_human
WHERE name IN ('cta_booking_click','cta_anchor_click')
  AND device_type != 'server';

-- Compter toutes conversions sans rater les form_submit
SELECT COUNT(*) FROM events_human
WHERE name IN ('cta_phone_click','cta_booking_click','cta_anchor_click','form_submit')
  AND (device_type != 'server' OR name = 'form_submit');
```

Préférer compter explicitement par nom d'event plutôt que par filtre
device.

### Ordres de grandeur observés (10 jours, 06/05/2026 → 15/05/2026)

Sur ~14 000 sessions :

```
Macro-conversions    :   37  (0.26 %)  ← métrique business
  cta_phone_click    :   30
  form_submit        :    7

Micro-conversions    :  173  (1.2 %)
  cta_booking_click  :  120
  cta_anchor_click   :   53

Engagement qualifié  : ~880  (~6.3 %)
```

**Ratio micro → macro ≈ 21 %.** Le vrai goulot d'étranglement n'est
pas l'amont du funnel (acquérir du trafic, faire scroller, faire
cliquer un CTA) mais le **passage de l'intent à l'action** sur la
page `/honoraires-rendez-vous` (95 % des `cta_booking_click` ne se
transforment pas en `form_submit`).

---

## Taxonomy du site jplouton-avocat.fr

Le site a **4 grands types de pages** qu'il est essentiel de distinguer
dans toute analyse. Sans cette distinction, les conclusions sont
trompeuses (cf. erreur du 11/05/2026 où l'agent Cooked avait listé des
articles "ressources" sans les distinguer des "affaires").

### 1. Pages Expertise (14)
- `/defense-penale/*` (sauf le hub `/defense-penale`)
- `/indemnisation-des-victimes/*` (sauf le hub)
- `/droit-des-contrats-et-des-personnes/*` (sauf le hub)
- Pattern : pages service / landing page, dwell court (15-50s), scroll
  faible (médiane 0%), but = conversion directe CTA. Trafic majoritaire
  via Adwords. **Bandeau CTA sticky bar mobile uniquement sur ces pages**.

### 2. Pages Cabinet (institutionnelles)
- `/` (home)
- `/notre-cabinet`
- `/honoraires-rendez-vous`
- `/mentions-legales`
- Hubs `/defense-penale`, `/indemnisation-des-victimes`,
  `/droit-des-contrats-et-des-personnes`
- Pattern : pages de navigation/branding, peu de conversion directe.

### 3. Posts — Ressources et notions juridiques
- Path pattern : `/post/*`
- **Source authoritative** : la page hub `/comprendre-le-droit`
  (maintenue manuellement par Nicolas — c'est la vraie liste exhaustive).
- ⚠️ La catégorie Wix Blog `/blog/categories/ressources-et-notions-juridiques`
  ne contient que ~20 articles (sous-ensemble). NE PAS l'utiliser comme
  référence. Toujours scraper `/comprendre-le-droit` pour la liste complète.
- **51 articles au 22/05/2026** (49 au 11/05/2026, +2 nouveaux en 11 jours).
- **Pattern critique confirmé** : **plus gros volume de trafic du site**
  - Top article `/post/durée-de-la-garde-à-vue-24h-48h-96h` : 219 sess/28j
  - Top 5 cumule 488 sessions (42 % de la catégorie)
  - Total catégorie : ~1 156 sessions cumulées, dont 64 % Google organique
  - Dwell moyen 80-150s (lecteurs engagés)
  - **0 conversion vers /honoraires-rendez-vous sur les 47 articles à trafic**
- Intent du lecteur : éducatif / informatif (cherche à comprendre, pas
  à embaucher un avocat).
- Source SEO majeure → top du funnel.

### 4. Posts — Classiques
- Path pattern : `/post/*`
- Toutes les autres catégories Wix Blog : Affaires, Médias, Droit Pénal,
  Procès criminels, Violences Conjugales et féminicides, Trafic de
  stupéfiants, Droit pénal des affaires, Victimes de délits ou crimes,
  Accidents et erreurs médicales, Accidents de la route, Droit et
  accidents du travail, Accidents de la vie courante.
- Pattern : case studies (affaires gagnées), actualités cabinet,
  reportages médias.
- Volume moyen-bas mais **convertissent mieux que les ressources** vers
  /honoraires-rendez-vous (au 11/05/2026, sur 5j, 3 conversions article →
  honoraires venaient TOUTES de posts classiques, pas de ressources).

### Catégorie & thème : ce que Cooked stocke (à jour 11/06/2026)

`page_taxonomy` (table) + `cooked_page_type(path)` stockent le **type**
(cabinet/hub/expertise/post/blog-nav), le **theme** (heuristique slug,
source tracée) et — depuis le 11/06/2026 — la **catégorie Wix Blog** :
`category` = `ressource` (56 paths) ou `classique` (328 paths observés),
renseignée depuis l'**API Wix Blog via le MCP Wix** (migration
`20260611202556_page_taxonomy_wix_blog_categories`). Convention : un post
multi-catégories qui contient « Ressources et notions juridiques » est
`ressource` ; les autres posts publiés vus dans le trafic sont `classique`.
La colonne `source` trace la provenance du THEME ; la provenance de
`category` est toujours `wix_api`.

⚠️ **Pas de refresh automatique** : un nouvel article publié n'a pas de
`category` tant qu'on ne rejoue pas la synchro API Wix. Endpoint faisant
autorité : `GET https://www.wixapis.com/blog/v3/posts?categoryIds=…`
(catégorie « Ressources et notions juridiques » =
`9477320f-5902-40e9-ace3-b0e3b6b8b51f`, site Cabinet Plouton
`0870235c-b92d-4a69-a2f4-25a976ae5f0c` ; pagination `paging.limit` /
`paging.offset`, 100 max par page). Ne JAMAIS présumer la catégorie d'un
article à partir de son slug : l'API Wix est la seule référence (remplace
l'ancien plan « scraper /comprendre-le-droit »).

⚠️ **Le mode de défaillance n'est PAS `category IS NULL`** — c'est
**l'absence totale de ligne**. Les deux mécanismes qui créent des lignes
(`refresh_page_taxonomy_heuristic()` pour le thème, les synchros Wix
successives) ne considèrent que les paths déjà vus dans `events_human` :
un article publié mais pas encore visité n'obtient aucune ligne, et n'est
jamais rattrapé au tour suivant. Constaté le 30/08/2026 : 12 articles
manquants dont 5 ressources, certaines publiées en juin — invisibles de
l'onglet Articles Ressources, de `content_performance` et du suivi du
contrat éditorial pendant deux mois (migration `20260831090540`). Depuis,
l'alerte **`page_taxonomy_gap`** (règle `alert_rule_page_taxonomy_gap()`,
cron horaire via `cooked_alerts_refresh()`) compte les `/post/` avec
≥ 5 vues/30 j sans catégorie et sonne à partir de 3. Quand elle sonne :
rejouer la synchro Wix, puis migration nommée pour l'upsert.

### Contexte business (recueilli auprès de Nicolas le 11/06/2026)

- **Le cabinet a de la capacité** : Me Plouton « n'attend que ça » →
  l'objectif du système est le **volume de contacts qualifiés** (pas un
  arbitrage de mix sous contrainte de capacité).
- **~40 nouveaux dossiers signés/mois** toutes sources confondues (réseau,
  bouche-à-oreille, SEO, site, GMB…) — pas de ventilation connue. Les appels
  passent par le standard (une secrétaire) ; pas de comptage par source.
- **Nicolas est seul sur la maintenance du site** ; Adrien (Nomad) ne gère
  QUE les Google Ads. Contrat éditorial : **4 articles « ressources et
  notions juridiques » par mois** rédigés par Nicolas (750 €/mois) → la
  question « les ressources convertissent-elles ? » est une question de
  pilotage de SON livrable, à traiter avec ce niveau de soin.
- **Valeur par domaine (grille PROVISOIRE, Nicolas 11/06/2026)** :
  FORT = **indemnisation des victimes** toutes déclinaisons (victimes de
  délits/crimes, accidents route/travail/médical/vie courante, CIVI/SARVI)
  — « c'est ce qui rapporte beaucoup à Julien ». Le pénal (stup,
  féminicides, criminel) = l'ADN et la notoriété de Me Plouton (Julien),
  valeur dossier à préciser. Paniers moyen/faible NON validés — ne pas
  pondérer le CPI tant que la grille n'est pas confirmée.
- **Nicolas a la main totale sur les articles** (choix des sujets, contenu,
  template) → les deux leviers contenu (sujets pilotés par Cooked, CTA/
  maillage dans le corps des posts) sont actionnables sans tiers.
- **Cooked est mono-utilisateur (Nicolas)** : pas de digest/rapport pour
  des tiers ; le mode de sortie reste le question/réponse ad-hoc.
- **GMB : canal à part entière depuis le 27/07/2026** (`classify_channel` v3).
  La décision du 11/06 (« non branché, angle mort assumé ») reposait sur une
  erreur : le **trafic web** de la fiche était bel et bien tracké, mais classé
  `organic_google` — les clics du Local Pack arrivent sur `/?utm_source=gmb`
  avec un referrer `google.*`. 137 des 306 entrées « organiques » de la home
  sur 28 j étaient du GMB (44,8 %). Il convertit à **3,68 %** contre **0,57 %**
  pour le SEO organique réel : meilleur canal du site, devant le paid.
  **Numéro traçable sur la fiche : DÉCLINÉ par Nicolas le 28/07/2026** — ne
  plus le proposer. Ordre de grandeur côté web mesuré : GMB pèse 6 contacts /
  28 j sur les 208 du site (2,9 %), contre 12 % des formulaires qui déclarent
  GMB dans l'export Wix.
- **Les appels passés depuis la fiche sont MESURÉS depuis le 28/07/2026** —
  l'angle mort n'est plus assumé, il est fermé. L'API Google Business Profile
  a été approuvée le soir même ; elle donne `CALL_CLICKS` par jour sans
  toucher à la fiche et sans numéro traçable. Table **`gbp_daily`** (format
  long day × location × metric), backfill 18 mois fait (4 842 lignes,
  03/02/2025 →), cron `gbp-daily-ingest.yml` à 05:30 UTC.
  - **~162 clics d'appel / 28 j**, stables sur 18 mois (133-236/mois). Même
    nature que `cta_phone_click` (un tap, pas un appel décroché) donc
    comparable aux 208 contacts macro du site — l'angle mort pesait le même
    ordre de grandeur que tout le contact mesuré.
  - **C'est un plancher.** Les compteurs Google sous-comptent : `WEBSITE_CLICKS`
    = 121 vs 180 visiteurs-jours Cooked sur fenêtre alignée (×1,49), écart
    stable de part et d'autre du correctif tracker du 12/07 donc ni
    fragmentation de sessions ni accident de période. Même signe que le ×2,4
    mesuré sur GSC le 11/06. **Ne jamais extrapoler `CALL_CLICKS` par ce
    ratio** : il est mesuré sur des clics de lien, pas sur un tap qui n'ouvre
    aucune page.
  - **Piège d'ingestion** : l'API rembourre la fin de fenêtre avec des jours
    à **zéro** tant que Google n'a pas consolidé (lag ~J-4). Un zéro récent
    n'est PAS un vrai zéro — `gbp_ingest.py` coupe cette queue, toute lecture
    ad-hoc doit faire pareil.
  - **Impressions Maps : rupture de comptage en 09/2025** (8 685 → 452) SANS
    baisse des actions (appels 140 → 191). Changement côté Google, pas un
    déclin de la fiche. Ne pas lire un « effondrement » avant cette date.
  - Le compte donne accès à **4 fiches** (REWOLF, deux restaurants) : toujours
    filtrer sur `locations/3503242316391395629`.
  - Auth : **OAuth utilisateur obligatoire**, les APIs Business Profile
    refusent les comptes de service (contrairement à GSC). Local = ADC
    gcloud ; CI = secret `GBP_CREDENTIALS_B64`.
  - ⚠️ **Fragilité connue — le cron GBP peut mourir en silence.** Le credential
    ADC utilisateur exige une **reauth Google périodique** : le cron a échoué
    6 jours d'affilée, du 30/07 au 04/08/2026, sans qu'aucune alerte sonne
    (`RefreshError: Reauthentication is needed`). Réparé le 05/08 —
    `gcloud auth application-default login --scopes=…business.manage,…cloud-platform`
    (les DEUX scopes sont obligatoires, gcloud refuse `business.manage` seul),
    puis secret `GBP_CREDENTIALS_B64` re-poussé ; la fenêtre 30 j du script a
    rebouché le trou toute seule. **L'alerte de fraîcheur `gbp_gap` n'existe
    pas encore** (contrairement à `gsc_gap`) — donc les réflexes de démarrage
    de session ne détectent PAS un pipeline GBP mort : jusqu'à sa création,
    vérifier `max(day)` de `gbp_daily` avant de livrer un chiffre GBP. Parade
    durable à la reauth : client OAuth dédié (voie 2 de `scripts/gbp_ingest.py`).
  - **Requêtes de recherche de la fiche** (sonde du 05/08/2026, endpoint
    `searchkeywords/impressions/monthly`, 12 mois) : 839 mots-clés,
    ~18 100 impressions exactes (+ ~11 000 sous seuil — Google masque les
    petits volumes en `threshold`). La fiche est **quasi invisible sur
    l'indemnisation** (≤75 impressions vs ~2 100 pénal) alors que la demande
    locale existe (DFS « avocat dommage corporel bordeaux » : 210/mois).
    Catégories, ~43 services et description sont **déjà** orientés
    indemnisation, et les avis aussi (200 avis, 4,6 ; 45 mentions pénal /
    20 indemnisation) : le seul signal encore 100 % pénal est le **nom** de la
    fiche (« Avocats en Droit Pénal à Bordeaux ») → renommage = décision
    Julien/Nicolas, annotation à poser le jour J. **Ne pas toucher la catégorie
    principale** (saborderait le pénal). Lag de publication ≈ 1 mois → toute
    ingestion de ces requêtes doit être **mensuelle**, pas quotidienne.

  **B3 clos.**
- **Google Ads : MCP CONNECTÉ** (vérifié le 01/07/2026 — 5 customer IDs
  accessibles). Premier usage à cadrer : coûts/CPA par campagne croisés
  avec les macro-contacts Cooked (« boucle 3 »).
- **Paid** : utm_source seul (pas de utm_campaign), ~1 800 entrées/28j,
  atterrit surtout home + pages expertise. Le CPI n'est PAS pollué (toutes
  ses composantes filtrent `organic%`), mais toute analyse de conversion
  par page hors CPI doit décomposer par canal.
- **Table `annotations`** (`day`, `kind` media/presse/site_change/campagne/
  autre, `label`, `paths[]`) : à remplir quand Me Plouton passe à la TV ou
  dans la presse (migration `20260611201942`). À terme : neutralisation des
  pics dans le momentum CPI.
- **Formulaire Divorce** : champs cachés `cooked_aid`/`cooked_sid` ajoutés
  par Nicolas le 11/06/2026 — vérification **jamais close** au 05/08/2026
  (aucune trace dans les docs ni le CHANGELOG). Contrôle à passer :
  ```sql
  SELECT to_char(occurred_at AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI'),
         props->>'cooked_aid'
  FROM events_human
  WHERE name = 'form_submit' AND occurred_at > '2026-06-11'
    AND props->>'objet_de_ma_demande' ILIKE '%divorce%'
  ORDER BY occurred_at DESC LIMIT 5;
  ```
  Si `cooked_aid` est renseigné : clore la ligne avec la date. Si aucune
  soumission Divorce n'est arrivée : le dire, plutôt que de laisser une action
  ouverte sans statut.

---

## Git — routine de push

Le push direct GitHub fonctionne (PRs #11→#30, juin-juillet 2026). Routine :
branche `claude/<sujet>` → commit(s) → `git push -u origin` → PR via `gh pr
create` → merge si vert (`gh pr merge --merge --delete-branch`). Règles :
(1) toute migration appliquée en prod via MCP a son miroir EXACT dans
`supabase/migrations/` (timestamp réel via `schema_migrations`) dans la
même PR ; (2) jamais de contenu placeholder ; (3) `latest_rpc_health()` +
advisors vérifiés après chaque migration. (L'ancienne routine « bundle »
de l'époque container est obsolète — historique dans git si besoin.)

## Agent skills

> Configuration consommée par les skills d'ingénierie (Matt Pocock :
> `triage`, `to-issues`, `to-prd`, `tdd`, `diagnose`,
> `improve-codebase-architecture`…). Détails dans `docs/agents/*.md`.

### Issue tracker

Issues & PRDs → **GitHub Issues** du repo (`github.com/NicolasRewolf/cooked`),
via la CLI `gh`. Voir `docs/agents/issue-tracker.md`.

### Triage labels

5 rôles canoniques, vocabulaire **par défaut** (`needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`). Voir
`docs/agents/triage-labels.md`.

### Domain docs

**Mono-contexte** : `CONTEXT.md` + `docs/adr/` à la racine (créés à la demande
par `/grill-with-docs`). Voir `docs/agents/domain.md`.
