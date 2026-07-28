-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Briques d'extraction du framework d'analyse mathematique : math_visit_sequences
-- (toutes les visites recousues, converties ET non converties — denominateur
-- absent de conversion_journeys) et math_internal_edges (aretes du graphe).
-- NOTE : les corps de ces deux fonctions ont ete remplaces par les migrations
-- suivantes (perf, puis fenetre de rattachement). Voir 20260728215013 pour
-- l'etat final de math_visit_sequences et 20260728213410 pour celui de
-- math_internal_edges. Cette migration ne conserve que les GRANT et COMMENT,
-- les CREATE OR REPLACE ulterieurs faisant foi pour le code.

COMMENT ON FUNCTION public.math_visit_sequences(integer) IS
'Visites recousues (identity_stitch, segments 30 min) agregees par sequence
distincte, converties ET non converties. Denominateur manquant pour Markov /
Shapley : conversion_journeys ne rend que les convertisseurs. Paths
dedupliques par premiere occurrence, troncature au contact +3 min.';

COMMENT ON FUNCTION public.math_internal_edges(integer) IS
'Aretes du graphe de navigation : kind=flow (transitions consecutives
observees dans les visites recousues) et kind=click (click_internal, avec
placement). Les cibles de clic sans pageview (URL accentuees redirigees)
sont resolues vers leur forme desaccentuee quand celle-ci existe —
dst_resolved trace la substitution.';

GRANT EXECUTE ON FUNCTION public.math_visit_sequences(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.math_internal_edges(integer) TO service_role;
