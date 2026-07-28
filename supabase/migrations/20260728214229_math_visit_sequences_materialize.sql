-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Perf 3/3 — la CTE `contacts` contient form_submits_attributed(). Sans
-- AS MATERIALIZED, le planner la replace dans le nested loop de `vc` et
-- reexecute la fonction une fois par visite (~16 000 x 20 ms = 5 min).
-- Toutes les CTE reutilisees sont desormais materialisees explicitement.
-- Le SET statement_timeout porte par la fonction est retire : il est sans
-- effet, le timer du statement etant arme par l'appelant.
-- Corps remplace par 20260728215013 (etat final).

ALTER FUNCTION public.math_visit_sequences(integer) RESET statement_timeout;
ALTER FUNCTION public.math_internal_edges(integer) RESET statement_timeout;
