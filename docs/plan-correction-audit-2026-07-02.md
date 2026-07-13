> ⚠️ Archive du 02/07/2026 — exécuté à 100 % (18 PRs), clos le 03/07/2026.

# Plan de correction — audit du 02/07/2026

> **Public : développeur tiers qui découvre le repo.** Ce document est
> auto-suffisant : contexte minimal, règles non négociables, puis une
> fiche par tâche (T-01 → T-18) avec fichiers exacts, changement attendu,
> validation et pièges. Source des constats :
> [audit-fable5-2026-07-02.md](audit-fable5-2026-07-02.md) (preuves
> détaillées). Les numéros de ligne sont valables au commit du 02/07/2026.
>
> **Ordre d'exécution = ordre des vagues.** Ne pas paralléliser à
> l'intérieur d'une vague sans lire la fiche (certaines tâches dépendent
> l'une de l'autre). Une tâche = une PR.

---

## 0. Contexte en 60 secondes

Cooked est un analytics first-party pour `jplouton-avocat.fr` (site Wix) :

```
wix/tracker.html (collé dans Wix Custom Code, minifié < 15 000 chars)
  → proxy Velo wix/http-functions.js (same-origin)
  → Edge Function Supabase `track` (Deno, supabase/functions/track/index.ts)
  → table events (brut) → vue events_human (events − bots − bruit)
+ scripts/gsc_ingest.py (cron GitHub Actions quotidien) → tables gsc_*
+ RPCs SQL publiées (l'« API » du système) + dashboard Next.js (dashboard/)
```

- **Projet Supabase** : `mxycmjkeotrycyneacje`. L'accès prod (clé service /
  connection string) est fourni par Nicolas — ne jamais la committer.
- **Timezone** : la base stocke en UTC, TOUT le métier raisonne en
  Europe/Paris. **Dates affichées : JJ/MM/AAAA.**
- La prod reçoit du trafic en continu : c'est un banc de test **en
  lecture** ; toute écriture passe par une migration.

## 1. Règles non négociables (extraites de CLAUDE.md)

1. **Un fix DB = une migration nommée** dans `supabase/migrations/`
   (`YYYYMMDDHHMMSS_<sujet>.sql`, timestamp réel), appliquée en prod ET
   committée. Jamais d'UPDATE/DDL manuel non tracé. Après chaque
   migration : vérifier les advisors Supabase (security + performance) et
   `SELECT * FROM latest_rpc_health();` (tous les tests de contrat OK).
2. **Requêtes métier : `FROM events_human`, jamais `FROM events`**
   (sauf audit du filtrage lui-même — l'expliciter en commentaire).
3. **Filtrage par date** : `(occurred_at AT TIME ZONE 'Europe/Paris')::date`,
   jamais `occurred_at::date`.
4. **Ne JAMAIS toucher aux colonnes identité des `form_submit`**
   (`anonymous_id`/`session_id` en `webhook-…`) — invariants Sprints 24/29.
   L'attribution vit dans `props` et les RPCs de lecture.
5. **Tracker** : modifier UNIQUEMENT `wix/tracker.html` (source commenté),
   minifier via `python3 scripts/minify-tracker.py`, **asserter < 15 000
   caractères**, rejouer `tests/tracker.test.js` (jsdom) sur source ET
   minifié. Ne jamais éditer le `.min` à la main. Le collage dans Wix est
   fait par Nicolas — livrer le fichier prêt + le bloc d'instructions.
6. **Contrats de sortie des RPCs publiées : stables.** On peut corriger
   l'intérieur, pas les signatures/colonnes sans décision explicite.
7. **Interdit sans validation explicite de Nicolas** : DROP TABLE, DELETE
   de masse, changement de coût (plan Supabase, API payante), toute
   action dans Wix Studio.

## 2. Pré-requis d'accès (à demander à Nicolas)

- Connection string Postgres du projet (ou accès Supabase Studio) — pour
  appliquer les migrations (`supabase db push` ou psql).
- `SUPABASE_SECRET_KEY` + fichier service-account GSC
  (`gsc-credentials.json`) — uniquement pour T-01 (backfill).
- Accès en écriture au repo GitHub `NicolasRewolf/cooked` (branches + PR ;
  les secrets Actions existants : `GSC_CREDENTIALS`, `SUPABASE_SECRET_KEY`,
  `DFS_USERNAME`, `DFS_PASSWORD` — vérifier les noms exacts dans
  `.github/workflows/*.yml`).

---

# VAGUE 1 — Stopper les pertes (jour 1)

## T-01 · Backfill GSC : récupérer le 31/05 et le 30/06 ⚠️ URGENT

- **Priorité** : P0 — chaque jour qui passe rapproche le 31/05 de la
  limite des 16 mois de rétention Google (mais on a de la marge) ; le
  30/06 est déjà consolidé (`dataState:final`) et récupérable.
- **Problème** : la fenêtre du cron est un mois calendaire (voir T-02) →
  `day='2026-05-31'` et `day='2026-06-30'` ont 0 ligne dans
  `gsc_path_daily`, `gsc_query_daily`, `gsc_query_page_daily`.
- **Action** (locale, avec les env du workflow) :
  ```bash
  export SUPABASE_SECRET_KEY=…       # fourni par Nicolas
  export GSC_CREDENTIALS_PATH=…      # chemin du service-account JSON
  # (vérifier le nom exact de la variable dans scripts/gsc_common.py)
  python3 scripts/gsc_ingest.py path-query --end-date 2026-06-30 --months 2
  python3 scripts/gsc_ingest.py query-page --end-date 2026-06-30 --months 2
  ```
  Les upserts sont idempotents (PK composites) : re-couvrir mai/juin est
  sans danger.
- **Validation** :
  ```sql
  SELECT 'path' src, count(*) FROM gsc_path_daily  WHERE day IN ('2026-05-31','2026-06-30')
  UNION ALL SELECT 'query', count(*) FROM gsc_query_daily WHERE day IN ('2026-05-31','2026-06-30')
  UNION ALL SELECT 'qpd',  count(*) FROM gsc_query_page_daily WHERE day IN ('2026-05-31','2026-06-30');
  -- attendu : ~250-320 rows/jour pour path, plus pour query/qpd, AUCUN zéro
  ```
- **Estimation** : 30 min.

## T-02 · Fix durable de la fenêtre d'ingestion GSC

- **Fichiers** : `scripts/gsc_common.py:113-128` (`list_months`) et
  `.github/workflows/gsc-daily-ingest.yml` (args `--months 1`).
- **Problème** : `list_months()` fait `cursor = end.replace(day=1)` →
  `--months 1` = « depuis le 1er du mois courant », pas 30 jours. Combiné
  au lag J-2/J-3 de Google, les derniers jours de chaque mois ne sont
  jamais ré-ingérés.
- **Changement** (option simple, recommandée) : passer `--months 1` →
  `--months 2` dans le workflow (les DEUX invocations : path-query et
  query-page). Coût : le run passe de ~1 à ~2-3 min, quota GSC
  négligeable. Mettre à jour le commentaire du workflow (« fenêtre : 2
  mois calendaires — couvre le trou de fin de mois »).
  *Option propre (facultative)* : réécrire `list_months(end, n)` en
  fenêtre glissante `[end − 35 j, end]` — dans ce cas ajouter un test
  dans `tests/` qui vérifie qu'un `end_date` au 2 du mois couvre bien la
  fin du mois précédent.
- **Validation** : le run suivant (06:00 UTC) est vert ET
  `SELECT count(*) FROM gsc_path_daily WHERE day='2026-06-30'` reste > 0
  (pas d'effet destructeur), aucun jour manquant (requête de T-03).
- **Estimation** : 30 min.

## T-03 · Alerte `gsc_gap` : détecter les trous de jours (pas seulement le lag)

- **Objet SQL** : fonction `cooked_alerts_refresh()` (cron horaire
  `15 * * * *`). Récupérer le corps actuel :
  `SELECT pg_get_functiondef('cooked_alerts_refresh()'::regprocedure);`
- **Problème** : l'alerte `gsc_lag` regarde `max(day)` — aveugle à un jour
  manquant AU MILIEU de l'historique.
- **Changement** : migration `..._alerte_gsc_gap.sql` — ajouter un bloc :
  ```sql
  -- bloc gsc_gap : jours manquants sur les 90 derniers jours couverts
  with expected as (
    select generate_series(gsc_last_data_day() - 90, gsc_last_data_day(), '1 day')::date d
  ), missing as (
    select d from expected
    except select distinct day from gsc_path_daily where day >= gsc_last_data_day() - 90
  )
  -- si missing non vide → raise_cooked_alert('gsc_gap','warn',
  --   'jour(s) GSC manquant(s) : ' || string_agg(...)) — réutiliser le
  --   helper raise_cooked_alert existant et son mécanisme anti-doublon.
  ```
  Regarder comment les blocs existants dédupliquent (ne pas ré-alerter
  toutes les heures pour le même trou — même pattern que `gsc_lag`).
- **Validation** : `SELECT cooked_alerts_refresh();` à la main → 0 alerte
  `gsc_gap` après T-01 ; test négatif en simulant (dans une transaction
  ROLLBACK) la suppression d'un jour.
- **Estimation** : 1-2 h.

## T-04 · Fermer `cpi_gisement` au rôle `anon` (+ grants résiduels)

- **Problème** : la vue `public.cpi_gisement` est SECURITY DEFINER
  implicite (pas de `security_invoker=true`, contrairement aux autres
  vues) ET a un GRANT SELECT à `anon`/`authenticated` → lisible via
  PostgREST avec la seule clé publishable (embarquée dans le front
  data.rewolf.studio). Advisor Supabase security = ERROR.
- **Changement** : migration `..._cpi_gisement_security_invoker.sql` :
  ```sql
  ALTER VIEW public.cpi_gisement SET (security_invoker = true);
  REVOKE ALL ON public.cpi_gisement FROM anon, authenticated;
  -- au même endroit : nettoyer les grants résiduels détectés par l'audit
  REVOKE ALL ON public.dashboard_trend_snapshot FROM anon, authenticated;
  GRANT SELECT ON public.dashboard_trend_snapshot TO service_role;
  ```
- **Attention** : le dashboard lit en **clé service** (server-side) →
  rien ne casse. Vérifier quand même après déploiement que
  data.rewolf.studio affiche toujours ses panneaux.
- **Validation** : (a) advisor security : l'ERROR disparaît ;
  (b) `curl 'https://mxycmjkeotrycyneacje.supabase.co/rest/v1/cpi_gisement?select=path&limit=1' -H "apikey: <clé publishable>"`
  → doit renvoyer une erreur de permission (plus de 200 avec données) ;
  (c) le dashboard fonctionne.
- **Estimation** : 30 min.

## T-05 · Acker les 3 alertes `cpi_drop` (opérationnel, pas une migration)

- **Contexte** : instruites par l'audit — c'est un artefact du gel de
  `cpi_daily` (22-28/06), pas un decay SEO. Les 4 pages sont saines.
- **Action** : `UPDATE alerts SET acked = true WHERE id IN (28, 30, 31);`
  (données opérationnelles, pas de migration ; tracer dans la PR de T-06).
  Si de nouvelles `cpi_drop` identiques sont apparues depuis, les acker
  aussi (même diagnostic tant que `ecart_jours > 8`, cf. T-06).
- **NE PAS acker** l'alerte `form_attribution_degraded` (id 29) : elle
  reflète un vrai problème côté Wix (action Nicolas, §hors périmètre) —
  elle sera ackée quand les champs cachés seront posés.

## T-06 · Durcir `cpi_drop` contre les écarts de fenêtre

- **Objets SQL** : vue `cpi_movers` (elle expose déjà `ecart_jours`) et le
  bloc `cpi_drop` de `cooked_alerts_refresh()`.
- **Problème** : après un trou dans `cpi_daily`, la « dérivée ~7 j »
  compare à J-10+ et la volatilité conversion (`zv`) redevient dominante —
  exactement le faux positif que la recalibration du 17/06 devait tuer.
- **Changement** : migration `..._cpi_drop_ecart_jours_guard.sql` :
  1. Dans le bloc `cpi_drop` : ne déclencher que si `ecart_jours <= 8`.
  2. Enrichir le message : ajouter pour chaque page la part du delta due
     à `zv` (ex. `round(100*delta_zv*0.35/delta_cpi)`) pour rendre
     l'artefact visible à l'œil nu.
- **Validation** : `SELECT cooked_alerts_refresh();` → plus de nouvelle
  `cpi_drop` tant que la fenêtre 01/07 vs 21/06 persiste ; re-tester
  vers le 08/07 quand `ecart_jours` sera redescendu ≤ 7.
- **Estimation** : 1-2 h.

---

# VAGUE 2 — Avant le 08/07 : protocole de validation CPI

## T-07 · Figer la cible primaire du test J+28 ⚠️ DEADLINE 08/07 — binôme avec Nicolas/agent Cooked

- **Fichier** : `scripts/cpi_validation_j28.sql` (header = critères) +
  `docs/cpi-cooked-page-index.md` (§ Validation à J+28).
- **Problème** : la cible primaire « Spearman(CPI_t0, Δcontacts) > 0,3 »
  est un change-score (c_fut − c_pas) mécaniquement anti-corrélé au CPI :
  le terme conversion `zv` est construit sur les MÊMES contacts que
  c_pas → régression vers la moyenne. Mesuré au t0 du 10/06 :
  ρ(score, c_pas) = +0,49 mais ρ(score, Δ) = **−0,43**. Tel quel, le test
  conclura « échec » et la grille fera baisser le poids conversion pour
  une mauvaise raison.
- **Changement** (à faire valider par Nicolas AVANT d'éditer — c'est une
  décision méthodo, pas un fix mécanique) :
  1. Cible primaire → **niveau futur** : ρ(CPI_t0, contacts_{t0→t0+28}),
     normalisé par `n_org` (taux plutôt que compte brut), périmètre
     grade A/B (n=51), seuil à pré-déclarer (proposition : ρ > 0,3).
  2. Garder l'actuel Δcontacts en **descriptif annexe** (ne décide rien).
  3. Pré-déclarer les seuils de la branche « test sous-puissant »
     (86 % de ties déjà mesurés sur la cible contacts) : cibles
     secondaires Δvaleur composite et Δclics GSC avec leurs seuils, et la
     règle de verdict global — TOUT écrit dans le header avant le 08/07.
  4. §3 calibration : le critère « écart médian < 20 % » est en échec
     alors que la section est marquée PASSE → soit amender officiellement
     le critère (avec justification écrite), soit acter l'échec partiel.
     Ne pas le passer sous silence.
- **À ne PAS faire** : toucher aux poids du CPI ou à
  `cooked_page_index()` — décision produit S39 : on ne complexifie plus
  le modèle. Ce ticket ne modifie QUE le protocole de test.
- **Validation** : dry-run complet du script (sections en SELECT, sans
  erreur) ; relecture du header par Nicolas ; le gel 22-28/06 de
  `cpi_daily` n'affecte pas le test (t0 du 10/06 intact — vérifié).
- **Estimation** : 2-4 h (dont la boucle de validation).

---

# VAGUE 3 — Fiabilité (semaine 1)

## T-08 · `refresh_bot_fingerprints` : passer en incrémental

- **Objet SQL** : fonction `refresh_bot_fingerprints()` (appelée par le
  cron horaire `refresh_noise_filters_hourly`). Corps actuel :
  `pg_get_functiondef`.
- **Problème** : DELETE + re-INSERT full avec un GROUP BY sur TOUTE la
  table `events` (1,03 M lignes, ×2,6 depuis l'écriture de la fonction) à
  chaque heure → 11 timeouts en 7 jours fin juin, durée en croissance
  ~+14 %/36h. Chaque échec laisse le bruit non flaggé ≥ 1 h (cause du
  « faux pic visiteurs » du dashboard le 01/07).
- **Changement** : migration `..._bot_fingerprints_incremental.sql` :
  - conserver les fingerprints historiques (ne plus DELETE) ;
  - ne recalculer que pour les `anonymous_id` vus dans les dernières
    48 h : `WHERE e.occurred_at > now() - interval '48 hours'` sur la
    sous-requête source, puis `INSERT … ON CONFLICT DO NOTHING` ;
  - ⚠️ piège relevé en vérification : une borne du type
    `occurred_at >= now() - '90 days'` serait un no-op (l'historique fait
    < 90 j) — c'est bien la logique **incrémentale** qui protège, pas une
    grande borne.
  - même traitement pour `refresh_noise_sessions` si son plan montre le
    même full-scan (vérifier avec `EXPLAIN ANALYZE` avant/après).
- **Validation** : `EXPLAIN ANALYZE` avant/après (attendu : de plusieurs
  dizaines de s → < 5 s) ; comparer `count(*)` de `bot_fingerprints`
  avant/après sur 24 h (pas de perte de détection) ; 0 échec cron sur
  48 h (`cron.job_run_details`).
- **Estimation** : 3-5 h.

## T-09 · Endiguer le swarm de bots (en cours depuis ~20/06)

- **Contexte** : ~12 000 `anonymous_id`/jour, UA Chrome Windows desktop,
  n'émettent QUE web_vitals/engagement_tick/page_exit (jamais de
  pageview). `events` brut : 13 k/j début juin → 69 k/j au 01/07.
  `events_human` filtre correctement (chiffres métier propres) mais la
  table brute double toutes les ~2 semaines → récidive des timeouts
  garantie.
- **Changement en 2 volets** :
  1. **Purge des events de bruit anciens** — migration
     `..._purge_bruit_ancien.sql` + job cron hebdo : DELETE des events
     bruts de plus de 28 j dont la session est dans `noise_sessions` /
     l'`anonymous_id` dans `bot_fingerprints`. ⚠️ **DELETE de masse =
     validation explicite de Nicolas requise AVANT d'appliquer** (règle
     §1.7). Argumentaire : ces lignes sont déjà exclues de toute analyse,
     leur seul effet est le coût. Mesurer avant/après
     (`pg_total_relation_size('events')`) et prévoir un `VACUUM`.
  2. **Garde à l'ingestion** (Edge `track`, → version v23 avec T-13) :
     rejeter silencieusement (HTTP 204) les batches SANS `pageview` dont
     l'`anonymous_id` n'a AUCUN pageview sur les dernières 24 h (un
     `SELECT EXISTS` indexé par batch, pas par event — coût ~1 requête
     par POST). Tracer un compteur (log Edge) pour mesurer le taux de
     rejet. Ne JAMAIS appliquer cette garde aux events critiques
     (`cta_*`, `form_submit` n'arrive pas par là de toute façon).
- **Validation** : volume `events` brut/jour redescend vers ~15-20 k ;
  `events_human`/jour STABLE (~10-11 k — c'est le garde-fou : si ça
  bouge, rollback immédiat de la garde) ; contacts macro du jour
  inchangés vs veille de déploiement.
- **Estimation** : 1 j (dont mesure et rollback plan).

## T-10 · Backup hebdomadaire hors Supabase

- **Problème** : `events` (1,03 M lignes) = seule copie au monde de la
  donnée comportementale ; GSC > 16 mois non re-téléchargeable ; purge
  400 j programmée (juin 2027) sans archive. Zéro mécanisme d'export.
- **Changement** : nouveau workflow `.github/workflows/backup-weekly.yml`
  (cron dimanche 05:00 UTC) :
  ```yaml
  # étapes : psql "$SUPABASE_DB_URL" -c "\copy (select * from <table>) to stdout csv header" | gzip
  # tables : events, gsc_path_daily, gsc_query_daily, gsc_query_page_daily,
  #          cpi_daily, page_taxonomy, annotations, alerts
  # destination : bucket S3-compatible (Backblaze B2 ou Cloudflare R2) via rclone
  # secrets nouveaux : SUPABASE_DB_URL, B2_KEY_ID, B2_APP_KEY (à créer par Nicolas)
  # rétention : garder 8 hebdos + 6 mensuels (rclone delete --min-age)
  ```
  Fallback si Nicolas ne veut pas ouvrir un bucket tout de suite :
  artifact GitHub (90 j de rétention max — le documenter comme pis-aller).
  ⚠️ Ouverture d'un compte B2/R2 = décision de coût (quasi nul, ~0,01 €/Go/mois,
  mais c'est à Nicolas de créer le compte).
- **Validation** : run manuel (`workflow_dispatch`) → fichiers présents
  dans le bucket, restauration testée sur UNE table dans une base locale
  (`\copy from`), taille cohérente (~150-300 Mo gz).
- **Estimation** : 3-5 h.

## T-11 · Alertes : ajouter un canal push minimal

- **Problème** : `raise_cooked_alert` = INSERT dans une table lue
  manuellement en session. Une panne d'ingestion d'une semaine est
  invisible. En prime, GitHub désactive les workflows cron après 60 j
  sans activité repo.
- **Changement** :
  1. Dans `gsc-daily-ingest.yml`, `dfs-weekly-sync.yml` et le futur
     `backup-weekly.yml` : step finale
     ```yaml
     - name: notify-failure
       if: failure()
       run: curl -s -d "Cooked ⚠ ${{ github.workflow }} en échec — voir Actions" ntfy.sh/${{ secrets.NTFY_TOPIC }}
     ```
     (topic ntfy.sh privé — Nicolas installe l'app ntfy et s'abonne ;
     alternative mail possible mais ntfy = 5 min de setup, zéro compte).
  2. Migration `..._alertes_push_critical.sql` : dans
     `raise_cooked_alert`, si `severity = 'critical'`, POST via
     `pg_net.http_post` vers le même topic (vérifier que l'extension
     `pg_net` est activée : `SELECT * FROM pg_extension WHERE extname='pg_net';`
     — sinon l'activer via le dashboard Supabase, pas de coût).
- **Validation** : forcer un échec de workflow (step `exit 1` sur une
  branche) → notification reçue ; `SELECT raise_cooked_alert('test','critical','test push');`
  → notification reçue, puis nettoyer l'alerte de test.
- **Estimation** : 2-3 h.

## T-12 · Hygiène ingestion (3 petits fixes groupés, 1 PR)

1. **`scripts/gsc_common.py`** : `request.execute()` →
   `request.execute(num_retries=3)` (backoff intégré googleapiclient)
   sur tous les `.execute()` de `fetch_gsc`.
2. **`scripts/dfs_common.py` (`run_sync`, lignes ~276-315)** : si
   `total_failed == total_requested` (ou > 50 %) → `sys.exit(1)` pour que
   le workflow passe rouge. + migration `..._alerte_dfs_stale.sql` : bloc
   dans `cooked_alerts_refresh()` — warn si
   `max(last_synced_at) FROM dfs_keyword_volume < now() - interval '10 days'`.
3. **Détection de drift tracker** : migration
   `..._alerte_tracker_version.sql` — mini-table `cooked_config(key, value)`
   avec `expected_tracker_version = 'sprint38'` (mise à jour par la
   migration accompagnant chaque release tracker) + bloc d'alerte : si la
   version majoritaire de `props->>'_v'` des pageviews 24 h ≠ valeur
   attendue → warn `tracker_drift`.
- **Validation** : tests unitaires existants verts
  (`tests/test_dfs_common.py` — en ajouter un sur le code de sortie) ;
  `SELECT cooked_alerts_refresh();` sans nouvelle alerte intempestive.
- **Estimation** : 3-4 h.

---

# VAGUE 4 — Justesse de la mesure (semaine 2)

## T-13 · Edge `track` v23 : clamp horloge + garde swarm (+ webhook durci)

- **Fichiers** : `supabase/functions/track/index.ts` (v22) et
  `supabase/functions/form-webhook/index.ts` (v10).
- **Problèmes** :
  - `occurred_at` client accepté tel quel (`iso()` valide juste le
    parsing) : 102 events > 24 h dans le passé en juin → mauvais jour
    calendaire Paris.
  - `form-webhook` : `submissionTime` non validé du tout, et toute erreur
    d'insert non-23505 → HTTP 200 « dropped » silencieux (perte muette
    possible d'une macro-conversion).
- **Changements** :
  1. `track` : clamp — si `|occurred_at − now()| > 48 h` → remplacer par
     `now()` et poser `props.clock_clamped = true` (spec déjà écrite dans
     docs/data-quality-audit-2026-06-10.md, jamais appliquée). Idem cap
     `engagement_tick.active_ms` à 60 000.
  2. `track` : intégrer la garde swarm de T-09 (même release v23).
  3. `form-webhook` v11 : valider `submissionTime` avec le même `iso()` +
     fallback `now()` ; dans la branche « dropped » non-23505 : INSERT
     dans `alerts` (`form_submit_dropped`, severity `critical` → push via
     T-11) au lieu d'avaler dans un log.
  4. Corriger le commentaire mensonger sur `canonical_path` (le SQL ne
     décode PAS — aligner le commentaire, pas le comportement).
- **Déploiement** : `supabase functions deploy track` puis `form-webhook`
  (ou via MCP) ; bump du numéro de version dans le code ; miroir exact
  dans le repo (règle : le code déployé EST le code committé).
- **Validation** :
  ```sql
  -- clamp actif :
  SELECT count(*) FROM events
  WHERE received_at > now() - interval '24 hours'
    AND abs(extract(epoch FROM occurred_at - received_at)) > 172800;  -- attendu : 0
  -- form_submit : soumettre un form de test (Nicolas) → row présente + pas d'alerte dropped
  ```
  + `SELECT * FROM latest_rpc_health();` inchangé.
- **Estimation** : 0,5-1 j.

## T-14 · Tracker : ré-armer `page_exit` après retour d'onglet

- **Fichier** : `wix/tracker.html` — l.934 (`visibilitychange` →
  `flushExit()` si hidden) et l.410-415 (handler retour visible).
- **Problème** : `flushExit()` pose `exitSent = true` ; le retour visible
  ne le reset jamais (seuls nav SPA l.312, `pageshow` persisted l.341,
  `popstate` l.930 le font). Un visiteur qui masque l'onglet puis revient
  lire n'émettra JAMAIS de page_exit final → dwell/max_scroll figés au
  premier masquage. Mesuré : ~10-13 % des pages engagées sous-comptées.
- **Changement** :
  1. Dans le handler `visibilitychange` quand `!document.hidden` :
     ajouter `exitSent = false;` (le cumul `totAMs` continue déjà — le
     page_exit final portera la durée totale).
  2. **Corollaire SQL obligatoire (même PR)** : avec ce fix, une même
     session×path peut émettre PLUSIEURS page_exit (durées croissantes).
     Le snapshot fait déjà `max(duration)` par session×path (migration
     `20260630092247`) → OK. MAIS la RPC dashboard
     (`20260629112816_dashboard_v1_rpcs.sql:48-52`) fait
     `percentile_cont` PAR EVENT, et la rétention CPI
     (`20260616142127`) teste `duration_seconds >= 15` par event →
     migration `..._page_exit_max_par_session.sql` : dans ces deux
     lectures, agréger d'abord `max(duration_seconds)` par
     session_id×path. Sans ça, le fix tracker biaiserait dans l'autre
     sens (exit partiel + exit cumulatif comptés deux fois).
  3. Ajouter les tests jsdom manquants dans `tests/tracker.test.js` :
     hide → visible → pagehide = 2 page_exit à durées croissantes ;
     clic Cookiebot dans conteneur fixed = 0 cta_anchor_click ;
     expiration de session (fenêtre 30 min).
  4. `python3 scripts/minify-tracker.py` → **asserter < 15 000** (marge
     actuelle 952 chars — le fix fait ~20 chars). Livrer
     `wix/tracker.min.html` avec `COOKED_VERSION` bumpé (`sprint40`) et
     mettre à jour `cooked_config.expected_tracker_version` (T-12.3)
     dans la même PR.
- **Déploiement** : ⚠️ le collage dans Wix Custom Code = **Nicolas
  uniquement**. Livrer le bloc d'instructions (coller le .min, publier,
  vérifier `select props->>'_v', count(*) from events where occurred_at > now() - interval '15 minutes' group by 1`).
- **Validation post-déploiement (J+3)** : la médiane de
  `duration_seconds` des page_exit organiques doit monter légèrement ;
  le taux de session×path « activité après exit unique » (requête dans
  l'audit) doit tomber vers ~0.
- **Estimation** : 0,5-1 j.

## T-15 · `classify_channel` v2 : IA, Yahoo, t.co — une migration

- **Objet SQL** : fonction `classify_channel(text,text,text,text)`
  (IMMUTABLE, appliquée à la lecture → **tout fix est rétroactif
  gratuitement**). Contrat de sortie inchangé (mêmes libellés de canaux).
- **Trois corrections dans une migration `..._classify_channel_v2.sql`** :
  1. **IA via utm_source** (sous-comptage prouvé ~35 % du canal) : après
     le bloc paid, si `utm_source` ∈
     (`chatgpt.com`, `openai`, `perplexity`, `perplexity.ai`, `claude.ai`,
     `gemini`, `copilot`) → `organic_ai`. Ajouter aux referrers détectés :
     `grok.com`, `x.ai`, `meta.ai`, `chat.mistral.ai`, `chat.deepseek.com`.
  2. **Yahoo redirect** : la branche 1 teste le self-host en sous-chaîne
     de l'URL COMPLÈTE → `r.search.yahoo.com/...RU=https%3a%2f%2fwww.jplouton-avocat.fr...`
     matche et sort NULL. Remplacer par un test sur le hostname :
     `substring(ref from '^https?://([^/]+)') = self_host` (garder le
     comportement NULL pour le vrai self-referral).
  3. **t.co** : `'%t.co%'` matche n'importe quel hostname contenant
     « t.co » → restreindre à l'hôte exact
     (`ref ~* '^https?://t\.co/'` ou hostname = 't.co').
- **Validation** (avant/après sur 90 j) :
  ```sql
  SELECT classify_channel(e.referrer_hostname, e.utm_source, e.utm_medium,
         'www.jplouton-avocat.fr') AS canal, count(*)
  FROM events_human e
  WHERE e.name='pageview'
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= current_date - 90
  GROUP BY 1 ORDER BY 2 DESC;
  -- attendu : organic_ai ~+50 %, apparition des ex-"direct" utm chatgpt,
  -- r.search.yahoo.com → organic_other, aucun autre canal ne bouge > 1 %
  ```
  + `latest_rpc_health()` OK. Noter dans la PR : c'est un
  **restatement** — les chiffres de canaux historiques bougent, prévenir
  Nicolas avec la phrase type (« correction de mesure, pas un changement
  de trafic »).
- **Estimation** : 2-3 h.

## T-16 · Dashboard : 6 fixes (1 PR front + 1 migration)

- **Fichiers** : `dashboard/src/…` + migrations `dashboard_*`.
1. **Dernier point figé sur ¼ de journée** (CONFIRMÉ) : le refresh de
   10:15 Paris fige le jour en cours (84 vs 340 visiteurs le 01/07) →
   faux effondrement en fin de courbe + KPI 28j biaisé. Migration : dans
   les fonctions de refresh des snapshots dashboard, ancrer la fin de
   fenêtre sur **J-1 Paris** (`paris_today() - 1`) pour les séries ET les
   KPI. Adapter le libellé front (« au JJ/MM » plutôt que « auj. »).
2. **Bandeau de fraîcheur** : `FreshnessBanner.tsx:30` — seuil
   `lagDays > 2` → `> 3` (le lag GSC structurel observé est J-3 ; aligner
   sur le seuil des alertes). Extraire le seuil en constante commentée.
3. **Open redirect** : `dashboard/src/app/auth/callback/route.ts` —
   n'accepter `next` que si
   `next.startsWith('/') && !next.startsWith('//') && !next.includes('\\')` ;
   même garde dans `login/page.tsx`.
4. **TrendChart** : labels d'axe X codés en dur `−90j/−60j/−30j` → les
   dériver de `series.length`.
5. **`getResourcesTrend`** (`dashboard/src/data/trend.ts`) : ne plus
   avaler toutes les erreurs — remonter un flag d'erreur (même pattern
   que les autres data-fetchers) pour qu'une régression du RPC soit
   visible.
6. Grants `dashboard_trend_snapshot` : déjà couverts par T-04.
- **Validation** : build Vercel vert ; la courbe ne « s'effondre » plus
  le matin ; `?next=//evil.com` sur le callback → redirection interne ;
  bandeau vert avec lag 3.
- **Estimation** : 0,5-1 j.

## T-17 · `click_internal.target_path` : variantes accentuées (investigation + backfill)

- **Problème découvert par l'audit** : deux variantes coexistent —
  `/indemnisation-des-victimes/victimes-de-délits-ou-crimes` (33 clics,
  accentué) et `…victimes-de-delits-ou-crimes` (35 clics, non accentué) —
  alors que SEUL le path non accentué existe en pageview. `canonical_path`
  fait decode+NFC mais ne translittère pas é→e : le href du site contient
  la variante accentuée quelque part.
- **Étapes** :
  1. Inventorier les paires : `SELECT props->>'target_path', count(*)
     FROM events_human WHERE name='click_internal' GROUP BY 1` puis
     rapprocher par `unaccent()` des paths de pageview réels (extension
     `unaccent` à activer si absente).
  2. Backfill : migration `..._click_internal_unaccent_backfill.sql` —
     UPDATE ciblé des `target_path` accentués vers le path pageview
     correspondant UNIQUEMENT quand la correspondance `unaccent` est
     univoque. Compter avant/après dans le commentaire de migration.
  3. Ingestion : dans l'Edge v23 (T-13), appliquer le même rapprochement
     est trop coûteux — à la place, documenter le piège dans le playbook
     (« joindre click_internal.target_path aux paths via unaccent ») OU
     normaliser à la lecture dans les RPCs qui consomment target_path.
- **Estimation** : 2-3 h.

## T-18 · Lot documentation (1 PR, aucune migration)

Corrections factuelles vérifiées par l'audit — appliquer telles quelles :
1. `README.md:189` : « ~390 000+ événements bruts » → « ~1 M d'événements
   bruts (dont ~50 % de bruit bot récent, filtré par events_human) » ;
   `README.md:70` : « 15 à 20 % » → nuance sur le swarm depuis le 20/06.
2. `CLAUDE.md` : « Google Ads : MCP non connecté » → connecté (5 customer
   IDs accessibles, vérifié le 01/07/2026) ; « lag J-2 normal » →
   « J-2/J-3 normal » ; supprimer/rattacher le paragraphe orphelin
   « Sert de remplaçant GA4… » (milieu du bloc Sprint 39) ; remplacer la
   routine git « bundle » par la routine réelle (branche → PR → merge,
   le push direct fonctionne — PRs #11-#13) ; contradiction contacts :
   préciser « ~10/mois » = contacts organiques attribuables par page
   (usage zv) vs ~170 macro/28j site-wide.
3. `docs/OPERATIONS.md` : table des crons à l'état prod (8 jobs pg_cron,
   snapshot SEO timeout 600 s / rebuild ~230 s temp-table appliquée,
   `refresh-dashboard-snapshots` à 08:15 UTC) ; ajouter `dashboard/` et
   `wix/masterpage-cooked.js` au layout + procédure de redémarrage
   (déploiement Vercel, collage Velo).
4. `docs/HISTORY-sprints.md` : compléter 30/06 soir + 01/07 (refonte
   dashboard, fix faux pic, swarm de bots documenté) ; « 6 crons » → 8.
5. `docs/PLAYBOOK-analyse-seo.md` piège 7 : ratio site-wide Cooked/GSC
   réel = **1,19×** (fenêtre alignée 16-29/06) — le 2,4× ne vaut que
   page-level sur les pages à enjeu local.
6. `docs/ROADMAP-sprint38-handoff.md` : passer le fix temp-table en ✅ ;
   corriger l'item `country` : PAS « toujours NULL » — peuplée du 06/05
   au 02/06 puis plus rien (régression à dater, décision réactiver vs
   amputer à instruire).
- **Estimation** : 2-3 h.

---

# Hors périmètre développeur (à ne PAS faire)

| Qui | Quoi |
|---|---|
| **Nicolas (Wix Studio)** | Ajouter les 3 champs cachés (`page_source`, `cooked_aid`, `cooked_sid`) au formulaire embarqué sur `/indemnisation-des-victimes/droit-et-accidents-du-travail` — cause de l'alerte `form_attribution_degraded` (id 29) ; test de soumission du Formulaire Divorce ; coller le tracker minifié (T-14) ; passer `COOKED_DEBUG=false` dans masterPage. |
| **Nicolas (comptes)** | Créer le bucket B2/R2 (T-10), le topic ntfy (T-11). |
| **Décisions produit (ne pas implémenter)** | Import de conversions Google Ads (gclid/consentement), call tracking, numéro GMB, refonte loader tracker, purge massive (T-09.1 : GO explicite requis). |

# Récapitulatif

| Tâche | Priorité | Type | Taille |
|---|---|---|---|
| T-01 backfill GSC | P0 | ops | S |
| T-02 fenêtre GSC | P0 | script+workflow | S |
| T-03 alerte gsc_gap | P1 | migration | S |
| T-04 cpi_gisement security | P0 | migration | S |
| T-05 ack cpi_drop | ops | SQL opérationnel | S |
| T-06 garde ecart_jours | P1 | migration | S |
| T-07 protocole J+28 ⚠️ 08/07 | P1 | méthodo (binôme) | M |
| T-08 fingerprints incrémental | P1 | migration | M |
| T-09 endiguer le swarm | P1 | edge+migration (GO Nicolas pour purge) | L |
| T-10 backup hebdo | P1 | workflow | M |
| T-11 push alertes | P1 | workflow+migration | S |
| T-12 hygiène ingestion | P2 | scripts+migrations | M |
| T-13 Edge v23 clamp+webhook | P1 | edge deploy | M |
| T-14 page_exit ré-armé | P1 | tracker+migration (+collage Nicolas) | M |
| T-15 classify_channel v2 | P1 | migration (restatement) | S |
| T-16 dashboard ×6 | P1/P2 | front+migration | M |
| T-17 target_path unaccent | P2 | migration | S |
| T-18 lot docs | P2 | docs | S |

**Definition of done globale** : `SELECT * FROM alerts WHERE NOT acked;`
vide (hors alertes attendant une action Wix) ; `refresh_pipeline_health()`
healthy ; `latest_rpc_health()` tout OK ; advisors security sans ERROR ;
0 jour manquant dans `gsc_path_daily` ; `events` brut/jour < 20 k ;
un backup restaurable existe hors Supabase.
