# Fenêtres d’analyse et provenance des snapshots maths

La migration `20261103100420_unify_analytics_windows.sql`, appliquée le
**03/11/2026**, ajoute la provenance nécessaire au rapport maths. Seules les
lignes recalculées depuis son application attestent leur période exacte.

## Ce qui change

| Lecture | Avant | Nouveau contrat |
|---|---|---|
| Parcours maths | Pageviews/téléphones sur une fenêtre glissante à l’heure ; formulaires clos à J-1. | Même intervalle de jours Paris clos à J-1 pour tous les événements ; URL transmise à la classification du canal. |
| Graphe de navigation | Fenêtre glissante à l’heure du calcul. | Même intervalle Paris que les parcours du refresh. |
| Synthèse Python | Snapshot hebdomadaire croisé avec des contacts des derniers jours au moment du lancement. | Contacts relus entre les dates exactes du snapshot ; parcours et graphe de la même génération. |
| Contacts illisibles | Erreur remplacée par un dictionnaire vide, interprété comme zéro. | Champs `direct_contacts` et `assist_ratio` à `null`, qualification des ponts suspendue, rapport partiel. |

Le refresh `math_refresh_snapshots(N)` remplace les deux snapshots pour la
fenêtre demandée dans une même transaction. Il écrit sur leurs lignes :

- `window_days` : nombre de jours inclus ;
- `window_start` et `window_end` : dates Paris inclusives ;
- `computed_at` : instant commun de la génération, avec fuseau ;
- `calculation_version` : `paris_j1_v1`.

Les bornes SQL vont du début du premier jour Paris au début du jour suivant
`window_end`, exclu. La durée réelle peut donc différer de `N × 24 heures`
lors d’un changement d’heure. `window_end` correspond à la veille du jour
Paris de `computed_at`.

Le rapport vérifie ces métadonnées et leur uniformité. Les anciennes lignes
ont des bornes/version inconnues ; elles ne sont pas antidatées ni déclarées
conformes. Un nouveau refresh produit la provenance attendue.

Les contacts sont lus par
`macro_contacts_by_path(start_date, end_date)`, avec ces dates explicites.
Cette lecture peut inclure des corrections arrivées après la génération du
snapshot : une fenêtre identique ne constitue pas une révision immuable de
la donnée. La date du snapshot reste visible dans le rapport.

## Exécuter et lire le résultat

Installer les dépendances du rapport et des tests :

```sh
.venv/bin/python -m pip install -e '.[dev,math]'
.venv/bin/python scripts/advanced_math_analytics.py --module all --window 28
```

La source Supabase lit uniquement les tables/RPC ; elle exige la variable
`SUPABASE_SECRET_KEY` déjà configurée. Aucune clé n’est à placer dans le dépôt.
Le rapport ne déclenche pas lui-même le refresh des snapshots.

Pour rejouer un export local sans clé ni appel réseau :

```sh
.venv/bin/python scripts/advanced_math_analytics.py \
  --source cache --cache-dir /tmp/cooked-cache --module all --window 28 \
  --json-out /tmp/cooked-report.json
```

| Résultat | Interprétation |
|---|---|
| Code `0`, JSON `status: complete` | Les lectures nécessaires au rapport ont réussi et les métadonnées requises sont comparables. |
| Code `2`, JSON `status: partial` | Une donnée comparative manque, ses dates sont inconnues, ou les snapshots ne sont pas comparables. Les analyses indépendantes restent présentes. |
| Échec avant rapport | Source principale absente ou inexploitable ; aucun résultat complet n’est annoncé. |

`sources` expose la provenance des snapshots. `comparison.status` distingue
`available`, `unavailable` et `incompatible`. Si les contacts seuls manquent,
le classement des modèles reste lisible avec des valeurs directes/indices
inconnus et `invisible_bridges: null`. Si les snapshots diffèrent, les deux
synthèses sont `null`. `null` signifie non calculé ; `[]` signifie calculé,
sans page répondant aux critères. Le statut ne certifie ni fraîcheur courante,
ni exhaustivité de collecte, ni effet causal.

## Contrat du cache

Le module `all` lit `visit_sequences_28.json`, `internal_edges_28.json`,
`macro_contacts_28.json`, `gsc_daily.json` et `annotations.json`.
Le suffixe change avec `--window`.

Les snapshots acceptent une liste avec les métadonnées sur chaque ligne, ou
une enveloppe `{ "metadata": ..., "rows": [...] }`. Exemple synthétique pour
`visit_sequences_28.json` :

```json
{
  "metadata": {
    "window_days": 28,
    "window_start": "2026-10-01",
    "window_end": "2026-10-28",
    "computed_at": "2026-10-29T06:00:00+00:00",
    "calculation_version": "paris_j1_v1"
  },
  "rows": [
    { "journey": ["/post/exemple"], "converted": false,
      "entry_channel": "organic_google", "n": 3 }
  ]
}
```

`internal_edges_28.json` porte les mêmes métadonnées et des lignes
`src`, `dst`, `kind`, `placement`, `weight`, `dst_resolved`. Un graphe connu
vide peut utiliser la même enveloppe avec `rows: []`.

Les contacts comportent des lignes `path`, `contacts` et au minimum les deux
dates dans les métadonnées. Un zéro confirmé exige une enveloppe datée :

```json
{
  "metadata": { "window_start": "2026-10-01", "window_end": "2026-10-28" },
  "rows": []
}
```

Un fichier manquant ou un simple `[]` sans dates ne prouve pas ce zéro.
Les anciennes listes restent lisibles pour les analyses individuelles, mais
ne permettent pas de croisement si leur période n’est pas vérifiable.
L’option `--dump-cache`, qui n’effectuait aucun export, a été retirée.

## Lecture des modèles

Le retrait Markov est un scénario du modèle ; les « équivalents contacts »
ne sont pas des pertes observées. L’indice de pont rapproche des actions de
contact et des visites converties, deux grains distincts : ce n’est pas une
mesure directe de la part de parcours convertis ailleurs. Le champ JSON
historique `assist_ratio` conserve ce calcul pour compatibilité ; le texte
le nomme « indice ». Le contrôle synthétique produit un écart estimé sous
hypothèses de comparabilité des témoins, sans démontrer à lui seul une cause.
