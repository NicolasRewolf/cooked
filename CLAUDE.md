# CLAUDE.md — instructions pour les sessions Claude Code travaillant sur ce repo

> Ce fichier est lu automatiquement au démarrage de chaque session
> Claude Code dans ce repo. Il définit le périmètre d'autonomie de
> l'agent et le protocole de coordination avec les agents jumeaux.

---

## Identité du projet

`cooked` est un **système de tracking d'événements first-party**
(cookieless, RGPD-exempt, non échantillonné) pour le site
`jplouton-avocat.fr` (Wix Studio). Stack :

```
tracker.html (Wix Custom Code)
   ↓
Velo HTTP proxy (/_functions/track) — same-origin
   ↓
Supabase Edge Function `track` (Deno)
   ↓
events table (Supabase Postgres)
   ↓
seo_url_snapshot (rebuilt nightly via pg_cron)
   ↓
RPCs publiées vers le projet Seo
```

Capture pageview / scroll_depth / engagement_tick / web_vitals /
click_outbound / page_exit / cta_phone_click / cta_booking_click /
cta_anchor_click (Sprint 19). Plus `form_submit` inséré directement
par la deuxième Edge Function `form-webhook` qui reçoit les webhooks
Wix Automations (Sprint 18). Bot filtering via la vue `events_human`
(Sprint 17). Sert de remplaçant GA4 pour fournir des données
comportementales fiables au pipeline SEO.

---

## Périmètre d'autonomie de cet agent

L'agent `cooked` est **propriétaire** de :

- Le tracker `wix/tracker.html` déployé en Custom Code
- Le proxy Velo `wix/http-functions.js`
- L'Edge Function `supabase/functions/track/index.ts` (Deno, tracker ingest)
- L'Edge Function `supabase/functions/form-webhook/index.ts` (Deno, Wix Automations webhook pour `form_submit`)
- Le schéma Cooked (`mxycmjkeotrycyneacje`) :
  `events`, `seo_url_snapshot`, vues, RPCs publiées
- Les migrations Supabase (`supabase/migrations/*.sql`,
  `supabase/views.sql`)
- Le pg_cron de rebuild nocturne `refresh_seo_url_snapshot()`
- Le contrat des RPCs publiées (signatures, types de retour,
  comportement)
- Le README du repo Cooked

L'agent `cooked` **N'EST PAS propriétaire** de :

- Le projet Supabase Seo (`lzdnljppbenqoflyxbhi`)
- Le repo seo (https://github.com/NicolasRewolf/seo)
- Les wrappers TypeScript de Seo qui consomment les RPCs Cooked
  (`src/lib/cooked.ts` côté Seo)
- Les prompts diagnostic / fix-generation côté Seo
- Le pipeline Seo, les workflows GitHub Actions Seo, l'issue template
- Les findings / proposed_fixes / audit_findings côté Seo

---

## Coordination avec l'agent Seo

Le projet jumeau **Seo** (https://github.com/NicolasRewolf/seo) est
le consommateur principal des données Cooked. Il est maintenu par
une **session Claude Code séparée**.

**Les deux agents ne peuvent pas se parler directement.** Nicolas est
le relais humain entre les sessions.

### 🟢 Tu peux faire SANS coordination

- Modifier le tracker `tracker.html` tant que tu ne casses pas le
  schéma d'event (ajout d'un champ optionnel = OK, rename d'un
  champ existant = NON sans escalade)
- Modifier l'Edge Function tant que tu ne casses pas le contrat
  d'event ni le schéma de la table `events`
- Modifier le Velo proxy
- Ajouter de nouvelles RPCs (sans toucher aux existantes)
- Faire évoluer `seo_url_snapshot` en mode additif (nouvelles
  colonnes, nouvelles fenêtres temporelles)
- Backfill / UPDATE / DELETE sur la DB Cooked dont tu es proprio
- Tuner le pg_cron, la fréquence du refresh
- Ajouter de nouveaux types d'events (`form_view`, `scroll_milestone`,
  …) côté tracker + Edge Function + table — à condition de prévenir
  Seo qu'ils existent et sont consommables
- Pousser des PRs sur ce repo
- Déployer Edge Function via Supabase MCP

### 🟡 Tu peux PRÉPARER, pas EXÉCUTER — escalader d'abord

- **Casser/changer le contrat d'une RPC publiée** (rename, type
  change, comportement) → écris la migration proposée, l'impact
  côté Seo, demande à Nicolas de me consulter
- **Supprimer une RPC publiée** → idem, l'agent Seo peut encore la
  consommer
- **Changer la sémantique d'un event existant** (ex: `engagement`
  passe de "cumul de dwell" à "snapshot instantané") → l'agent Seo
  a peut-être déjà une analyse qui en dépend
- **Réduire la rétention** des events ou de `seo_url_snapshot` →
  l'agent Seo audit sur 28d/90d, doit savoir
- **Renommer une table publique** consommée par Seo

### 🔴 STOP — interdit sans go explicite

Avant de toucher à L'UNE des choses suivantes, écris explicitement
**"@nicolas peux-tu demander à l'agent Seo si OK pour …"** et
attends le retour :

- Toute modification du repo `seo` (`src/lib/cooked.ts`, prompts,
  pipeline, schémas TS)
- Toute modification du projet Supabase Seo (`lzdnljppbenqoflyxbhi`)
- Tout commit ou push sur le repo `seo`
- Toute action qui déclenche des workflows GitHub Actions côté Seo
- Toute modification de la DB Seo (`audit_findings`,
  `behavior_page_snapshots`, `gsc_*_snapshots`, `internal_link_graph`,
  …)
- Toute création / fermeture / commentaire d'issue GitHub sur le
  projet jplouton-avocat suivi par Seo

### Format de demande d'escalade

Quand tu veux escalader (zone 🟡 ou 🔴), écris à Nicolas, dans le chat
de la session, en bloc isolé :

```
@nicolas — je veux [faire X] côté Seo / au contrat RPC.

Raison : [pourquoi maintenant, pourquoi indispensable]
Impact attendu : [breaking change, additif, taille de la migration]
Alternative locale : [si je peux faire un workaround sans casser le
contrat publié, ex: nouvelle RPC v2 plutôt que modif de la v1]

Peux-tu demander à l'agent Seo :
- si OK sur le principe ?
- si une RPC v2 + dépréciation lente lui va, plutôt qu'un breaking
  change immédiat ?
- s'il a besoin d'une fenêtre de migration ?
```

Nicolas relaie, l'agent Seo répond, Nicolas re-relaie. Round-trip
typique : 5-15 min selon le niveau de réflexion technique nécessaire.

**Ne préempte pas** : ne commence pas à coder le côté Seo en
local "au cas où" — tu vas créer du code mort ou pire, des conflits
au moment où l'agent Seo aura sa propre approche.

---

## Méthodologie qui marche (Sprints 12-13 retex)

À garder comme grille de qualité pour les sprints futurs :

1. **Critères de validation explicites avant exécution** — quand tu
   demandes à Nicolas / à l'agent Seo de valider quelque chose,
   liste 3-5 critères concrets, vérifiables. Pas de "ça devrait
   marcher", on doit savoir que ça marche.

2. **Avant de valider, regarde concrètement le résultat** — ne signe
   pas "RAS" sans avoir lu le payload event, le retour de la RPC, le
   contenu de `seo_url_snapshot`. Les bugs subtils (URL-encoding du
   Sprint 13, 5% capture rate du Sprint 12) se cachent dans ce qu'on
   n'a pas regardé.

3. **Le math nudge** — quand un verdict semble damning (capture rate
   5%, scroll 0%, etc.), refais les comptes avec les fenêtres
   temporelles avant de conclure à un bug. La plupart des "bugs" de
   bootstrap sont des artefacts d'amorçage (Cooked-36h vs GSC-28d).

4. **Mode itératif strict avant scale** — quand un changement touche
   au tracker ou à l'Edge Function, valide sur **1 type d'event** ou
   **1 page** avant d'élargir. C'est le pattern qui a évité de
   poursuivre la backfill URL-decode globale avec un bug subtil.

5. **Un fix = une migration nommée** — pas de UPDATE manuel non
   tracé sur la DB. Tout fix Cooked (URL-decode du Sprint 13, ajout
   de RPC du Sprint 12, etc.) passe par une migration commitée dans
   `supabase/views.sql` ou `supabase/migrations/*.sql` pour pouvoir
   rejouer / auditer plus tard.

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
  ├─ decodeURIComponent(path) (Sprint 13)   └─ INSERT events (name=form_submit)
  └─ INSERT events
       ↓
events table (raw)
       ↓ refresh_bot_fingerprints() — Sprint 17
       ↓ events_human view (events MINUS bots)
       ↓ pg_cron nightly
refresh_seo_url_snapshot()
       ↓
seo_url_snapshot (66 colonnes : 4 fenêtres × 11 metrics + CWV +
                  provenance + device + conversion CTAs)
       ↓ RPCs cross-project (service_role secret_key)
Seo project (lzdnljppbenqoflyxbhi)
       ↓ src/lib/cooked.ts
       ↓ pipeline diagnose v6
       ↓ issue GitHub
```

RPCs publiées (contrat stable consommé par Seo) :
- `snapshot_pages_export()` — top pages avec metrics 28d/90d
- `site_context_export()` — site-wide aggregates
- `outbound_destinations_for_path(path, days)` — top destinations
  outbound par page
- `cta_breakdown_for_path(path, days)` — répartition CTAs
  phone/booking par placement
- `tracker_first_seen_global()` — première date de capture (Sprint
  13bis), pour le pro-rating capture rate côté Seo
- `behavior_pages_for_period(from, to)` — toutes les pages avec
  metrics + CWV pour une période donnée

Pre-deployment date "tracker live" : 2026-05-05.
First end-to-end issue diagnostiquée : 2026-05-07
(`que-se-passe-t-il-après-une-garde-à-vue` #30 côté Seo).

---

## Taxonomy du site jplouton-avocat.fr

Le site a **4 grands types de pages** qu'il est essentiel de distinguer
dans toute analyse. Sans cette distinction, les conclusions sont
trompeuses (cf. erreur du 11 mai 2026 où l'agent Cooked avait listé des
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
- ~49 articles au 2026-05-11.
- **Pattern critique confirmé** : **plus gros volume de trafic du site**
  - Top article `/post/durée-de-la-garde-à-vue-24h-48h-96h` : 219 sess/28j
  - Top 5 cumule 488 sessions (42% de la catégorie)
  - Total catégorie : ~1 156 sessions cumulées, dont 64% Google organique
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
  /honoraires-rendez-vous (au 2026-05-11, sur 5j, 3 conversions article→
  honoraires venaient TOUTES de posts classiques, pas de ressources).

### Cooked ne stocke PAS la catégorie

L'info catégorie n'est PAS dans la DB Cooked (`events`,
`seo_url_snapshot`). Pour filtrer une analyse par type, il faut soit :
1. Lister manuellement les slugs de la catégorie en allant sur
   `/blog/categories/...` côté browser
2. Demander à l'agent Seo (qui a un wrapper Wix Blog API) de fournir
   la liste
3. Considérer un futur enrichissement de Cooked : table
   `post_categories(slug, category)` mise à jour par job quotidien qui
   scrape `/blog/categories/*` ou appelle Wix Blog API

**Avant de parler de "ressources" vs "affaires" dans une analyse :
toujours vérifier la liste des slugs de la catégorie.** Ne JAMAIS
présumer la catégorie d'un article à partir de son slug.
