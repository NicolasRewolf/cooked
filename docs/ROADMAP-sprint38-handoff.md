# Cooked — Roadmap Sprint 38+ (passation Fable 5 → Opus 4.8)

Rédigé le 09/06/2026 en fin de Sprint 37, par l'agent qui vient de passer la
journée dans la prod. Ce document est la mémoire de travail : l'état exact,
les bugs restants classés, ce que je corrigerais si je continuais, et la
méthode qui marche. **Lis CLAUDE.md avant tout** (règles absolues :
`events_human` jamais `events`, timezone Paris via `paris_date()`, dates
JJ/MM/AAAA, taxonomie macro/micro, invariants form_submit). Ce fichier-ci
est le « quoi faire » ; CLAUDE.md est le « comment se comporter ».

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

### P1 — dette qui mord
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

### P2 — améliorations opportunistes
- **Clamp horloge client à l'ingestion** (audit 10/06 : 0,28 % d'events avec
  occurred_at client déréglé, dont 15/90j à > 24 h → mauvais jour Paris).
  Spec : dans l'Edge `track`, si |occurred_at − now()| > 48 h → remplacer
  par now() et tracer `props.clock_clamped=true`. Idem cap
  `engagement_tick.active_ms` à 60 000 (9 cas/90j). Voir
  docs/data-quality-audit-2026-06-10.md.
- Jour GSC 31/05/2026 absent : trou côté API Google (re-fetché ~10× par le
  daily --months 1). Documenté, aucune action — ne pas le « réparer ».
- **Catégorie Wix ressource/classique** : toujours NULL dans
  `page_taxonomy` (non déductible du slug, règle CLAUDE.md). La liste
  authoritative est sur `/comprendre-le-droit`, rendu client-side → il
  faut un navigateur (Claude in Chrome) ou un export Velo. Une session de
  scrape → `source='hub_scrape'`, et `content_performance` gagne l'axe
  catégorie.
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
