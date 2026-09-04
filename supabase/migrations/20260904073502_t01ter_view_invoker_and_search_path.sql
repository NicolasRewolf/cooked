-- T-01 ter (suite) — deux restes relevés par la re-mesure du 04/09/2026 (02-apres.md, Q-10 / advisors) :
--   1. la vue `cpi_opportunite_contact` (renommée depuis `cpi_gisement` le 23/07) est la seule des 11 vues
--      sans `security_invoker` : elle s'exécutait avec les droits de son propriétaire.
--   2. `page_taxonomy_theme_from_slug` (T-15, 03/09) a été créée sans `search_path` figé (advisor 0011) —
--      régression de la mission elle-même, corrigée ici. `paris_date` / `paris_today` gardent volontairement
--      `proconfig = NULL` (contrat d'inlining, migration 20260725045430) : non touchées.
ALTER VIEW public.cpi_opportunite_contact SET (security_invoker = true);
ALTER FUNCTION public.page_taxonomy_theme_from_slug(text) SET search_path = public, pg_catalog;
