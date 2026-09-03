-- T-15 (mission 02/09/2026, #116) — page_taxonomy : synchro Wix automatisable, filtres de l'alerte.
-- Constats e-06 (P2), e-07 (P3). Invariant I7 (registre page_taxonomy posé au T-10).
--
-- Mesure avant (03/09/2026 23:45 Paris) :
--   · liste publiée de l'API Wix : 434 posts (62 ressources) ; page_taxonomy : 438 lignes /post/
--     (63 ressources, 1 sans catégorie : /post/accident-médical-oniam, vestige re-sluggé).
--   · /post/histoire-artan-engagement-grands-traumatises (publié 18/08, 6 vues/30 j) : aucune ligne —
--     rechute 2 jours après le rattrapage manuel du 31/08 ; alerte page_taxonomy_gap muette (seuil 3).
--   · 11 non-articles passaient les filtres de l'alerte (8 × /post/fp_0.50_0.50/<image>, 1 base64
--     tronqué, 1 slug + parenthèse, 1 slug tronqué).
--   · aucun artefact exécutable de synchro dans le repo (grep wixapis → 0), aucun cron.
--   · « path tronqué à 105 caractères » (e-06) : le slug Wix lui-même est tronqué à 100 caractères
--     (application-de-la-responsabilité-…-usage-profe = slug API) — rien à corriger côté Cooked.
--
-- Changement :
--   1. page_taxonomy_theme_from_slug(path) : l'heuristique de thème sort de refresh_page_taxonomy_heuristic
--      (qui l'appelle désormais) — une seule implémentation.
--   2. page_taxonomy_sync_wix(p_posts jsonb, p_dry_run) : insère les /post/<slug> publiés absents
--      (category + theme + source 'wix_api'), corrige `category` seule sur les lignes existantes,
--      compte les paths en base absents de la liste (jamais supprimés : historique de trafic).
--      Appelée par scripts/wix_taxonomy_sync.py (cron GitHub hebdomadaire, secret WIX_API_KEY).
--   3. alert_rule_page_taxonomy_gap : exclusions /fp_x_y/ et « un seul segment de slug » ;
--      sonne dès 1 article dont la première vue date de plus de 8 jours (la synchro hebdo a eu sa chance).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Heuristique de thème — une implémentation
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.page_taxonomy_theme_from_slug(p_path text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_path ~* 'garde-.?-vue|gav' then 'garde à vue'
    when p_path ~* 'violence|f.minicide|conjugal|harc.lement|contr.le-coercitif' then 'violences & harcèlement'
    when p_path ~* 'indemnis|victime|civi|sarvi|pr.judice|dommage' then 'indemnisation victimes'
    when p_path ~* 'accident|erreur-m.dicale|route|travail' then 'accidents & réparation'
    when p_path ~* 'stup.fiant|trafic|drogue' then 'stupéfiants'
    when p_path ~* 'd.tention|prison|peine|sursis|bracelet|ddse|suret.|am.nagement' then 'peines & détention'
    when p_path ~* 'affaires|fraude|abus-de|escroquerie|blanchiment|corruption|fiscal' then 'pénal des affaires'
    when p_path ~* 'famille|divorce|filiation|succession|contrat' then 'famille & contrats'
    when p_path ~* 'instruction|proc.dure|comparution|tribunal|cour-d|assises|appel|mise-en-examen|t.moin|pr.venu|accus|perquisition|audition' then 'procédure pénale'
    when p_path ~* 'diffamation|injure|r.putation|presse' then 'réputation & presse'
    else null
  end
$function$;

CREATE OR REPLACE FUNCTION public.refresh_page_taxonomy_heuristic()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_count int;
begin
  with paths as (
    select distinct path from public.events_human
    where (path like '/post/%' or public.cooked_page_type(path) in ('expertise','hub'))
      -- T-19 : ne considérer que le trafic récent (évite de ressusciter de
      -- vieux paths morts) et exclure la poubelle structurelle
      and occurred_at > now() - interval '90 days'
      and path not like '%/preview/%'   -- previews Wix avec token
      and path !~ 'https?://'           -- URLs concaténées par erreur
      and path !~ '[ÃÂ]'                -- mojibake (double encodage)
      and length(path) <= 140           -- tokens/concaténations aberrantes
  ), themed as (
    -- T-15 : heuristique partagée avec page_taxonomy_sync_wix
    select path, public.page_taxonomy_theme_from_slug(path) as theme
    from paths
  )
  insert into public.page_taxonomy (path, theme, source)
  select path, theme, 'slug_heuristic' from themed where theme is not null
  on conflict (path) do update
    set theme = excluded.theme, updated_at = now()
    where page_taxonomy.source = 'slug_heuristic';
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Synchro depuis la liste publiée
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.page_taxonomy_sync_wix(p_posts jsonb, p_dry_run boolean DEFAULT false)
 RETURNS TABLE(inserted integer, updated integer, unpublished integer, inserted_paths text[], updated_paths text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_n int;
BEGIN
  IF p_posts IS NULL OR jsonb_typeof(p_posts) <> 'array' OR jsonb_array_length(p_posts) < 300 THEN
    RAISE EXCEPTION 'page_taxonomy_sync_wix : liste publiée suspecte (% éléments, attendu ≥ 300) — rien n''est écrit',
      coalesce(jsonb_array_length(p_posts), 0);
  END IF;

  CREATE TEMP TABLE _wix_posts ON COMMIT DROP AS
    SELECT DISTINCT public.canonical_path('/post/' || (e->>'slug')) AS path,
           CASE WHEN e->>'category' = 'ressource' THEN 'ressource' ELSE 'classique' END AS category
    FROM jsonb_array_elements(p_posts) e
    WHERE coalesce(e->>'slug', '') <> '';

  SELECT count(*) INTO v_n FROM _wix_posts;
  IF v_n < 300 THEN
    RAISE EXCEPTION 'page_taxonomy_sync_wix : % paths après canonicalisation (attendu ≥ 300)', v_n;
  END IF;

  SELECT coalesce(array_agg(w.path ORDER BY w.path), '{}') INTO inserted_paths
  FROM _wix_posts w LEFT JOIN public.page_taxonomy t ON t.path = w.path WHERE t.path IS NULL;
  SELECT coalesce(array_agg(w.path ORDER BY w.path), '{}') INTO updated_paths
  FROM _wix_posts w JOIN public.page_taxonomy t ON t.path = w.path
  WHERE t.category IS DISTINCT FROM w.category;
  SELECT count(*) INTO unpublished
  FROM public.page_taxonomy t WHERE t.path LIKE '/post/%'
    AND NOT EXISTS (SELECT 1 FROM _wix_posts w WHERE w.path = t.path);
  inserted := coalesce(array_length(inserted_paths, 1), 0);
  updated  := coalesce(array_length(updated_paths, 1), 0);

  IF NOT p_dry_run THEN
    INSERT INTO public.page_taxonomy (path, category, theme, source)
    SELECT w.path, w.category, public.page_taxonomy_theme_from_slug(w.path), 'wix_api'
    FROM _wix_posts w
    WHERE w.path = ANY (inserted_paths);

    -- Lignes existantes : seule `category` bouge (theme/source préservés — garde-fou
    -- `source = 'slug_heuristic'` de refresh_page_taxonomy_heuristic).
    UPDATE public.page_taxonomy t
       SET category = w.category, updated_at = now()
      FROM _wix_posts w
     WHERE w.path = t.path AND t.path = ANY (updated_paths);
  END IF;

  RETURN NEXT;
END $function$;

REVOKE ALL ON FUNCTION public.page_taxonomy_theme_from_slug(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.page_taxonomy_theme_from_slug(text) TO service_role;
REVOKE ALL ON FUNCTION public.refresh_page_taxonomy_heuristic() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_page_taxonomy_heuristic() TO service_role;
REVOKE ALL ON FUNCTION public.page_taxonomy_sync_wix(jsonb, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.page_taxonomy_sync_wix(jsonb, boolean) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Alerte : filtres structurels + seuil
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.alert_rule_page_taxonomy_gap()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_n  bigint;
  v_ex text;
BEGIN
  WITH vus AS (
    SELECT e.path, count(*) FILTER (WHERE e.name = 'pageview') AS pv, min(e.occurred_at) AS first_seen
    FROM public.events_human e
    WHERE e.path LIKE '/post/%'
      AND e.occurred_at > now() - interval '30 days'
      -- mêmes exclusions structurelles que refresh_page_taxonomy_heuristic (T-19)
      AND e.path NOT LIKE '%/preview/%'   -- previews Wix avec token
      AND e.path !~ 'https?://'           -- URLs concaténées par erreur
      AND e.path !~ '[ÃÂ]'                -- mojibake (double encodage)
      AND e.path !~ '%'                   -- restes d'URL-encoding
      AND length(e.path) <= 140
      -- T-15 (e-07) : un article = /post/<un seul segment de slug>, sans parenthèse ;
      -- exclut les URL de point focal d'image Wix (/post/fp_0.50_0.50/<hex>~mv2.png)
      AND e.path ~ '^/post/[^/()]+$'
      AND e.path !~ '/fp_[0-9.]+_[0-9.]+/'
    GROUP BY e.path
    HAVING count(*) FILTER (WHERE e.name = 'pageview') >= 5
  )
  SELECT count(*), string_agg(v.path, ', ' ORDER BY v.pv DESC)
    INTO v_n, v_ex
  FROM vus v
  LEFT JOIN public.page_taxonomy t ON t.path = v.path
  WHERE (t.path IS NULL OR t.category IS NULL)
    -- la synchro hebdomadaire (wix-taxonomy-sync) a eu au moins une occasion de passer
    AND v.first_seen < now() - interval '8 days';

  IF v_n >= 1 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j, vus depuis > 8 j) sans catégorie Wix dans page_taxonomy — toute lecture par catégorie (dashboard Articles Ressources, content_performance, contrat éditorial) les ignore. La synchro hebdomadaire wix-taxonomy-sync (GitHub Actions, lundi 05:00 UTC) n''a pas tourné ou le secret WIX_API_KEY manque : relancer `python3 scripts/wix_taxonomy_sync.py`. Concernés : %s',
        v_n, left(coalesce(v_ex, ''), 400)
      );
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.alert_rule_page_taxonomy_gap() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_page_taxonomy_gap() TO service_role;
