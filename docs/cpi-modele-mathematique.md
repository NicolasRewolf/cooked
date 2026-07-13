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
Chaque page reçoit un **grade de confiance** $\in \{A,B,C\}$ (volume de données)
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

Mesures de référencement hors **branded** (`query ~* 'plouton'` exclu).
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

## Annexe A — code source v2.2 (source de vérité)

Fonction `public.cooked_page_index(p_days int default 28)`, SQL pur `STABLE`.
Diffs v2.2 surlignés en commentaire (`-- v2.2`).

```sql
WITH fit AS (
  SELECT regr_slope(ln(ctr), ln(pos)) pente, regr_intercept(ln(ctr), ln(pos)) icept
  FROM (SELECT round(position)::int pos, (sum(clicks)+1.0)/(sum(impressions)+20.0) ctr
        FROM gsc_query_page_daily WHERE day > current_date-90 AND query !~* 'plouton'
        GROUP BY 1 HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions)>=200) b),
capq AS (SELECT g.path, sum(g.impressions) i_qpd,
    sum(g.impressions*least(greatest(exp(f.icept+f.pente*ln(greatest(g.position,1.0))),0.0005),0.5)) e_qpd
  FROM gsc_query_page_daily g, fit f WHERE g.day>current_date-p_days AND g.query !~* 'plouton' GROUP BY g.path),
capb AS (SELECT path, sum(clicks) o_b, sum(impressions) i_b FROM gsc_query_page_daily
  WHERE day>current_date-p_days AND query ~* 'plouton' GROUP BY path),
capp AS (SELECT path, sum(clicks) o_full, sum(impressions) i_full FROM gsc_path_daily WHERE day>current_date-p_days GROUP BY path),
cap AS (SELECT p.path, greatest(p.o_full-coalesce(b.o_b,0),0)::numeric o,
    CASE WHEN coalesce(q.i_qpd,0)>0 THEN q.e_qpd*(greatest(p.i_full-coalesce(b.i_b,0),0)::numeric/q.i_qpd) ELSE NULL END e,
    q.i_qpd, greatest(p.i_full-coalesce(b.i_b,0),0) i_nb
  FROM capp p LEFT JOIN capq q ON q.path=p.path LEFT JOIN capb b ON b.path=p.path),
firstpv AS (SELECT DISTINCT ON (session_id) session_id, eh.path,
    classify_channel(referrer_hostname,utm_source,utm_medium,'www.jplouton-avocat.fr') chan
  FROM events_human eh WHERE name='pageview' AND occurred_at>now()-make_interval(days=>p_days) ORDER BY session_id, occurred_at),
orge AS (SELECT session_id, firstpv.path FROM firstpv WHERE chan LIKE 'organic%'),
norg AS (SELECT orge.path, count(*) n_org FROM orge GROUP BY orge.path),
spv AS (SELECT session_id, count(*) pv FROM events_human WHERE name='pageview' AND occurred_at>now()-make_interval(days=>p_days) GROUP BY session_id),
ex2 AS (SELECT o.path, cooked_page_type(o.path) ptype, (e.props->>'duration_seconds')::numeric d,
    coalesce((e.props->>'max_scroll')::numeric,0) s,
    ((e.props->>'duration_seconds')::numeric>=15 OR coalesce(s2.pv,1)>=2) retained
  FROM orge o JOIN events_human e ON e.session_id=o.session_id AND e.path=o.path AND e.name='page_exit'
  LEFT JOIN spv s2 ON s2.session_id=o.session_id),
thr AS (SELECT ptype, percentile_cont(0.5) WITHIN GROUP (ORDER BY d) tau,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY s) sig FROM ex2 WHERE retained GROUP BY ptype),
reads AS (SELECT e.path, max(e.ptype) ptype, count(*) n, count(*) FILTER (WHERE retained) r,
    count(*) FILTER (WHERE retained AND d>=t.tau AND s>=t.sig) k FROM ex2 e JOIN thr t ON t.ptype=e.ptype GROUP BY e.path),
tmeans AS (SELECT ptype, coalesce(sum(r)::numeric/nullif(sum(n),0),0.5) rho, coalesce(sum(k)::numeric/nullif(sum(r),0),0.25) q FROM reads GROUP BY ptype),
-- v2.2 : pseudo-comptes EB dynamiques par type (Beta-Binomial, méthode des moments)
ebk AS (SELECT t.ptype, t.rho, t.q,
    CASE WHEN er.np>=5 AND er.v>0 AND er.v<t.rho*(1-t.rho) THEN least(greatest(t.rho*(1-t.rho)/er.v-1,5),200) ELSE 20 END kappa_ret,
    CASE WHEN el.np>=5 AND el.v>0 AND el.v<t.q*(1-t.q) THEN least(greatest(t.q*(1-t.q)/el.v-1,5),200) ELSE 20 END kappa_lec
  FROM tmeans t
  LEFT JOIN (SELECT ptype, var_samp(r::numeric/n) v, count(*) np FROM reads WHERE n>=10 GROUP BY ptype) er ON er.ptype=t.ptype
  LEFT JOIN (SELECT ptype, var_samp(k::numeric/nullif(r,0)) v, count(*) np FROM reads WHERE r>=10 GROUP BY ptype) el ON el.ptype=t.ptype),
jx AS (SELECT * FROM conversion_journeys(p_days) WHERE entry_channel LIKE 'organic%'),
direct AS (SELECT entry_path path, count(*)::numeric v FROM jx WHERE entry_path IS NOT NULL GROUP BY 1),
assist AS (SELECT jp.path, sum(1.0/greatest(j.pages_count,1)) v FROM jx j CROSS JOIN LATERAL unnest(j.journey) jp(path) WHERE jp.path<>j.entry_path GROUP BY jp.path),
book AS (SELECT o.path, 0.25*count(*)::numeric v FROM orge o JOIN events_human b ON b.session_id=o.session_id AND b.path=o.path AND b.name='cta_booking_click' GROUP BY o.path),
convv AS (SELECT n.path, n.n_org, coalesce(d.v,0)+coalesce(a.v,0)+coalesce(b.v,0) val
  FROM norg n LEFT JOIN direct d ON d.path=n.path LEFT JOIN assist a ON a.path=n.path LEFT JOIN book b ON b.path=n.path),
tconv AS (SELECT cooked_page_type(convv.path) ptype, coalesce(sum(val)/nullif(sum(convv.n_org),0),0) nu FROM convv GROUP BY 1),
xs AS (SELECT r.path, r.ptype, c.n_org, c.val, coalesce(cap.o,0) o, cap.e, coalesce(cap.i_qpd,0) i_qpd, coalesce(cap.i_nb,0) i_nb,
    coalesce(ln((coalesce(cap.o,0)+3)/(cap.e+3)),0) x_cap,
    -- v2.2 : kappa_ret / kappa_lec dynamiques au lieu de 20
    ln( least(greatest((r.r+tm.kappa_ret*tm.rho)/(r.n+tm.kappa_ret),0.001),0.999) / (1-least(greatest((r.r+tm.kappa_ret*tm.rho)/(r.n+tm.kappa_ret),0.001),0.999)) ) x_ret,
    ln( least(greatest((r.k+tm.kappa_lec*tm.q)/(r.r+tm.kappa_lec),0.001),0.999) / (1-least(greatest((r.k+tm.kappa_lec*tm.q)/(r.r+tm.kappa_lec),0.001),0.999)) ) x_lec,
    ln( (c.val+30*tc.nu+0.05)/(c.n_org+30) ) x_conv
  FROM reads r JOIN convv c ON c.path=r.path LEFT JOIN cap ON cap.path=r.path
  JOIN ebk tm ON tm.ptype=r.ptype JOIN tconv tc ON tc.ptype=r.ptype WHERE c.n_org>=5 AND r.n>=3),
-- medt/madt (par type) + medg/madg (global, repli) : médiane + MAD écrêtée, sur chaque x
medt AS (SELECT ptype, count(*) cnt, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs GROUP BY ptype),
madt AS (SELECT x.ptype,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-m.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-m.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-m.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-m.mv)),0.15) sv FROM xs x JOIN medt m ON m.ptype=x.ptype GROUP BY x.ptype),
medg AS (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs),
madg AS (SELECT greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-g.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-g.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-g.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-g.mv)),0.15) sv FROM xs x, medg g),
mom AS (SELECT gpd.path,
    coalesce(sum(clicks) FILTER (WHERE day>current_date-p_days),0) c1,
    coalesce(sum(clicks) FILTER (WHERE day BETWEEN current_date-2*p_days AND current_date-p_days-1),0) c0,
    avg(position) FILTER (WHERE day>current_date-p_days) p1,
    avg(position) FILTER (WHERE day BETWEEN current_date-2*p_days AND current_date-p_days-1) p0
  FROM gsc_path_daily gpd WHERE day>current_date-2*p_days GROUP BY gpd.path),
site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom),
lcp AS (SELECT eh.path, percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric) lcp75
  FROM events_human eh WHERE name='web_vitals' AND props->>'metric'='LCP' AND device_type='mobile'
    AND occurred_at>now()-make_interval(days=>p_days) GROUP BY eh.path),
scored AS (SELECT x.path, x.ptype, x.n_org, round(greatest(coalesce(x.e,0)-x.o,0))::int clics_perdus,
    CASE WHEN coalesce(x.i_nb,0)>0 THEN round(100.0*x.i_qpd/x.i_nb)::int ELSE 0 END couv,
    round(least(greatest((x.x_cap-CASE WHEN mt.cnt>=15 THEN mt.mc ELSE mg.mc END)/(CASE WHEN mt.cnt>=15 THEN dt.sc ELSE dg.sc END),-3),3)::numeric,1) zc,
    round(least(greatest((x.x_ret-CASE WHEN mt.cnt>=15 THEN mt.mr ELSE mg.mr END)/(CASE WHEN mt.cnt>=15 THEN dt.sr ELSE dg.sr END),-3),3)::numeric,1) zr,
    round(least(greatest((x.x_lec-CASE WHEN mt.cnt>=15 THEN mt.ml ELSE mg.ml END)/(CASE WHEN mt.cnt>=15 THEN dt.sl ELSE dg.sl END),-3),3)::numeric,1) zl,
    round(least(greatest((x.x_conv-CASE WHEN mt.cnt>=15 THEN mt.mv ELSE mg.mv END)/(CASE WHEN mt.cnt>=15 THEN dt.sv ELSE dg.sv END),-3),3)::numeric,1) zv,
    -- v2.2 : momentum à transition continue (mélange sigmoïde w autour de 20 clics)
    round(exp(least(greatest(
      (1-1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0)))*(-0.08*coalesce(m.p1-m.p0,0))
      + (1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0)))*(ln((coalesce(m.c1,0)+5.0)/(coalesce(m.c0,0)+5.0))-ln((s.s1+50.0)/(s.s0+50.0)))
    ,-0.336),0.336))::numeric,2) mm,
    round((1-0.15*least(greatest((coalesce(l.lcp75,2500)-2500)/2500.0,0),1))::numeric,2) gg,
    CASE WHEN x.n_org>=100 AND coalesce(x.e,0)>=20 THEN 'A' WHEN x.n_org>=30 AND coalesce(x.e,0)>=5 THEN 'B' ELSE 'C' END grade
  FROM xs x LEFT JOIN medt mt ON mt.ptype=x.ptype LEFT JOIN madt dt ON dt.ptype=x.ptype
  CROSS JOIN medg mg CROSS JOIN madg dg LEFT JOIN mom m ON m.path=x.path CROSS JOIN site s LEFT JOIN lcp l ON l.path=x.path)
SELECT scored.path, scored.ptype, scored.grade,
  least(100, round(100*(1/(1+exp(-(0.30*zc+0.15*zr+0.20*zl+0.35*zv)/0.8)))*mm*gg))::int cpi,
  round(100*(1/(1+exp(-(0.30*zc+0.15*zr+0.20*zl+0.35*zv)/0.8)))*mm*gg)::int cpi_raw,
  mm momentum, (CASE WHEN mm>=1.15 THEN '↗' WHEN mm<=0.87 THEN '↘' ELSE '→' END) momentum_badge,
  gg gate, zc, zr, zl, zv, clics_perdus, n_org, couv couv_gsc_pct
FROM scored;
```

---

*Mis à jour le 13/07/2026 (v2.2 — intègre la validation J+28 du 11/07/2026 et
le restatement conversion recousue du 12/07/2026). En cas de divergence, **le
code en base fait foi** — merci de signaler tout écart.*
