-- Incident 13/06 (suite) : le rebuild snapshot re-timeoutait à 120 s MALGRÉ
-- le fix du 14/06 (migration 20260614013457 : ALTER FUNCTION ... SET
-- statement_timeout=600000). Cause : pg_cron arme le statement_timeout de
-- SESSION (120 s) sur le SELECT top-level AVANT d'entrer dans la fonction ;
-- le SET attaché à la fonction s'applique trop tard pour reprogrammer ce
-- timer. Preuve empirique : run du 14/06 05:00 = failed 120 s, alors que le
-- ALTER FUNCTION était appliqué depuis 03:34.
--
-- Fix standard pg_cron : poser le SET dans la COMMANDE du job. Exécuté comme
-- statement distinct AVANT le SELECT, dans la même session worker, il fixe
-- le timeout à 600 s pour le rebuild qui suit. Schedule inchangé (0 3 * * *).
-- L'ALTER FUNCTION de la migration précédente est conservé (défense en
-- profondeur, sans effet de bord).
--
-- VÉRIFIÉ le 15/06/2026 à 01:42 Paris : run jetable avec la commande
-- corrigée = succeeded en 152 s (donc > 120 s : aurait échoué à chaque fois
-- avec l'ancien plafond). Snapshot rebuildé, 697 lignes.
--
-- RESTE (P1, non traité ici) : le rebuild est lent par design (~152 s et
-- croissant avec le bloat events) — à optimiser avant que 600 s ne suffise
-- plus (matérialiser seo_pages_overview / fenêtre 365j / incrémental).
-- RESTE (P1, monitoring) : cooked_alerts_refresh() n'a levé AUCUNE alerte
-- sur le snapshot périmé / cron en échec pendant 2 nuits — ajouter un check
-- pipeline_health dans le refresh d'alertes horaire.

select cron.schedule(
  'refresh_seo_url_snapshot',
  '0 3 * * *',
  $cmd$ set statement_timeout = '600s'; select public.refresh_seo_url_snapshot(); $cmd$
);
