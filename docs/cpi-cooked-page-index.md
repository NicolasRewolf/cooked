# CPI — Cooked Page Index (v2.2, Sprint 38)

Score de santé 0-100 par page, calculé sur 28 jours glissants. Croise GSC
(capture) et Cooked (rétention, lecture, conversion), avec momentum relatif
au site et gate technique LCP.

> **v2.2 (16/06/2026)** — deux raffinements adoptés après revue mathématique
> externe (corr 0,9855 avec v2.1, aucun verdict fiable A/B déplacé de ≥5 pts) :
> momentum à **transition continue** (fin de la bascule discrète à 20 clics) et
> lissage **empirical Bayes dynamique** (Beta-Binomial par type) pour rétention
> et lecture. Formules : `cpi-modele-mathematique.md`. Analyse de sensibilité :
> la conversion porte **65 % de la variance** du score (surpoids effectif vs
> poids nominal 0,35 — point ouvert, à juger au J+28).

## Usage

```sql
-- Classement complet
SELECT * FROM cooked_page_index(28) ORDER BY cpi ASC;

-- Les malades certifiés (à traiter en priorité)
SELECT path, cpi, zc, zr, zl, zv, momentum_badge, clics_perdus
FROM cooked_page_index(28)
WHERE grade IN ('A','B') AND cpi < 35 ORDER BY n_org DESC;

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
```

L'alerte `cpi_drop` (cron horaire, bloc 6 de `cooked_alerts_refresh`) pointe
les pages fiables (grade A/B aux deux dates) qui perdent ≥ 15 pts sur ~7 j.
Le diagnostic vit dans les `delta_z*` de la vue — même grille que les z.

## Grille de lecture

| CPI | État |
|---|---|
| > 75 | champion |
| 50-75 | sain |
| 35-50 | à surveiller |
| < 35 | malade |

**Grades de confiance** : A = verdict (n_org≥100, E≥20) · B = solide · C = hypothèse.
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

`momentum` ∈ [0,71-1,40] : tendance clics **relative au site** (une marée qui
baisse partout ne punit personne) ; **transition continue** entre régime
position (peu de clics) et régime clics relatif (v2.2 — fin du saut à 20 clics).
`couv_gsc_pct` : part des impressions dont Google révèle la requête (peut
descendre à 6 % — d'où le scaling v2.1).

## Archétypes détectés (run de validation 10/06/2026)

- zc−− zl−− zv−− : **dictionnaire** (mis-en-cause, période-de-sûreté)
- zc−− zr++ zl++ zv−− : **mauvaise cible** — lus à fond, jamais clients (bail-commercial)
- zv−− M↘ : **hors-périmètre qui décline** (loi Badinter, exclue de la CIVI)
- zc−− M↘ : **prochain malade** (casier-judiciaire)
- zv++ M↗ : **étoile montante** (délai-déraisonnable, CTR ×6 l'attendu)

Premier snapshot : 10/06/2026 — 192 pages, CPI pondéré trafic = 32,
446 clics perdus/28j.

## Validation à J+28 (P1)

Spearman(CPI_t, Δcontacts_{t→t+28}) > 0,3 ; calibration courbe CTR ;
ablation par composante ; stabilité des poids ±0,05 (Kendall τ > 0,9).

**Protocole prêt à lancer : `scripts/cpi_validation_j28.sql`** (sections
autonomes, critères et grille de décision en tête de fichier). À lancer à
partir du **08/07/2026**. Déjà validé au dry-run du 10/06/2026 :

- §0 intégrité : le score se recompose exactement depuis les z stockés de
  `cpi_daily` (194/194, écart 0) — l'ablation et la stabilité sont fondées.
- §5 stabilité des poids : **PASSE** — τ-b ∈ [0,952 ; 0,966] sur les 8
  perturbations ±0,05. Le classement n'est pas un artefact des poids.
- §3 calibration : R² = 0,915 (réf. 0,917 au fit initial — stable). Réserve :
  la loi de puissance ne capte pas la courbure de la SERP (CTR observé
  +44/+67 % vs prédit en pos 3-4, −28/−42 % en pos 9-13). Le zc des pages
  rankant 9-13 est donc légèrement pénalisé, celui des pages 3-4 flatté —
  en partie absorbé par la comparaison aux pairs. Candidat v2.2 : fit
  log-log à 2 segments. §3 sert aussi de check mensuel (les SERP dérivent).
- Périmètres figés du test : n = 194 pages (toutes), n = 51 (grade A/B —
  le critère officiel s'applique là). Attendre ~70-90 % de ties sur la
  cible contacts : si le test primaire est sous-puissant, juger sur les
  cibles secondaires (Δvaleur composite, Δclics GSC) avant de recalibrer.

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
