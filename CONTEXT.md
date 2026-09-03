# Cooked — Contexte du domaine

Système d'analytics first-party pour le site du cabinet Plouton. Ce fichier
fige le **vocabulaire des conversions et de leur attribution** — la source de
confusion identifiée le 13/07/2026 (trois « contacts » différents à l'écran,
dont un calculé avec une méthode obsolète). Il **complète** la taxonomie
macro / micro / engagement de `CLAUDE.md` en tranchant la question de
l'**attribution**.

## Language

### Conversions

**Conversion** / **Contact** :
Un **appel** (`cta_phone_click`) ou un **formulaire envoyé** (`form_submit`
comptant comme macro). Un seul concept, deux mots par convention :
**« conversion »** est le terme technique (code, specs, RPC) ; **« contact »**
est le mot **affiché** dans l'UI (plus lisible pour Me Plouton). = la
macro-conversion de `CLAUDE.md`.
_Avoid_ : « lead », « conversion » comme libellé d'écran, « contact » dans
le code. « **Prospect** » a un sens précis depuis le 10/08/2026 : une row de
`crm_prospects` (identité issue d'un formulaire web, pont SECIB) — ne pas
l'employer pour une conversion web ordinaire.

**Intention** (micro) :
Un clic « prendre RDV » (`cta_booking_click`) qui ne se matérialise pas.
**N'est PAS une conversion / un contact.**
_Avoid_ : compter une intention comme une conversion (erreur de l'audit du
15/05/2026 : 157 « conversions » pour 37 vrais contacts).

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

**Visite recousue** :
Parcours d'un même visiteur reconstitué par `identity_stitch` (couture
aid ↔ sid), segmenté aux trous > 30 min, conversion rattachée à la dernière
pageview ≤ 6 h avant. C'est **la** base de l'attribution « à l'entrée ».
Ne jamais coudre via un `anonymous_id` 32-hex (fallback serveur hash IP|UA,
partageable entre visiteurs).
_Avoid_ : « session » (brute) comme base d'attribution à l'entrée.

**Conversions du site** :
Total des conversions **toutes pages confondues** — le chiffre business de
référence. Se présente **avec son détail** : appels vs formulaires, et la part
qui touche les articles ressources. Source : `site_macro_counts`.
_Avoid_ : présenter un total scopé (ressources seules) comme « les contacts du
site » — c'est le piège de la tuile actuelle (36 affichés pour 210 réels au
13/07/2026).

### Lecture

Le CPI repose à parts égales sur quatre composantes, dont deux — `zr` rétention
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

**Source** :
Un flux qui alimente Cooked en données : tracker (events), formulaires
(webhook Wix), GSC, GBP, DataForSEO, snapshots internes (CPI, SEO,
dashboard), demain SECIB. Chaque source a une ligne dans
`freshness_contract` — le registre est la liste exhaustive de ce qui est
surveillé, et son complément est la liste de ce qui ne l'est pas.
_Avoid_ : « pipeline » pour désigner une source précise (le pipeline est
l'ensemble).

**Lag normal** :
Le retard structurel d'une source en jours, dû à son fournisseur — GSC
consolide à ~J-2/J-3, GBP à ~J-4/J-5, un snapshot nocturne est à J-0/J-1.
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
Un warn ininterrompu ≥ 5 jours devient critical (et pousse sur ntfy).
**Acker la dernière alerte du kind suspend l'escalade et le re-push** —
c'est le sens de `acked` : « vu, je gère ».

## Invariants

- **Une seule méthode pour l'attribution à l'entrée : la visite recousue.**
  Tout compteur « attribué / assisté » (colonne du tableau, fiche article,
  **objectif trimestriel**) doit lire la même base.
  ✅ Résolu le 25/07/2026 : `dashboard_assisted_quarter` lit désormais
  `assisted_contacts_by_entry_path` (visite recousue via `identity_stitch`),
  migration `20260725220100_audit_assisted_contacts_unified`.
  Depuis T-08 (03/09/2026) : elle lit un **snapshot** nocturne (plus de calcul
  à l'affichage) ; les forms sans identifiant sont sur la ligne `(non attribuable)`
  — comptés dans le total site, pas dans le compteur ressources. Pas d'objectif
  trimestriel posé.
- **« sur la page » et « à l'entrée » ne se somment jamais** et ne partagent
  jamais un libellé nu « contacts ». Toujours qualifier lequel des deux.
- **Conversion = macro uniquement.** Le booking (micro, intention) n'entre
  jamais dans un décompte de conversions / contacts.
- **Une seule source pour la profondeur de lecture : `page_exit.max_scroll`.**
  Voir [ADR-0001](docs/adr/0001-source-unique-profondeur-lecture.md).
  ⚠️ Au 28/07/2026, `seo_pages_overview` et `refresh_seo_url_snapshot` lisent
  encore `scroll_depth.percent` — à migrer pour respecter cette définition.
- **Toute statistique de lecture se présente avec sa couverture.** Un dwell
  médian sans son taux de `page_exit` n'est pas un chiffre livrable — la
  couverture varie de 40 % à 92 % selon la page et elle est corrélée
  négativement (−0,32) au dwell mesuré.
- **Toute nouvelle source d'ingestion reçoit sa ligne `freshness_contract`
  dans la migration qui la crée.** Une source sans contrat est invisible du
  monitoring — c'est le trou par lequel les pannes d'août 2026 sont passées
  (ADR-0002). `scripts/c2_alerts_contract.sql` vérifie la couverture des
  sources attendues.
