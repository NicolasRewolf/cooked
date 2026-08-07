# Playbook — analyses SEO avec Cooked × GSC

Guide opérationnel pour mener les analyses que Nicolas demande, sans
retomber dans les pièges déjà payés. Issu des sessions des 09-10/06/2026
(Sprint 37-38), **à jour au 12/07/2026** : CPI **v2.2** (validé J+28 le
11/07/2026) + vue `cpi_opportunite_contact` (ex-gisement) + couture d'identité
`identity_stitch` / `conversion_journeys` v2 recousue (12/07/2026). À lire
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
| « Quelles pages vont bien/mal ? » | `cooked_page_index(28)` — trier `cpi ASC`, filtrer `grade IN ('S','A','B')` |
| « Pages à fort trafic qui ne convertissent pas ? » | `cpi_opportunite_contact` — `grade IN ('S','A','B') AND NOT convertit ORDER BY potentiel DESC` |
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

⚠️ **Sémantique recousue depuis le 12/07/2026** : `conversion_journeys` v2
reconstruit les parcours sur le **visiteur recousu** (`identity_stitch` —
les sessions coupées par l'ancien bug de rotation d'ids sont recollées).
Les chiffres d'assists produits AVANT le 12/07/2026 sous-comptaient ~2× sur
les ressources : toute comparaison avant/après le 12/07 doit le dire
explicitement (cf. piège 11).

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
**pilotage conversion**, la vue `cpi_opportunite_contact` sépare le *potentiel* d'une
page (capture + rétention + lecture, hors conversion) du badge *conversion
réalisée*. L'opportunité de contact (`grade IN ('S','A','B') AND NOT convertit ORDER BY
potentiel DESC`) = les pages qui captent une audience mais ne la convertissent
pas encore → où poser un pont vers le contact. **Croiser avec l'intention du
sujet** (indemnisation = audience concernée > pénal éducatif = curieux).
L'alerte `cpi_drop` ne sonne que sur un vrai decay (momentum/capture en baisse),
pas sur la volatilité de la conversion (recalibrée 17/06).

⚠️ **Note pratique** : `cooked_page_index(28)` en ad-hoc peut dépasser le
timeout MCP. Préférer lire le dernier snapshot :
`SELECT * FROM cpi_daily WHERE day = (SELECT max(day) FROM cpi_daily)`.

## 5. Les 15 pièges (chacun a déjà coûté une fausse conclusion)

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
   ⚠️⚠️ **Ces deux ratios ont été mesurés AVANT le 27/07/2026**, quand le
   trafic de la fiche Google vivait encore dans `organic_google` (piège 15) :
   ils gonflaient donc d'autant. Sur une fenêtre post-27/07, `organic_google`
   exclut le GMB — le ratio doit être **re-mesuré** avant d'être cité, pas
   repris tel quel.
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
10. **Coudre des parcours via un aid 32-hex — INTERDIT** (12/07/2026) : un
    `anonymous_id` 32-hex est le fallback serveur (hash IP|UA), **partageable
    entre visiteurs** — le joindre fusionnerait des inconnus entre eux. Pour
    rattacher sessions et visiteurs, passer par `identity_stitch`
    (`visitor_key`), jamais par une jointure directe sur l'aid.
11. **Attribution pré-12/07/2026 = mono-session** : avant la couture
    d'identité, les contacts assistés étaient sous-comptés (16 → 37 sur les
    ressources, 28 j). Requalifier toute analyse d'assists antérieure au
    12/07/2026 avant de la citer ; toute comparaison avant/après doit nommer
    le restatement.
12. **La position GSC n'est PAS la position à l'écran — vérifier le SERP réel
    avant toute reco de title/meta** (27/07/2026). GSC compte le rang *dans le
    bloc organique* et ignore tout ce qui le précède : AI Overview, People Also
    Ask, Knowledge Graph, Local Pack. Deux mesures faites le 27/07 :
    - `période de sûreté` — GSC annonce « position 1,9 » ; le SERP mobile réel
      donne AI Overview, puis PAA (dont la 1ʳᵉ question est *le titre exact de
      l'article*), puis Legifrance, puis Wikipédia, **puis** le cabinet en 5ᵉ
      position absolue.
    - `avocat bordeaux` — le cabinet est **n°1 du Local Pack** mais son
      résultat organique n'apparaît pas dans les 22 premiers items ; le 1ᵉʳ
      organique est en position absolue 7, sous 6 entrées Local Pack.

    Conséquence : une page « sous-capturante » informationnelle n'a pas
    forcément un problème de snippet — le clic est capté en amont. Sur les
    sujets définitionnels, l'objectif réaliste n'est plus le clic mais la
    citation dans l'AI Overview. **Contrôle obligatoire** :
    `mcp__dataforseo__serp_organic_live_advanced`, `device: mobile`,
    `location_name: France`. Les relevés sont consignés dans **`serp_features`**
    (panel fixe — le changer casse la comparabilité) : y regarder d'abord avant
    de rappeler l'API.

    ⚠️ **Le zéro-clic n'explique pas tout — vérifier aussi l'intention.**
    Relevé du 28/07/2026 sur `surveillance électronique`, plus grosse requête
    du site (**10 394 impressions, 5 clics**) : GSC annonce position 7
    organique, le visiteur nous voit en **position absolue 19**, sous un
    Knowledge Graph, un PAA, 3 organiques, un carrousel d'annuaires et **six
    entrées de Local Pack qui sont des magasins de caméras de
    vidéosurveillance**. L'intention dominante de la requête n'a rien à voir
    avec le droit pénal. Des impressions massives à CTR nul peuvent donc être
    un problème d'intention, pas de capture — et aucun travail éditorial ne
    les récupérera.
13. **`couv_gsc_pct` faible ⇒ `clics_perdus` non interprétable** (27/07/2026).
    → Ne plus lire `cpi_daily.clics_perdus` à la main : passer par la vue
    **`cpi_capture_perdue`** et filtrer `interpretable`. Elle porte
    `fiabilite_capture` (directe ≥ 40 % / partielle 20-39 % / extrapolée < 20 %).
    Au 27/07 : 13 pages en déficit, **5 seulement interprétables** — et
    `accident-du-travail`, 2ᵉ plus gros déficit apparent (56 clics), en sort
    avec ses 19 % de couverture.
    Le classement des clics perdus est partiellement un classement de la
    couverture GSC : `corr(couv_qpd, capture) = −0,29` sur 120 pages, −0,19 sur
    les seuls grades S/A/B. Sous 10 % de couverture (indemnisation-passager
    3 %, responsabilité-du-fait-des-choses 5 %), l'extrapolation de la traîne
    anonymisée produit mécaniquement des ratios de 3× à 5× — à ne pas lire
    comme de la surperformance, ni l'inverse comme un gisement.
14. **Le dwell ne prédit pas la conversion en organique** (27/07/2026).
    `corr(dwell, taux de contact) = −0,05` sur 38 posts organiques (soit
    *rien*) contre **+0,65** sur 12 cellules paid. L'agrégat tous canaux
    (−0,35) est un paradoxe de Simpson : deux mécaniques opposées moyennées.
    Les 4 articles les plus lus du site (152 s, 128 s, 126 s, 118 s) font
    **0 contact** chacun. Ne jamais utiliser le dwell comme proxy de qualité
    éditoriale ; c'est l'intention transactionnelle du sujet qui discrimine.
    Voir aussi le caveat de mesure au §5 du document CPI.
15. **Le GMB n'est PLUS de l'organique depuis le 27/07/2026**
    (`classify_channel` v3). Les clics du Local Pack arrivent sur
    `/?utm_source=gmb` avec un referrer `google.*` : jusqu'au 27/07 ils étaient
    comptés `organic_google` — **44,8 %** des entrées « organiques » de la home
    en étaient. Conséquences dures : (a) toute série `organic_google` qui
    traverse le 27/07 a une **rupture de définition**, pas une baisse de
    trafic ; (b) le GMB convertit à **3,68 %** contre **0,57 %** pour le SEO
    réel — les mélanger écrase le vrai signal SEO ; (c) le CPI a été restaté
    ce jour-là (home grade S→A). Toujours nommer le canal exact et vérifier de
    quel côté du 27/07 tombe la fenêtre.
    Corollaire de mesure : la fiche Google est **quasi invisible sur
    l'indemnisation** (sonde du 05/08/2026 : ≤75 impressions/12 mois contre
    ~2 100 sur le pénal) — donc un « le local ne marche pas en indemnisation »
    lu dans Cooked peut n'être que l'ombre de ce déséquilibre de fiche.

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
