-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Securite : Postgres accorde EXECUTE a PUBLIC a la creation d'une fonction.
-- Le GRANT ... TO service_role des migrations precedentes n'a donc RIEN
-- restreint : les trois RPC math_* etaient appelables par `anon` via
-- /rest/v1/rpc/... (advisor 0028/0029). math_visit_sequences expose des
-- parcours de navigation — aucune raison qu'ils soient publics.
REVOKE ALL ON FUNCTION public.math_visit_sequences(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.math_internal_edges(integer)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.math_refresh_snapshots(integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.math_visit_sequences(integer)   TO service_role;
GRANT EXECUTE ON FUNCTION public.math_internal_edges(integer)    TO service_role;
GRANT EXECUTE ON FUNCTION public.math_refresh_snapshots(integer) TO service_role;
