> ⚠️ Archive du 03/06/2026 — chiffres de perf mesurés le 03/06/2026, re-mesurer avant toute réutilisation.

# Audit vitesse — page « avocat divorce Bordeaux »

**URL :** https://www.jplouton-avocat.fr/droit-des-contrats-et-des-personnes/droit-de-la-famille/avocat-divorce-bordeaux
**Plateforme :** Wix Studio · **Date :** 03/06/2026
**Objectif :** LCP mobile < 2,5 s (p75) et réduire le Time-to-Interactive. La vitesse mobile sert à la fois le SEO organique et le Quality Score Google Ads (59 % du trafic = Adwords mobile).

> ⚠️ **Correction post-mesure (03/06/2026, émulation mobile réelle)** : le **LCP mobile est un élément TEXTE** (`<p class="font_3 wixui-rich-text__text">`), **pas l'image héros** (qui est `display:none` sur mobile — aucune image au-dessus de la ligne de flottaison). Décomposition LCP : TTFB 27 ms + **render delay 1 436 ms (98 %)**, 0 % chargement de ressource. → **L'optimisation image (action A ci-dessous) ne concerne QUE le LCP desktop, le poids et le SEO — PAS le LCP mobile.** Le vrai levier LCP mobile = réduire le JS tiers / render-blocking pour libérer le main-thread (action B), qui devient donc **la priorité nº1 sur mobile**.

---

## 1. Ce que disent les mesures

| Métrique | Terrain Cooked p75 (vrais users) | Lab mobile (4G + CPU 4×) | Lab desktop (rapide) | Seuil OK |
|---|---|---|---|---|
| Score perf | — | **59/100** | 69/100 | ≥ 90 |
| LCP | **4,6 s** | **4,7 s** | 3,76 s | < 2,5 s |
| TTFB | **3,3 s** | — | 0,23 s | < 0,8 s |
| TBT | — | 463 ms | 191 ms | < 200 ms |
| Time-to-Interactive | — | **28,3 s** | 4,5 s | < 3,8 s |
| INP | 256 ms | — | — | < 200 ms |
| CLS | 0,01 | 0,05 | 0,03 | < 0,1 ✅ |
| Poids page | — | — | **4,85 Mo** | < 1,5 Mo |

**Le diagnostic clé :** la **médiane est correcte** (p50 LCP 2,2 s / TTFB 0,37 s). C'est la **queue mobile (p75)** qui est mauvaise. Le TTFB terrain 3,3 s alors que le serveur Wix répond en 230 ms en lab = ce n'est **pas du temps serveur**, c'est du réseau mobile + un main-thread saturé. → On rapatrie la queue, on ne reconstruit pas un site lent.

**Pourquoi TTI 28 s en mobile :** le thread principal est bombardé après le 1er affichage par **5 tags tiers** (Google Tag Manager, Google Analytics, Google Ads/Doubleclick, Sentry, Cookiebot) **+ l'hydratation du framework Wix** (722 ms de JS bootup même sans throttle). Le tracker Cooked, lui, est léger et n'est PAS en cause.

---

## 2. Plan priorisé (ROI décroissant)

### 🥇 A. Optimiser et prioriser l'image LCP — *effort faible, impact fort*
1. Identifier l'élément LCP (très probablement l'image héros en haut de page).
2. **Désactiver le lazy-load dessus** (Wix lazy-load par défaut → fatal si c'est le LCP).
3. **Compresser + redimensionner** l'asset source dans le **Media Manager** (ne pas servir un 2500 px pour un affichage mobile ~800 px).
4. **Précharger** via Custom Code (Head) : `<link rel="preload" as="image" fetchpriority="high" href="…wixstatic.com/…">` (⚠️ l'URL Wix change si tu remplaces l'image).
→ **Gain LCP : −0,5 à −1,2 s.**

### 🥈 B. Consolider la pile de tags dans UN seul GTM — *effort moyen, impact fort*
- Tout centraliser dans **un seul conteneur Google Tag Manager** (GA4 + pixel Ads). Supprimer les snippets GA/Ads autonomes dans **Settings → Custom Code** et éviter le doublon avec « Marketing Integrations » natif de Wix.
- Mettre le snippet GTM en **« End of body »**.
- Différer **GA4** (trigger GTM « Window Loaded ») et **Sentry** (chargement après `load`).
- **Garder le pixel Google Ads fiable** : le tirer via GTM avec **Consent Mode v2** (ne jamais le mettre « après interaction » au risque de rater une conversion payante).
→ **Gain TBT −150 à −250 ms, TTI fortement réduit.**

### 🥉 C. Lazy-load / monter-au-scroll le below-the-fold — *effort moyen, impact fort*
- Les **13 études de cas, la FAQ, les simulateurs** sont sous la ligne de flottaison. Vérifier qu'ils sont en lazy-load.
- **Simulateurs** (prestation compensatoire, pension) = du JS qui s'initialise au load → les monter au scroll (IntersectionObserver en Velo) ou en embed `loading="lazy"`.
→ **Gain TBT/TTI + poids initial, sans toucher au texte qui fait ranker.**

### D. Déplacer tout le Custom Code non critique en « End of body » — *effort faible*
Rien en `<head>` sauf Cookiebot (obligation légale) et le `<link rel=preload>` de l'image LCP. GTM, Sentry, Cooked → **End of body**.

### E. Alléger poids/DOM — *effort moyen/élevé*
- 4,85 Mo et > 1 500 nœuds = trop. Sur les 13 études de cas : n'en afficher que 3-4 en dur + « voir plus » qui charge le reste.
- Compresser les 16 autres images (Media Manager, dimensions réelles).
- ⚠️ **Ne pas sacrifier les 3 389 mots** : c'est ce contenu qui fait ranker la page.

### F. Auditer Cookiebot — *effort faible*
Vérifier qu'il n'est **pas en mode « auto-blocking »** (qui scanne/réécrit tout le DOM = très coûteux en main-thread). Préférer le mode manuel avec catégories déclarées dans GTM. *(C'est aussi ce bandeau qui pollue les `cta_anchor_click` dans Cooked — cf. tâche séparée.)*

### G. Quick wins (hors perf pure) — *effort faible*
- **17 images sans `alt`** → ajouter le texte alternatif (panneau image Wix). Impact accessibilité + SEO image.
- **Title 66 car.** → raccourcir sous ~60 car.

---

## 3. Contrôlable dans Wix vs limite de la plateforme

| ✅ Contrôlable | ❌ Limite Wix (plafond) |
|---|---|
| Emplacement Custom Code (Head / End of body / delay) | Bundle Thunderbolt/React + hydratation (722 ms incompressibles) |
| Consolidation + gating GTM/tags | Les 41 feuilles CSS render-blocking générées par Wix |
| Compression/dimensionnement images | Pas de critical CSS inline, pas d'accès au `<head>` de rendu |
| Preload `fetchpriority` image LCP | Pas de tree-shaking du JS Wix |
| Lazy-load, IntersectionObserver Velo | Pas de service worker / cache edge custom |
| Réduction DOM/contenu, nombre d'apps | TTFB du CDN Wix sur certaines connexions mobiles |

**Plafond réaliste à assumer :** sur Wix Studio, une page riche comme celle-ci plafonne autour de **70-80/100 Lighthouse mobile** une fois optimisée. **Ne pas viser 90+.** En revanche **LCP < 2,5 s p75 et TBT < 200 ms sont atteignables** en exécutant A + B + C, parce que la médiane est déjà bonne.

---

## ⚡ Si tu ne fais que 3 choses

1. **Tags** : tout dans un seul GTM en « End of body », différer GA4 + Sentry après `load`, garder le pixel Ads fiable (GTM + Consent Mode). → libère le main-thread = **le texte LCP mobile peint plus tôt** (le vrai levier LCP mobile + TTI).
2. **Lazy-init les simulateurs** (+ supprimer l'appel backend `getPension` lancé au `onReady`).
3. **Images** : compression + dimensionnement + `alt`. → pour le **LCP desktop**, le **poids** et le **SEO** — **pas** le LCP mobile (image héros masquée).

À vérifier vu que le LCP mobile est du texte : le **`font-display`** de la police « font_3 » (si le titre attend la webfont, ça rallonge le render delay).
