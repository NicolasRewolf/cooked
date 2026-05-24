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

dashboard/ (Next.js 15, READ-ONLY)
   ↓ lib/cooked.ts → RPCs cross-source (site_kpis, pages_overview_unified,
     pulse, funnel, sparklines…)
```

Capture côté browser : pageview / scroll_depth / engagement_tick /
web_vitals / click_outbound / page_exit / cta_phone_click /
cta_booking_click / cta_anchor_click (Sprint 19). Plus `form_submit`
inséré directement par la deuxième Edge Function `form-webhook` qui
reçoit les webhooks Wix Automations (Sprint 18). Bot filtering via la
vue `events_human` (Sprint 17). Sert de remplaçant GA4 pour fournir
des données comportementales fiables à Nicolas et à Me Plouton, et
permet désormais les analyses Cooked × GSC (intent matching, funnel
SEO complet, pogo-stick × ranking).

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
  `supabase/views.sql`)
- Le pg_cron de rebuild nocturne `refresh_seo_url_snapshot()`
- Le contrat des RPCs publiées (signatures, types de retour,
  comportement)
- Le README du repo Cooked
- Les analyses, graphes, rapports produits depuis Cooked
- Les scripts d'outillage (`scripts/minify-tracker.py`,
  `scripts/gsc_ingest.py`, `scripts/gsc_common.py`,
  `scripts/deploy_track.py`, etc.)
- Le dashboard `dashboard/` (UI lecture ; schéma/RPCs restent ici)
- Le workflow GitHub Actions GSC (`.github/workflows/gsc-daily-ingest.yml`)
- L'ingestion DataForSEO (`scripts/dfs_common.py`, `dfs_sync.py`,
  table `dfs_keyword_volume`, cron `dfs-weekly-sync.yml`)
- L'auth Service Account GSC (`gsc-mcp-claude@plouton-472207...`)
  et le fichier `~/.claude/gsc-credentials.json` qui ne doit JAMAIS
  être committé

L'agent peut prendre toutes les décisions techniques sur ces objets.
Demander une validation explicite à Nicolas uniquement pour :

- Une décision business ou de produit (ex : multi-tenancy, nouveau client,
  refonte produit dashboard visible par le client final)
- Une suppression de donnée irrécupérable (DROP TABLE, DELETE de masse)
- Un changement de coût significatif (ex : passer à un plan Supabase
  payant supérieur, activer une API tierce facturée)

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
   dans `supabase/views.sql` ou `supabase/migrations/*.sql` pour
   pouvoir rejouer / auditer plus tard.

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
  ├─ canonicalPath(path) (Sprint 13 + NFC)    ├─ strip PII (Sprint 30)
  └─ INSERT events                          └─ INSERT events (name=form_submit)
       ↓                                          ↓
events table (raw)
       ↓ refresh_bot_fingerprints() — Sprint 17
       ↓ events_human view (events MINUS bots MINUS noise)
       ↓ pg_cron nightly
refresh_seo_url_snapshot()
       ↓
seo_url_snapshot (70 colonnes post-Sprint-30 : 4 fenêtres × ~11
                  metrics + CWV + provenance + device + CTAs + pogo
                  + device CTA rate. Sprint 30 a dropé 4 colonnes
                  email_clicks_* qui étaient à 0 depuis le début)
       ↓
RPCs internes + dashboard (`dashboard/lib/cooked.ts`)
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

- `cooked_period_bounds(period_kind)` — bornes Paris (today / week / month / rolling_28 / rolling_90)
- `site_kpis_compare(period_kind)` — KPIs business N vs N-1 (macro = phone + form)
- `pages_overview_unified(max_rows)` — univers pages (~490 paths), contacts macro séparés de booking_intent
- `gsc_page_performance(target_path)` — fiche page complète
- `gsc_top_queries_for_path(path, period_kind, max_rows)` — requêtes → landing (overload `days_back` conservé)
- `site_macro_counts(start, end)` — contacts macro site-wide (phone + form filtré)
- `gsc_pages_overview(max_rows)` — top pages SEO (tri clics) ; v3 contacts macro
- `gsc_top_queries_global(days_back, max_rows)` — top requêtes site
- `site_pulse` / `pages_pulse` — quadrants GSC 28v28 × Cooked 7v7 (`pulse_quadrant` helper)
- `site_seo_funnel(period_days)` — funnel impressions → contacts
- `gsc_page_daily_series` / `cooked_page_daily_series` — séries quotidiennes (sparklines)
- `dfs_keywords_to_sync(limit_n)` — liste keywords à syncer (union GSC 28j ∪ 90j)
- `gsc_x_dfs_opportunities(...)` — quick wins SEO (volume DFS + position 5–15)

**DataForSEO (agent Cooked)** : pas d'appel API live depuis Cursor (pas de MCP
DFS ici). Volumes = `dfs_keyword_volume` alimentée par `scripts/dfs_sync.py`
(env `DFS_USERNAME` / `DFS_PASSWORD` ou GitHub Actions). Sanitize keywords
avant envoi (`sanitize_for_dfs` dans `dfs_common.py`). Après changement RPC
ou script : relancer `dfs_sync.py --limit 500`.

**Contacts dashboard** : `cooked_contacts_*` = `cta_phone_click` + `form_submit` uniquement.
`cooked_booking_intent_*` = `cta_booking_click` (micro). Ne pas mélanger.
Source SQL unique : `macro_contacts_by_path(days_back)` — utilisée par
`pages_overview_unified`, `gsc_pages_overview`, `gsc_page_performance`.
Pour ajouter un signal macro futur (ex. SMS), ne modifier que cette fonction.

Pre-deployment date "tracker live" : 05/05/2026 → 06/05/2026 19:14
Paris (première ingestion réelle). Le tracker est en sprint30
depuis le 21/05/2026 21:19 Paris.

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

### Cooked ne stocke PAS la catégorie

L'info catégorie n'est PAS dans la DB Cooked (`events`,
`seo_url_snapshot`). Pour filtrer une analyse par type, il faut soit :
1. Lister manuellement les slugs de la catégorie en allant sur
   `/blog/categories/...` côté browser
2. Considérer un futur enrichissement de Cooked : table
   `post_categories(slug, category)` mise à jour par job quotidien qui
   scrape `/blog/categories/*` ou appelle Wix Blog API

**Avant de parler de "ressources" vs "affaires" dans une analyse :
toujours vérifier la liste des slugs de la catégorie.** Ne JAMAIS
présumer la catégorie d'un article à partir de son slug.
