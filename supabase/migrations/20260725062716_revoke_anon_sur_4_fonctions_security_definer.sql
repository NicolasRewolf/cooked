-- Ferme l'accès `anon`/`authenticated` sur 4 fonctions SECURITY DEFINER.
--
-- PROBLÈME
-- --------
-- SECURITY.md:36 prescrit un REVOKE sur toute RPC. Rien ne le vérifie, et
-- 4 fonctions créées après coup l'ont manqué. Vérifié en prod le 25/07/2026
-- via has_function_privilege('anon', oid, 'EXECUTE') :
--
--   cooked_refresh_after_gsc        SECURITY DEFINER   anon = true
--   dashboard_expertises_kpis       SECURITY DEFINER   anon = true
--   dashboard_expertises_overview   SECURITY DEFINER   anon = true
--   dashboard_expertises_trend      SECURITY DEFINER   anon = true
--
-- Les 13 autres fonctions `dashboard_*` sont déjà à anon = false : ce n'est pas
-- un défaut global, c'est un REVOKE oublié sur les fonctions ajoutées les
-- 02-03/07/2026 pour l'onglet Expertises. Cette migration les aligne sur le
-- motif déjà en place.
--
-- IMPACT DE LA FUITE
-- ------------------
-- 1. Les 3 `dashboard_expertises_*` exposent, sans aucune authentification, la
--    performance commerciale des 14 pages expertise (visiteurs, contacts, mix
--    de canaux payant/organique) à qui connaît l'URL du projet Supabase — celle-ci
--    figure dans le bundle public du dashboard.
-- 2. `cooked_refresh_after_gsc` est pire : c'est un DÉCLENCHEUR, pas une lecture.
--    Un appel anonyme lance la séquence complète de refresh (4 étapes, plusieurs
--    minutes de CPU et d'I/O) sur une instance qui a saturé son disque le
--    24/07/2026. Répété, c'est un déni de service à un appel de coût.
--
-- INNOCUITÉ
-- ---------
-- Le dashboard lit exclusivement côté serveur avec la clé service
-- (dashboard/src/lib/supabase-admin.ts, importé par call-rpc.ts sous
-- `import "server-only"`), donc via le rôle `service_role` — non concerné par ce
-- REVOKE. Les crons s'exécutent en `postgres`. Aucun appelant légitime ne passe
-- par `anon` ni `authenticated`.

-- Signatures relevées en prod (p.oid::regprocedure) — dashboard_expertises_overview
-- prend (text, integer), pas (text) : une signature approximative ferait échouer
-- la migration au lieu de fermer la porte.

REVOKE ALL ON FUNCTION public.cooked_refresh_after_gsc()               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dashboard_expertises_kpis(text)          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dashboard_expertises_overview(text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dashboard_expertises_trend(text)         FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.cooked_refresh_after_gsc()               TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_expertises_kpis(text)          TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_expertises_overview(text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.dashboard_expertises_trend(text)         TO service_role;
