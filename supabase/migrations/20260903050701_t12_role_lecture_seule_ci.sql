-- T-12 (mission 02/09/2026, issue #113) — appliquée en prod le 03/09/2026 07:07 Paris (version 20260903050701)
-- par la session de mission, SANS SAVOIR que la session Cursor du 02/09 23:00 avait déjà créé le rôle
-- (20260902212045) et le lecteur cooked_ci_cron_jobs() (20260902220012). Redondante mais appliquée :
-- conservée pour la parité schema_migrations (gate prod-drift). Effets nets : NOLOGIN/NOINHERIT non appliqués
-- (rôle déjà existant, bloc IF NOT EXISTS), statement_timeout 30 s et default_transaction_read_only pour le rôle,
-- policy SELECT explicite sur freshness_contract (RLS deny-all → sans policy le GRANT du 02/09 ne rendait rien).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cooked_ci_ro') THEN
    CREATE ROLE cooked_ci_ro NOLOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER NOREPLICATION;
  END IF;
END $$;
ALTER ROLE cooked_ci_ro SET statement_timeout = '30s';
ALTER ROLE cooked_ci_ro SET default_transaction_read_only = on;
GRANT USAGE ON SCHEMA public, supabase_migrations, cron TO cooked_ci_ro;
GRANT SELECT ON supabase_migrations.schema_migrations TO cooked_ci_ro;
GRANT SELECT ON cron.job TO cooked_ci_ro;
GRANT SELECT ON public.freshness_contract TO cooked_ci_ro;
DROP POLICY IF EXISTS freshness_contract_ci_ro ON public.freshness_contract;
CREATE POLICY freshness_contract_ci_ro ON public.freshness_contract FOR SELECT TO cooked_ci_ro USING (true);
COMMENT ON ROLE cooked_ci_ro IS 'Lecture seule pour la CI (prod-drift : pg_proc, schema_migrations, cron.job, freshness_contract). Mission 02/09/2026, T-12.';
