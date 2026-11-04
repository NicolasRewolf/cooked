# ADR-0001 — Source unique de la profondeur de lecture

- **Statut** : accepté le 28/07/2026 ; portée actualisée le 04/11/2026.
- **Concerne** : interprétation des événements de lecture conservés.

## Décision

**`page_exit.props.max_scroll` est la source de la profondeur de lecture.**
C’est une mesure continue de 0 à 100, portée par le même événement que la durée.
`scroll_depth.props.percent` décrit les paliers franchis en cours de lecture ;
il ne doit pas être mélangé à cette mesure pour combler sa couverture.

## Pourquoi

Les anciens lecteurs utilisaient ces deux sources sous le même nom. Les paliers
et le maximum continu ne décrivent pourtant pas la même précision et n’ont pas
la même couverture. Les combiner change le sens du chiffre obtenu.

Toute lecture de la profondeur doit donc indiquer la couverture de `page_exit`.
Un événement de sortie absent reste une donnée manquante.

## Portée actuelle

Les anciens scores et lecteurs de profondeur sont retirés. Le tracker conserve
ses événements ; cette décision n’ajoute aucune métrique au tableau éditorial et
ne justifie pas de rétablir un score. Les règles des visites et contacts restent
celles de [CONTEXT.md](../../CONTEXT.md).

La justification chiffrée du 28/07 et les anciens consommateurs restent dans
[l’ADR historique](https://github.com/NicolasRewolf/cooked/blob/b6aa6370b9041763814bc0b1253182ece2694772/docs/adr/0001-source-unique-profondeur-lecture.md).
