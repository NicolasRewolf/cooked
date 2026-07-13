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
_Avoid_ : « lead », « prospect », « conversion » comme libellé d'écran,
« contact » dans le code.

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

## Invariants

- **Une seule méthode pour l'attribution à l'entrée : la visite recousue.**
  Tout compteur « attribué / assisté » (colonne du tableau, fiche article,
  **objectif trimestriel**) doit lire la même base.
  ⚠️ Au 13/07/2026, `dashboard_assisted_quarter` utilise encore la **session
  brute** (19 vs 38 sur une même fenêtre 28 j) — à migrer vers
  `identity_stitch` pour respecter cette définition.
- **« sur la page » et « à l'entrée » ne se somment jamais** et ne partagent
  jamais un libellé nu « contacts ». Toujours qualifier lequel des deux.
- **Conversion = macro uniquement.** Le booking (micro, intention) n'entre
  jamais dans un décompte de conversions / contacts.
