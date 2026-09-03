# Changelog

Format basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Versions datées (pas de semver strict) — jalons opérationnels du système Cooked.

## [2026-09-03] — T-03 : taux de rebond ×100, une unité par nom de colonne, contrat d'unités

Mission du 02/09/2026 (`docs/mission-2026-09-02/`), ticket T-03 (#104), constats d-01 (P0) et d-04 (P1).

### Corrigé
- **`behavior_pages_for_period` renvoyait un rebond 100× trop faible** (0,23 pour 23,28) depuis le 26/07/2026 :
  le correctif du défaut « deux unités » avait redivisé par 100 une fraction déjà 0‑1 et mis la fraction dans
  `bounce_rate_pct`. Migration `20260903053754`.
- **`cooked_bounce_rate` unifié en pourcentage 0‑100** dans `gsc_page_performance` (était une fraction) et dans le
  chemin lent de `pages_overview_unified` (idem) — même unité que le chemin rapide et `seo_url_snapshot`.
- **`seo_pages_overview` : les sessions à referrer spam sortent du dénominateur du rebond.** Le bot Baidu (UA `pc`)
  faisait 99 des 152 entrées de `/honoraires-rendez-vous` sans jamais « rebondir » (1 pageview + ticks ≥ 10 s) :
  21,7 % au lieu de 32,1 %. C'était l'écart résiduel non expliqué de d-04.

### Invariant livré (I5)
- Quatre contrats d'unités dans `run_rpc_contract_tests` (`units_*`, 0 ligne en violation attendue) : `*_rate` ∈ [0,1],
  `*_pct` ∈ [0,100], et un lot de `cooked_bounce_rate` dont le max ≤ 1 est refusé.

### Restatement (annotation du 03/09/2026)
- Lecteurs de `behavior_pages_for_period` (contract-tests, ad-hoc) : ×100. `gsc_page_performance` : ×100 et hors bot.
  Le dashboard (snapshot) ne bouge pas. Phrase : « correction d'unité et de mesure, pas un changement de comportement ».

## [2026-08-31] — page_taxonomy : 12 articles jamais ingérés + alerte de récidive

Question de Nicolas (« tu as ingéré les tout derniers articles de ressources
et notions juridiques ? ») : **non**. La catégorie Wix Blog n'a pas de cron ;
dernière synchro le 22/07/2026 (ressource) / 10/07/2026 (classique).

### Diagnostic
- L'API Wix déclare **433 posts publiés** (62 `ressource` + 371 `classique`) ;
  `page_taxonomy` n'en connaissait que **426**, dont 58 ressources.
- Diff exhaustif contre la liste faisant autorité : **421 déjà corrects,
  12 absents, 0 catégorie erronée**, 5 paths en base qui ne sont plus publiés
  (dépubliés ou re-sluggés — conservés pour l'historique de trafic).
- **Cause** : ni `refresh_page_taxonomy_heuristic()` (filtre trafic 90 j) ni les
  synchros Wix précédentes ne créent de ligne pour un path jamais vu dans
  `events_human`. Un article publié mais pas encore visité passe à travers —
  et n'est jamais rattrapé, la passe suivante repartant du même filtre. Les
  5 ressources manquantes ont toutes démarré leur trafic après le 22/07.
- Le mode de défaillance n'est donc **pas** `category IS NULL` mais l'absence
  totale de ligne — ce que le réflexe documenté jusqu'ici ne cherchait pas.

### Réparé
- **Migration `20260831090540`** : upsert des 12 lignes manquantes (5 ressources
  — `soumission-chimique`, `fraude-bancaire`, `faute-inexcusable`,
  `pension-alimentaire`, `changer-d-avocat` — et 7 classiques). Thème calculé
  par la même heuristique de slug, `source='slug_heuristic'` pour rester
  maintenables ; `theme`/`source` des lignes existantes préservés.
  Après : 438 posts, **63 ressources** (62 Wix + 1 vestige 301), 374 classiques.
- **Alerte `page_taxonomy_gap`** (`alert_rule_page_taxonomy_gap()`, découverte
  automatiquement par `cooked_alerts_refresh()`) : compte les `/post/` avec
  ≥ 5 vues/30 j sans catégorie, `warn` à 3, `critical` à 10. Entièrement en SQL,
  aucun appel Wix. Elle aurait sonné dès juillet.
- **Migration `20260831090702`** : `revoke execute … from anon, authenticated`
  — `revoke all … from public` ne suffit pas face aux default privileges
  Supabase (advisors 0028/0029 levés par la migration précédente, refermés).

### Vérifications
- Deux méthodes indépendantes donnent le même écart de 12 (diff par empreinte
  md5 côté client, et requête de détection SQL côté serveur).
- Comptes réconciliés : 421 + 12 = 433 = total Wix ; 426 + 12 = 438 en base.
- `alert_rule_page_taxonomy_gap()` → 0 ligne après correctif ;
  `cooked_alerts_refresh()` → 0 alerte, aucun crash de règle ;
  `latest_rpc_health()` → 0 KO ; ACL alignée sur les autres règles
  (`postgres=X | service_role=X`) ; `rpcs.sql` + méta régénérés (121 → 122).

## [2026-08-23] — Panne silencieuse du webhook forms : backfill + réparations

Découvert pendant le bilan mensuel du 22/08 : l'automation Wix « Form
Submitted → POST form-webhook » a été **supprimée le 11/08** lors d'un
remaniement des automations du site. Onze jours sans un seul `form_submit`,
**aucune alerte** (`form_submit_dropped` ne voit que les payloads reçus ;
aucune règle « zéro form depuis N jours » n'existait). 22 soumissions
réelles (12–21/08) confirmées côté API Wix et export CSV officiel.
Seconde panne du même week-end : le cron GBP en échec reauth ADC depuis le
08/08 (`gbp_gap` a sonné, mais à J+14).

### Réparé
- **Automation Wix recréée** (22/08, token `FORM_WEBHOOK_SECRET` régénéré) —
  nommée « ⚠️ Cooked analytics — form → webhook (NE PAS SUPPRIMER) ».
- **Backfill des 22 `form_submit` perdus** (migration `20260823112541`) :
  rows iso-format v13 sans PII, `capture_source='wix-backfill'`,
  `props->>'submission_id'` = empreinte `wiximport-…` **identique** à
  `crm_prospects.wix_submission_id` (lien events↔crm matérialisé pour ces 22).
  Contacts macro 01-21/08 : 124 → **143** (vs 156 en juillet, soit −8 % et
  non −21 %). Annotation posée dans `annotations`.
- **`crm_prospects` rattrapé** via `wix_forms_import.py` (+29, total 827) ;
  dédoublonnage des 7 captures webhook du 10-11/08 réimportées par le CSV
  (migration `20260823112604` — on garde la row au vrai submissionId Wix).
- **Index `events_form_submit_submission_id_uniq` matérialisé** dans les
  migrations (existait en prod depuis Sprint 25, absent du repo — drift).
- **Secret `NTFY_TOPIC` posé côté GitHub** : les steps `notify-failure` des
  4 workflows d'ingestion étaient inertes depuis toujours (constat Majeur
  audit 25/07) — les 14 échecs consécutifs du cron GBP n'ont jamais rien
  poussé. Désormais tout échec CI notifie sur ntfy.
- **GBP réingéré** (credential ADC renouvelé par Nicolas, secret re-poussé,
  run vert) : `gbp_daily` de retour à J-3, 12 jours rebouchés, la fiche n'a
  pas décliné (~175 appels/mois, rythme stable).

### Suite (revue d'architecture du 22/08, programme acté 1→3→2)
Trois chantiers de résilience : registre déclaratif des contrats de
fraîcheur (+ règle « Silence » — forms : warn 48 h / critical 4 j, escalade
générique warn→critical à +5 j), module d'ingestion forms à deux adapters
(push webhook + pull de réconciliation API Wix), battement d'exécution des
jobs GitHub + pg_cron.

## [2026-08-11] — Dashboard : lifting UI (tokens, chrome de tableau collant)

Reprise de l'**architecture** de [beautiful-ui](https://beautiful-ui-five.vercel.app/),
pas de son esthétique. Identité Cooked inchangée : angles vifs, orange rewolf
`#FF4F04`, IBM Plex, thème clair. Aucune donnée, RPC ni migration touchée.

### Modifié
- **41 couleurs en dur → 0.** Elles étaient disséminées dans 14 composants
  (`#45423c` seul revenait 14 fois) : le système de tokens fuyait et une
  retouche de palette demandait 14 éditions. `#45423c` devient
  `--color-ink-2` (l'encre des valeurs de tableau) ; 5 gris quasi identiques
  (`#efefed #f1f1ef #f2f2f0 #eeeeec #ececea`) fusionnent en `line-soft` /
  `field` / `line`. Rendu inchangé au pixel — c'est une déduplication.
- `globals.css` : surfaces en couches (paper/panel/inset/hover/field), filets
  gradués, sémantique doublée d'une teinte (`up`/`down`/`warn`/`info` +
  `-tint`), élévation par anneau (`shadow-overlay`, `shadow-sticky`).
  Token mort `--color-zebra` retiré.
- **`SortableTable` : en-tête, 1re colonne et pied collants.** Sur 51 articles
  × `min-width: 1160`, on perdait le nom de l'article au défilement horizontal
  et le nom des colonnes dès la ligne ~15.
- Le popover `Info` passe par un **portail** : depuis que les `th` sont
  `sticky` avec z-index, ils ouvrent un contexte d'empilement et un `fixed`
  resté dedans passerait sous la colonne figée.
- Filtre santé : **chips à compteurs** au lieu du `<select>` — la distribution
  est visible en permanence, et les compteurs (calculés hors filtre santé)
  annoncent ce qu'on obtient en cliquant.
- Squelettes de chargement : balayage au lieu du clignotement, avec garde
  `prefers-reduced-motion`.

### Ajouté
- `Column.total(rows)` → ligne de totaux, sur les lignes **visibles**.
  Volontairement **sans total** : la position (une moyenne inter-pages est le
  piège n°2 du playbook) et la lecture (une médiane de médianes n'est pas une
  médiane). Le CTR s'agrège correctement : `aggregateCtrPct` =
  Σ clics / Σ impressions, extrait en fonction pure et testé.
- 4 tests (92 au total). Règles dures ajoutées dans `dashboard/CLAUDE.md`
  (n° 5 tokens, n° 6 totaux) et section « Système visuel » du README.

## [2026-08-10] — Pont SECIB : fondations (PIVOT — PII en clair)

### Décision produit
- **Cooked stocke désormais EN CLAIR nom/prénom/email/téléphone des prospects
  web** pour les rapprocher des dossiers SECIB réellement ouverts/facturés
  (décision Nicolas du 10/08/2026 ; le hachage a été proposé et refusé).
  La PII est confinée à `crm_prospects` + `secib_dossiers` (RLS deny-all,
  service_role uniquement) — `events`/`events_human` et toutes les RPCs
  analytics restent sans PII. **Registre RGPD + politique de confidentialité
  du site à mettre à jour (action Nicolas).**

### Ajouté
- Migration `20260810082433_secib_pont_fondations` : tables `crm_prospects`
  (capture web) et `secib_dossiers` (miroir dossiers, colonne `env`
  test/prod), fonctions `cooked_normalize_email` / `cooked_normalize_phone_fr`
  (E.164 FR), vue **`pont_prospects_dossiers`** (matching email > téléphone,
  statut converti / client_existant / non_converti, délai en jours).
- **Edge `form-webhook` v13** : extraction heuristique de l'identité prospect
  (clés `field:*`, fallback `submissions[]`, fallback contact Wix) →
  `crm_prospects`, AVANT l'insert events, jamais bloquante. Le texte libre
  (message) est exclu volontairement. Tests deno ajoutés (dont l'invariant
  « la row events reste sans PII »).
- `scripts/secib_ingest.py` (probe/ingest) : dossiers SECIB + identité premier
  client + facturation par dossier via `ExportComptable/ExportFinancier`
  (seul endroit où le lien facture→dossier existe : `DossierCode` +
  `DossierMatiereId`). Validé sur le cabinet bac à sable (49 dossiers,
  chargés en base `env='test'`).
- **Backfill historique** : `scripts/wix_forms_import.py` + migration
  `20260810085356_crm_prospects_utm_columns` — les **795 soumissions** de
  l'export Wix (03/2025 → 08/2026) sont dans `crm_prospects`, 100 % avec
  email ET téléphone normalisables, 104 avec `cooked_aid` (attribution
  canal), 438 avec `utm_source`. Import idempotent (empreinte
  `wiximport-<sha1>`, INSERT only) — rejouable sur un export plus frais.
  Le pont couvre donc tout l'historique dès la connexion prod SECIB.

### Étape 0 API SECIB (validée le 10/08/2026 sur credentials de test)
- Token client_credentials OK ; `Dossier/Get` en **POST** (le GET renvoie 400) ;
  le `PremierClient.Personne` inline contient nom/prénom/email/téléphones.
- **Rectificatif du 05/08** : les `InfoComplementaire` sont écrivables par
  l'API (`SaveOrUpdateListInfoComplementaire`) mais **PAS lisibles** dans ce
  swagger — la question est posée à Septeo. Le pont par identité (ce jalon)
  n'en dépend pas.
- Accès **prod** conditionné à la signature du devis SECIB+ (120 €HT/mois,
  engagement 12 mois, devis n° 165256_26085613 du 07/08 — validité 10 jours).

### Rangement post-pivot (audit du soir, migration `rangement_post_pivot_secib`)
- **Alerte `gbp_gap` créée** (warn > 7 j, critical > 14 j → ntfy) — première
  levée immédiate : le cron GBP est retombé en panne reauth ADC du 06 au
  10/08 (5 échecs GitHub Actions silencieux). Reauth = action Nicolas.
- **Tables `cpi_pre_restatement_20260712` / `_20260727` supprimées**
  (échéances ~19/07 et ~03/08 dépassées, recul pris).
- **VACUUM FULL annuel désarmé** : le « one-shot » de l'audit du 26/07 était
  programmé `0 2 26 7 *` et se serait rejoué chaque 26 juillet avec un lock
  exclusif de `events`.
- **19 alertes historiques acquittées** (cpi_drop de contenu résumées à
  Nicolas, cpi_gap historiques, pipeline_dead transitoire du 01/08).
- **Audit doc multi-agents : 39 désynchronisations corrigées** (form-webhook
  v12→v13 dans 4 fichiers, 118→121 routines, ROADMAP resynchronisée,
  `views.sql` régénéré — il datait du 10/07 et manquait 4 vues dont
  `events_main`/`pont_prospects_dossiers`, vocabulaire « prospect » scopé
  dans CONTEXT.md).

## [2026-08-05] — Cron GBP réparé + sonde des requêtes de la fiche

### Corrigé
- **Cron `gbp-daily-ingest` en échec silencieux du 30/07 au 04/08** : le
  credential ADC utilisateur exigeait une reauth Google (`RefreshError`).
  Re-login gcloud (scopes `business.manage` **+** `cloud-platform` —
  obligatoires ensemble), secret `GBP_CREDENTIALS_B64` re-poussé, run vert,
  trou 29/07→04/08 rebouché par la fenêtre 30 j du script.
- **À faire** : alerte de fraîcheur **`gbp_gap`** (elle n'existe pas — 6 jours
  de panne sans signal) ; parade durable à la reauth = client OAuth dédié
  (voie 2 de `scripts/gbp_ingest.py`).

### Ajouté — mesures (lecture seule, hors base)
- **Requêtes de recherche de la fiche GBP** (12 mois, endpoint
  `searchkeywords/impressions/monthly`) : 839 mots-clés, ~18 100 impressions
  exactes. La fiche est **quasi invisible sur l'indemnisation**
  (≤75 impressions vs ~2 100 pénal) alors que la demande locale existe
  (DataForSEO « avocat dommage corporel bordeaux » : 210/mois). Lag de
  publication ≈ 1 mois → toute ingestion devra être **mensuelle**.
- **Lecture API de la fiche** : catégories (dont « dommages corporels »),
  ~43 services et description sont **déjà** orientés indemnisation ; le seul
  signal encore 100 % pénal est le **nom** de la fiche. Avis : 200, moyenne
  4,6, 45 mentions pénal / 20 indemnisation → les avis sont disculpés.
- **API SECIB** : swagger lu (04/08), ticket d'accès envoyé à Septeo (05/08).
  Pas de champ « origine du dossier » natif ; champs personnalisés
  `InfoComplementaire` lisibles et écrivables par l'API.

## [2026-07-29] — Framework d'analyse mathématique (PR #91)

### Ajouté
- `scripts/advanced_math_analytics.py` : chaînes de Markov, graphe de
  navigation interne, valeurs de Shapley, inférence causale, STL/Kalman.
- Briques SQL : RPC `math_visit_sequences` / `math_internal_edges` +
  snapshots `math_*_snapshot` (refresh `math_refresh_snapshots`).
- Rapport et **limites de conclusion** :
  `docs/analyse-mathematique-avancee-2026-07-29.md` (lire avant d'invoquer
  ces méthodes).

### Sécurité
- `EXECUTE` public révoqué sur les RPC `math_*` (advisors 0028/0029).

## [2026-07-28] — Les appels depuis la fiche Google sont mesurés (B3 clos)

### Ajouté
- API Google Business Profile approuvée → table **`gbp_daily`** (format long
  jour × fiche × métrique), backfill 18 mois (4 842 lignes), cron
  `gbp-daily-ingest.yml` à 05:30 UTC. **~162 clics d'appel / 28 j**, stables
  sur 18 mois : l'angle mort pesait l'ordre de grandeur de tout le contact
  web mesuré (208 contacts macro / 28 j).
- Vue **`cpi_capture_perdue`** : clics perdus face à la courbe CTR du site,
  **avec la fiabilité du chiffre** (`fiabilite_capture`, `interpretable`).
  Ne plus lire `cpi_daily.clics_perdus` à la main.

### Pièges documentés
- L'API rembourre la fin de fenêtre avec des **zéros** tant que Google n'a pas
  consolidé (lag ~J-4) : un zéro récent n'est pas un vrai zéro.
- Impressions Maps : **rupture de comptage en 09/2025** sans baisse des
  actions — changement côté Google, pas un déclin de la fiche.
- Auth : OAuth **utilisateur** obligatoire (les comptes de service sont
  refusés, contrairement à GSC).

### Décision
- Numéro de téléphone traçable sur la fiche : **décliné par Nicolas**.

## [2026-07-27] — `classify_channel` v3 : GMB devient un canal à part entière

### Modifié
- Les clics venant de la fiche Google (`utm_source=gmb`) sortent de
  `organic_google` : **44,8 %** des entrées « organiques » de la home en
  étaient. GMB convertit à **3,68 %** contre **0,57 %** pour le SEO organique
  réel — meilleur canal du site, devant le paid.
- **Restatement CPI** : home n_org 305→164, grade S→A, `zv` en baisse.
  Annotation posée, photo dans `cpi_pre_restatement_20260727` (migration
  `20260727215805`). ⚠️ Un « avant/après 27/07 » sur la home **n'est pas un
  decay**.

## [2026-07-25] — Revue d'architecture n°2 (48 constats)

### Modifié
- Edge `track` **v26** : la taxonomie `ua_bot` est appliquée **avant**
  l'INSERT (les crawlers ne sont plus écrits ; drops comptés dans
  `ingest_drops`) — constat n°5 / R2. Puis **v27** : gate `x-cooked-key` à
  l'ingestion (constat n°3).
- `dashboard_assisted_quarter` unifié sur la **visite recousue** via
  `assisted_contacts_by_entry_path` (migration
  `20260725220100_audit_assisted_contacts_unified`) — l'invariant
  d'attribution de CONTEXT.md est respecté.

### Ajouté
- Contrat CI **`contracts/dashboard_rpc_columns.json`** (Arch #6) : colonnes
  des RPC dashboard ↔ schémas Zod `rpc-schemas.ts`.

### Détail
- 48 constats et leur avertissement de fiabilité :
  `docs/audit-architecture-2026-07-25.md`.

## [2026-07-23] — Norme CPI : Fiabilité S/A/B/C + Opportunité de contact

### Modifié
- **Fiabilité** (colonne SQL `grade`) : échelle **S / A / B / C**
  (S: n_org≥200∧E≥40 ; A: ≥100∧≥20 ; B: ≥30∧≥5 ; C: sinon).
  `cpi_movers.fiable` et opportunités = S/A/B.
- Vue **`cpi_opportunite_contact`** (ex-libellé « gisement ») ; alias
  déprécié `cpi_gisement` conservé pour les refreshers.
- Dashboard : filtre ★ opportunité de contact, badges Fiabilité, docs
  (CLAUDE, PLAYBOOK, CPI, OPERATIONS, README).

### Non renommé
- `GisementsPanel` / quick wins SEO (autre concept : gain clics GSC).

## [2026-07-13] — Grand ménage : docs A→Z + hygiène repo

### Modifié — Documentation (audit 4 agents + 5 rédacteurs, 12-13/07)
- **28 fichiers .md alignés** sur l'état canonique du 12/07/2026 au soir :
  sprint41 déployé, couture d'identité documentée partout (README, CLAUDE.md,
  AGENTS.md, OPERATIONS — nouvelle section dédiée + table des 12 crons réels +
  inventaire des restatements + procédure de vérif J+1 tracker), validation
  CPI J+28 écrite au passé (11/07, VALIDÉE, « score de priorisation »),
  encadré « ruptures de série cpi_daily » (02/07 + 12/07), 2 nouveaux pièges
  au playbook (aid 32-hex, assists pré-12/07 sous-comptés), 105 RPC partout.
- **Index docs/README.md** restructuré (docs vivants vs archives datées) ;
  **8 bandeaux d'archive** posés ; ROADMAP-sprint38-handoff gelé en archive,
  remplacé par **`docs/ROADMAP.md`** (reste-à-faire courant, 6 items datés) ;
  JOURNAL-actions-contenu clos (source canonique = table `annotations`,
  verdict vague 11/06 consigné : validée, phone posts ~2→~43).
- **dashboard/README.md** : section Données réécrite (14 RPC consommées
  vérifiées dans le code, crons, zod) + paragraphe « Contacts assistés v2 » ;
  **dashboard/CLAUDE.md** : 4 règles dures projet (contrat RPC, secret
  server-only, snapshots J-1, sémantique assistés).

### Corrigé — Hygiène
- **`backup-weekly.yml` : schedule retiré** — il échouait en rouge chaque
  dimanche (secret jamais créé ; backup décliné le 02/07, risque assumé).
  Déclenchement manuel uniquement.
- **Trou de CI comblé** : `edge-shared-helpers.yml` exécute désormais les
  tests Deno de `track_row.ts` et `form_row.ts` (D4) — jamais lancés en CI.
- `cooked_events_window_contract.sql` retiré des paths CI (contrat manuel,
  documenté dans OPERATIONS) ; smoke-tests `test_refresh_*.sql` documentés.
- Supprimés : `supabase/scripts/` (répertoire fantôme périmé),
  `scripts/c1_finish_noise_regression.sql`,
  `scripts/cooked_events_window_adoption_regression.sql` (one-shots morts).
- Migration `20260713000733` : `expected_tracker_version` → `sprint41`
  (évite une fausse alerte `tracker_drift` post-déploiement).

## [2026-07-12] — Couture d'identité : sessions coupées recollées, attribution réparée

### Corrigé — Bug d'identité tracker (cause racine)
- **Tracker `sprint41`** : ids auto-réparants. Un wipe/transition de storage en
  cours de page (typ. décision du bandeau de consentement ~10 s après l'arrivée)
  faisait tourner le `sid` (relu à chaque event, re-minté sur miss) puis l'`aid`
  (caché en closure, jamais ré-écrit → tournait à la navigation suivante).
  Mesuré : ~22 % des sessions coupées en deux, ~95 % des `cta_phone_click` sans
  amont visible, stable ≥6 semaines (antérieur à sprint40). Quatre gestes,
  iso-comportement si le storage est sain : cache mémoire `_cachedSid` ré-écrit
  au lieu de re-minter ; `healAid()` opportuniste (adossé au debounce 5 s) ;
  lecture sessionStorage sur MISS (plus seulement sur exception) avec
  rapatriement ; `exposeIds()` rejoué au flush si la paire (aid,sid) a tourné.
  **À déployer via minify + Wix Custom Code.**

### Ajouté — SQL (migrations `20260712*`, appliquées en prod le 12/07)
- Table **`identity_stitch`** + `refresh_identity_stitch(90)` : composantes
  connexes du graphe biparti aid↔sid (label propagation, convergence 2 iter.,
  aids 32-hex fallback serveur exclus comme clé). Recolle rétroactivement les
  visites coupées. Cron nocturne `40 3 * * *` (avant les refreshers dashboard).
- **`refresh_dashboard_resources_assisted` v2** : entrée d'un contact = première
  pageview de la **visite recousue** (segmentation à trous >30 min, rattachement
  à la dernière pageview ≤6 h avant le contact), fallback session brute.
  Contrat de sortie inchangé. Validation prod 12/07 : contacts assistés
  « ressource » 28 j **16 → 37**, entrée connue des phone clicks 54 % → 99 %,
  0 composante multi-device (garde-fou faux recollages), cas d'école du
  11/07 18:52 attribué à son article d'entrée réel.
- Cron `refresh-dashboard-assisted` : timeout 300 s → 590 s (v2 plus lourde).

### Ajouté — soirée du 12/07 : conversion_journeys v2 + restatement CPI
- **`conversion_journeys` v2** (migration `20260712203935`) : parcours sur le
  visiteur recousu (visitor_key via `identity_stitch`, sid > aid > fallback
  session brute), journey = pageviews de la **visite** ([t-6h, t+3min], chaîne
  sans trou > 30 min). Contrat de sortie inchangé, ~1 s sur 28 j. Répare par
  héritage `seo_to_contact_funnel` (le contact du 11/07 apparaît enfin sur sa
  landing organique) et `content_performance` (crédit posts au lieu de cabinet).
  Sur 28 j : 210 contacts, 3 seuls sans canal (vs des dizaines), 53 avec une
  entrée ≠ page du contact.
- **Restatement CPI du 12/07 au soir** (via `cooked_cpi_snapshot()`, one-off
  22:48–22:55 Paris, upsert sur `cpi_daily` du jour) : la composante conversion
  (zv, jx = conversion_journeys organic) voit enfin les contacts recousus.
  Contrôles : zc/zr/zl/momentum/gate strictement inchangés page par page ;
  delta CPI moyen −0,1 pt (aucune inflation) ; **0 changement de grade** ;
  7 movers ≥ 15 pts, tous expliqués — 6 articles récupèrent leurs conversions
  (arnaque-en-ligne 41→100 [2 contacts contre-vérifiés event par event],
  sarvi-ou-civi 39→85, ordonnance-protection 40→77 [C], panneaux-solaires
  60→92 [C], faute-lourde 23→38, ddse 12→27) et `/nos-affaires` 67→12 rend le
  crédit usurpé (première page des sessions coupées). Annotation posée dans
  `annotations` (12/07) : un saut de CPI au 12/07 n'est PAS un mouvement de
  page. Sauvegarde d'audit `cpi_pre_restatement_20260712` (157 lignes, à
  supprimer ~J+7). Dashboard entièrement resnapshotté le 12/07 à 23:04–23:09
  Paris (KPIs, resources, assisted, expertises).

### Connu — reste à faire (session du 12/07)
- Dashboard UI : harmoniser les deux compteurs (« contacts sur la page » du
  tableau vs « contacts assistés » de la fiche) — afficher les deux, étiquetés.
- Vérif J+1 (13/07) : taux de sessions coupées sous tracker `sprint41` (attendu
  ≈ 0 vs ~22 %) ; premiers `cpi_movers` post-restatement ~19/07 (fenêtre 7 j).
- `cooked_page_index` : sensibilité conversion inchangée (~65 % de la variance,
  point ouvert S39) — le restatement corrige l'INPUT, pas la pondération.

## [2026-07-10] — Revue architecture complète + repo standardisé

### Ajouté — SQL (Arch #1–#5, PRs #60–#61)
- Lens **`live_j1`** dans `cooked_period_bounds` (ancrage J-1 Paris dashboard).
- **`gsc_is_branded(query)`** + contrat `contracts/branded_query_vectors.json`.
- Procédure **`cooked_snapshot_window`** (driver des 3 refreshers dashboard).
- **`supabase/rpcs.sql`** — miroir lecture 104 RPC + gate CI `check_rpcs_sql_fresh.py`.

### Ajouté — Dashboard (D6–D8, PRs #58–#59, #64)
- **D7** `data/view-models.ts` — view-models purs (pages → props UI testables).
- **D8** `lib/chart-geometry.ts` — géométrie SVG partagée (TrendChart, Sparkline, CohortChart).
- **D6** `metric-columns.tsx` + `useTableViewState` — colonnes partagées Resources / Expertises / SEO.

### Ajouté — Edge & tracker (D4, D9, PRs #57, #65)
- **D4** `_shared/track_row.ts` + `_shared/form_row.ts` (builders testables Deno) ;
  Edge **track v25**, **form-webhook v12** dans le repo.
- **D9** refactor helpers tracker (`stripSlash`, `inStickyAncestor`, `labelOf`) —
  iso-comportement, `COOKED_VERSION` inchangé (`sprint40`).

### Ajouté — Maintenabilité repo (PR #63)
- LICENSE, CONTRIBUTING, SECURITY, AGENTS.md, CHANGELOG, `.env.example`,
  `.editorconfig`, templates GitHub Issues/PR.

### Modifié
- Fin des blocs `v_shift` copiés dans 11 callers dashboard.
- Documentation synchronisée sur l'ensemble du repo.
- **`main` unique** — branches et worktrees Claude obsolètes purgés (PRs #57–#65 mergées).

### Déploiement manuel (repo ≠ prod tant que non fait)
- Edge : `supabase functions deploy track` + `form-webhook` (v25 / v12).
- Tracker D9 : `python3 scripts/minify-tracker.py` → coller dans Wix Custom Code.

## [2026-07-04 — 2026-07-09] — Programme architecture C1–C9

### Ajouté
- `paris_date()` / `paris_today()` + garde CI C6.
- `cooked_events_window()` adopté par les refreshers nocturnes.
- Alertes modulaires (9 règles + driver C2).
- Contrat `canonical_path` unifié SQL / Edge / Python (C3).
- Tests Python GSC/DFS + `cooked_store.py` (C7).
- Dashboard : `lib/dates.ts`, Zod, vitest (C9).
- Modules Edge `_shared/events_row` (C5).

## [2026-07-01 — 2026-07-03] — Audit Fable 5 (T-01 → T-19)

### Ajouté
- Tracker **sprint40** (page_exit ré-armé) ; Edge **track v23** ; webhook **v11**.
- Alerte `gsc_gap` ; ingest GSC `--daily` (2 mois) ; backfill 31/05 & 30/06.
- `classify_channel` v2 (IA via utm_source).
- Purge hebdo bruit > 28 j ; filtres incrémentaux 48 h.
- Alertes critical → ntfy.
- Dashboard : onglet Expertises, fiches article, contacts assistés.

### Modifié
- Restatement CPI léger (±7 pts, grain session×path).
- 14 pages expertise = liste business explicite.

## [2026-06-29 — 2026-06-30] — Dashboard V1 + fiabilité pipeline

### Ajouté
- Sous-app **dashboard/** live sur data.rewolf.studio.
- RPC `dashboard_*` sur snapshots quotidiens.

### Corrigé
- Cron CPI gelé (timeout) ; snapshot SEO optimisé (671 s → 210 s).
- Filtres bruit : `TRUNCATE` → `DELETE` (fin deadlocks).

## [2026-06-15 — 2026-06-18] — Sprint 39

### Ajouté
- CPI v2.2 ; vue `cpi_gisement` ; alertes recalibrées.

### Corrigé
- `click_internal.target_path` URL-décodé (Edge v22 + backfill).

## Versions antérieures

Chronologie complète : [docs/HISTORY-sprints.md](docs/HISTORY-sprints.md).
