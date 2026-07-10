# Playbook — analyses SEO avec Cooked × GSC

Guide opérationnel pour mener les analyses que Nicolas demande, sans
retomber dans les pièges déjà payés. Issu des sessions des 09-10/06/2026
(Sprint 37-38), à jour CPI **v2.2** + vue `cpi_gisement` (Sprint 39). À lire
AVANT la première analyse d'une session.

## 0. Démarrage de session (30 secondes)

```sql
SELECT * FROM alerts WHERE NOT acked;     -- incident en cours ?
SELECT * FROM refresh_pipeline_health();  -- healthy / issues[]
SELECT gsc_last_data_day();               -- lag J-2 = normal
```

Un chiffre produit pendant un incident pipeline est un chiffre faux.
Traiter ou expliquer l'alerte d'abord.

## 1. Quelle RPC pour quelle question

| Question de Nicolas | Outil |
|---|---|
| « Bilan de cette page / cet article » | `gsc_page_performance(path)` + décomposition canal (recette §2) |
| « Quelles pages vont bien/mal ? » | `cooked_page_index(28)` — trier `cpi ASC`, filtrer `grade IN ('A','B')` |
| « Pages à fort trafic qui ne convertissent pas ? » | `cpi_gisement` — `grade IN ('A','B') AND NOT convertit ORDER BY potentiel DESC` |
| « Qui monte, qui chute ? » | momentum 28v28 sur `gsc_path_daily` (recette §3.1) |
| « Des pages qui se cannibalisent ? » | requêtes multi-paths sur `gsc_query_page_daily` (§3.2) |
| « Quelles pages aident à convertir ? » | `conversion_journeys(days)` + unnest journey (§3.3) |
| « Le funnel SEO → contacts ? » | `seo_to_contact_funnel(days)` |
| « Combien de contacts cette semaine ? » | `site_macro_counts(start, end)` — jamais additionner les bookings |
| « Quick wins SEO ? » | `gsc_x_dfs_opportunities(...)` + striking distance pos 4-12 |
| « D'où viennent les forms ? » | `form_submits_attributed(days)` |

## 2. Bilan d'une page — la recette

1. **GSC d'abord** : impressions/clics/position depuis `gsc_path_daily`
   (totaux complets) ; requêtes depuis `gsc_query_page_daily`.
2. **PUIS décomposer le comportement PAR CANAL** — jamais de dwell/scroll
   global :

```sql
SELECT public.classify_channel(e.referrer_hostname, e.utm_source,
    e.utm_medium, 'www.jplouton-avocat.fr') AS canal,
  count(*) AS pageviews,
  round(percentile_cont(0.5) WITHIN GROUP (
    ORDER BY (x.props->>'duration_seconds')::numeric)) AS dwell_median
FROM events_human e
LEFT JOIN events_human x ON x.session_id = e.session_id
  AND x.path = e.path AND x.name = 'page_exit'
WHERE e.path = $1 AND e.name = 'pageview'
  AND e.occurred_at > now() - interval '28 days'
GROUP BY 1 ORDER BY 2 DESC;
```

Cas d'école (article chirurgie, 10/06) : dwell global 2 s = artefact.
Décomposé : social 1 s, navigation interne 2 s, **Google 45 s**. L'article
était bon ; le chiffre global mentait.

3. **Conversion** : clics CTA sur la page + assists via
   `conversion_journeys`. Zéro conversion sous 30 entrées organiques
   n'est pas un verdict.

## 3. Top/flop — les trois forces (toujours les trois)

Une URL n'est jamais « bonne » ou « mauvaise » dans l'absolu. Mesurer :

### 3.1 Momentum (qui monte, qui pourrit)
28 derniers jours vs les 28 précédents, par path, clics ET position.
Diagnostic différentiel crucial :
- clics ↓ + position STABLE → **marée** (demande/SERP), pas la page.
  Ne pas réécrire pour le SEO.
- clics ↓ + position ↓ → **vrai decay**. Refresh contenu + maillage.

### 3.2 Cannibalisation
```sql
-- requêtes où ≥2 paths captent ≥40 imps chacun (28j)
... GROUP BY query HAVING count(DISTINCT path) >= 2 ...
```
Brand multi-pages = normal (sitelinks). Hors-brand = un seul candidat doit
être désigné et renforcé, l'autre 301/dé-optimisé.

### 3.3 Pivots invisibles
Pages présentes dans les parcours convertis SANS être la page d'entrée
(unnest de `conversion_journeys.journey`). Exemple structurel du site :
`/notre-cabinet` + `/nos-affaires` + catégorie médias = colonne vertébrale
de confiance — investir là rapporte sur TOUS les parcours.

## 4. CPI — l'outil de tri

```sql
SELECT * FROM cooked_page_index(28)
WHERE grade IN ('A','B') AND cpi < 35
ORDER BY n_org DESC;            -- les malades certifiés, gros d'abord
```

Le CPI **trie**, les quatre z **diagnostiquent**. Archétypes (cf.
`docs/cpi-cooked-page-index.md`) : dictionnaire (zc−− zl−− zv−−),
mauvaise cible (zr++ zl++ zv−−), hors-périmètre déclinant (zv−− M↘),
snippet malade + decay (zc−− M↘) = le prochain à réparer, étoile montante
(zv++ M↗) = pousser maintenant. La trajectoire vit dans `cpi_daily`.

**CPI v2.2 (Sprint 39)** : momentum à transition continue + empirical Bayes
dynamique par type (formules dans `cpi-cooked-page-index.md`). Pour le
**pilotage conversion**, la vue `cpi_gisement` sépare le *potentiel* d'une
page (capture + rétention + lecture, hors conversion) du badge *conversion
réalisée*. Le gisement (`grade IN ('A','B') AND NOT convertit ORDER BY
potentiel DESC`) = les pages qui captent une audience mais ne la convertissent
pas encore → où poser un pont vers le contact. **Croiser avec l'intention du
sujet** (indemnisation = audience concernée > pénal éducatif = curieux).
L'alerte `cpi_drop` ne sonne que sur un vrai decay (momentum/capture en baisse),
pas sur la volatilité de la conversion (recalibrée 17/06).

## 5. Les 8 pièges (chacun a déjà coûté une fausse conclusion)

1. **Mix de canaux** → métriques de lecture sur organique uniquement.
2. **Position moyenne** → pondérée impressions, mélange des requêtes.
   CTR attendu = requête par requête via la courbe du site (loi de
   puissance, R²=0,917, p1≈10 % — SERP juridiques compressées par
   ads/local pack), puis somme.
3. **Couverture `gsc_query_page_daily`** : Google anonymise jusqu'à ~94 %
   des requêtes d'une page. Totaux → `gsc_path_daily` ; qpd → mix
   positionnel et attribution seulement.
4. **Marée vs ranking** (cf. §3.1) — la GAV a perdu 282 clics à position
   5,1 constante : c'était la SERP, pas la page.
5. **Branded** : `NOT public.gsc_is_branded(query)` partout où on juge un CTR
   (équivalent historique : `query !~* 'plouton'`).
6. **Petits volumes** : lissage empirical Bayes + grades A/B/C. Sous
   n_org 30, on émet des hypothèses, pas des verdicts.
7. **Quick win GSC non vérifié** (retex 11/06/2026) : avant d'annoncer
   un « gisement » (grosses impressions, peu de clics), DEUX contrôles
   obligatoires. (a) Décomposer requête par requête (piège 2 appliqué) :
   defense-des-consommateurs affichait 3 434 imp pos 10 → 81 % venaient
   d'une requête navigationnelle d'un cabinet concurrent (« avocats-lpbc »),
   gisement réel ~650 imp. (b) Croiser clics GSC × visites Cooked
   (`organic_google`, fenêtre alignée sur `gsc_last_data_day()`) : GSC
   sous-compte ~2,4× sur les pages à enjeu local (clics pack local/fiche
   GMB invisibles dans Search Console). ⚠️ Réf. re-mesurée le 02/07/2026 :
   le ratio SITE-WIDE organic_google/clics GSC ≈ **1,19×** (fenêtre alignée
   16-29/06) — le 2,4× ne vaut que page par page sur les pages à enjeu
   local, ne pas l'appliquer globalement. Les visites Cooked font foi pour
   le trafic réel ; GSC fait foi pour impressions/positions.
8. **Date de publication Wix trompeuse (antidatable)** (retex 22/06/2026) :
   `firstPublishedDate` (API Wix) et le `<lastmod>` du sitemap peuvent être
   **antidatés** à la main → ils ne reflètent PAS la mise en ligne réelle. Pour
   juger l'âge SEO d'un article (« a-t-il eu le temps de ranker ? »), utiliser la
   **1ère impression GSC** (`min(day)` de `gsc_path_daily`) et la **1ère vue
   tracker** (`min(occurred_at)` de `events_human`) — jamais la date Wix seule.
   Cas `cycliste-renversé` : date affichée 12/05, 1ère impression Google 17/06
   → âge réel **5 jours**, pas 6 semaines (conclu « n'a pas pris » à tort). Un
   fort écart date Wix ↔ 1ère vue/impression = mise en ligne tardive : recompter
   l'âge depuis la découverte Google.
9. **`click_internal.target_path` : variantes accentuées** (retex 02/07/2026) :
   certains href du site portent des slugs accentués qui n'existent pas en
   pageview (é vs e). 8 paires univoques backfillées (migration
   `20260702132222`) ; pour toute jointure target_path ↔ paths, passer par
   `unaccent()` en lecture (les variantes sans jumeau pageview restent).

## 6. Livraison à Nicolas

- Dates **JJ/MM/AAAA**, heures Paris, fenêtres explicites (« 28j au
  08/06 » — GSC est à J-2).
- Quand une correction de mesure change l'historique, la nommer
  **restatement** et fournir la phrase client (ex. Sprint 37 : « contacts
  téléphone 28j 110 → 95 : correction de mesure, pas baisse d'activité »).
- Toujours donner le diagnostic AVEC l'action (« title à réécrire »,
  « bloc urgence à ajouter », « 301 le zombie »), classé par ROI.
- Les actions côté Wix (Custom Code, contenus, metas) sont à Nicolas :
  livrer le matériel prêt à coller, ne jamais prétendre l'avoir fait.
