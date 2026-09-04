-- T-01 ter (mission 02/09/2026, invariant I1) — privilèges par défaut sur les TABLES et SÉQUENCES.
-- Mesure du 04/09/2026 09:00 Paris : `pg_default_acl` pour `postgres` dans `public` donne encore ALL
-- (arwdDxtm) à `anon` et `authenticated` sur les tables et rwU sur les séquences (les fonctions ont été
-- corrigées au T-01) ; 22 des 36 tables portent ces GRANT, dont `events` : `has_table_privilege('anon',
-- 'events', 'TRUNCATE') = true`. RLS deny-all bloque SELECT/INSERT/UPDATE/DELETE via PostgREST, mais
-- TRUNCATE n'est PAS soumis à RLS. Aucun consommateur légitime : dashboard et Edge lisent en service_role,
-- la CI en `cooked_ci_ro`. Objectif : plus aucun GRANT anon/authenticated sur une relation de `public`,
-- et plus jamais par défaut (fin des « récidives » constatées les 25/07 et 31/08).
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES    FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM PUBLIC, anon, authenticated;
