-- Sprint perf (25/05/2026) — Postgres best practices : indexes + sécurité
--
-- Contexte :
--   - gsc_query_page_daily : 1 012 266 lignes (stats étaient à 3 060 → planner aveugle)
--   - gsc_query_daily      : 878 814 lignes (stats étaient à 2 910)
--   - gsc_path_daily       : 122 829 lignes (stats étaient à 526)
--   ANALYZE lancé en dehors de cette migration pour corriger les stats.
--
-- Changements :
--   1. Drop 2 index non utilisés (23 MB de write overhead inutile)
--   2. Ajout index composites (path, day DESC) sur les 2 grandes tables GSC
--      → accélère gsc_top_queries_for_path, gsc_page_performance,
--        gsc_page_daily_series, cooked_page_daily_series, pages_pulse par-path
--   3. canonical_path : SET search_path = '' (WARN sécurité Supabase)

-- ── 1. Drop des index jamais utilisés ────────────────────────────────────────

-- 11 MB, 0 utilisation depuis le démarrage de l'instance
DROP INDEX IF EXISTS public.gsc_query_daily_query_idx;

-- 12 MB, 0 utilisation depuis le démarrage de l'instance
DROP INDEX IF EXISTS public.gsc_query_page_daily_query_idx;


-- ── 2. Index composites (path, day DESC) ──────────────────────────────────────
-- Créés dans 20260525160000_drop_redundant_indexes.sql (avant DROP path_idx).
-- IF NOT EXISTS ici = no-op si déjà appliqué via 251600 ; rattrape les envs
-- où 301200 a été appliqué avant correction de l'ordre 251600.
CREATE INDEX IF NOT EXISTS gsc_query_page_daily_path_day_idx
  ON public.gsc_query_page_daily (path, day DESC);
CREATE INDEX IF NOT EXISTS gsc_path_daily_path_day_idx
  ON public.gsc_path_daily (path, day DESC);


-- ── 3. canonical_path : search_path fixe ─────────────────────────────────────
-- Fonction IMMUTABLE sans SET search_path → alerte WARN Supabase Linter.
-- Toutes les fonctions appelées (char_length, right, left, normalize,
-- COALESCE, NULLIF) sont dans pg_catalog, accessible même avec search_path = ''.
CREATE OR REPLACE FUNCTION public.canonical_path(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN char_length(n) > 1 AND right(n, 1) = '/' THEN left(n, char_length(n) - 1)
    ELSE COALESCE(NULLIF(n, ''), '/')
  END
  FROM (SELECT normalize(COALESCE(p, ''), NFC) AS n) AS s;
$function$;


-- ── 4. Stats planner après changements d'index ─────────────────────────────────
ANALYZE public.gsc_path_daily;
ANALYZE public.gsc_query_daily;
ANALYZE public.gsc_query_page_daily;
