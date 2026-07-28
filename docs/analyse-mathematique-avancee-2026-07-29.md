# Framework d'analyse mathématique avancée — rapport d'exécution

**Date : 29/07/2026** · fenêtres 28 j et 84 j · données GSC jusqu'au **26/07/2026**
Script : `scripts/advanced_math_analytics.py` · RPC : `math_visit_sequences`,
`math_internal_edges` · snapshots : `math_*_snapshot`

---

## 0. Préalable — état du système

| Contrôle | État |
|---|---|
| `alerts WHERE NOT acked` | 3 alertes `warn`, **aucune `critical`** |
| `refresh_pipeline_health()` | `healthy`, 0 issue |
| `gsc_last_data_day()` | 25/07/2026 (lag J-3, normal) |

Les 3 alertes ont été instruites avant tout calcul :

- **`cpi_gap`** — `cpi_daily` a perdu les 20, 21 et 24/07. Cause trouvée dans
  `cron.job_run_details` : le 24/07, **12 exécutions consécutives** de
  `cooked_refresh_after_gsc` (11:00 → 22:00) ont échoué sur
  `could not write to file "base/pgsql_tmp/…": No space left on device`.
  Le disque a été dégagé depuis (le `VACUUM FULL events` du 26/07) et le job
  tourne de nouveau. **Jours perdus définitivement** — sans conséquence sur ce
  rapport, qui ne lit pas `cpi_daily`.
- **`cpi_drop` ×2** (26 et 27/07) — signal métier, pas incident pipeline.
  Le module 5 ci-dessous adresse précisément cette question.

⚠️ **Point d'attention hors périmètre** : la saturation disque du 24/07 est un
risque récurrent (base à 2,1 Go, dont 1,14 Go pour `events`). Elle a déjà coûté
3 jours de `cpi_daily`. À surveiller.

---

## 1. Cadrage — ce qui est calculable, et ce qui ne l'est pas

**C'est la section la plus importante du rapport.** Les cinq méthodes demandées
sont implémentées et fonctionnent ; leur pouvoir de conclusion, lui, est borné
par la matière disponible.

### Le site est massivement mono-page

Sur 28 jours, après couture d'identité (`identity_stitch`) :

| | visites | part |
|---|---|---|
| 1 seule page vue | 15 561 | **93,2 %** |
| 2 pages | 830 | 5,0 % |
| 3 pages et + | 299 | 1,8 % |

Markov, Shapley et la centralité mesurent tous des **transitions entre pages**.
Sur 93 % du trafic, il n'y a pas de transition à mesurer.

### La matière multi-touch convertie, en clair

| fenêtre | visites | converties | dont **multi-touch** |
|---|---|---|---|
| 28 j | 16 682 | 161 | **54** |
| 84 j | 51 132 | 394 | **146** |

Le removal effect de Markov et la valeur de Shapley reposent donc, sur 28 jours,
sur **54 parcours**. C'est peu. Toutes les analyses ci-dessous sont livrées en
**double fenêtre (28 j et 84 j)** : la concordance entre les deux est le seul
juge de robustesse disponible, et les intervalles de confiance bootstrap sont
systématiquement affichés.

### Horizon réel des séries

- **GSC** : 01/02/2025 → 26/07/2026 — les 16 mois annoncés sont bien là,
  c'est le socle des modules 4 et 5.
- **`cpi_daily`** : 10/06 → 28/07/2026, soit **49 jours dont 39 présents**
  (10 trous). Trop court et trop troué pour une décomposition STL. Le module 5
  tourne donc **sur GSC uniquement**, ce qui est de toute façon le bon niveau
  (le CPI est un score dérivé, pas une mesure).

---

## 2. Contrôle de cohérence avec le système existant

`conversion_journeys` ne rend que les **convertisseurs** ; Markov a besoin du
dénominateur (les parcours non convertis), d'où la nouvelle RPC
`math_visit_sequences`. Elle a été alignée sur la RPC canonique :

| | `math_visit_sequences(28)` | `conversion_journeys(28)` |
|---|---|---|
| grain | visite | contact |
| conversions | 161 visites | 192 contacts |
| multi-touch | 54 | 63 |

**Écart entièrement expliqué** : 192 − 161 = 31 contacts surnuméraires (une même
visite peut porter un appel *et* un formulaire), dont 9 sur des visites
multi-touch → 63 − 9 = 54. ✔

Une première version perdait 25 contacts sur 192 (dont **19 formulaires sur 43**) :
la fenêtre de rattachement de 3 min ne couvrait pas le temps de remplissage d'un
formulaire. Alignée sur les 6 h de `conversion_journeys` v2.

---

## 3. Top pages ponts — croisement Markov × Betweenness × Shapley

Classement par rang moyen des trois méthodes (fenêtre **84 j**, la plus fournie).
`direct` = contacts pris **sur** la page ; `assist` = part des parcours convertis
où le contact est pris **ailleurs**.

| # | page | removal | shapley | betweenness | direct | assist |
|---|---|---|---|---|---|---|
| 1 | `/honoraires-rendez-vous` | 25,6 % | 0,237 % | 0,322 | 103 | 12 % |
| 2 | `/droit-des-contrats-et-des-personnes/droit-de-la-famille` | 15,0 % | 0,680 % | 0,038 | 76 | 0 % |
| 3 | `/` | 17,6 % | 0,084 % | **0,645** | 67 | 32 % |
| 4 | `/notre-cabinet` | 8,5 % | 0,170 % | 0,159 | 22 | **51 %** |
| 5 | `/indemnisation-des-victimes/victimes-de-delits-ou-crimes` | 5,0 % | 0,300 % | 0,040 | 17 | 32 % |
| 6 | `/defense-penale/violences-conjugales-et-feminicides` | 3,3 % | 0,396 % | 0,020 | 11 | 8 % |
| 7 | `/defense-penale/droit-penal-des-affaires` | 3,3 % | 0,399 % | 0,016 | 13 | 13 % |

Lecture : *removal 25,6 %* signifie que si `/honoraires-rendez-vous` disparaissait
du site, le modèle prédit **−25,6 % de contacts** — soit ~101 contacts sur 84 j.

### Les vraies pages ponts invisibles

Critère : présente dans ≥ 3 parcours convertis **et** ≥ 50 % des contacts pris
ailleurs.

| page | perte si retirée | assist | contacts directs |
|---|---|---|---|
| `/notre-cabinet` | **33,5 contacts** | 51 % | 22 |
| `/nos-affaires` | 6,7 contacts | **80 %** | 1 |
| `/indemnisation-des-victimes/accidents-et-erreurs-medicales` | 3,3 contacts | 60 % | 2 |
| `/comprendre-le-droit` | 1,5 contact | **100 %** | 0 |
| `/post/la-détention-domiciliaire-…-ddse` | 1,2 contact | 100 % | 0 |
| `/defense-penale` (hub) | 0,9 contact | 100 % | 0 |
| `/droit-des-contrats-et-des-personnes` (hub) | 0,6 contact | 100 % | 0 |

`/notre-cabinet` est le seul à ressortir sur **les deux fenêtres** (28 j :
10,8 contacts, 61 % d'assist). C'est le pont le plus solide du site : une page
de réassurance que l'on consulte avant d'appeler ailleurs.

### 🔍 Le résultat qui contredit l'hypothèse de départ

La commande supposait que les **articles ressources** agissent comme carrefours
vers les pages business. **Les données disent l'inverse** : les articles qui
produisent des contacts les produisent **sur place**, au téléphone.

| article | parcours convertis | contacts directs | assist |
|---|---|---|---|
| `/post/indemnisation-civi-2025-…` | 10 | 9 | 10 % |
| `/post/sarvi-comment-récupérer-…` | 9 | 8 | 11 % |
| `/post/durée-de-la-garde-à-vue-24h-48h-96h` | 9 | 8 | 11 % |
| `/post/arnaque-en-ligne-…` | 6 | 5 | 17 % |
| `/post/itt-pénale-définition-en-2025` | 6 | 4 | 33 % |

Sur 17 articles présents dans ≥ 2 parcours convertis, **seuls 4 dépassent 50 %
d'assist — tous à support 2 ou 3**, donc sans verdict possible.

Ce constat recoupe un fait déjà documenté (`CLAUDE.md`) : *« 0 conversion vers
/honoraires-rendez-vous sur les 47 articles à trafic »*. Les articles ne
renvoient pas vers la page de contact — mais ils convertissent quand même, par
appel direct. **Les ponts du site sont ses pages de navigation** (`/notre-cabinet`,
`/nos-affaires`, `/comprendre-le-droit`, les hubs), pas ses contenus.

### Shapley vs attribution 1/L — ne pas confondre les deux

L'écart entre les deux colonnes est **structurel, pas correctif** :

- **1/L** (ce qu'utilise le terme `zv` du CPI) répartit un **volume** de contacts.
- **Shapley**, tel qu'implémenté ici, répartit un **taux** de conversion :
  `v(S)` = taux de conversion des visites dont toutes les pages sont dans `S`.

D'où des classements très différents : `/honoraires-rendez-vous` domine en 1/L
(19,1 sur 28 j) et arrive dernier en Shapley (0,023 %). Ce n'est **pas** le signe
que le CPI la surévalue — les deux mesurent des choses différentes.

Note technique : avec `v(S)` = *nombre* de conversions, la valeur de Shapley se
réduirait **exactement** à l'attribution 1/L (démonstration en commentaire dans
le script). C'est le passage au taux qui rend le calcul informatif.

**Validations mathématiques passées** :
- Axiome d'efficacité : Σφᵢ = v(univers) = **1,8189 %** contre 1,8189 % attendu
  (écart < 10⁻⁴). L'implémentation est correcte.
- Couverture : le jeu couvre **85 % des conversions** (137/161) mais 45 % des
  visites. `v(univers) = 1,82 %` est donc le taux de la sous-population
  concernée, **pas** le taux du site (0,965 %).
- 9 pages sur 27 ont une valeur **négative** : elles abaissent le taux de
  conversion des coalitions où elles apparaissent.

---

## 4. Inférence causale — les 3 interventions annotées

Méthode : **contrôle synthétique contraint** (Abadie — poids ≥ 0, Σ = 1),
inférence par **placebos**. Ce n'est pas un BSTS bayésien complet (pas de
spike-and-slab MCMC) ; c'est dit explicitement dans le script.

| page | intervention | observé | contrefactuel | effet | p | verdict |
|---|---|---|---|---|---|---|
| `/post/traumatisme-cranien-accident-voiture` | refonte 02/07 | 21 | 20 | +1 (+4,9 %) | 0,34 | **non interprétable** (R²=0,10) |
| `/post/mes-droits-en-garde-a-vue` | supprimée + 301 le 13/07 | 2 | 4 | −2 | 0,61 | **non interprétable** (R²=0,17) |
| `/post/la-garde-à-vue-définition-…` | cible du 301 du 13/07 | 82 | 103 | −21 (−20,3 %) | 0,96 | non concluant |

**Verdict : aucun effet causal démontrable sur les trois interventions.** Les
raisons sont explicites et non négociables :

1. **Recul insuffisant** — GSC s'arrête au 26/07, soit 14 jours après le 13/07 et
   25 après le 02/07.
2. **Témoins inadéquats** — sur des pages à 0,2–8 clics/jour, aucun panier de
   témoins ne reproduit correctement la pré-période (R² de 0,10 à 0,55).

L'hypothèse de de-cannibalisation du 13/07 (« la page définition va monter »)
**n'est ni confirmée ni infirmée**. À rejouer vers **le 10/08/2026**, quand la
post-période atteindra 28 jours pleins.

⚠️ Le module ignore volontairement les annotations `site_change` qui décrivent un
**changement de mesure** et non du site (restatement CPI du 27/07, `classify_channel`
v3…). Les traiter comme des interventions fabriquerait un effet purement comptable.
→ *Suggestion* : ajouter une valeur `restatement` à la taxonomie `annotations.kind`.

---

## 5. Signaux précoces — STL + Kalman sur 400 jours GSC

Décomposition STL (période 7 j, robuste) pour isoler la tendance du cycle
hebdomadaire, puis modèle *local linear trend* filtré par Kalman pour obtenir la
**pente courante et son erreur standard** — donc un test de significativité.

Sur 176 pages, **87 ont un volume suffisant** pour un verdict (≥ 15 clics/28 j).
**Une seule est en déclin de tendance confirmé** :

| page | pente | z | Δ tendance | clics/28 j |
|---|---|---|---|---|
| `/post/une-saisie-de-meubles-qui-n-appartenaient-pas-aux-débiteurs` | −12 %/28 j | −2,3 | −26 % | 29 |

**Contre-vérifié sur les données brutes** (clics par période de 28 j) :
61 → 45 → 55 → 31 → 32 → 41 → **29**. Déclin réel et régulier (−52 % depuis
janvier), pas un artefact de modèle. ✔

Un premier passage sortait 10 « pages en déclin » — toutes à 0-3 clics/28 j, où
un z de −6 ne signifie rien. Le module applique désormais un plancher de volume
(piège n°6 du playbook : *petits volumes = pas de verdict*).

---

## 6. Artefacts détectés et corrigés en cours de route

Consignés parce qu'ils se reproduiront :

1. **Post-période GSC densifiée à zéro** — GSC accuse 2-3 jours de lag. Une
   fenêtre post de 28 j après le 13/07 comptait **15 jours de zéros inventés**,
   produisant un faux « −65 % » sur `/post/la-garde-à-vue-…`. Au-delà du dernier
   jour livré il n'y a pas *zéro clic*, il n'y a **pas de donnée**.
2. **Régression libre → extrapolation absurde** — sans contrainte, le
   contrefactuel prédisait **1 231 clics** pour une page qui en fait 82 (×15).
   D'où le passage aux poids d'Abadie (≥ 0, somme 1).
3. **Témoin lui-même choqué** — `/post/affaire-christophe-b-gironde…` (pic
   d'actualité, indice post **×73**) apportait, avec un poids de 0,016, **59 % du
   contrefactuel**. Un donneur qui subit son propre choc ne mesure plus la marée.
4. **URL accentuées redirigées** — 56 clics internes / 28 j pointent vers des URL
   qui ne reçoivent aucun pageview (`/défense-pénale/…` → `/defense-penale/…`).
   Sans résolution, le graphe dédoublerait ces nœuds. 11 arêtes sont remappées
   (`dst_resolved`). *Effet de bord SEO/UX : les liens internes du site passent
   par une redirection — corrigeable côté Wix.*
5. **`events_human` coûte ~12 s par scan** (anti-join `nested loop` sur
   `bot_fingerprints` : 77 lignes × 20 000 boucles). Les RPC la scannaient 2-3
   fois → timeout. Un seul scan matérialisé désormais. **La vue elle-même n'a pas
   été touchée** (source canonique) — mais c'est le goulot documenté des crons
   nocturnes, et il grossit.

   → Ce n'est plus théorique : le contract test de **`behavior_pages_for_period`
   échoue en production** sur `canceling statement due to statement timeout`
   après 53,8 s (dernier passage : 28/07/2026 10:19). C'est **antérieur et
   étranger à ce chantier**, mais c'est la même cause racine. Piste, sans
   toucher à la définition de la vue : matérialiser `bot_fingerprints` dans un
   `IN (…)` ou forcer un *hash anti join*.

6. **RPC `SECURITY DEFINER` ouvertes à `anon`** — Postgres accorde `EXECUTE` à
   `PUBLIC` à la création. Le `GRANT … TO service_role` ne retire rien : les
   trois RPC `math_*` étaient appelables **sans authentification** via
   `/rest/v1/rpc/…`. Corrigé (migration `20260728222238`), advisors 0028/0029
   propres pour ces fonctions.
   *Restent exposées, hors périmètre : `page_reads` et `rpc_contract_check`.*

---

## 7. Ce qui est en base

| objet | rôle |
|---|---|
| `math_visit_sequences(days)` | toutes les visites recousues, converties **et** non converties — le dénominateur qui manquait |
| `math_internal_edges(days)` | arêtes du graphe (`flow` observé + `click` tracé, cibles orphelines résolues) |
| `math_visit_sequences_snapshot`, `math_internal_edges_snapshot` | photos matérialisées |
| `math_refresh_snapshots(days)` | rafraîchit une fenêtre |
| cron `math-refresh-snapshots-weekly` | dimanche 05:10 UTC, fenêtre 28 j |

**Pourquoi des snapshots plutôt qu'un appel RPC direct** : `math_visit_sequences(28)`
coûte ~65 s, or PostgREST plafonne à **8 s** (`statement_timeout` du rôle
`authenticator`). Une RPC lourde n'est pas appelable depuis un script. Le script
lit donc les tables. Fenêtre 84 j à la demande :

```sql
SET statement_timeout='600s'; SELECT math_refresh_snapshots(84);
```

### Ce que je n'ai **pas** créé, volontairement

**Aucune vue de scoring « pages ponts »**, alors que la commande l'autorisait.
Raison : la métrique reposerait sur 2 pages (28 j) à 7 pages (84 j), dont la
plupart à support 2-3. Industrialiser un score sur cette base reviendrait à
publier du bruit avec une décimale — exactement ce que le projet a refusé pour le
CPI v2.3 (« l'outil est suffisant, on ne complexifie pas »). Les briques
d'extraction, elles, ont une valeur durable et sont en base.

---

## 8. Utilisation

```bash
pip install -r scripts/requirements-math.txt
export SUPABASE_SECRET_KEY=...          # jamais commitée

python3 scripts/advanced_math_analytics.py --module all --window 28
python3 scripts/advanced_math_analytics.py --module all --window 84 --top 15
python3 scripts/advanced_math_analytics.py --module trend            # STL/Kalman
```

Mode hors-ligne (aucun secret requis, pour rejouer un export) :

```bash
python3 scripts/advanced_math_analytics.py --source cache --cache-dir <dir>
```

---

## 9. À reprendre

- **Vers le 10/08/2026** : rejouer le module 4 sur le 301 du 13/07, avec 28 jours
  pleins de post-période.
- **Surveiller** `/post/une-saisie-de-meubles-…` — seul déclin de tendance
  confirmé.
- **Taxonomie `annotations`** : distinguer changement de site et changement de
  mesure (valeur `restatement`).
- **Disque Supabase** : la saturation du 24/07 a coûté 3 jours de `cpi_daily`.
- **Liens internes accentués** : 56 clics/28 j passent par une redirection.
- **`behavior_pages_for_period`** : contract test en échec (timeout 53,8 s),
  antérieur à ce chantier — même cause racine que le goulot `events_human`.
- **`page_reads` / `rpc_contract_check`** : `SECURITY DEFINER` toujours
  exécutables par `anon` (advisors 0028/0029).
