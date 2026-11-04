-- La lecture des événements sur 90 jours dépasse le délai REST par défaut de 8 s.
-- Délai réservé à cette RPC ; aucun changement des rôles, du calcul ou des filtres.
BEGIN;
ALTER FUNCTION public.page_view_counts(integer) SET statement_timeout TO '30s';
NOTIFY pgrst, 'reload schema';
COMMIT;
