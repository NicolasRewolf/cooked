# ADR-0001 — Une seule source pour la profondeur de lecture : `page_exit.max_scroll`

- **Statut** : accepté
- **Date** : 28/07/2026
- **Concerne** : `cooked_page_index` (`zl`), `content_performance`,
  `seo_pages_overview`, `refresh_seo_url_snapshot`

## Contexte

Le système émet deux événements qui mesurent la profondeur de lecture, et les RPC
se répartissent entre les deux sans que rien ne le signale :

| Source | Émission | Nature | Lecteurs |
|---|---|---|---|
| `page_exit.props.max_scroll` | une fois, à la sortie | continue (0–100) | `cooked_page_index`, `content_performance` |
| `scroll_depth.props.percent` | au franchissement | paliers 25 / 50 / 75 / 100 | `seo_pages_overview`, `refresh_seo_url_snapshot` |

Deux chiffres publiés sous le même mot « scroll » ne mesuraient donc pas la même
chose. Il fallait trancher avant de réifier la Lecture en un module unique.

## Décision

**`page_exit.props.max_scroll` est la source unique de `scroll_pct`.**
`scroll_depth` reste émis — il sert à mesurer la progression en cours de lecture —
mais il n'alimente plus aucune statistique de profondeur agrégée.

## Justification

Mesures du 28/07/2026 sur 4 467 visites (fenêtre 20 → 26/07/2026,
`events_human`, une ligne par session × path) :

- **Couverture** — `page_exit.max_scroll` : **74,4 %** des visites.
  `scroll_depth.percent` : **51,6 %**. L'intuition qu'une source indépendante de
  `page_exit` couvrirait davantage est fausse : `scroll_depth` ne récupère que
  **2,6 %** de visites que `page_exit` n'a pas.
- **Granularité** — `scroll_depth` est quantifié aux paliers franchis, donc il
  arrondit systématiquement vers le haut : médiane **50 %** contre **40 %** pour
  `max_scroll` sur les mêmes visites. Il surestime la profondeur réelle.
- **Accord** — les deux corrèlent à **0,906**, écart médian 11 points. Le choix
  ne change donc pas les classements, seulement le niveau et la couverture.
- **Cohérence de grain** — `max_scroll` arrive dans le même événement que
  `duration_seconds`. Les deux moitiés d'une Lecture partagent ainsi exactement
  la même couverture, ce qui rend l'invariant « toute statistique de lecture se
  présente avec sa couverture » vérifiable par un seul chiffre.

## Conséquences

- `zl` du CPI **ne bouge pas** : `cooked_page_index` lisait déjà `max_scroll`.
  Cette décision **n'entraîne aucun restatement du CPI**.
- `seo_pages_overview` et `refresh_seo_url_snapshot` doivent migrer. Leurs
  colonnes de scroll baisseront d'environ 10 points (effet de dé-quantification,
  pas une dégradation) et leur couverture montera de ~52 % à ~74 %.
- La couverture de `page_exit` devient un point de fragilité assumé et unique :
  59 % sur 28 j, 50 % en desktop. Elle est traitée séparément — voir la piste de
  reconstruction depuis `engagement_tick` (écart médian 0,44 s avec
  `duration_seconds`), qui relève d'un changement de comportement à annoter, pas
  de cette décision.

## Alternatives écartées

- **Garder les deux et documenter la différence** — c'est l'état actuel ; il a
  produit deux chiffres incomparables sous un même libellé pendant des mois sans
  que personne le remarque.
- **Prendre le max des deux sources** — remonterait la couverture à ~77 % mais
  mélangerait une mesure continue et une mesure quantifiée dans la même colonne,
  rendant la valeur ininterprétable et le biais impossible à corriger ensuite.
