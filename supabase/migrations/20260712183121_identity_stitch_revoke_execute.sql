-- refresh_identity_stitch est un refresher interne (cron) : pas
-- d'exécution via l'API REST par anon/authenticated (advisor 0028/0029).
REVOKE EXECUTE ON FUNCTION public.refresh_identity_stitch(integer) FROM anon, authenticated, public;
