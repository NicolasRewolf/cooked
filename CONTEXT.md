# Cooked — Contexte du domaine

Système d'analytics first-party pour le site du cabinet Plouton. Ce fichier
fige le **vocabulaire des conversions et de leur attribution** — la source de
confusion identifiée le 13/07/2026 (trois « contacts » différents à l'écran,
dont un calculé avec une méthode obsolète). Il **complète** la taxonomie
macro / micro / engagement de `CLAUDE.md` en tranchant la question de
l'**attribution**.

> **Depuis le 4 novembre 2026** — la définition courante est celle du socle
> décrit dans [SIMPLIFICATION.md](docs/SIMPLIFICATION.md). Les anciens
> instantanés CPI, dashboard, SEO et math restent des archives datées.

## Language

### Conversions

**Conversion** / **Contact** :
Un **clic sur un numéro** (`cta_phone_click`) ou un **formulaire envoyé** (`form_submit`
comptant comme macro). Un seul concept, deux mots par convention :
**« conversion »** est le terme technique (code, specs, RPC) ; **« contact »**
est le mot **affiché** dans l'UI (plus lisible pour Me Plouton). = la
macro-conversion de `CLAUDE.md`.
Le clic n'atteste pas que l'appel a abouti ; ce compteur ne mesure ni les
clients acquis ni les dossiers facturés.
_Avoid_ : « lead », « conversion » comme libellé d'écran, « contact » dans
le code. « **Prospect** » a un sens précis depuis le 10/08/2026 : une row de
`crm_prospects` (identité issue d'un formulaire web, pont SECIB) — ne pas
l'employer pour une conversion web ordinaire.

**Intention** (micro) :
Un clic « prendre RDV » (`cta_booking_click`) qui ne se matérialise pas.
**N'est PAS une conversion / un contact.**
_Avoid_ : compter une intention comme une conversion (erreur de l'audit du
15/05/2026 : 157 « conversions » pour 37 vrais contacts).
Dans les archives CPI, le badge `convertit` utilise les contacts macro directs
ou assistés. La contribution pondérée des intentions au score historique reste
distincte du badge ; ce score n’est plus recalculé depuis le 04/11/2026.

### Attribution — deux vues d'une conversion, jamais fusionnées

**Conversion sur la page** :
Conversion attribuée à la page **où l'action a eu lieu** (le lecteur tape le
numéro pendant qu'il lit l'article). Source : `macro_contacts_by_path`
(attribution au `path` de l'event).
_Avoid_ : « contacts » tout court — ambigu avec l'attribution à l'entrée.

**Conversion attribuée** (à l'entrée) :
Conversion attribuée à la page **par laquelle le visiteur est entré** sur le
site, avant de convertir au cours de la **même visite**. Attribution
**toujours via la visite recousue** — une seule méthode, partout.
_Avoid_ : « assisté » employé seul sans qualifier ; toute variante calculée
sur la session brute.

**Visite observée et recousue** :
Activité d’un même navigateur rapprochée par `identity_stitch` (aid ↔ sid),
segmentée dès qu’un écart d’activité dépasse 30 minutes. La couture couvre
l’historique conservé et converge réellement ; l’argument historique de durée
ne tronque plus ce rapprochement. `web_vitals` ne prolonge pas une visite.
La première page vue est l’entrée, même si elle précède la période demandée.
Le parcours d’un contact ne contient jamais de page postérieure à ce contact.
Ne jamais coudre via un `anonymous_id` 32-hex de repli serveur, partageable entre
navigateurs. Une identité technique ne prouve pas une personne distincte.
_Avoid_ : « session » brute comme base d’attribution à l’entrée.

**Contact non attribué** :
Contact compté dans le site mais sans visite observable certaine. Un formulaire
sans identifiant explicite ne reçoit plus de page par simple proximité dans le
temps. Il reste conservé comme inconnu, jamais attribué à la page suivante.

**Visite ayant contacté** :
Visite distincte ayant produit au moins un clic téléphone ou un formulaire macro.
Le téléphone, le formulaire et leur union sont trois compteurs : leurs nombres
ne s’additionnent pas si la même visite a fait les deux. `page_visits(start,end)`
calcule le taux sur la cohorte des visites **entrées dans la fenêtre**, actions
observées avant sa clôture. Sans entrée, le taux est inconnu (`NULL`). Une visite
qui consulte une page sans entrer dessus augmente les consultations, pas le
dénominateur des contacts attribués à cette page d’entrée.

**Conversions du site** :
Total des conversions **toutes pages confondues** — le chiffre business de
référence au grain des actions. Se présente **avec son détail** : clics téléphone
vs formulaires, et la part
qui touche les articles ressources. Source : `site_macro_counts`.
_Avoid_ : présenter un total scopé (ressources seules) comme « les contacts du
site » — c'est le piège de la tuile actuelle (36 affichés pour 210 réels au
13/07/2026).

### Lecture — vocabulaire historique conservé

Cette section décrit les indicateurs de lecture et les archives CPI d’avant le
04/11/2026. Elle ne définit pas le nouveau taux de visites ayant contacté.

Le CPI historique repose à parts égales sur quatre composantes, dont deux — `zr` rétention
et `zl` lecture — relèvent de ce vocabulaire. Il a été figé le 28/07/2026, après
avoir constaté que la lecture était redérivée à la main dans **8 RPC** avec trois
définitions divergentes (grain, source du scroll, traitement du zéro).

**Lecture** :
Une visite d'**une page** par un visiteur, avec sa **durée** (`dwell_s`) et sa
**profondeur** (`scroll_pct`). Grain : **une ligne par (session × path)** — une
même visite qui voit trois pages produit trois lectures, et repasser sur une page
au cours de la même visite n'en crée pas une seconde (on garde le `max`).
Source : `page_exit`.
_Avoid_ : « dwell » ou « temps passé » sans dire de quel grain ; agréger au
niveau session quand la question porte sur une page.

**Retenue** :
Lecture qui franchit le seuil de survie — `dwell_s >= 15` **OU** la visite compte
au moins 2 pageviews. C'est le dénominateur de `zl` et le numérateur de `zr`.
_Avoid_ : « rebond » (notion importée de GA, jamais définie ici).

**Lecture qualifiée** :
Parmi les retenues, celle dont la durée **et** la profondeur dépassent toutes deux
les médianes de son **type de page** (`cooked_page_type`). C'est ce que `zl`
mesure — une profondeur relative aux pairs, jamais un seuil absolu.
_Avoid_ : parler de « lecture complète » ou d'un seuil fixe (75 %, 2 min) : les
seuils sont calculés par type à chaque run.

**Couverture de lecture** :
Part des visites pour lesquelles `page_exit` est bien arrivé. **Elle n'est pas de
100 % et ne le sera jamais** : mesurée à **59 %** sur 28 j au 27/07/2026 (66 %
mobile, **50 % desktop**), et elle varie de 40 % à 92 % selon la page. En desktop,
94,9 % des visites sans `page_exit` sont pourtant actives — ce sont des onglets
laissés ouverts, pas des rebonds.
_Avoid_ : présenter un dwell médian comme un fait sans sa couverture.

### Sources & fraîcheur (23/08/2026 — ADR-0002)

**Horloge de source** :
Cooked regroupe les événements par jour Paris ; la date GSC correspond au jour
Pacifique fourni par Google. Les comparaisons affichent les bornes de chaque
source. Une même date n'assure pas une même tranche de 24 heures.

**Lot GSC terminé** :
Une ingestion n’est complète qu’après succès des trois tables sur une même
fenêtre. `gsc_ingest_begin` ouvre le lot, `gsc_ingest_complete` le clôt ; erreur
ou mode partiel impose `gsc_ingest_fail`. Depuis le 04/11/2026, aucun ancien
recalcul dashboard n’est attendu en aval.
Un timestamp récent dans la seule table pages n'est pas une preuve d'exhaustivité.

**Source** :
Un flux qui alimente Cooked en données : tracker (events), formulaires
(webhook Wix), GSC, GBP, DataForSEO, snapshots internes (CPI, SEO,
dashboard), ou SECIB. `freshness_contract` conserve leur registre ; seules les
lignes `enabled=true` ont une fraîcheur attendue. Les six sources
CPI/calibration/dashboard/SEO/math/DFS sont désactivées depuis le 04/11/2026 ;
leur ancienneté reste visible dans les archives sans devenir une panne.
_Avoid_ : « pipeline » pour désigner une source précise (le pipeline est
l'ensemble).

**Lag normal** :
Le retard structurel d'une source en jours, dû à son fournisseur — GSC
consolide à ~J-3 (registre `freshness_contract` : normal 3, warn > 6, critical > 10),
GBP à ~J-4/J-5. Les snapshots suspendus n’ont plus de cadence attendue.
Un âge ≤ lag normal n'est jamais une anomalie.

**Retard** (`<source>_stale`) :
L'âge du dernier jour de donnée dépasse le lag normal au-delà des seuils du
contrat (warn puis critical). Se mesure toujours avec `paris_today()`.
_Avoid_ : « stale » appliqué à une source dont l'âge est dans son lag normal.

**Trou** (`<source>_gap`) :
Un jour manquant À L'INTÉRIEUR de la série, alors que des jours plus
récents existent (ex. la fenêtre mois-calendaire GSC qui perdait les fins
de mois). Un trou ne se voit pas dans l'âge du dernier point.

**Silence** :
Une source événementielle qui n'émet plus alors que sa cadence historique
en prévoyait (forms : ~45/mois → warn > 2 j, critical > 4 j). Le Silence
est le mode de panne des deux incidents d'août 2026 : le système savait
dire « donnée dégradée », jamais « donnée absente ».
_Avoid_ : confondre avec le Retard d'un snapshot — le Silence porte sur des
événements humains, sa normalité dépend de la cadence réelle du site.

**Escalade** :
Un warn ininterrompu ≥ 5 jours devient critical (et pousse sur ntfy), sous
réserve des exclusions existantes. Au plus deux pushs par épisode, puis silence
jusqu’à acquittement. Acquitter signifie « vu, je gère » ; ce n’est pas une preuve
de correction. Cibler les alertes contrôlées, sans vider globalement le stock.
Les familles de calculs retirées sont acquittées explicitement lors du gel.

## Invariants

- **Une seule méthode courante pour l’attribution à l’entrée : la visite observée.**
  `cooked_visit_events` la fournit aux lecteurs de contacts ; `page_visits` compte
  la cohorte d’entrées et les visites ayant contacté. Les contacts sans amont
  restent dans le total site. Les anciennes tables dashboard conservent la
  méthode de leur dernier calcul et ne sont pas présentées comme actualisées.
- **« sur la page » et « à l'entrée » ne se somment jamais** et ne partagent
  jamais un libellé nu « contacts ». Toujours qualifier lequel des deux.
- **Conversion = macro uniquement.** Le booking (micro, intention) n'entre
  jamais dans un décompte de conversions / contacts.
- **Visiteurs distincts non additifs.** Le distinct d'un ensemble de pages ne
  se déduit pas de la somme des distincts par page ; aucun footer filtré ne
  remplace ce calcul par un total global.
- **CWV au grain document.** Le tracker conserve le chemin du chargement
  initial, y compris après navigation SPA. Une révision après retour d'onglet
  remplace la précédente pour `measurement_id` × métrique avant percentile.
  Les anciens événements sans identifiant gardent leur grain historique.
- **Version CPI visible.** Deux définitions ne sont pas reliées comme une
  série homogène. Le graphique conserve les ruptures et les annotations.
- **Une seule source pour la profondeur de lecture : `page_exit.max_scroll`.**
  Voir [ADR-0001](docs/adr/0001-source-unique-profondeur-lecture.md).
  Constat historique du 28/07/2026 : des anciens lecteurs et le producteur SEO
  utilisaient encore `scroll_depth.percent`. Le producteur SEO est retiré depuis
  le 04/11/2026 ; ce constat ne constitue pas une nouvelle tâche de recalcul.
- **Toute statistique de lecture se présente avec sa couverture.** Un dwell
  médian sans son taux de `page_exit` n'est pas un chiffre livrable — la
  couverture varie de 40 % à 92 % selon la page et elle est corrélée
  négativement (−0,32) au dwell mesuré.
- **Toute nouvelle source d'ingestion reçoit sa ligne `freshness_contract`
  dans la migration qui la crée.** Une source sans contrat est invisible du
  monitoring — c'est le trou par lequel les pannes d'août 2026 sont passées
  (ADR-0002). `scripts/c2_alerts_contract.sql` vérifie la couverture des
  sources attendues.
