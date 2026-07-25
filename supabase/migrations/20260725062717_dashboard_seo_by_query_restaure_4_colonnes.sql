-- Répare l'onglet /seo du dashboard, cassé depuis le 10/07/2026.
--
-- PROBLÈME
-- --------
-- La migration 20260710183000_gsc_is_branded.sql a réécrit dashboard_seo_by_query
-- pour remplacer le prédicat `query NOT ILIKE '%plouton%'` par le prédicat unique
-- public.gsc_is_branded(query) — c'est un progrès, il est conservé ici.
--
-- Mais la réécriture a perdu au passage la CTE `qprev` (période précédente) et les
-- QUATRE colonnes qu'elle alimentait :
--     clicks_prev, position_prev, ctr_expected, opportunity_clicks
--
-- Or dashboard/src/data/rpc-schemas.ts:128-149 les déclare toutes les quatre, et
-- `clicks_prev: num` n'est même pas nullable. Le .parse() lève donc à chaque appel :
-- l'onglet /seo rend une page d'erreur depuis 15 jours, et le composant
-- GisementsPanel qui consomme `opportunity_clicks` est du code mort.
--
-- Vérifié en prod le 25/07/2026 : pg_get_function_result() renvoie 16 colonnes,
-- le schéma Zod en exige 20.
--
-- CORRECTIF
-- ---------
-- On repart de la version en prod (avec gsc_is_branded) et on réintroduit la CTE
-- `qprev` + les 4 colonnes, dans l'ordre exact du schéma Zod. La CTE `qprev` utilise
-- elle aussi gsc_is_branded, pour que les deux périodes comparées appliquent le même
-- filtre branded — l'ancienne version utilisait NOT ILIKE des deux côtés, la symétrie
-- est donc préservée.
--
-- DROP puis CREATE (et non CREATE OR REPLACE) : le type de retour change, Postgres
-- refuse un remplacement dans ce cas.
--
-- DROITS : le DROP réinitialise les privilèges. On repose donc explicitement le motif
-- des 13 autres fonctions dashboard_* (anon et authenticated fermés, service_role
-- seul autorisé) — sans quoi la recréation rouvrirait la fonction à `anon`, exactement
-- le défaut corrigé par la migration 20260725062716.

DROP FUNCTION IF EXISTS public.dashboard_seo_by_query(text, text, integer, integer);

CREATE FUNCTION public.dashboard_seo_by_query(
  period_kind text DEFAULT 'rolling_90'::text,
  scope       text DEFAULT 'ressource'::text,
  min_volume  integer DEFAULT 0,
  max_rows    integer DEFAULT 200)
RETURNS TABLE(
  query text, clicks bigint, impressions bigint, position_avg numeric, ctr_pct numeric,
  nb_pages integer, top_page text, top_page_clicks bigint, top_page_theme text,
  volume_fr integer, cpc numeric, competition_level text, capture_pct numeric,
  is_quick_win boolean, clicks_prev bigint, position_prev numeric, ctr_expected numeric,
  opportunity_clicks numeric, gsc_start date, gsc_end date)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
WITH gb AS (SELECT * FROM cooked_period_bounds(period_kind,'gsc')),
res AS (SELECT pt.path FROM page_taxonomy pt WHERE pt.category='ressource'),
qp AS (
  SELECT d.query, d.path, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT n_start FROM gb) AND (SELECT n_end FROM gb)
    AND NOT public.gsc_is_branded(d.query)
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query, d.path),
agg AS (SELECT query, SUM(clicks) clicks, SUM(impr) impr, SUM(pos_w) pos_w, COUNT(*) nb_pages FROM qp GROUP BY query),
top AS (SELECT DISTINCT ON (query) query, path top_page, clicks top_clicks FROM qp ORDER BY query, clicks DESC, impr DESC),
qprev AS (
  SELECT d.query, SUM(d.clicks) clicks, SUM(d.impressions) impr, SUM(d.position*d.impressions) pos_w
  FROM gsc_query_page_daily d
  WHERE d.day BETWEEN (SELECT prev_start FROM gb) AND (SELECT prev_end FROM gb)
    AND NOT public.gsc_is_branded(d.query)
    AND (scope <> 'ressource' OR d.path IN (SELECT path FROM res))
  GROUP BY d.query)
SELECT a.query, a.clicks, a.impr,
  ROUND(a.pos_w/NULLIF(a.impr,0),1), ROUND(100.0*a.clicks/NULLIF(a.impr,0),2),
  a.nb_pages::int, t.top_page, t.top_clicks, pt.theme,
  dfs.search_volume, dfs.cpc, dfs.competition_level,
  CASE WHEN dfs.search_volume>0 THEN ROUND(100.0*a.clicks/(dfs.search_volume*(SELECT day_count FROM gb)/30.0),1) END,
  (ROUND(a.pos_w/NULLIF(a.impr,0),1) BETWEEN 5 AND 15 AND COALESCE(dfs.search_volume,0)>=100),
  COALESCE(p.clicks,0),
  ROUND(p.pos_w/NULLIF(p.impr,0),1),
  ROUND(ctr_for_position(a.pos_w/NULLIF(a.impr,0))*100,2),
  CASE WHEN COALESCE(dfs.search_volume,0)>0
    THEN GREATEST(0, ROUND(dfs.search_volume*ctr_for_position(3) - a.clicks*30.0/NULLIF((SELECT day_count FROM gb),0)))
  END,
  (SELECT n_start FROM gb), (SELECT n_end FROM gb)
FROM agg a
LEFT JOIN top t ON t.query=a.query
LEFT JOIN page_taxonomy pt ON pt.path=t.top_page
LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=a.query AND dfs.location_code=2250
LEFT JOIN qprev p ON p.query=a.query
WHERE COALESCE(dfs.search_volume,0) >= min_volume
ORDER BY a.clicks DESC, a.impr DESC
LIMIT max_rows;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_seo_by_query(text, text, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_seo_by_query(text, text, integer, integer) TO service_role;

COMMENT ON FUNCTION public.dashboard_seo_by_query(text, text, integer, integer) IS
  'SEO par requete pour l onglet /seo : periode courante + periode precedente (clicks_prev, position_prev), CTR attendu et opportunite. Le contrat de sortie (20 colonnes) est verifie par dashboard/src/data/rpc-schemas.ts:seoQueryRowSchema — toute colonne retiree casse la page. Filtre branded : public.gsc_is_branded(), applique SYMETRIQUEMENT aux deux periodes.';
