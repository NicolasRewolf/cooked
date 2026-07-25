-- Restaure le CONTRAT D'INLINING de paris_date() / paris_today().
--
-- CONTEXTE
-- --------
-- 20260604150000_paris_date_seam.sql crée paris_date() SANS clause SET, avec un
-- avertissement explicite dans son en-tête :
--     "⚠️ CONTRAT D'INLINING — NE PAS CASSER (sinon l'index meurt) [...]
--      paris_date NE DOIT JAMAIS recevoir STRICT ni SET search_path"
--
-- Une remédiation en masse de l'advisor Supabase "function_search_path_mutable"
-- (99 fonctions publiques sur 107 en portent une au 25/07/2026) a néanmoins posé
--     SET search_path TO 'public', 'pg_catalog'
-- sur paris_date ET paris_today, directement en prod, hors repo. Le miroir
-- supabase/rpcs.sql régénéré le 23/07/2026 a fidèlement enregistré la régression
-- (lignes 2650 et 2661) sans que rien ne la signale.
--
-- MÉCANISME
-- ---------
-- Postgres n'inline PAS une fonction SQL porteuse d'une clause SET :
-- inline_function() exige proconfig IS NULL. paris_date est donc devenue une
-- boîte noire pour le planner, et l'index fonctionnel idx_events_paris_date,
-- défini sur ((occurred_at AT TIME ZONE 'Europe/Paris')::date) DESC
-- (cf. 20260525170000_events_paris_date_index.sql), ne peut plus être matché.
--
-- MESURE AVANT (prod, 25/07/2026, table events ≈ 2,38 M lignes) :
--   WHERE paris_date(occurred_at) = date '2026-07-24'
--     -> Parallel Index Only Scan on idx_events_occurred + Filter, cost = 495 118
--   WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date = date '2026-07-24'
--     -> Index Scan using idx_events_paris_date,                   cost = 1.79
--   idx_events_paris_date : 18 Mo, idx_scan = 0 depuis sa création.
--
-- 43 call sites dans supabase/rpcs.sql appellent paris_date().
-- Symptôme aval observé : run_rpc_contract_tests échoue tous les jours depuis le
-- 05/07/2026 sur un statement timeout de site_context_export().
--
-- INNOCUITÉ DE LA SUPPRESSION DU SET
-- ----------------------------------
-- Ni paris_date ni paris_today ne sont SECURITY DEFINER (prosecdef = false) :
-- elles s'exécutent avec les droits de l'appelant, il n'y a aucune escalade de
-- privilège à contenir. Leurs corps ne résolvent AUCUN objet par search_path
-- (uniquement la construction AT TIME ZONE, la fonction now() de pg_catalog et
-- un cast ::date). L'advisor Supabase les re-signalera : c'est un faux positif
-- assumé, tracé ici et gardé par scripts/check_migration_paris_date.py.
--
-- Aucun changement de sémantique : corps identiques, mêmes valeurs retournées.
-- Seule la capacité du planner à inliner change.

CREATE OR REPLACE FUNCTION public.paris_date(ts timestamptz)
RETURNS date
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT (ts AT TIME ZONE 'Europe/Paris')::date;
$$;

-- paris_today() délègue désormais au foyer plutôt que de recopier le cast :
-- un seul endroit exprime la règle, et l'appel schema-qualifié rend la
-- fonction insensible au search_path de l'appelant SANS clause SET
-- (c'est la bonne réponse à l'advisor, pas le SET qui casse l'inlining).
CREATE OR REPLACE FUNCTION public.paris_today()
RETURNS date
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT public.paris_date(now());
$$;

COMMENT ON FUNCTION public.paris_date(timestamptz) IS
  'Date calendaire Europe/Paris d''un instant. Foyer unique de la règle "fenêtre Paris" (CLAUDE.md). IMMUTABLE, non-STRICT, SANS clause SET search_path -> s''inline et réutilise idx_events_paris_date. Ne JAMAIS ajouter STRICT ni SET search_path : l''advisor Supabase "function_search_path_mutable" est un faux positif ici (fonction non-SECURITY DEFINER, corps sans resolution par search_path). Contrat garde par scripts/check_migration_paris_date.py.';

COMMENT ON FUNCTION public.paris_today() IS
  'Date calendaire Europe/Paris de maintenant. Meme contrat d''inlining que paris_date() : jamais de STRICT ni de SET search_path.';
