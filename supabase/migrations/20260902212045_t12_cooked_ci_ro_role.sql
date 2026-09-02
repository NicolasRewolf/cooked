-- T-12 (mission 02/09/2026, issue #113) — rôle lecture seule pour la CI.
-- Mot de passe POSÉ HORS FICHIER (session Cursor 02/09/2026) — ne jamais le committer.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cooked_ci_ro') THEN
    CREATE ROLE cooked_ci_ro LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS CONNECTION LIMIT 4;
  END IF;
END $$;

COMMENT ON ROLE cooked_ci_ro IS
  'CI lecture seule (mission 02/09 T-12) : drift prod↔repo. Pas de PII métier nécessaire ; SELECT catalogue + migrations + cron + freshness_contract.';

GRANT USAGE ON SCHEMA public TO cooked_ci_ro;
GRANT USAGE ON SCHEMA cron TO cooked_ci_ro;
GRANT USAGE ON SCHEMA supabase_migrations TO cooked_ci_ro;

-- Catalogue Postgres : lecture déjà ouverte aux rôles non-super ; explicite pour la doc.
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO cooked_ci_ro;

GRANT SELECT ON TABLE supabase_migrations.schema_migrations TO cooked_ci_ro;
GRANT SELECT ON TABLE cron.job TO cooked_ci_ro;
GRANT SELECT ON TABLE public.freshness_contract TO cooked_ci_ro;
GRANT SELECT ON TABLE public.cooked_config TO cooked_ci_ro;

-- Futures tables de ces schémas : pas de default GRANT large — on reste minimal.
