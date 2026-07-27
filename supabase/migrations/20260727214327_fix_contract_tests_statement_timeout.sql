-- Bloc 0 / A1 — run_rpc_contract_tests est mort depuis le 04/07/2026.
--
-- La duree du harnais croit avec le volume de `events` (54 s le 25/06 -> 114 s
-- le 04/07), puis bute sur un plafond de 120 s, la valeur par defaut de
-- statement_timeout.
--
-- ATTENTION : le commentaire pose ici affirmait que le SET de la commande
-- pg_cron ne s'applique pas. C'est FAUX et rectifie par la migration
-- 20260727220006 — au moment des echecs, le job n'avait tout simplement
-- aucun SET (ajoute le 27/07 a 22:34 par 20260727203415).
--
-- Reste vrai : un SET porte par la DEFINITION de la fonction ne protege pas,
-- car PostgreSQL arme le minuteur au debut du statement de plus haut niveau.
-- Cette migration est donc insuffisante seule ; voir 20260727215029.

ALTER FUNCTION public.run_rpc_contract_tests() SET statement_timeout TO '900s';
