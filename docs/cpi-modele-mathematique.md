# CPI — Cooked Page Index : spécification mathématique

> Document destiné à une relecture par un mathématicien / statisticien.
> Il décrit **exactement** le modèle tel qu'implémenté dans la fonction
> Postgres `cooked_page_index(p_days)` (le code SQL source est reproduit en
> annexe A pour vérifiabilité). Toute formule ci-dessous est traçable au code.
>
> **Version du modèle : v2.2 (16/06/2026).** Évolutions vs v2.1, adoptées après
> une revue externe (cf. §13) : (1) **momentum à transition continue**, (2)
> **lissage empirical Bayes dynamique** (Beta-Binomial par type) pour la
> rétention et la lecture. Le reste (capture, conversion, standardisation,
> gate, agrégation) est inchangé. Fenêtre par défaut : $D = 28$ jours.
>
> **Mise à jour du 03/09/2026 (mission T-14, constat f-06).** La copie du code en annexe A avait
> dérivé de la prod pendant 39 jours (momentum, grades, filtre brandé) : elle est **retirée**, la
> source de vérité est `supabase/rpcs.sql` (marqueur `public.cooked_page_index(p_days integer)`,
> régénéré depuis la prod en CI). Écarts entre ce texte (v2.2) et la prod du 03/09/2026 :
> - **grades** : $\{S,A,B,C\}$ depuis le 23/07/2026 ($S$ : $n_{org}\ge200 \wedge e\ge40$) ;
> - **brandé** : `gsc_is_branded(query)` (vecteurs `contracts/branded_query_vectors.json`)
>   remplace `query ~* 'plouton'` (10/07/2026) ;
> - **fenêtres** : 28 jours **clos à `gsc_last_data_day()`** pour GSC et pour $z_v$
>   (`conversion_journeys(p_days, gsc_last_data_day())`), plus aucune borne d'horloge (T-05, T-09) ;
> - **momentum (§8)** : $c_1,c_0$ = clics **totaux** de la page (`gsc_path_daily`) **moins** les clics
>   brandés révélés (`gsc_query_page_daily` ∩ brandé) ; du 25/07 au 03/09 la prod ne lisait que la
>   traîne de requêtes révélées (16-28 % des clics) — corrigé T-06 (restatement annoté) ;
> - `cpi_opportunite_contact.potentiel` = `cpi_compose(zc, zr, zl, 0, 1, 1, true)` (sans momentum ni gate).

---

## 1. Contexte et objectif

Le CPI est un **score de santé $\in [0,100]$ calculé par page web**, pour le
site d'un cabinet d'avocats. Il agrège, sur une fenêtre glissante de $D$ jours,
quatre dimensions hétérogènes mesurées sur deux sources :

- **Google Search Console (GSC)** — données de référencement : pour chaque
  (jour, page, requête) : impressions, clics, position moyenne dans la SERP.
- **Analytics propriétaire (« Cooked »)** — événements first-party côté
  navigateur : `pageview`, `page_exit` (durée, profondeur de scroll),
  `web_vitals`, clics de contact, soumissions de formulaire ; plus une
  reconstruction de parcours de conversion (`conversion_journeys`).

L'objectif est **opérationnel** : trier les pages pour prioriser le travail
éditorial. Le score n'est pas une probabilité ; c'est un **indice ordinal
borné**. Doctrine d'usage : *« le CPI trie, les quatre $z$ diagnostiquent »*.
Chaque page reçoit un **grade de confiance** $\in \{S,A,B,C\}$ (volume de données ; $S$ depuis le 23/07/2026)
et la comparaison entre pages se fait **par type** (§2).

**Contrainte de données majeure** (déterminante pour les choix de §13) :
~185 pages, **~10 contacts/mois**, 28–35 j d'historique, couverture GSC
parfois ~6 %. Le modèle est délibérément conçu pour la **robustesse à faible
volume**, pas pour la finesse asymptotique.

---

## 2. Notations, ensembles et dimensions

On fixe une page $p$ et une fenêtre courante $W_1 = [\,t_0 - D,\; t_0\,]$.
La fenêtre précédente $W_0 = [\,t_0 - 2D,\; t_0 - D\,]$ sert au momentum.
Type $\tau(p) \in \{$ `cabinet`, `hub`, `expertise`, `post`, `blog-nav` $\}$.

| Symbole | Définition | Dimension / domaine |
|---|---|---|
| $\text{pos}$ | position moyenne SERP | réel $\geq 1$, sans dim. |
| $\text{impr}, \text{clk}$ | impressions, clics GSC | comptes $\in \mathbb{N}$ |
| $\text{ctr}$ | clics/impressions | $\in [0,1]$ |
| $n(p)$ | entrées organiques (1er pageview de session, canal organique) | compte |
| $r(p)$ | entrées **retenues** | compte, $r \le n$ |
| $k(p)$ | entrées **lues en profondeur** (parmi retenues) | compte, $k \le r$ |
| $d_{\text{dur}}$ | durée de visite (`duration_seconds`) | secondes |
| $s$ | scroll max (`max_scroll`) | $\in [0,100]$, % |
| $\ell$ | LCP, p75 mobile | millisecondes |
| $\text{val}(p)$ | « valeur de conversion » agrégée (§6) | sans dim. |
| $x_c, x_r, x_l, x_v$ | signaux latents | log-ratios / logits, sans dim. |
| $z_c, z_r, z_l, z_v$ | versions standardisées robustes écrêtées | $\in [-3,3]$ |
| $M$ | momentum | $\in [0.714, 1.40]$ |
| $G$ | gate LCP | $\in [0.85, 1]$ |
| $\text{CPI}(p)$ | score final | entier $\in [0,100]$ |

Mesures de référencement hors **branded** (`gsc_is_branded(query)` — historiquement `query ~* 'plouton'`).
$o(p)$ = clics non-branded observés, $e(p)$ = attendus. **Inclusion** :
$n(p)\ge5$ et $n_{\text{exits}}(p)\ge3$.

---

## 3. Vue d'ensemble

$$
\text{CPI}(p) = \min\!\Big(100,\;
100 \cdot \sigma\!\Big(\tfrac{S(p)}{T}\Big)\cdot M(p)\cdot G(p)\Big),
\qquad
S(p) = \sum_{j} w_j\, z_j(p)
$$

$\sigma(u)=(1+e^{-u})^{-1}$, température $T=0.8$, poids
$(w_c,w_r,w_l,w_v)=(0.30,0.15,0.20,0.35)$. Point neutre : $z_j=0 \Rightarrow
\text{CPI}=50\,MG$.

---

## 4. Capture — clics réels vs attendus ($x_c$) *(inchangé v2.1)*

### 4.1 Courbe de CTR du site (loi de puissance)
Régression log–log sur 90 j, hors branded, positions $j\in\{1,\dots,20\}$ avec
$\ge200$ impressions, CTR empirique lissé $\widehat{\text{ctr}}_j=\frac{\sum\text{clk}+1}{\sum\text{impr}+20}$ :
$$\ln\widehat{\text{ctr}}_j=\alpha+\beta\ln j+\varepsilon_j \;\Rightarrow\; \widehat{\text{ctr}}(x)=e^\alpha x^\beta\quad(R^2\approx0{,}917).$$

### 4.2 Standardisation indirecte
$$e_{\text{qpd}}(p)=\sum_q \text{impr}_{p,q}\,\operatorname{clip}\!\big(e^{\alpha+\beta\ln\max(\text{pos}_{p,q},1)},0{,}0005,0{,}5\big),\quad
e(p)=e_{\text{qpd}}(p)\frac{i_{\text{nb}}(p)}{i_{\text{qpd}}(p)}.$$

### 4.3 Signal
$$\boxed{\,x_c(p)=\ln\frac{o(p)+3}{e(p)+3}\,}\quad(x_c=0\text{ si }e\text{ indéfini}).$$

---

## 5. Rétention et lecture — cascade + EB dynamique ($x_r, x_l$) *(modifié v2.2)*

Entrées organiques $n(p)$. *Retenue* si durée $\ge15$ s **ou** $\ge2$ pages.
Seuils par type $\theta^{\text{dur}}_\tau,\theta^{\text{scr}}_\tau$ = médianes des
retenues. *Lue en profondeur* si $d_{\text{dur}}\ge\theta^{\text{dur}}_\tau$ **et**
$s\ge\theta^{\text{scr}}_\tau$. Taux moyens du type :
$\rho_\tau=\frac{\sum r}{\sum n}$, $\psi_\tau=\frac{\sum k}{\sum r}$.

### 5.1 Pseudo-compte dynamique (Beta-Binomial, méthode des moments) — **nouveau**
En v2.1 le lissage utilisait un pseudo-compte **fixe** ($=20$). En v2.2, la
force du lissage $\kappa_\tau$ (= concentration $\alpha+\beta$ de la loi Beta a
priori) est **estimée par type** depuis la dispersion observée des taux par
page. Pour la rétention, sur les pages du type ayant $n_p\ge10$ : moyenne
$m=\rho_\tau$ et variance $v=\operatorname{Var}_p(r_p/n_p)$, puis
$$
\boxed{\;\kappa^{\text{ret}}_\tau=\operatorname{clip}\!\Big(\frac{m(1-m)}{v}-1,\;5,\;200\Big)\;}
\qquad(\text{repli } \kappa=20 \text{ si }<5\text{ pages ou }v\notin(0,m(1-m))).
$$
Idem pour la lecture avec $m=\psi_\tau$ et $v=\operatorname{Var}_p(k_p/r_p)$
(pages à $r_p\ge10$) $\to \kappa^{\text{lec}}_\tau$. **Interprétation** : type
homogène (faible $v$) $\Rightarrow \kappa$ grand $\Rightarrow$ fort retrait vers
la moyenne ; type dispersé $\Rightarrow \kappa$ petit $\Rightarrow$ on fait
davantage confiance à l'observation. *(Limite assumée : la méthode des moments
naïve ne retranche pas la variance binomiale intra-page ; les bornes $[5,200]$
contiennent les estimations aberrantes. Cf. §13.)*

### 5.2 Signaux latents
$$
\boxed{\,x_r(p)=\operatorname{logit}\frac{r(p)+\kappa^{\text{ret}}_\tau\,\rho_\tau}{n(p)+\kappa^{\text{ret}}_\tau}\,},
\qquad
\boxed{\,x_l(p)=\operatorname{logit}\frac{k(p)+\kappa^{\text{lec}}_\tau\,\psi_\tau}{r(p)+\kappa^{\text{lec}}_\tau}\,}
$$
(taux écrêté dans $[0{,}001,0{,}999]$ avant logit). Lecture conditionnée aux
retenues ($k\le r$) : orthogonalité par construction.

---

## 6. Conversion ($x_v$) *(inchangé v2.1)*

$\text{val}(p)=d(p)+a(p)+b(p)$ : directs $d$ (entrée = $p$), assists
$a(p)=\sum_{J:\,p\in J,\,p\ne\text{entry}}\frac{1}{|J|}$, bookings
$b(p)=0{,}25\times(\#\,\text{cta\_booking})$. Prior
$\nu_\tau=\frac{\sum\text{val}}{\sum n_{\text{org}}}$ (pseudo-compte fixe 30,
$\varepsilon=0{,}05$) :
$$\boxed{\,x_v(p)=\ln\frac{\text{val}(p)+30\,\nu_\tau+0{,}05}{n(p)+30}\,}.$$
*(EB volontairement laissé fixe ici : trop peu de contacts par type pour
estimer $\kappa$ de façon fiable — cf. §13.)*

> **Entrée des données (12/07/2026)** : `conversion_journeys` est depuis le
> 12/07/2026 la **v2 « recousue »** — parcours reconstruits sur le visiteur
> recousu via `identity_stitch` (sessions coupées par l'ancien bug de
> rotation d'ids recollées). Restatement du `cpi_daily` du 12/07 : seul
> $x_v$ (donc $z_v$) bouge, **0 changement de grade**. La formule ci-dessus
> est inchangée.

---

## 7. Standardisation robuste (médiane / MAD) → $z_j$ *(inchangé v2.1)*

Par type si $\ge15$ pages, sinon global. $m_j$ = médiane,
$s_j=\max(1{,}4826\cdot\operatorname{median}|x_j-m_j|,\,0{,}15)$,
$$\boxed{\,z_j=\operatorname{clip}\!\big(\tfrac{x_j-m_j}{s_j},-3,3\big)\,}.$$

---

## 8. Momentum — transition continue ($M$) *(modifié v2.2)*

Clics page courant/précédent $c_1,c_0$ ; clics site $s_1,s_0$ ; positions
$p_1,p_0$. **En v2.1**, la log-variation $L$ basculait *discrètement* à
$c_1+c_0=20$ entre un régime « position » et un régime « clics », créant une
**discontinuité** (un gain de 1 clic franchissant le seuil changeait
l'équation). **En v2.2**, les deux régimes sont mélangés par un poids continu
$$
w(p)=\sigma\!\Big(\frac{(c_1+c_0)-20}{5}\Big)\in(0,1),
$$
$$
\boxed{\;L(p)=\big(1-w\big)\underbrace{\big(-0{,}08\,(p_1-p_0)\big)}_{\text{régime position}}
+\;w\,\underbrace{\Big(\ln\tfrac{c_1+5}{c_0+5}-\ln\tfrac{s_1+50}{s_0+50}\Big)}_{\text{régime clics, relatif au site}}\;}
$$
$$
M(p)=\exp\!\big(\operatorname{clip}(L(p),-0{,}336,0{,}336)\big)\in[0{,}714,1{,}40].
$$
$w\to0$ à faible volume (on lit la position), $w\to1$ à fort volume (on lit la
croissance relative des clics) ; **plus de saut**. La soustraction de la
croissance du site rend le momentum *relatif*. Badge : ↗ si $M\ge1{,}15$, ↘ si
$M\le0{,}87$.

---

## 9. Gate technique — LCP ($G$) *(inchangé v2.1)*

$\ell$ = p75 LCP mobile (défaut $2500$ ms $\Rightarrow$ gate neutre) :
$$\boxed{\,G(p)=1-0{,}15\,\operatorname{clip}\!\big(\tfrac{\ell-2500}{2500},0,1\big)\in[0{,}85,1]\,}.$$
**Pénalité nulle sous $2500$ ms** (seuil « good » Google), bornée à $-15\%$.

---

## 10. Agrégation finale *(inchangé v2.1)*

$$S=0{,}30z_c+0{,}15z_r+0{,}20z_l+0{,}35z_v,\quad
\text{CPI}=\min\!\big(100,\,100\,\sigma(S/0{,}8)\,M\,G\big).$$
Grades : $A$ si $n\ge100,e\ge20$ ; $B$ si $n\ge30,e\ge5$ ; $C$ sinon.

---

## 11. Tableau des hyperparamètres

| Param. | Valeur | Rôle |
|---|---|---|
| $D$ | 28 j | fenêtre |
| fit CTR | 90 j, pos. 1–20, ≥200 impr., lissage $+1/+20$ | $(\alpha,\beta)$ |
| clip CTR | $[0{,}0005,0{,}5]$ | bornes courbe |
| lissage capture | $+3$ | régularise $x_c$ |
| **EB rétention/lecture** | **$\kappa_\tau$ dynamique (Beta-Binomial, moments), borné $[5,200]$, repli 20** | force du prior, **adaptée par type (v2.2)** |
| EB conversion | pseudo-comptes 30, $\varepsilon=0{,}05$ (fixe) | régularise $x_v$ |
| poids booking / dilution assist | $0{,}25$ / $1/|J|$ | conversion |
| MAD | $1{,}4826$, plancher $0{,}15$ ; clip $z$ $[-3,3]$ | échelle robuste |
| bascule type/global | 15 pages | granularité référence |
| seuil rétention | $\ge15$ s **ou** $\ge2$ pages | définition « retenu » |
| **momentum** | **mélange continu $w=\sigma((c_1+c_0-20)/5)$** ; clip $L\in[\pm0{,}336]$ ; lissage $+5/+50$ ; coef pos. $-0{,}08$ | **transition continue (v2.2)** |
| gate LCP | seuil 2500 ms, pénalité max 15 % | technique |
| poids agrégation | $(0{,}30,0{,}15,0{,}20,0{,}35)$ ; température $T=0{,}8$ | importance dimensions |
| inclusion | $n\ge5,\ n_{\text{exits}}\ge3$ | seuil minimal |

---

## 12. Propriétés, validation, sensibilité

**Propriétés.** $\text{CPI}\in[0,100]$ ; croissant en chaque $z_j$ ; point
neutre $50\,MG$ ; momentum désormais **continu** en $(c_1,c_0,p_1,p_0)$.

**Validation empirique — tir réel du 11/07/2026 : VALIDÉ** (protocole
`cpi_validation_j28.sql`, t0 = 10/06/2026). §0 recomposition exacte du score
depuis les $z$ stockés (194/194, écart 0) ; §3 calibration CTR $R^2=0{,}931$
(médiane $|\text{obs}-\text{préd}|$ = 20,5 %, indicateur de suivi non liant —
courbure SERP mal captée en pos. 9–13, candidat fit 2 segments) ; §5 stabilité
des poids Kendall $\tau_b\ge0{,}952$ sur les 8 perturbations ±0,05. Bonus
prédictif (non liant) : ratio de taux de contact futur tiers haut/bas = 3,11
(score complet) vs 0,10 (sans conversion) → le signal prédictif vient de la
**mémoire de conversion** de $z_v$, pas des composantes comportementales.
Libellé acté : **score de priorisation**, non prédicteur d'outcome à 28 j.
Limite connue : biais de taille (issue GitHub #19). Re-test diagnostic 56 j :
05/08/2026.

**Analyse de sensibilité (16/06/2026).** $S$ étant linéaire en $z$, la
décomposition de variance est exacte : $\text{part}_j=w_j\operatorname{Cov}(z_j,S)/\operatorname{Var}(S)$.

| Signal | poids nominal | **part de variance** | $\sigma(z_j)$ |
|---|---|---|---|
| capture | 0,30 | 0,15 | 0,93 |
| rétention | 0,15 | 0,07 | 1,03 |
| lecture | 0,20 | 0,13 | 1,11 |
| **conversion** | 0,35 | **0,65** | **1,58** |

→ **La conversion porte 65 % de la variance** (vs poids nominal 35 %), car
$z_v$ est le signal le plus dispersé (sature massivement à $\pm3$ : sépare « 0
contact » de « quelques contacts »). Le CPI est *de facto* dominé par le signal
le moins abondant en données — point **tranché au J+28 du 11/07/2026** (cf. §13).

---

## 13. Réponse à la revue externe (16/06/2026)

Une revue mathématique externe a confronté la v2.1 à l'état de l'art. Bilan.

**Adopté (v2.2) :**
- **Discontinuité du momentum** → corrigée par transition continue (§8). Vrai
  défaut de cohérence ordinale. *Sans* recourir au filtre de Kalman suggéré
  (inutilement lourd ici).
- **Pseudo-comptes EB figés** → rendus dynamiques par type (§5). *Effet pratique
  faible* (corr 0,9855 avec v2.1, 0 verdict A/B déplacé : la standardisation
  médiane/MAD en aval absorbe l'essentiel), mais plus rigoureux.
- **Analyse de sensibilité** (Sobol/variance) → réalisée analytiquement (§12).

**Écarté (disproportionné vs la contrainte de données, §1) :** ULTR / PBM /
TrustPBM (capture), Kaplan-Meier par page (rétention), attribution markovienne /
Shapley (conversion), intégrale de Choquet / TOPSIS (agrégation), filtre de
Kalman (momentum). Toutes gourmandes en données ; sur ~10 contacts/mois et
~150 visites/page, elles produiraient des estimations **plus bruitées** que les
heuristiques robustes actuelles. À reconsidérer si le volume est multiplié par
~10.

**Deux inexactitudes relevées dans la revue :**
1. *Gate LCP* — la revue affirme une pénalité « dès l'écart au zéro absolu » :
   faux, la formule (§9) a un seuil à 2500 ms ($G=1$ en deçà).
2. *Compensabilité* — la revue donne une page $z_c=3,z_r=z_v=-3$ comme obtenant
   « un score intermédiaire acceptable ». Calcul réel :
   $S=0{,}30(3)+0{,}15(-3)+0{,}20(-3)+0{,}35(-3)=-1{,}2\Rightarrow
   \text{CPI}\approx100\,\sigma(-1{,}5)\approx 18$ (« malade »). Le poids fort de
   la conversion gère déjà le cas.

**Point ouvert prioritaire — TRANCHÉ au J+28 (11/07/2026)** : le surpoids
effectif de la conversion (65 % de variance) sur un signal fragile désignait
comme levier une **régularisation plus forte de $z_v$** (EB conversion plus
agressif, ou compression de l'échelle). Le tir réel (§12) a montré que ce
surpoids porte le **seul signal prédictif** du score — la mémoire de
conversion (ratio tiers 3,11 avec conversion vs 0,10 sans) : re-régulariser
$z_v$ détruirait ce signal. **Décision : pas de re-régularisation de $z_v$,
v2.2 conservée telle quelle.**

---

## Annexe A — code source (source de vérité)

Le code n'est plus reproduit ici : la copie inline du 16/06/2026 avait dérivé de la prod
(momentum sur la traîne de requêtes révélées, grille A/B/C, filtre `plouton`) sans que personne
le voie — c'est le mécanisme par lequel le défaut f-01 de la mission du 02/09/2026 est resté
invisible 39 jours.

- **Corps exact en prod** : `supabase/rpcs.sql`, marqueur `-- ═══ public.cooked_page_index(p_days integer) ═══`
  (régénéré depuis la prod par le workflow `rpcs-regenerate`, sha comparé à la prod par `prod-drift`).
- **Helpers** : `cpi_compose`, `cpi_capture_perdue`, `cpi_opportunite_contact`, `cooked_cpi_snapshot`
  (même fichier).
- **Contract-tests nocturnes** qui gardent les propriétés décrites ici : `cpi_sans_horloge`
  (aucune borne `now()`/`current_date`), `cpi_momentum_source_complete` (momentum lu sur
  `gsc_path_daily`), `potentiel_sans_momentum_gate`.
- **Ruptures de série** (restatements annotés dans `annotations`) : 02/07, 12/07, 27/07, 03/09/2026 (×3) —
  liste dans `docs/cpi-cooked-page-index.md` et `docs/OPERATIONS.md` § Restatements.
