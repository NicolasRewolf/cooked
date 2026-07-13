> ⚠️ Archive du 18/06/2026 — revue experte close le 18/06/2026, verdict : outil suffisant, ne pas complexifier.

# Prompt — Revue critique experte du « Cooked Page Index » (CPI v2.2)

> **Comment utiliser ce document.** Copiez-le tel quel à un·e mathématicien·ne,
> statisticien·ne ou IA experte. Il est autoportant : contexte, contraintes,
> modèle complet, ce qui est déjà connu, et les questions précises sur
> lesquelles un regard neuf est attendu.

---

## 1. Votre rôle et votre mission

Vous êtes un·e expert·e en **statistiques appliquées / data science / théorie
de la décision et des indices composites**. On vous soumet un indice de scoring
opérationnel (le CPI) déjà en production. **Votre mission :**

1. **Évaluer le modèle de façon critique** — hypothèses fragiles, biais,
   incohérences, choix arbitraires.
2. **Proposer des améliorations concrètes**, hiérarchisées par rapport
   gain/risque, **et réalistes compte tenu des contraintes de données (§3)**.
3. **Apporter des perspectives nouvelles** : approches, métriques de validation,
   reformulations que nous n'aurions pas envisagées.

**Trois règles impératives pour que votre retour soit exploitable :**

- **Vérifiez par le calcul.** N'affirmez rien sur le comportement du modèle sans
  l'avoir vérifié sur les formules fournies. *(Une revue précédente contenait
  deux erreurs factuelles dues à des suppositions non vérifiées — un seuil
  ignoré dans une formule, et un exemple chiffré faux.)*
- **Tenez compte du volume de données (§3).** Une méthode plus sophistiquée mais
  **plus bruitée à notre échelle est une régression, pas une amélioration**.
  Toute proposition gourmande en données doit être accompagnée d'un argument de
  faisabilité à notre volume — sinon, classez-la explicitement « à reconsidérer
  si le volume est multiplié par ~10 ».
- **Distinguez le but** : c'est un indice **ordinal de tri** pour prioriser un
  travail éditorial, **pas** un estimateur de précision ni une probabilité. Les
  critères de qualité pertinents sont donc la **stabilité du classement**, le
  **pouvoir discriminant**, et la **valeur prédictive** vis-à-vis des contacts.

---

## 2. Ce que mesure le CPI (contexte métier)

Score de santé **entier ∈ [0,100], par page web**, recalculé chaque jour sur une
fenêtre glissante de **D = 28 jours**, pour le site d'un **cabinet d'avocats**.
Objectif : repérer les pages à améliorer (capter plus de trafic qualifié, mieux
le retenir, le convertir en prises de contact). Il croise deux sources :

- **Google Search Console (GSC)** : par (jour, page, requête) — impressions,
  clics, position SERP moyenne.
- **Analytics propriétaire** : événements first-party (`pageview`, `page_exit`
  avec durée + profondeur de scroll, `web_vitals`, clics téléphone, clics
  « prendre RDV », soumissions de formulaire) + reconstruction de parcours de
  conversion.

Chaque page est rattachée à un **type** τ ∈ {accueil, hub, page-service, article
de blog, page-nav}. Les comparaisons entre pages se font **par type**.

---

## 3. Contraintes de données (déterminantes)

- **~185 pages** scorées.
- **~10 prises de contact (« conversions ») par MOIS**, tous canaux confondus —
  c'est la cible business, et elle est **rare**.
- **28 à 35 jours d'historique** seulement (outil jeune) ; un snapshot quotidien
  est archivé depuis peu.
- **Couverture GSC partielle** : Google masque les requêtes rares ; la table
  (page × requête) ne couvre parfois que **~6 %** des impressions d'une page.
- **Implémentation** : SQL Postgres pur (fonction unique, pas de pipeline ML
  externe). Les méthodes proposées doivent être implémentables raisonnablement
  dans cet environnement, ou justifier leur coût.

Conséquence assumée : le modèle privilégie la **robustesse à faible volume**
(estimateurs robustes, lissage bayésien, bornage) plutôt que la finesse
asymptotique.

---

## 4. Le modèle (v2.2) — formules exactes

Notations : page $p$, type $\tau(p)$, fenêtre courante $W_1$ et précédente $W_0$
(chacune $D$ jours). Toutes les mesures SEO excluent les requêtes de marque.

### 4.1 Score final
$$
\text{CPI}(p)=\min\!\Big(100,\;100\cdot\sigma\!\big(\tfrac{S(p)}{T}\big)\cdot M(p)\cdot G(p)\Big),
\quad
S(p)=\sum_{j\in\{c,r,l,v\}} w_j\,z_j(p),
$$
avec $\sigma(u)=(1+e^{-u})^{-1}$, température $T=0{,}8$, poids
$(w_c,w_r,w_l,w_v)=(0{,}30,\,0{,}15,\,0{,}20,\,0{,}35)$. Point neutre :
$z_j=0\Rightarrow\text{CPI}=50\,MG$. Les $z_j$ sont des écarts standardisés
robustes (§4.6) de quatre signaux latents.

### 4.2 Capture $x_c$ (acquisition SEO)
Courbe de CTR du site estimée par régression log–log sur 90 j (loi de puissance,
$R^2\approx0{,}92$) : $\widehat{\text{ctr}}(x)=e^{\alpha}x^{\beta}$, $x$=position.
Clics attendus par **standardisation indirecte** (on calcule l'attendu sur la
strate de requêtes couverte, puis on l'extrapole au volume non-marque total) :
$$
e(p)=\Big[\textstyle\sum_q \text{impr}_{p,q}\,\widehat{\text{ctr}}(\text{pos}_{p,q})\Big]\cdot\frac{i_{\text{nb}}(p)}{i_{\text{qpd}}(p)},
\qquad
x_c(p)=\ln\frac{o(p)+3}{e(p)+3},
$$
où $o$ = clics observés (non-marque), $i_{\text{nb}}$ = impressions non-marque
totales, $i_{\text{qpd}}$ = impressions de la strate couverte.

### 4.3 Rétention $x_r$ et lecture $x_l$ (cascade + Empirical Bayes dynamique)
Entrées organiques $n(p)$. *Retenue* si durée ≥ 15 s **ou** ≥ 2 pages vues
($r(p)$). *Lue en profondeur* (parmi retenues) si durée et scroll ≥ médianes du
type ($k(p)$). Taux moyens du type : $\rho_\tau=\frac{\sum r}{\sum n}$,
$\psi_\tau=\frac{\sum k}{\sum r}$.

**Pseudo-compte EB estimé par type** (Beta-Binomial, méthode des moments ;
$m$ = taux moyen, $v$ = variance inter-pages des taux) :
$$
\kappa_\tau=\operatorname{clip}\!\Big(\frac{m(1-m)}{v}-1,\;5,\;200\Big)\quad(\text{repli }20).
$$
$$
x_r(p)=\operatorname{logit}\frac{r+\kappa^{\text{ret}}_\tau\rho_\tau}{n+\kappa^{\text{ret}}_\tau},
\qquad
x_l(p)=\operatorname{logit}\frac{k+\kappa^{\text{lec}}_\tau\psi_\tau}{r+\kappa^{\text{lec}}_\tau}.
$$

### 4.4 Conversion $x_v$
$\text{val}(p)=d(p)+a(p)+b(p)$ : contacts directs $d$ (page d'entrée du
parcours), assists $a(p)=\sum_{J\ni p,\,p\neq\text{entrée}}\frac{1}{|J|}$
(crédit dilué par longueur de parcours), bookings $b=0{,}25\times$(clics RDV).
Prior $\nu_\tau=\frac{\sum\text{val}}{\sum n}$ (pseudo-compte **fixe** 30) :
$$
x_v(p)=\ln\frac{\text{val}(p)+30\,\nu_\tau+0{,}05}{n(p)+30}.
$$

### 4.5 Momentum $M$ (tendance, transition continue)
Clics page $c_1,c_0$ (fenêtres courante/précédente), clics site $s_1,s_0$,
positions $p_1,p_0$. Poids de mélange $w=\sigma\!\big(\frac{(c_1+c_0)-20}{5}\big)$ :
$$
L=(1-w)\big(-0{,}08(p_1-p_0)\big)+w\Big(\ln\tfrac{c_1+5}{c_0+5}-\ln\tfrac{s_1+50}{s_0+50}\Big),
$$
$$
M=\exp\!\big(\operatorname{clip}(L,-0{,}336,\,0{,}336)\big)\in[0{,}714,\,1{,}40].
$$
(La soustraction de la croissance du site rend le momentum *relatif* : une marée
qui touche tout le site ne pénalise personne.)

### 4.6 Standardisation robuste → $z_j$
Par type si ≥ 15 pages, sinon global. $m_j$ = médiane,
$s_j=\max(1{,}4826\cdot\text{MAD}(x_j),\,0{,}15)$,
$z_j=\operatorname{clip}\!\big(\frac{x_j-m_j}{s_j},-3,3\big)$.

### 4.7 Gate technique $G$ et grades
$G=1-0{,}15\,\operatorname{clip}\!\big(\frac{\text{LCP}_{p75}-2500}{2500},0,1\big)\in[0{,}85,1]$
(pénalité **nulle** sous 2500 ms). Grade de confiance : **A** si $n\ge100$ et
clics attendus $\ge20$ ; **B** si $n\ge30$, attendus $\ge5$ ; **C** sinon.

---

## 5. Ce que nous savons déjà (ne pas réinventer)

- **Analyse de sensibilité (décomposition de variance exacte, $S$ linéaire) :**
  la **conversion porte 65 % de la variance** du score (vs poids nominal 35 %),
  parce que $z_v$ est le plus dispersé ($\sigma\approx1{,}58$) — il sature à
  $\pm3$ et sépare surtout « 0 contact » de « quelques contacts ». **Le CPI est
  donc de facto un score de conversion**, porté par le signal **le moins abondant
  en données**. *(C'est, selon nous, le point faible n°1.)*
- **Volatilité observée en production** : un seul contact entrant/sortant de la
  fenêtre de 28 j fait bouger une page fiable de **±50 points**.
- **Déjà adopté** (après une 1ʳᵉ revue) : momentum à transition continue (§4.5,
  élimine une discontinuité) ; EB dynamique pour rétention/lecture (§4.3).
- **Déjà écarté faute de volume** : Unbiased Learning-to-Rank / Position-Based
  Model (capture), analyse de survie par page (rétention), attribution
  markovienne / valeur de Shapley (conversion), intégrale de Choquet / TOPSIS
  (agrégation non-compensatoire), filtre de Kalman (momentum). Inutile de les
  represente **sauf** si vous démontrez leur robustesse à ~10 contacts/mois.
- **Limites connues** : poids fixés à dire d'expert ; température 0,8 et
  multiplicativité $M\cdot G$ non dérivées ; calibration CTR en loi de puissance
  qui sous-ajuste la courbure de la SERP en positions 9-13 ; EB conversion laissé
  à pseudo-compte fixe (trop peu de contacts par type pour l'estimer).

---

## 6. Vos questions de challenge (cœur de la demande)

Traitez en priorité celles où vous avez un apport réel ; ajoutez les vôtres.

1. **Le surpoids de la conversion (priorité).** Comment réconcilier un objectif
   *orienté contacts* avec la **fragilité** de $z_v$ (saturation, ±50 pts sur 1
   contact, ~10 contacts/mois) ? Faut-il : régulariser $z_v$ plus fortement
   (EB plus agressif, compression d'échelle, transformation) ? réduire/asseoir
   son poids ? lisser le CPI temporellement (le score devient une moyenne mobile
   plutôt qu'un instantané) ? Quelle option a le meilleur ratio gain/risque **à
   notre volume** ?
2. **Validation à cible rare.** Comment **valider et calibrer** un score dont la
   cible (contacts) est aussi rare (~10/mois, ~70-90 % d'ex æquo attendus sur la
   corrélation de rang) ? Quelles métriques de validation sont fiables à ce
   volume (au-delà d'un Spearman sous-puissant) ? Comment éviter le surapprentissage
   en recalibrant les hyperparamètres ?
3. **Agrégation.** La forme $\big[\text{somme pondérée}\big]\to$ sigmoïde,
   puis $\times M\times G$ multiplicatif : défendable, ou y a-t-il mieux **sans**
   exiger une calibration que nos données ne supportent pas ? Le mélange
   compensatoire est-il un vrai problème ici (la conversion étant déjà dominante)
   ou un faux procès ?
4. **Capture à faible couverture.** L'extrapolation
   $e=e_{\text{qpd}}\cdot i_{\text{nb}}/i_{\text{qpd}}$ suppose l'homogénéité du
   CTR entre requêtes exposées et masquées. À ~6 % de couverture, quelle est
   l'ampleur probable du biais, et existe-t-il un estimateur plus robuste
   (intervalle, rétrécissement) implémentable simplement ?
5. **Standardisation par type avec repli à 15 pages** : la bascule type/global
   introduit-elle une discontinuité ou une instabilité problématique ? Mieux :
   un rétrécissement continu type↔global (style modèle hiérarchique léger) ?
6. **EB par méthode des moments.** Notre $\kappa_\tau$ ne corrige pas la variance
   binomiale intra-page (donc sous-lisse possiblement). Vaut-il l'effort de
   passer à un vrai estimateur (MLE Beta-Binomial, ou hiérarchique) compte tenu
   que la standardisation médiane/MAD en aval absorbe une grande partie de
   l'effet (impact mesuré du passage fixe→dynamique : quasi nul sur le rang) ?
7. **Métrique de qualité du tri.** Pour un indice **ordinal**, quels critères
   devrions-nous optimiser et suivre (stabilité de Kendall dans le temps, gain
   cumulé type nDCG vis-à-vis des contacts, pouvoir séparateur) — et comment les
   mesurer proprement à notre volume ?

---

## 7. Format de réponse attendu

Pour chaque proposition retenue, indiquez :

- **Problème visé** et **gravité** (bloquant / amélioration / cosmétique).
- **Solution** : formulation mathématique précise + intuition.
- **Faisabilité à notre volume** (§3) : « maintenant » / « à volume ×10 » /
  « impossible ici » — avec justification (et idéalement un ordre de grandeur du
  bruit d'estimation attendu).
- **Effort d'implémentation** en SQL Postgres (faible / moyen / lourd).
- **Comment la valider** (test, métrique, donnée nécessaire).

Terminez par un **classement des 3 changements les plus rentables** à tenter en
premier, et signalez **toute erreur factuelle** que vous trouvez dans ce
document (formules, chiffres, raisonnements) — vérifiée par le calcul.

---

## Annexe — code source de référence

L'implémentation SQL Postgres complète (~120 lignes, fonction
`cooked_page_index`) est disponible sur demande et fait foi en cas de doute sur
une formule. Les constantes (lissages $+3$, $+5/+50$, bornes de clip, seuils de
grade) y sont explicites. Demandez-la si vous souhaitez auditer l'implémentation
ligne à ligne plutôt que les formules de §4.
