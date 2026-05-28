-- Sprint 33+ (25/05/2026) — Nettoyage index redondants
--
-- Audit live Supabase (25/05/2026) : indexes_size > table_size sur
-- gsc_query_page_daily (247 MB index vs 165 MB data). 6 index redondants
-- identifiés — couverts soit par la PK, soit par un composite plus large.
--
-- Impact attendu : ~75-120 MB libérés, INSERTs GSC + DFS plus rapides,
-- zéro régression de lecture (les query patterns utilisés par les RPCs
-- sont tous couverts par les index conservés).
--
-- Règle appliquée :
--   - Un index sur colonne X est redondant si un index composite sur
--     (X, Y, ...) ou la PK commençant par X existe déjà → l'index simple
--     n'est jamais utilisé seul par le planner quand le composite couvre.
--   - Un index (A) seul est redondant si un index (A, B) existe, car la
--     PK / composite satisfait toute lookup sur A seul (leftmost prefix).

-- ============================================================
-- gsc_path_daily — PK (day, path)
-- ============================================================

-- Composites path-first AVANT drop des index path seuls (greenfield-safe).
CREATE INDEX IF NOT EXISTS gsc_path_daily_path_day_idx
  ON public.gsc_path_daily (path, day DESC);

-- day DESC seul : redondant, PK commence par day → range scan day OK
DROP INDEX IF EXISTS public.gsc_path_daily_day_idx;

-- path seul : redondant une fois path_day_idx en place (leftmost prefix)
DROP INDEX IF EXISTS public.gsc_path_daily_path_idx;

-- gsc_path_daily_path_day_idx : gsc_page_performance, gsc_page_daily_series

-- ============================================================
-- gsc_query_daily — PK (day, query)
-- ============================================================

-- day DESC seul : redondant, PK commence par day
DROP INDEX IF EXISTS public.gsc_query_daily_day_idx;

-- Pas d'index sur query seul ni query-first — intentionnel : les RPCs
-- agrègent par query sur une fenêtre de jours (scan PK par day range,
-- puis GROUP BY query). Un index query-first n'aiderait pas ces patterns.

-- ============================================================
-- gsc_query_page_daily — PK (day, path, query)
-- ============================================================

CREATE INDEX IF NOT EXISTS gsc_query_page_daily_path_day_idx
  ON public.gsc_query_page_daily (path, day DESC);

-- day DESC seul : redondant, PK commence par day (247 MB indexes !)
DROP INDEX IF EXISTS public.gsc_query_page_daily_day_idx;

-- path seul : redondant une fois path_day_idx en place
DROP INDEX IF EXISTS public.gsc_query_page_daily_path_idx;

-- gsc_query_page_daily_path_day_idx : gsc_page_daily_series, gsc_top_queries_for_path

-- ============================================================
-- dfs_keyword_volume — PK (keyword, location_code)
-- ============================================================

-- keyword seul : redondant, PK commence par keyword (leftmost prefix)
DROP INDEX IF EXISTS public.dfs_kw_volume_keyword_idx;

-- Conservés : dfs_kw_volume_volume_idx (search_volume DESC NULLS LAST)
--             dfs_kw_volume_synced_idx (last_synced_at)
--   Utilisés par le script dfs_sync.py pour tri et détection stale.
