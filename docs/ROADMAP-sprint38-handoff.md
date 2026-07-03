# Cooked — Roadmap Sprint 38+ (passation Fable 5 → Opus 4.8)

Rédigé le 09/06/2026 en fin de Sprint 37, par l'agent qui vient de passer la
journée dans la prod. Ce document est la mémoire de travail : l'état exact,
les bugs restants classés, ce que je corrigerais si je continuais, et la
méthode qui marche. **Lis CLAUDE.md avant tout** (règles absolues :
`events_human` jamais `events`, timezone Paris via `paris_date()`, dates
JJ/MM/AAAA, taxonomie macro/micro, invariants form_submit). Ce fichier-ci
est le « quoi faire » ; CLAUDE.md est le « comment se comporter ».

---

## ⭐ MISE À JOUR 18/06/2026 — Sprint 39 : passage en PROD OPÉRATIONNELLE

> Ce document reste la mémoire de travail de Fable 5 (09/06). Cette section
> en synchronise l'état au 18/06 et **réoriente la priorité** ; le détail
> historique ci-dessous est conservé tel quel.

**Désormais : l'outil est en prod opérationnelle, le focus passe au SITE
(conversion), plus à l'outil.** 3 revues d'experts du CPI ont conclu que le
modèle est suffisant ; le benchmark a montré que « réparer » la conversion en
continu est une impasse vu la rareté des contacts (~10/mois). Le levier n'est
plus mathématique — il est dans l'**action sur le gisement** (pages à fort
trafic qui ne convertissent pas).

**Items de ce ROADMAP désormais RÉSOLUS :**
- ✅ **P1 `click_internal.target_path` URL-encodé** → Edge `track` v22 décode
  `canonical_path(url_decode(...))` + backfill 143 lignes (`20260615234052`).
- ✅ **Incident 13/06 snapshot timeout** → corrigé le 14/06 (`20260614013457`,
  `statement_timeout` propre + `format()` réécrit).
- ✅ **`snapshot_pages_export` cassée** (colonnes email_clicks droppées S30)
  → réparée (`20260615220500`, renvoie `0::bigint`, contrat préservé).
- ✅ **CPI v2.2** déployé (`20260616142127`) : momentum continu + empirical
  Bayes dynamique. Validation J+28 (08/07) inchangée, harnais rebasé v2.2.
- ✅ **Alertes recalibrées** : `double_embed_suspect` (sessions réelles, seuil
  30, `20260616082041`), `cpi_drop` (vrai decay uniquement, `20260617215132`).
- ✅ **Vue `cpi_gisement`** (`20260618102429`) : pilotage conversion (potentiel
  vs conversion réalisée) — l'outil pointe désormais où agir sur le site.
- ✅ **Croisement export Wix ↔ `form_submit`** : comptage fiable, aucun raté.

## ⭐ MISE À JOUR 30/06/2026 — Dashboard V1 + fiabilité pipeline

> Synchronise l'état au 30/06 ; détail durable dans HISTORY-sprints.md.

- ✅ **Dashboard V1** (lecture seule, articles ressources) live sur
  data.rewolf.studio (Next 16 + Supabase). Auto-analyse multi-agents →
  corrigée (allowlist fail-closed, garde de fraîcheur, KPI SEO calculés SQL).
- ⚠️→✅ **L'incident snapshot-timeout a RÉCIDIVÉ** : le fix du 14/06 ne
  protégeait pas tous les crons. Le cron CPI a planté **en silence depuis le
  21/06** (`cpi_daily` gelé 8 j) — réparé le 29/06 (`SET statement_timeout`
  dans la commande cron **et** la fonction) puis rattrapé. La cause des
  deadlocks `refresh_noise_filters` / `refresh_seo_url_snapshot` (le
  `TRUNCATE` à verrou exclusif) est supprimée (`TRUNCATE`→`DELETE`). Snapshot
  SEO : stopgap 1500 s (rebuild ≈ 671 s) ; **vrai fix tracé** = matérialiser
  `events_human` en table temporaire (pattern dashboard).
- ✅ **Ménage repo** (audit multi-agents) : scaffold + doublons SQL morts
  supprimés, CI tracker câblée, doc resynchronisée (le dashboard est revenu).

**Reste ouvert mais DÉPRIORISÉ (l'outil est « assez bon ») :**
- P0 anti-forge `cta_phone_click` (égalité origin Velo + rate-limit Edge) —
  à faire si un burst suspect apparaît.
- Dette `events` bloat (~405 MB), 2 overloads ambigus, colonne `country` morte,
  `conversion_journeys` 5 sous-requêtes, API sprawl (~55 RPCs).
- Chantiers de fond §2 (loader tracker, CI, source de vérité SQL unique) —
  valables, mais hors du cap conversion immédiat.

## ⭐ MISE À JOUR 03/07/2026 — Audit Fable 5 : plan T-01→T-19 exécuté à 100 %

> Audit complet (docs/audit-fable5-2026-07-02.md) puis plan de correction
> (docs/plan-correction-audit-2026-07-02.md) livré en 48 h — 18 PRs.
> Chronologie : HISTORY-sprints. Ce qui change pour ce document :

**Résolus depuis le 30/06 :**
- ✅ Clamp horloge client (P2 §1) → Edge `track` v23 (T-13).
- ✅ `events` bloat / TTL `noise_sessions` (P1/P2 §1) → purge hebdo
  `purge_cooked_noise(28)` + TTL 90 j (T-09) ; filtres bruit incrémentaux
  48 h (T-08, 155 s → 4 s).
- ✅ Trou de monitoring (P1 §incident) → alertes `gsc_gap`, `dfs_stale`,
  `tracker_drift`, `form_submit_dropped` + push ntfy des critical (T-11/12).
- ✅ Fenêtre GSC mois-calendaire (perte fins de mois) → `--months 2` +
  backfill 31/05 & 30/06 (T-01/02/03).
- ✅ Restatement CPI grain lectures (tracker sprint40 + session×path) ;
  protocole J+28 corrigé et figé AVANT le 08/07 (cible niveau + tiers).
- ✅ Taxonomie seedée depuis le sitemap + purge poubelle + garde-fous (T-19).

**Toujours ouverts (inchangés) :** P0 anti-forge `cta_phone_click`
(dépriorisé assumé) ; loader tracker (§2.1) ; 2 overloads ambigus ;
`gsc_path_metrics_28d` ; catégorie Wix sans refresh auto ; colonne
`country` — précision : PAS « toujours NULL », capture MORTE depuis le
02/06/2026 (régression à dater/décider) ; INP gate (instruit GO-si-relatif,
jamais implémenté) ; issue GitHub #19 (biais de taille CPI, clics_fut −0,40).

**Décision actée :** pas de backup externe (Nicolas, 02/07 — re-poser
UNIQUEMENT à l'approche de la purge 400 j, ~juin 2027).

**Nouveau cap : agir sur le site.** Voir la vue `cpi_gisement` et le PLAYBOOK
(§4) — les pages indemnisation à fort trafic / 0 contact sont les premières
cibles (ponts vers le contact dans le corps des articles).

---

## 0. État exact au moment de la passation (09/06/2026 ~20h Paris)

### Fait, déployé, vérifié en prod
- **4 migrations appliquées** (et reflétées dans `supabase/migrations/`) :
  `20260609180000_sprint37_cleanup_vestiges` (drop events_stitched,
  session_canonical_id, sessions_corrected_daily + search_path pinné sur
  paris_date/paris_today → **0 WARN advisors**),
  `20260609181000_sprint37_page_taxonomy` (cooked_page_type() + table
  page_taxonomy, 274 pages thématisées par heuristique slug),
  `20260609182000_sprint37_conversion_attribution`
  (form_submits_attributed / conversion_journeys / content_performance —
  **75 % d'attribution en temporal**, vérifié : 47/63 sur 28j),
  `20260609183000_sprint37_dedup_double_embed` (events_human dédup les
  clics même-seconde ; **cta_phone_click 110→95 sur 28j**, surcoût ~36 ms).
- **form-webhook v10 déployé, ACTIVE** : lit `field:cooked_aid` /
  `field:cooked_sid` (validation 8-128 alphanum identique à l'Edge track),
  stocke dans `props` uniquement. Testé : boot OK, 401 sans token.
- **Tracker sprint37 écrit et testé** (`wix/tracker.html`, minifié
  `wix/tracker.min.html` = 14 488/15 000) : execution guard
  `window.__cookedLoaded`, batching `{events:[…]}` (flush 30 s / 10 events /
  pagehide ; critiques immédiats), seeding champs cachés, fix double-tick.
  Suite jsdom passée sur source ET minifié (−57 % POST pire cas mesuré).

### PAS fait — à faire en PREMIER
1. **PUSH GITHUB**. Le commit `57c6757` est local dans `/home/claude/cooked`
   (container éphémère !). `git push` échouera sans credentials ; le MCP
   `github:push_files` timeoutait en début de session — réessayer, sinon
   livrer le bundle/diff à Nico. **Si ce push n'est pas fait, tout le
   travail repo du Sprint 37 est perdu** (la prod, elle, est à jour).
2. **Actions Wix de Nico** (lui seul peut) — répéter ce bloc tel quel :
   - Coller `wix/tracker.min.html` (COOKED_VERSION='sprint37') dans
     Wix Admin → Settings → Custom Code, **et SUPPRIMER le snippet en
     double** (cause confirmée des +13,6 % phone). Publish.
   - Ajouter 2 champs cachés `cooked_aid` et `cooked_sid` dans **chaque**
     Wix Form (même mécanique que le champ caché `page_source` existant).
   - Optionnel : durcir `wix/http-functions.js` (origin `startsWith` →
     égalité stricte).

   > **Résolu le 11/06/2026** (avec un détour) : tracker sprint37 déployé
   > dans la nuit du 10/06 ; MAIS le seeding DOM était mort-né — Wix
   > Forms V2 ne rend pas les champs cachés dans le DOM de la page
   > publiée (payloads webhook sans `field:cooked_aid` malgré les champs
   > présents dans l'éditeur). Fix sprint38 le 11/06 : ids exposés en
   > query params par le tracker (`replaceState`) + `wix/masterpage-cooked.js`
   > (Velo `setFieldValues`, rail du `page_source` de faq-system.js).
   > Première attribution `hidden_field` vérifiée à 08:53. Il reste :
   > champs cachés à ajouter au « Formulaire Divorce » (seul « Prise de
   > contact site-web » les a) ; l'option origin stricte Velo reste ouverte.
3. **Contrôles post-déploiement** (dès que Nico a publié) :
   ```sql
   -- le sprint37 doit apparaître, le sprint36 s'éteindre :
   select props->>'_v', count(*) from public.events
   where occurred_at > now() - interval '15 minutes' group by 1;
   -- le double embed doit avoir disparu (côté shell) :
   -- curl -s https://www.jplouton-avocat.fr/ -A "Mozilla/5.0" | grep -c _ckd_aid  → 1
   -- volume de POST : comparer events/heure vs J-7 même heure
   -- premier form_submit post-champs-cachés :
   select occurred_at, props->>'cooked_aid' from public.events
   where name='form_submit' order by occurred_at desc limit 5;
   -- attribution_method='hidden_field' doit apparaître :
   select attribution_method, count(*) from public.form_submits_attributed(7) group by 1;
   -- pageviews ne doivent PAS chuter (le garde ne doit tuer que les doublons)
   ```
4. **Restatement à communiquer** : la dédup rétroactive fait passer les
   contacts téléphone de 110 → 95 sur 28j. Si Me Plouton compare avec un
   chiffre antérieur, il verra une « baisse » : c'est une **correction**,
   pas une baisse. Préparer une phrase claire pour Nico.
5. ~~Étendre les contract tests aux RPCs S37~~ **FAIT (Sprint 37b)** :
   `cooked_alerts_refresh()` les teste toutes les heures (+ insert rpc_health).

---

## 1. Bugs et problèmes identifiés, NON corrigés (par priorité)

### P0 — fiabilité de la mesure
- **Forge possible de `cta_phone_click`** : l'Edge `track` accepte tout
  payload bien formé ; le proxy Velo vérifie l'origin en `startsWith`
  (contournable par `https://www.jplouton-avocat.fr.evil.com`). Un curl
  peut gonfler les contacts. Piste lean : égalité stricte d'origin dans
  Velo (action Nico) + rate-limit Edge par anonymous_id (ex. max 3
  cta_phone_click/min/aid, silently dropped au-delà) + monitoring de
  bursts (cf. §2 monitoring). Pas de HMAC : sur-ingénierie pour ce site.
- ~~Identité instable en Safari privé~~ **FAIT (Sprint 37b)** : fallback
  sessionStorage dans getAnonymousId (testé localStorage bloqué). Constaté
  en prod (2 anonymous_id différents dans la même session, 09/06 16:58).
  Le fallback aid est un id par-instance en closure. Amélioration simple :
  fallback aid en **sessionStorage** (comme le sid) → stable dans l'onglet,
  l'attribution intra-session redevient correcte. ~3 lignes dans
  `getAnonymousId()`. Attention budget 15k (marge actuelle : 512 chars).

### Incident 13/06/2026 — rebuild snapshot en timeout (corrigé en tampon, fond P1)
- **Symptôme** : cron `refresh_seo_url_snapshot` (03:00 UTC) a échoué le 13/06
  sur `statement timeout` ; snapshot figé à J-2. La requête 365j (4× seo_pages_overview
  + pogo + CWV) met ~120 s et a franchi le timeout cron en grossissant avec `events`.
- **Aggravant** : `refresh_pipeline_health()` plantait sur `format('%.1f')`
  (Postgres ne supporte que %s/%I/%L) → l'auto-diagnostic était AVEUGLE à l'incident.
- **Corrigé** (migration `20260614013457`) : `statement_timeout=600000` propre à
  la fonction de rebuild + format() réécrit en `round()||`. Snapshot restauré à la
  main (job pg_cron one-shot, car la connexion MCP coupe à 60 s et rollback).
- **RESTE (P1)** : (a) le rebuild est lent par design — optimiser (matérialiser
  seo_pages_overview ? réduire la fenêtre 365j ? incrémental ?) avant que 600 s ne
  suffise plus ; lié à la dette `events` bloat ci-dessous. (b) **Trou de monitoring** :
  `cooked_alerts_refresh()` n'a PAS levé d'alerte sur snapshot stale / cron failed
  (seules form_attribution + gsc_lag remontent). Ajouter un check pipeline_health
  dans le refresh d'alertes horaire — sinon un prochain échec sera de nouveau muet
  jusqu'au réflexe de démarrage manuel.

### P1 — dette qui mord
- **`click_internal.target_path` URL-encodé (constat 11/06/2026)** : 101/391
  clics sur 28j ont un target_path type `/indemnisation-des-victimes/
  victimes-de-d%c3%a9lits-ou-crimes` — non joignable avec `events.path`
  (canonicalisé NFC, lui). L'Edge `track` applique `canonicalPath()` à
  `path` mais pas à `props.target_path`. Fix : canonicaliser target_path
  dans l'Edge (events futurs) + migration rétroactive (la fonction
  `url_decode` existe déjà, migration `20260507132254`). Toute analyse de
  nav interne d'ici là doit décoder à la lecture.
- **`events` = 405 MB pour 392k rows (~1 Ko/row)** : bloat + props lourds.
  `payload_meta` est dupliqué dans chaque form_submit ; les index pèsent.
  Audit : `pgstattuple`, politique `purge_old_events` (vérifier la
  rétention effective vs CNIL 13 mois pour l'audience exemptée), envisager
  de vider `props->'payload_meta'` au-delà de 90 j (update ciblé +
  vacuum). Mesurer avant/après.
- **2 overloads ambigus** : `gsc_top_queries_for_path(period_kind)` vs
  `(days_back)` et `macro_contacts_by_path(start,end)` vs `(days_back)`.
  Choisir la forme `period_kind` (couture `cooked_period_bounds` du S33),
  déprécier l'autre via migration, mettre à jour CLAUDE.md.
- **`gsc_path_metrics_28d`** : 0 dépendant en prod. Si les workflows
  Claude Code ne l'appellent pas (grep l'historique des sessions), la
  dropper proprement (migration) — c'est le dernier candidat vestige.
- **21 pages `autre`** dans la taxonomie : `/affaires`, `/equipe`,
  `/contactez-nous`, vieux paths FAQ… Vérifier lesquels sont des 404/
  redirects à déclarer dans Wix vs des pages réelles à classifier.
- **Colonne `country` morte** dans ~30 RPCs (toujours NULL). Deux options :
  (a) la peupler — l'Edge peut lire un header geo niveau pays
  (RGPD-compatible en granularité pays), (b) l'amputer partout (grosse
  migration mécanique). Décider, ne pas laisser pourrir.
- **`conversion_journeys` : 5 sous-requêtes corrélées par contact**
  (first_ref, utm_source, utm_medium, device, journey). OK à ~100
  contacts/28j, mais réécrire en un seul `LEFT JOIN LATERAL (… ORDER BY
  occurred_at LIMIT 1)` quand tu y retouches. Idem : le stitching temporel
  joint sur l'égalité de `path` brute — utiliser `canonical_path()`
  (existe déjà) pour absorber trailing slash/query.

### Livré pendant le Sprint 38 (10/06)
- **CPI v2.1** : RPC `cooked_page_index(days)` + table `cpi_daily` + snapshot
  quotidien (cron 07:30 UTC). Spec et grille de lecture :
  docs/cpi-cooked-page-index.md. Reste P1 : protocole de validation à J+28.
- **CPI reprise (après-midi du 10/06)** :
  (1) vue `cpi_movers` (dérivée ~7 j, statuts present/nouveau/disparu,
  delta_z par composante) + alerte `cpi_drop` dans `cooked_alerts_refresh()`
  — migration `20260610142622_sprint38_cpi_movers`, premier rendu ~17/06 ;
  (2) harnais de validation J+28 committé (`scripts/cpi_validation_j28.sql`,
  à lancer dès le 08/07/2026) — dry-run : recomposition exacte 194/194,
  stabilité des poids PASSE (τ-b ≥ 0,952), calibration CTR R²=0,915 stable
  mais courbure non captée (obs +44/+67 % en pos 3-4, −28/−42 % en pos 9-13)
  → candidat v2.2 fit 2 segments. Le §3 du harnais EST le check mensuel de
  la courbe (backlog #3 : le fit est inline 90 j glissants dans la RPC,
  donc déjà auto-refitté — c'est la calibration qu'il faut surveiller) ;
  (3) idées v2.2 instruites (doc CPI §v2.2) : thèmes NO-GO (1-5 contacts/
  trimestre/thème), INP GO-si-relatif-au-site (médiane p75 221 ms, un gate
  absolu mordrait 57 % des pages), cannibales DÉFER (8 paires dont 2 réelles,
  rival commun marginal — mais SARVI pos 10,4 / 5,2k imps = quick win).

### P2 — améliorations opportunistes
- **Clamp horloge client à l'ingestion** (audit 10/06 : 0,28 % d'events avec
  occurred_at client déréglé, dont 15/90j à > 24 h → mauvais jour Paris).
  Spec : dans l'Edge `track`, si |occurred_at − now()| > 48 h → remplacer
  par now() et tracer `props.clock_clamped=true`. Idem cap
  `engagement_tick.active_ms` à 60 000 (9 cas/90j). Voir
  docs/data-quality-audit-2026-06-10.md.
- Jour GSC 31/05/2026 absent : trou côté API Google (re-fetché ~10× par le
  daily --months 1). Documenté, aucune action — ne pas le « réparer ».
- ~~Catégorie Wix ressource/classique~~ **FAIT (11/06/2026)** via l'API
  Wix Blog (MCP Wix, pas de browser nécessaire) : 56 `ressource` /
  328 `classique` dans `page_taxonomy`, migration
  `20260611202556_page_taxonomy_wix_blog_categories`. Reste : pas de
  refresh auto — rejouer la synchro quand de nouveaux articles sortent
  (~4/mois), ou l'automatiser (job hebdo qui appelle l'API Wix).
- **Thèmes heuristiques à valider** : trier `page_taxonomy` par trafic
  desc, vérifier manuellement le top 50, corriger en `source='manual'`
  (l'upsert heuristique ne touche jamais manual).
- **`noise_sessions` 13k rows** sans TTL : purger > 90 j dans
  `refresh_noise_sessions`.
- **`seo_url_snapshot`** : ajouter colonnes `page_type`/`theme` au
  snapshot (refresh nocturne) pour éviter les joins à la lecture.
- **Cadence `engagement_tick` adaptative** (10 s les 2 premières minutes,
  30 s ensuite) : −40 % d'events de plus. Change la granularité de la
  donnée → documenter dans CLAUDE.md si tu le fais, et adapter les
  requêtes qui supposent 10 s.

---

## 2. Ce que je referais mieux — avis intime de l'agent sortant

C'est la partie « ressenti » demandée par Nico. Sans langue de bois.

1. **Le tracker monolithe est au bout de sa vie.** 1 000 lignes d'IIFE
   ES5, et le Sprint 37 m'a forcé à des renommages cryptiques (`fillCkd`,
   `normPC`, `flushQ`…) pour tenir sous 15 000 chars minifiés. C'est le
   signe qu'on optimise pour la mauvaise contrainte. La vraie solution :
   **un loader de ~200 chars dans Custom Code** qui charge le tracker
   depuis un fichier statique versionné (`?v=sprint38`) — hébergé en
   first-party (fichier public Wix ou le domaine lui-même, pas un CDN
   tiers, pour rester cohérent avec le positionnement RGPD). On récupère :
   code lisible, vrais noms, tests, sourcemaps, plus de limite de taille,
   et le double-embed devient inoffensif par construction. Trade-off
   honnête : une requête de plus au chargement, et le risque cache-busting
   à gérer. **À trancher avec Nico, mais j'y serais allé au Sprint 38.**
2. **Il n'y a pas de CI, et ça s'est vu.** Le double-embed a vécu en prod
   des semaines ; `views.sql` mentait (4 vues fantômes) ; le webhook
   déployé (v9) avait dérivé du repo. Une GitHub Action de 30 lignes
   suffit : (a) minifie et asserte < 15 000, (b) rejoue la suite jsdom —
   **j'ai écrit les harnais dans la session du 09/06, ils sont dans le
   transcript : les committer dans `tests/tracker.test.js` est un
   quick-win**, (c) `tsc --noEmit` sur les Edge Functions, (d) lint SQL
   des migrations. Une heure de travail, des sprints de sérénité.
3. **Deux sources de vérité SQL, c'est une de trop.** Le drift
   migrations/views.sql est structurel : tout le monde oublie de
   synchroniser. Recommandation ferme : **les migrations deviennent la
   seule vérité**, et `views.sql` est remplacé par un snapshot généré
   (dump schema-only automatisé, nightly ou en CI) qui sert de
   documentation en lecture seule. Plus jamais d'édition manuelle d'un
   fichier « état du monde ».
4. **53 fonctions RPC, c'est un API sprawl.** Chaque sprint a ajouté ses
   RPCs sans déprécier les anciennes. Faire un inventaire d'usage réel
   (les sessions Claude Code sont le seul consommateur : grep), tagger
   chaque RPC `-- @deprecated` ou la consolider sur la couture
   `period_kind`. Cible : ~30 fonctions cohérentes. La qualité d'un
   système de question/réponse dépend de la lisibilité de son API.
5. ~~Le monitoring est passif~~ **FAIT (Sprint 37b)** : table `alerts` +
   `cooked_alerts_refresh()` cron horaire (pipeline mort, récidive
   double-embed, RPCs S37, attribution dégradée, retard GSC). Première
   requête de session : `select * from alerts where not acked`. Détail
   d'origine : `rpc_health` et
   `tracker_version_distribution` existent mais personne ne les regarde
   entre les sessions. Ajouter un job pg_cron `cooked_alerts` qui écrit
   dans une table `alerts` quand : sprint attendu absent des events
   récents, ratio POST/session anormal, burst de clics même-seconde
   (récidive double-embed !), form_submit sans `cooked_aid` > 30 % après
   J+7, GSC en retard > 3 j. Première requête de chaque session :
   `select * from alerts where not acked`. L'agent suivant démarre
   informé au lieu de re-auditer.
6. **Mesurer d'abord, toujours.** Tout ce que le Sprint 37 a trouvé
   (double-embed, +13,6 % phone, 78 % de réseau en ticks, Safari privé)
   est sorti de requêtes de contrôle sur la prod, pas de la lecture du
   code. C'est la leçon de méthode : **chaque hypothèse se vérifie par un
   SELECT avant d'écrire le fix, et chaque fix se mesure après.** Le
   trafic est permanent sur le site : la prod est ton banc de test en
   lecture, traite-la comme tel (et uniquement en lecture hors migrations
   nommées).
7. **La boucle produit n'est pas fermée.** L'outil sait maintenant dire
   « qui contacte, par où, après quel parcours » (conversion_journeys) et
   « quel contenu performe » (content_performance). Il manque la jointure
   finale avec GSC : **`seo_to_contact_funnel(period)`** — requête Google
   → landing → parcours → contact, la seule vue qui répond à « quoi
   écrire ensuite ». Les briques existent toutes
   (gsc_query_page_daily × conversion_journeys sur entry_path). **FAIT
   (Sprint 37b)** : `seo_to_contact_funnel(days)` — premiers enseignements
   28j : home 6,1 % (branded), expertise famille 13,3 %, post DDSE 328
   entrées / 0,3 % (intent informationnel).
8. **Un digest hebdo auto** (pg_cron → table `weekly_digest` : contacts
   par canal, top pages en hausse/baisse via pages_pulse, thèmes qui
   convertissent, alertes) que Nico lit le lundi via Claude en une
   question. Lean : pas d'email, pas d'UI, juste une table propre.

---

## 3. Méthode de travail imposée (héritée des Sprints 12-37, elle marche)

1. Lire CLAUDE.md, puis `select * from latest_rpc_health()` et la
   distribution de versions tracker avant toute chose.
2. **Un fix = une migration nommée** (`sprint38_<sujet>`), appliquée via
   MCP, **miroir immédiat dans le repo**, advisors vérifiés après.
3. EXPLAIN ANALYZE sur toute vue/RPC modifiée ; comparer au baseline
   (events_human 7j ≈ 830 ms au 09/06).
4. Tracker : modifier `wix/tracker.html` (source commenté), minifier
   (`scripts/minify-tracker.py`), **asserter < 15 000**, rejouer la suite
   jsdom sur source ET minifié. Jamais éditer le .min directement.
5. **Ne JAMAIS toucher aux colonnes identité des form_submit**
   (`webhook-…`) : invariants Sprints 24/29. L'attribution vit en lecture
   dans `props` + RPCs.
6. Demander à Nico **uniquement** pour les actions Wix (Custom Code,
   forms, Velo, Automations) — tout le reste en autonomie, en consolidant
   les actions Wix en UN bloc en fin de réponse.
7. Pièges connus : MCP GitHub instable (fallback git local + instructions),
   `web_fetch` bloqué sur raw.githubusercontent (utiliser git/curl), pages
   Wix rendues client-side (le HTML serveur ne contient pas les liens),
   jsmin conserve les commentaires `/*!`.

## 4. Ordre de reprise conseillé

1. Push GitHub du commit `57c6757` (+ ce fichier).
2. Bloc Wix de Nico → contrôles post-déploiement du §0.3 → restatement 95/110.
3. Contract tests étendus aux RPCs S37 + alerting pg_cron (§2.5).
4. P0 : anti-forge phone + aid sessionStorage.
5. `seo_to_contact_funnel` (§2.7) — la RPC qui ferme la boucle.
6. P1 dans l'ordre, puis chantiers §2.1/2.3 si Nico valide.

Bonne route. La prod est saine, les fondations sont propres, et tout ce qui
reste est écrit ici. — Fable 5, 09/06/2026
