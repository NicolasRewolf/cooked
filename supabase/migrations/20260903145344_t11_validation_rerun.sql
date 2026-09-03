-- T-11 — validation de la garde par marqueur (03/09/2026 16:55 Paris).
-- On recule le marqueur « dernier refresh complet » AVANT l'ingestion GSC du jour
-- (10:35 UTC) : cooked_refresh_after_gsc_pending() passe à true et le tick de
-- 15:00 UTC doit rejouer la séquence complète, à une heure où l'ancienne garde
-- « ingestion du jour » l'aurait aussi acceptée mais sans journal. Attendu :
-- 6 lignes dans refresh_runs (5 étapes + _total), marqueur ré-avancé à 15:00 UTC.
-- Données rejouées à l'identique (snapshots idempotents, cpi_daily ON CONFLICT).
INSERT INTO public.cooked_config (key, value, updated_at)
VALUES ('last_full_refresh_after_gsc_at', '2026-09-03 10:00:00+00', now())
ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
