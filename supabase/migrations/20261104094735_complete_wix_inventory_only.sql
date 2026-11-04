-- Un seul format : inventaire complet des pages publiées, indépendant du trafic.
-- L’ancien tableau de catégories est rejeté sans écriture ; les données existantes restent conservées.
CREATE OR REPLACE FUNCTION public.page_taxonomy_sync_wix(p_posts jsonb, p_dry_run boolean DEFAULT false)
 RETURNS TABLE(inserted integer, updated integer, unpublished integer, inserted_paths text[], updated_paths text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_pages jsonb;
  v_observed_at timestamptz;
  v_count integer;
  v_unique integer;
  v_posts integer;
  v_categories integer;
  v_static integer;
BEGIN
  IF p_posts IS NULL OR p_dry_run IS NULL THEN
    RAISE EXCEPTION 'Wix inventory and dry-run flag are required' USING ERRCODE='22023';
  END IF;
  IF jsonb_typeof(p_posts) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_posts->'pages') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_posts->'counts') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Complete Wix inventory requires pages and source counts' USING ERRCODE='22023';
  END IF;
  v_pages := p_posts->'pages';
  v_observed_at := (p_posts->>'observed_at')::timestamptz;
  IF v_observed_at IS NULL OR v_observed_at > clock_timestamp() + interval '5 minutes'
     OR v_observed_at < clock_timestamp() - interval '24 hours' THEN
    RAISE EXCEPTION 'Wix observation timestamp missing or outside accepted range' USING ERRCODE='22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_pages) e
    WHERE jsonb_typeof(e) <> 'object' OR jsonb_typeof(e->'path') IS DISTINCT FROM 'string'
      OR e->>'path' NOT LIKE '/%' OR e->>'path' LIKE '//%'
      OR e->>'path' ~ '[?#[:cntrl:]]'
      OR e->>'path' IS DISTINCT FROM public.canonical_path(e->>'path')
      OR ((e->>'path' LIKE '/post/%') AND coalesce(e->>'category','') NOT IN ('ressource','classique'))
      OR ((e->>'path' NOT LIKE '/post/%') AND e->>'category' IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Invalid Wix path or category' USING ERRCODE='22023';
  END IF;
  SELECT count(*), count(DISTINCT path),
    count(*) FILTER(WHERE path LIKE '/post/%'),
    count(*) FILTER(WHERE path LIKE '/blog/categories/%'),
    count(*) FILTER(WHERE path NOT LIKE '/post/%' AND path NOT LIKE '/blog/categories/%')
    INTO v_count, v_unique, v_posts, v_categories, v_static
  FROM jsonb_to_recordset(v_pages) w(path text, category text);
  IF v_count=0 OR v_count<>v_unique THEN
    RAISE EXCEPTION 'Incomplete or repeated Wix paths' USING ERRCODE='22023';
  END IF;
  IF (
    v_posts < 1 OR v_categories < 1 OR v_static < 1
    OR v_posts IS DISTINCT FROM (p_posts->'counts'->>'posts')::integer
    OR v_categories IS DISTINCT FROM (p_posts->'counts'->>'categories')::integer
    OR v_static IS DISTINCT FROM (p_posts->'counts'->>'static')::integer
    OR NOT EXISTS (SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE path='/')
  ) THEN
    RAISE EXCEPTION 'Wix source counts or homepage do not match' USING ERRCODE='22023';
  END IF;

  -- Serialise inventory writes and the existing heuristic updater. Any failure
  -- rolls back both category changes and all publication changes in this RPC.
  LOCK TABLE public.page_taxonomy IN SHARE ROW EXCLUSIVE MODE;
  IF v_observed_at < (SELECT max(publication_checked_at) FROM public.page_taxonomy) THEN
    RAISE EXCEPTION 'A newer Wix inventory has already been applied' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(array_agg(w.path ORDER BY w.path), '{}') INTO inserted_paths
  FROM jsonb_to_recordset(v_pages) w(path text, category text)
  LEFT JOIN public.page_taxonomy t USING(path) WHERE t.path IS NULL;
  SELECT coalesce(array_agg(w.path ORDER BY w.path), '{}') INTO updated_paths
  FROM jsonb_to_recordset(v_pages) w(path text, category text)
  JOIN public.page_taxonomy t USING(path)
  WHERE w.path LIKE '/post/%' AND t.category IS DISTINCT FROM w.category;
  SELECT count(*) INTO unpublished FROM public.page_taxonomy t
  WHERE NOT EXISTS (SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE w.path=t.path);
  inserted := cardinality(inserted_paths);
  updated := cardinality(updated_paths);
  IF NOT p_dry_run THEN
    INSERT INTO public.page_taxonomy(path,category,theme,source)
      SELECT w.path,w.category,public.page_taxonomy_theme_from_slug(w.path),'wix_api'
      FROM jsonb_to_recordset(v_pages) w(path text, category text)
      WHERE w.path=ANY(inserted_paths);
    UPDATE public.page_taxonomy t SET category=w.category, updated_at=clock_timestamp()
      FROM jsonb_to_recordset(v_pages) w(path text, category text)
      WHERE w.path=t.path AND t.path=ANY(updated_paths);
    UPDATE public.page_taxonomy t SET
      is_published=EXISTS (SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE w.path=t.path),
      publication_checked_at=v_observed_at
    WHERE t.publication_checked_at IS DISTINCT FROM v_observed_at
      OR t.is_published IS DISTINCT FROM EXISTS (
        SELECT 1 FROM jsonb_to_recordset(v_pages) w(path text) WHERE w.path=t.path);
  END IF;
  RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.page_taxonomy_sync_wix(jsonb,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.page_taxonomy_sync_wix(jsonb,boolean) TO service_role;
COMMENT ON FUNCTION public.page_taxonomy_sync_wix(jsonb,boolean) IS
  'Applique un inventaire Wix complet (pages, observed_at, counts) : publication et catégories, contrôle de complétude, rejeu idempotent et dry-run. Aucune suppression de page.';
