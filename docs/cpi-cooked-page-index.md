# CPI — Cooked Page Index (v2.2)

Score de santé 0-100 par page, calculé sur 28 jours glissants. Croise GSC
(capture) et Cooked (rétention, lecture, conversion), avec momentum relatif
au site et gate technique LCP.

> **Fenêtres (depuis le 03/09/2026, ticket T-05 de la mission du 02/09)** —
> une seule fenêtre pour tout le score : **28 jours calendaires clos à
> `gsc_last_data_day()`** (le dernier jour livré par Google, lag J-3/J-4).
> Côté GSC : capture, courbe CTR (90 j) et momentum (`c1` = ces 28 jours,
> `c0` = les 28 précédents — mêmes durées). Côté Cooked : entrées organiques,
> pageviews, `page_exit`, LCP sur **les mêmes jours Paris**
> (`cooked_paris_ts_start` / `_end_exclusive`). Le score d'un `day` donné est
> donc reproductible ; le snapshot `cpi_daily` du jour J décrit les 28 jours
> qui se terminent à `gsc_last_data_day()`, pas « hier ». Avant : la moitié GSC
> était bornée par la date serveur (24-25 jours de données réelles sur 28
> nominaux) et la moitié Cooked par l'heure du run (deux snapshots consécutifs
> séparés de 18 à 34 h). Depuis le ticket T-09 (même jour), le terme
> conversion lit `conversion_journeys(p_days, gsc_last_data_day())` — la
> fenêtre du score — et le CPI n'a **plus aucune borne d'horloge**. Invariant :
> contract-test `cpi_sans_horloge` (0 borne d'horloge dans le corps de
> `cooked_page_index`).

> **v2.2 (16/06/2026)** — deux raffinements adoptés après revue mathématique
> externe (corr 0,9855 avec v2.1, aucun verdict fiable A/B déplacé de ≥5 pts) :
> momentum à **transition continue** (fin de la bascule discrète à 20 clics) et
> lissage **empirical Bayes dynamique** (Beta-Binomial par type) pour rétention
> et lecture. Formules : `cpi-modele-mathematique.md`. Analyse de sensibilité :
> la conversion porte **65 % de la variance** du score (surpoids effectif vs
> poids nominal 0,35). **Point tranché au J+28 (tir réel du 11/07/2026)** :
> ce surpoids porte le seul signal prédictif du score — la « mémoire de
> conversion » (ratio tiers 3,11 avec conversion vs 0,10 sans) — donc pas de
> re-régularisation de zv, v2.2 conservée telle quelle.

## Usage

```sql
-- Classement complet
SELECT * FROM cooked_page_index(28) ORDER BY cpi ASC;

-- Les malades certifiés (à traiter en priorité)
SELECT path, cpi, zc, zr, zl, zv, momentum_badge, clics_perdus
FROM cooked_page_index(28)
WHERE grade IN ('S','A','B') AND cpi < 35 ORDER BY n_org DESC;

-- Trajectoire d'une page (snapshot quotidien, cron 07:30 UTC)
SELECT day, cpi, zc, zv, momentum FROM cpi_daily
WHERE path = '/post/...' ORDER BY day;

-- La dérivée ~7j : qui chute, qui monte, qui disparaît (Sprint 38)
-- Vide tant que cpi_daily a < 7 j d'historique (premier rendu ~17/06/2026).
SELECT path, statut, cpi_ref, cpi_now, delta_cpi,
       delta_zc, delta_zr, delta_zl, delta_zv, delta_momentum
FROM cpi_movers
WHERE fiable AND delta_cpi <= -10 ORDER BY delta_cpi;

-- Les pages sorties du radar (souvent le decay le plus avancé)
SELECT path, ptype, cpi_ref, grade_ref FROM cpi_movers WHERE statut = 'disparu';

-- Pilotage conversion : opportunité de contact = potentiel haut, ne convertit pas
SELECT path, ptype, n_org, potentiel, cpi, convertit
FROM cpi_opportunite_contact
WHERE grade IN ('S','A','B') AND NOT convertit
ORDER BY potentiel DESC;
```

L'alerte `cpi_drop` (cron horaire, bloc 6 de `cooked_alerts_refresh`) pointe
les pages fiables (Fiabilité S/A/B aux deux dates) qui perdent ≥ 15 pts sur ~7 j,
**uniquement si la chute est portée par un vrai decay** (momentum ≤ −0,10 ou
capture delta_zc ≤ −0,5). La volatilité pure de la conversion (un contact qui
sort de la fenêtre 28 j) ne déclenche plus l'alerte (recalibrée 17/06/2026).
Le diagnostic vit dans les `delta_z*` de la vue — même grille que les z.

Pour le **pilotage conversion**, la vue `cpi_opportunite_contact` (alias
déprécié `cpi_gisement`) sépare le *potentiel* (capture + rétention + lecture,
renormalisés hors conversion) du badge *conversion réalisée* (`convertit`) —
voir la requête ci-dessus. Elle ne recalcule rien : elle relit le dernier
`cpi_daily`. Une **opportunité de contact** (potentiel haut + ne convertit
pas) = les pages où agir, à croiser avec l'intention du sujet
(indemnisation > pénal éducatif).

## Grille de lecture

| CPI | État |
|---|---|
| > 75 | champion |
| 50-75 | sain |
| 35-50 | à surveiller |
| < 35 | malade |

**Fiabilité** (colonne SQL `grade`) : S = très fiable (n_org≥200, E≥40) · A = fiable (≥100, ≥20) · B = indicatif (≥30, ≥5) · C = insuffisant.
Règle d'or : **le CPI trie, les quatre z diagnostiquent** — ne jamais lire le
nombre sans ses composantes.

## Les quatre z (vs pairs du même type de page, robustes médiane/MAD)

- **zc capture** : clics réels vs attendus à ces positions (courbe CTR propre
  au site, loi de puissance R²=0,917, branded exclu). zc<0 = snippet malade.
- **zr rétention** : survie des 15 premières secondes (organique) ; lissage
  empirical Bayes **dynamique** (pseudo-compte κ estimé par type, v2.2).
- **zl lecture** : profondeur qualifiée *parmi les retenus* (seuils = médianes
  du type), même lissage EB dynamique. Orthogonal à zr par construction.
- **zv conversion** : contacts directs + assists dilués (1/longueur du
  parcours) + 0,25×bookings, par entrée organique, lissage empirical Bayes.
  Depuis le **12/07/2026**, l'entrée vient de `conversion_journeys` **v2
  recousue** (parcours du visiteur recousu via `identity_stitch`).

`momentum` ∈ [0,71-1,40] : tendance clics **relative au site** (une marée qui
baisse partout ne punit personne) ; **transition continue** entre régime
position (peu de clics) et régime clics relatif (v2.2 — fin du saut à 20 clics).
**Source des clics (depuis le 03/09/2026, T-06, option (b))** : `gsc_path_daily`
— la source complète — **moins les clics brandés que Google révèle** dans
`gsc_query_page_daily` (≈ total non brandé). Du 25/07 au 03/09/2026 le momentum
ne lisait que la traîne révélée non brandée, soit 16 à 28 % des clics réels
d'une page : 15 des 47 pages fiables avaient une direction inverse à leurs
clics. Le terme position reste calculé sur les requêtes révélées non brandées
(une position n'a de sens que requête par requête).
`couv_gsc_pct` : part des impressions dont Google révèle la requête (peut
descendre à 6 % — d'où le scaling v2.1).

### ⚠️ Limites de mesure des quatre z (mesurées le 27/07/2026)

Trois limites structurelles, à citer chaque fois qu'un z est livré seul.

**1. `zr` et `zl` reposent sur un événement qui manque une visite sur deux.**
Le dwell et le scroll viennent de `page_exit`, qui ne se déclenche que sur
**~59 %** des visites — **66 %** sur mobile, **50 %** sur desktop. Pire, la
couverture varie de **40 % à 92 %** selon la page (médiane 63 %) et elle est
**corrélée négativement au dwell mesuré : r = −0,32** sur 63 posts à ≥ 30
visites. Autrement dit, les pages qui affichent les plus longs temps de lecture
sont en partie celles où l'événement de sortie se déclenche le moins : le
« champion de lecture » est mesuré sur un sous-échantillon auto-sélectionné.
Le seuil `retained = (d >= 15 OR pv >= 2)` hérite du même biais. Ne jamais
comparer un dwell médian entre deux pages sans sortir aussi leur couverture.

**2. `zc` est relatif à un plancher zéro-clic, pas à un standard.** La courbe
CTR du site — l'étalon du terme capture — donne **7,69 % en position 1** et
s'aplatit dès la position 2 (3,83 % → 3,79 % en position 3). Une courbe saine
s'effondre de ~30 % à ~5 %. Une courbe basse et plate est la signature de SERP
où le bloc organique n'est plus la réponse principale (AI Overview, PAA, Local
Pack). Donc `zc = 0` ne veut pas dire « capture normale » mais « aussi mal
capté que la moyenne d'un site qui plafonne à 7,7 % en position 1 ». C'est un
choix de conception assumé — le CPI trie, il ne mesure pas un absolu — mais le
niveau absolu, lui, n'est surveillé par personne.

**3. `zv` ne voyait pas la fiche Google Business jusqu'au 27/07/2026.** Voir la
rupture de série ci-dessous.

## Archétypes détectés (run de validation 10/06/2026)

- zc−− zl−− zv−− : **dictionnaire** (mis-en-cause, période-de-sûreté)
- zc−− zr++ zl++ zv−− : **mauvaise cible** — lus à fond, jamais clients (bail-commercial)
- zv−− M↘ : **hors-périmètre qui décline** (loi Badinter, exclue de la CIVI)
- zc−− M↘ : **prochain malade** (casier-judiciaire)
- zv++ M↗ : **étoile montante** (délai-déraisonnable, CTR ×6 l'attendu)

Premier snapshot : 10/06/2026 — 192 pages, CPI pondéré trafic = 32,
446 clics perdus/28j.

## Validation à J+28 — tir réel FAIT le 11/07/2026 : **VALIDÉ**

Harnais `scripts/cpi_validation_j28.sql` (t0 = snapshot du 10/06/2026,
grille de verdict pré-déclarée en tête de fichier). Résultats :

- **§0 intégrité : PASSE** — le score se recompose exactement depuis les z
  stockés de `cpi_daily` (194/194, écart 0).
- **§3 calibration : PASSE** — R² = 0,931 (critère liant ≥ 0,85). Médiane
  |obs−préd| = 20,5 % : indicateur de **suivi** (non liant) — reflète la
  courbure SERP non captée par la loi de puissance à 1 segment (candidat :
  fit log-log à 2 segments). §3 sert aussi de check mensuel.
- **§5 stabilité des poids : PASSE** — τ-b ≥ 0,952 sur les 8 perturbations
  ±0,05. Le classement n'est pas un artefact des poids.
- **Bonus prédictif (§1/§4, non liant)** : ratio de taux de contact futur
  tiers haut vs bas = **3,11** (score complet) contre **0,10** sans la
  composante conversion → le signal prédictif vient de la **mémoire de
  conversion** (zv encode les contacts passés des mêmes pages), pas des
  composantes comportementales. Cohérent avec la philosophie gisement :
  le potentiel ne convertit pas sans action.

**Libellé maximal acté** : le CPI est validé comme **score de
priorisation**, non comme prédicteur d'outcome à 28 j. **Limite connue** :
biais de taille (issue GitHub #19). **Re-test diagnostic 56 j** (t0
inchangé, horizon doublé, non-gating) : à lancer le **05/08/2026**.

## Ruptures de série `cpi_daily` (restatements)

Les corrections de mesure suivantes ont restaté le snapshot du jour. **Comparer un
CPI d'avant/après ces dates revient à comparer deux définitions**, pas une
évolution de la page. Annotations posées dans la table `annotations`.

- **02/07/2026 — grain lectures (session×path)** : ±7 pts max sur 4 pages
  A/B, 8 pages C sorties du scoring. Même jour : `classify_channel` v2 (IA détectée
  aussi par `utm_source`). Annotation posée le 04/09/2026 (T-20).
- **12/07/2026 — conversion recousue** : l'entrée de zv passe à
  `conversion_journeys` v2 (visiteur recousu via `identity_stitch`). Seule
  la composante zv bouge (zc/zr/zl/momentum/gate inchangés page par page),
  delta moyen −0,1 pt, **0 changement de grade**, 7 movers ≥ 15 pts — dont
  arnaque-en-ligne 41→100 et `/nos-affaires` 67→12 (qui rend un crédit
  usurpé par l'ancienne attribution mono-session).

- **25/07/2026 — momentum sur les requêtes révélées + badge `convertit`** (revue
  d'architecture n°2) : `c1`/`c0` lus dans `gsc_query_page_daily` non brandé —
  16-28 % des clics réels — jusqu'au 03/09/2026 (T-06). Sur cette période le
  momentum n'est pas un signal fiable. Annotation posée le 04/09/2026 (T-20).

- **27/07/2026 — la fiche Google Business sort de l'organique**
  (`classify_channel` v3). Les clics du Local Pack arrivent sur
  `/?utm_source=gmb` avec un referrer `google.*` : la branche
  `ref ilike '%google.%'` les classait `organic_google`, `classify_channel`
  ne testant `utm_source` que pour le paid et l'IA. **137 des 306 entrées
  « organiques » de la home sur 28 j étaient du GMB (44,8 %)** ; 672 sessions
  depuis le 06/05/2026, dont 99,3 % sur `/`. Le canal `gmb` ne matche pas
  `LIKE 'organic%'`, donc ce trafic sort du CPI, de `conversion_journeys` et
  de `seo_to_contact_funnel`. Impact mesuré : **`n_org` de `/` passe de 305 à
  164, grade S → A**, et son `zv` baisse. Aucune autre page n'est
  matériellement touchée (2 sessions au maximum ailleurs).
  Écart de performance que la moyenne masquait : GMB **3,68 %** de taux de
  contact contre **0,57 %** pour le SEO organique réel — 6,5×.

- **03/09/2026 — fenêtres alignées sur les données GSC** (ticket T-05 de la
  mission du 02/09, migration `20260903085351`). Avant : la moitié GSC du score
  ne couvrait que 24 jours de données sur 28 nominaux (lag Google) et la
  moitié Cooked glissait avec l'heure du run. Photo avant/après **du même
  jour, sur les mêmes données** : 175 pages → 175 (6 entrées / 6 sorties,
  toutes grade C au seuil `n_org` 5), delta moyen **−1,3 pt**, médiane |Δ| 3 ;
  46 pages fiables S/A/B : médiane |Δ| 2, **1 seul mover ≥ 15 pts**
  (assurance-perte-exploitation 21→41, terme conversion), 2 changements de
  grade (1 B→C, 1 C→B). `clics_perdus` 1 138 → 1 284 (+13 % : 28 jours de
  capture au lieu de 24). CPI pondéré trafic 48,5 → 45,6. Le momentum du
  03/09 se compare à un `c1` enfin de même durée que `c0`.

- **03/09/2026 — terme conversion sur la fenêtre du score** (ticket T-09 de
  la mission du 02/09, migration `20260903093320`). `zv` lit
  `conversion_journeys(p_days, gsc_last_data_day())` au lieu de
  `conversion_journeys(p_days)` sur `now()` : les contacts comptés sont ceux des
  28 jours du score, plus ceux des 28 × 24 h précédant le run (fenêtre reculée
  de 3 jours). `entry_channel` via `classify_channel` v5 (gclid ⇒ paid). Photo
  avant/après du même jour, mêmes données GSC : 175 pages → 175, **seul `zv`
  bouge** (64 pages ; zc/zr/zl/momentum/gate identiques), delta moyen
  **+0,3 pt**, **0 changement de grade**, 6 movers ≥ 15 pts
  (garde-à-vue-ou-audition-libre 50→23, cap-ferret-relaxe 11→38,
  abus-de-confiance 62→81, sarvi 31→13, escroqueries-cryptomonnaies 34→52,
  DDSE 48→30 — la volatilité connue du terme conversion sur ~10 contacts
  organiques attribuables/mois), 3 badges `convertit` changent, CPI pondéré
  trafic 45,6 → 45,7. Le CPI n'a plus aucune borne d'horloge.

- **03/09/2026 — momentum sur la source complète des clics** (ticket T-06 de
  la mission du 02/09, migration `20260903101652`, décision Nicolas : option
  (b)). `c1`/`c0` = `gsc_path_daily` moins les clics brandés révélés, au lieu
  de `gsc_query_page_daily` non brandé (16-28 % des clics réels ; 15 des 47
  pages fiables en direction inverse de leurs clics). Photo avant/après du
  même jour, mêmes données GSC : 175 pages → 175, **seul le momentum bouge**
  (132 pages ; zc/zr/zl/zv/gate identiques), delta moyen **+3,7 pts**, médiane
  |Δ| 4, **0 changement de grade**, 31 movers ≥ 15 pts dont 8 fiables
  (notre-cabinet 62→100, indemnisation-accident-moto 52→87,
  interdiction-de-gérer 56→80, assurance-perte-exploitation 43→61,
  5-8-millions-notaires 34→52, garde-à-vue-ou-audition-libre 23→40 ;
  abus-de-confiance 81→64, indemnisation-civi 80→60), CPI pondéré trafic
  45,7 → 45,9. Contrefactuel rejoué : **0 page fiable en direction inverse**.
  Deux choses à savoir pour lire ces momentums : (1) les clics GSC du site ont
  chuté de ~40 % fin juillet (≈ 2 300/sem → ≈ 1 350/sem depuis le 27/07) —
  le momentum étant relatif au site, une page stable apparaît « ↗ » ; (2) sur
  `/notre-cabinet` et la home, les clics brandés **non révélés** restent dans
  le total : biais de marque résiduel, borné à ces deux pages.
  `cpi_opportunite_contact.potentiel` ne dépend plus du momentum ni du gate ;
  `cpi_drop` ignore une page dont les clics réels (`gsc_path_daily`, 7 j vs
  7 j) montent.

Tables d'audit : `cpi_pre_restatement_20260712` et `_20260727` (supprimées le
10/08/2026), `cpi_pre_restatement_20260903` (phases `t05_avant` / `t09_avant` /
`t06_avant`, à supprimer **après lecture de la vérification J+1 du 04/09** —
condition posée par Nicolas sur #120).

### Version de définition (`cpi_daily.cpi_version`, T-20, 04/09/2026)

Le **modèle** reste v2.2 (pas de v2.3 : décisions du 18/06 et du 11/07). Ce qui
change à chaque restatement, c'est la **définition** des entrées ; elle est
versionnée dans `cooked_config.cpi_definition_version`, écrite par
`cooked_cpi_snapshot()` dans `cpi_daily.cpi_version`, et rétro-remplie :

| Version | Jours `cpi_daily` | Définition |
|---|---|---|
| 2.2.0 | 10/06 → 01/07/2026 | v2.2 (momentum continu, empirical Bayes dynamique) |
| 2.2.1 | 02/07 → 11/07 | lectures au grain session×path ; `classify_channel` v2 (IA) |
| 2.2.2 | 12/07 → 23/07 | conversion recousue (`identity_stitch`, `conversion_journeys` v2) |
| 2.2.3 | 25/07 → 26/07 | momentum sur `gsc_query_page_daily` non brandé ; badge `convertit` |
| 2.2.4 | 27/07 → 02/09 | `classify_channel` v3 : GMB hors `organic_google` |
| 2.2.5 | 03/09 → | fenêtres closes à `gsc_last_data_day()` (T-05), momentum sur `gsc_path_daily` (T-06), zv sur la fenêtre du score (T-09) |

**Invariant I10** : toute migration qui restate le CPI **bumpe la clé et pose
l'annotation** dans la même migration. Deux lignes de `cpi_daily` de versions
différentes ne se comparent pas sans lire `annotations` (`cpi_movers` compare à
~7 j : un restatement y apparaît comme un mover, pas comme un decay).

### Calibration de la courbe CTR — check mensuel (T-20)

Le §3 du harnais (`scripts/cpi_validation_j28.sql`) est rejoué le 1er du mois à
05:00 UTC (cron `cpi-calibration-monthly` → `cpi_calibration_check()` →
table `cpi_calibration_checks`, fenêtre 90 j close à `gsc_last_data_day()`,
brandé exclu via `gsc_is_branded`). **Critère liant : R² ≥ 0,85** (alerte
`cpi_calibration` critical sinon — le terme capture et `clics_perdus` reposent
sur cette loi de puissance) ; la médiane |écart| est un indicateur de suivi
(warn > 30 %). Points : 11/07 R² 0,930 / 20,1 % ; 02/09 0,909 / 28,8 % ;
**04/09/2026 : R² 0,913, pente −1,259, 20 buckets, médiane 25,5 %, CTR position 1
8,20 %**. Le registre `freshness_contract` sonne si le cron n'écrit pas (warn > 35 j).

## v2.2 — analyses d'impact (instruites le 10/06/2026, AVANT tout code)

**(a) Pondération valeur par thème — NO-GO.** 38 contacts organiques
attribués sur « 90 j » (en réalité ~35 j d'historique tracker), dont 71 %
sur des entrées **sans thème** en taxonomie (cabinet/hub). Par thème réel :
1 à 5 contacts par trimestre — piège #6, aucune valeur différenciée
estimable sur les données. Re-instruire si : volume ×10, OU pondération à
dire d'expert (valeur de dossier moyenne par thème, métadonnée statique,
décision business → Nicolas), et dans tous les cas après l'enrichissement
taxonomie via le hub (P2 roadmap).

**(b) INP dans le gate — GO v2.2, design « relatif au site » imposé.**
Couverture : 143/194 pages CPI (74 %) ont ≥ 5 mesures INP mobile/28 j.
Le signal mord : médiane p75 site = 221 ms (> seuil good 200), 90/158 pages
> 200 ms, 21 > 500 ms (poor), max 1 484 ms. Conséquence de design : un gate
ABSOLU pénaliserait ~57 % des pages → ce n'est plus un gate, c'est une
pénalité systémique qui dilue le tri (même leçon que le momentum relatif :
ce qui est commun au site ne punit personne individuellement). À chiffrer
au moment du dev : rampe relative (ex. 1,5× → 3× la médiane site, plancher
×0,9), défaut neutre sans données (comme le LCP à 2 500).

**(c) Paires cannibales en vue séparée — DÉFER, pas de vue.** 8 requêtes
hors-brand en chevauchement sur 28 j (6,8 % des imps qpd), dont 2 seules
notables (sarvi 5,2k imps, civi 3,5k) — et le « rival » y est chaque fois
le même article comparatif `sarci-ou-civi` à 50-76 imps (≈ 2 % du volume) :
chevauchement naturel très asymétrique, pas un combat de pages. La recette
playbook §3.2 suffit en ad-hoc. Re-mesurer au check mensuel (§3 du harnais) ;
créer la vue seulement si > 15 paires ou si une paire devient équilibrée.
Noté au passage (action contenu, hors CPI) : la page SARVI est en striking
distance (pos 10,4, 5 150 imps, 17 clics) — quick win à proposer.
