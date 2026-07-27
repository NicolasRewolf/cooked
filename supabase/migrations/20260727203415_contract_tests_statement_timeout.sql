-- Le job run_rpc_contract_tests (jobid 2) tournait sans SET statement_timeout,
-- donc au défaut de 120 s. Au dernier run vert (04/07/2026) la somme des durées
-- du batch faisait 113,4 s : 6,6 s de marge. La donnée a grossi, la barre a été
-- franchie -> échec quotidien depuis le 05/07/2026 (23 jours), avec une RPC
-- différente qui meurt chaque jour selon l'endroit où le cumul atteint 120 s.
--
-- Même protection que cooked-refresh-after-gsc (jobid 46, statement_timeout 2400s).
-- 600 s = ~5x la durée observée du batch, exécuté à 05:30 Paris (trafic bas).
SELECT cron.alter_job(
  2,
  command => $cmd$SET statement_timeout='600s'; SELECT public.run_rpc_contract_tests();$cmd$
);
