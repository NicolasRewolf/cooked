-- Passe les 3 refresh dashboard de ~10:15 Paris à 06:00 Paris (04:00 UTC en CEST).
-- Demande Nicolas 07/07/2026 : données Cooked fraîches chaque matin à 6h.
-- alter_job = changement d'horaire en place (aucun risque de doublon, commande conservée).
-- Espacés pour ne pas se chevaucher (resources ~6min, en hausse).
-- Note : horaire figé en UTC → 06:00 Paris l'été (CEST), 05:00 l'hiver (CET),
-- même comportement DST que le reste des crons Cooked.
-- Caveat : les colonnes GSC/CPI de la fiche restent alimentées par l'ingest GSC
-- (~08:00 Paris) et le snapshot CPI (09:30 Paris) → à 6h elles reflètent J-1.
SELECT cron.alter_job(jobid, schedule := '0 4 * * *')
FROM cron.job WHERE jobname = 'refresh-dashboard-snapshots';

SELECT cron.alter_job(jobid, schedule := '12 4 * * *')
FROM cron.job WHERE jobname = 'refresh-dashboard-expertises';

SELECT cron.alter_job(jobid, schedule := '16 4 * * *')
FROM cron.job WHERE jobname = 'refresh-dashboard-assisted';
