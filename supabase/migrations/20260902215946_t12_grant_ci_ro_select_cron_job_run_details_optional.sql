-- T-12 (mission 02/09/2026) — migration no-op appliquée par erreur pendant le
-- branchement du check CI (SELECT 1). Conservée pour parité schema_migrations.
-- Aucun effet sur le schéma. Ne pas rejouer manuellement.
SELECT 1;
