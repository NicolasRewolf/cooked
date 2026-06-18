# Revue critique experte — CPI v2.2

> Réponse au prompt `cpi-prompt-revue-expert.md`.  
> Revue réalisée à partir des formules du §4, du SQL `cooked_page_index` (migration v2.2), et de vérifications numériques.

---

## Vérifications par le calcul

| Affirmation | Résultat |
|---|---|
| Point neutre $z_j=0 \Rightarrow \text{CPI}=50\,MG$ | Confirmé ($\sigma(0)=0{,}5$) |
| Conversion ≈ 65 % de la variance de $S$ si $\sigma_{z_v}\approx1{,}58$ | **66,7 %** — cohérent |
| $\pm50$ pts sur 1 contact | Plausible : $z_v$ seul de $-3$ à $+3$ → **58 pts** de CPI ; avec les autres $z$ neutres et $M=G=1$, un saut $0\to1$ contact peut donner **14–28 pts** selon $s_v$ |
| $M \in [0{,}714,\,1{,}40]$ | Confirmé ($e^{\pm0{,}336}$) |
| $G=1$ si LCP ≤ 2500 ms | Confirmé dans le SQL |

**Correction mineure :** le document cite $R^2\approx0{,}92$ pour la courbe CTR (§4.2) ; la spec math et le dry-run indiquent **0,917**. Écart négligeable, pas une erreur de modèle.

---

## Réponses aux 7 questions

### 1. Surpoids de la conversion (priorité)

**Diagnostic vérifié.** Avec $w_v=0{,}35$ mais $\sigma_{z_v}\approx1{,}5$–$1{,}6$, la conversion domine le tri bien plus que son poids nominal. À ~10 contacts/mois, $z_v$ est surtout un détecteur binaire « zéro vs un peu », pas un gradient fin.

**Recommandation principale — triple action, faible risque :**

**A. Compresser $z_v$ avant agrégation (maintenant)**

Remplacer $z_v$ par :

$$
z_v' = \operatorname{sign}(z_v)\cdot\sqrt{|z_v|}
$$

ou $\tanh(z_v/2)$. Effet : réduire la variance effective de $z_v$ d'environ **40 %**, ramener sa part dans $S$ vers **~45 %** sans toucher aux poids. Le tri reste sensible aux pages sans contact, mais un contact unique ne fait plus sauter le classement de 50 pts.

**B. Durcir le lissage conversion (maintenant)**

Passer le pseudo-compte de **30 → 50–80** (ou $\kappa_v = \min(80,\, n_{\text{type}}/2)$). Pour $n=100$, $\Delta x_v$ sur $0\to1$ contact passe de ~1,5 à ~1,0 — bruit divisé par ~1,5.

**C. Lissage temporel du score affiché (maintenant, effort faible)**

Conserver le calcul instantané pour le diagnostic, mais afficher :

$$
\text{CPI}_{\text{affiché}} = \text{round}(0{,}7\cdot\text{CPI}_t + 0{,}3\cdot\text{CPI}_{t-1})
$$

Un contact entrant/sortant de la fenêtre glissante ne bouge plus le tri du jour au lendemain ; le signal reste visible en 2–3 jours.

**À éviter maintenant :** baisser $w_v$ seul en dessous de 0,25 — le CPI perdrait son lien avec l'objectif business sans gain de stabilité proportionnel.

| Option | Gain stabilité | Risque | Verdict |
|---|---|---|---|
| Compression $z_v$ | Élevé | Faible | **1er choix** |
| Pseudo-compte ↑ | Moyen | Faible | **2e choix** |
| EMA 70/30 | Élevé sur le bruit | Retard 1–2 j | **3e choix** |
| Baisser $w_v$ | Moyen | Perte de sens métier | Secondaire |

---

### 2. Validation à cible rare

Spearman(CPI, Δcontacts) à $n=51$ (grade A/B) et ~70 % d'ex æquo sur Δ=0 est **sous-puissant par construction**. Ce n'est pas un échec du modèle — c'est un plafond statistique.

**Métriques fiables à ce volume :**

1. **Kendall $\tau$ sur le score continu** (déjà prévu §5) — plus robuste aux ties que Spearman sur entiers.
2. **Top-K overlap** : stabilité du top 10 / bottom 10 sur 7 jours glissants (objectif : Jaccard > 0,7).
3. **Décile lift** : contacts des 28 j suivants dans le décile CPI le plus bas vs le reste — ratio > 2× déjà significatif à 10 contacts/mois.
4. **Permutation test** : p-value sur le lift décile (1000 permutations, faisable en SQL).
5. **Backtest par dates** : 3–4 snapshots espacés de 28 j (pas une seule date t0).

**Anti-surapprentissage :** ne recalibrer qu'**une constante à la fois** (pseudo-compte, puis compression, puis poids ±0,05), avec re-test Kendall §5 à chaque pas. Pas de grid search multi-paramètres : avec ~4 points de validation indépendants, le surajustement est garanti.

---

### 3. Agrégation sigmoïde × $M \times G$

**Défendable pour un indice ordinal à faible volume.** La sigmoïde borne naturellement ; $M$ et $G$ en multiplicateurs évitent qu'une bonne perf SEO compense une LCP catastrophique — cohérent avec l'usage éditorial.

**Le compensatoire n'est pas le vrai problème** : avec $z_v$ dominant, une page « zéro contact » reste pénalisée même si capture/rétention sont excellentes. Le souci est la **dominance + bruit** de $z_v$, pas la forme additive en amont.

**Amélioration légère (optionnelle, effort moyen) :** gate sur la conversion seule :

$$
S' = 0{,}30 z_c + 0{,}15 z_r + 0{,}20 z_l + 0{,}35\cdot\min(z_v,\, z_v^{\text{cap}})
$$

avec $z_v^{\text{cap}}=1{,}5$ — plafond doux sans refonte de l'agrégation.

---

### 4. Capture à ~6 % de couverture GSC

**Biais probable : modéré à fort, direction incertaine.** Les requêtes masquées sont le long tail ; si leur CTR est plus bas que la moyenne exposée, $e$ est **surestimé** → $x_c$ **sous-estimé** (page mieux qu'elle n'apparaît). L'ampleur typique : **10–30 %** d'erreur sur $x_c$ quand couverture < 10 %, d'après la structure habituelle des distributions GSC.

**Correctif simple (maintenant) :**

$$
x_c^{\text{shrunk}} = x_c \cdot \sqrt{\frac{i_{\text{qpd}}}{i_{\text{nb}}}}
$$

Rétrécit $x_c$ vers 0 quand la couverture est faible — même logique que l'EB, implémentable en une ligne SQL. Alternative : élargir le grade C quand `couv_gsc_pct < 15` pour ne pas trier agressivement sur une capture douteuse.

**À volume ×10 :** modèle à deux strates (head vs tail) ou intervalle bootstrap sur les requêtes couvertes.

---

### 5. Standardisation type/global à 15 pages

**Discontinuité réelle mais secondaire.** Une page à $n=14$ dans son type bascule médiane/MAD globaux — décalage typique de **0,2–0,5** en $z_j$, soit **3–8 pts** CPI. Rare (types petits) et moins grave que le bruit conversion.

**Amélioration continue (effort faible) :**

$$
\lambda = \frac{n_{\text{type}}}{n_{\text{type}} + 15}, \quad m_j = \lambda m_j^{\text{type}} + (1-\lambda) m_j^{\text{global}}
$$

Idem pour $s_j$. Transition lisse, pas de seuil dur.

---

### 6. EB méthode des moments vs MLE

**Verdict : ne pas investir maintenant.** La revue interne le confirme : fixe→dynamique a un impact quasi nul sur le rang. La standardisation médiane/MAD en aval **absorbe** l'essentiel du lissage EB. Le vrai levier conversion reste le pseudo-compte fixe 30, pas $\kappa^{\text{ret/lec}}$.

**Exception :** corriger la variance binomiale dans $\kappa$ coûte ~10 lignes SQL ($v_{\text{adj}} = \max(v - \bar{m}(1-\bar{m})/\bar{n}, \varepsilon)$) — cosmétique, pas prioritaire.

---

### 7. Métriques de qualité du tri

| Métrique | Cible | Fréquence |
|---|---|---|
| Kendall $\tau$ inter-jours (J, J+7) | > 0,85 (A/B) | Hebdo |
| Jaccard top/bottom 10 | > 0,70 | Hebdo |
| Lift décile bas vs reste (contacts J+28) | > 2× | Mensuel |
| % pages grade C | Suivi | Quotidien |
| Verdicts « priorité haute » stables 14 j | > 60 % | Mensuel |

**nDCG** : utile seulement si vous fixez une relevance binaire (contact oui/non sur 28 j) — avec 10 contacts/mois, trop de ties ; préférer le **lift décile**.

---

## Propositions détaillées (format §7)

### P1 — Compression de $z_v$

- **Problème :** conversion domine le tri et saute de ±50 pts sur un contact. **Gravité : bloquante.**
- **Solution :** $z_v' = \operatorname{sign}(z_v)\sqrt{|z_v|}$ avant $S$.
- **Faisabilité :** maintenant. Réduit l'écart-type effectif de $z_v$ de ~37 %.
- **Effort SQL :** faible (1 ligne dans `scored`).
- **Validation :** Kendall inter-jours ↑ ; simulation ±1 contact sur pages grade A → ΔCPI médian < 20 pts.

### P2 — Pseudo-compte conversion 30 → 60

- **Problème :** $x_v$ trop réactif. **Gravité : bloquante.**
- **Solution :** remplacer 30 par 60 dans $x_v$.
- **Faisabilité :** maintenant.
- **Effort SQL :** faible.
- **Validation :** corrélation v2.1↔v2.2 était 0,9855 ; viser > 0,97 ; ablation §4 ne doit pas améliorer ρ de > 0,05.

### P3 — EMA 70/30 sur CPI affiché

- **Problème :** volatilité jour-à-jour. **Gravité : amélioration.**
- **Solution :** stocker `cpi_raw` instantané + `cpi` lissé dans `cpi_daily`.
- **Faisabilité :** maintenant (historique `cpi_daily` existe).
- **Effort SQL :** faible.
- **Validation :** Jaccard top-10 ↑ de 0,5–0,6 vers > 0,7.

### P4 — Rétrécissement capture par couverture GSC

- **Problème :** extrapolation à 6 % couverture. **Gravité : amélioration.**
- **Solution :** $x_c \leftarrow x_c \cdot \sqrt{i_{\text{qpd}}/i_{\text{nb}}}$.
- **Faisabilité :** maintenant.
- **Effort SQL :** faible.
- **Validation :** pages `couv_gsc_pct < 10` — corrélation capture vs Δclics GSC J+28.

### P5 — Mélange continu type/global (médiane/MAD)

- **Problème :** discontinuité à 15 pages/type. **Gravité : cosmétique.**
- **Solution :** $\lambda = n_{\text{type}}/(n_{\text{type}}+15)$.
- **Faisabilité :** maintenant.
- **Effort SQL :** moyen.
- **Validation :** max $|\Delta z|$ sur pages proches du seuil 15.

---

## Top 3 changements à tenter en premier

1. **Compression $\sqrt{|z_v|}$** — attaque la cause racine (dominance + saturation) sans changer le sens métier. Effort minimal.
2. **Pseudo-compte conversion 30 → 60** — réduit le bruit à la source, complémentaire de P1.
3. **EMA 70/30 sur le CPI affiché** — stabilise l'outil éditorial immédiatement ; les signaux $z$ restent instantanés pour le diagnostic.

Ensemble, ces trois changements devraient ramener les sauts « 1 contact = ±50 pts » vers **±15–25 pts**, tout en gardant le CPI orienté contacts.

---

## Perspectives nouvelles

- **Score en deux volets :** `CPI_priorité = f(z_c, z_r, z_l)` pour le tri éditorial SEO, badge conversion séparé quand `val > 0`. Évite le dilemme poids/bruit sans sacrifier la visibilité business.
- **Horizon 56 j pour $z_v$ seul** (28 j pour le reste) — les contacts sont si rares qu'une fenêtre double sur la conversion seule peut stabiliser sans noyer le signal.
- **Simulation Monte Carlo en SQL** : bootstrap des contacts sur 1000 tirages pour estimer l'intervalle de confiance du rang de chaque page — faisable, lourd, utile surtout pour expliquer au client pourquoi une page grade C ne doit pas être priorisée.

---

## Erreurs factuelles dans le prompt source

Aucune erreur de formule ou de raisonnement majeure. Seul écart relevé : $R^2\approx0{,}92$ (§4.2) vs **0,917** mesuré (dry-run §3).
