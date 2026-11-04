-- Messages opératoires alignés sur le socle : aucun seuil ou comptage modifié.
CREATE OR REPLACE FUNCTION public.alert_rule_form_attribution_degraded()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_n bigint; v_tot bigint; v_pct numeric; v_forms text;
BEGIN
  -- 1. cooked_aid (attribution hidden_field) — inchangé
  SELECT count(*) FILTER (WHERE props->>'cooked_aid' IS NULL), count(*)
    INTO v_n, v_tot
  FROM public.events
  WHERE name = 'form_submit'
    AND occurred_at > now() - interval '7 days';
  IF v_tot >= 5 THEN
    v_pct := round(100.0 * v_n / v_tot, 0);
    IF v_pct > 30 THEN
      kind := 'form_attribution_degraded'; severity := 'warn';
      detail := format('%s %% des form_submit sans cooked_aid sur 7j (%s/%s) — champs cachés Wix manquants ou tracker pas à jour ?', v_pct, v_n, v_tot);
      RETURN NEXT;
    END IF;
  END IF;

  -- 2. T-18 : page_source (path) et objet par formulaire, 28 j, webhook seulement
  WITH f AS (
    SELECT btrim(coalesce(props->>'form_id', '?')) AS form_id,
           count(*) AS n,
           count(*) FILTER (WHERE path IS NULL) AS sans_path,
           count(*) FILTER (WHERE nullif(props->>'objet_de_ma_demande', '') IS NULL) AS sans_objet
    FROM public.events
    WHERE name = 'form_submit'
      AND coalesce(props->>'capture_source', 'wix-webhook') = 'wix-webhook'
      AND occurred_at > now() - interval '28 days'
    GROUP BY 1
  )
  SELECT string_agg(format('%s : %s/%s sans page_source, %s/%s sans objet', form_id, sans_path, n, sans_objet, n), ' ; ' ORDER BY n DESC)
    INTO v_forms
  FROM f
  WHERE (n >= 3 AND (100.0 * sans_path / n > 10 OR 100.0 * sans_objet / n > 10))
     OR (n >= 1 AND sans_path = n);

  IF v_forms IS NOT NULL THEN
    kind := 'form_fields_missing'; severity := 'warn';
    detail := format('Formulaires Wix sans page_source ou sans objet sur 28 j — une page_source absente limite le contexte ; le rattachement à l’entrée dépend des identifiants explicites et des pages observées ; sans objet, il est compté macro par défaut (candidature ?). Câbler les champs cachés `page_source` (seedé par masterPage) et « Objet de ma demande » sur le formulaire puis vérifier la prochaine soumission réelle. %s', v_forms);
    RETURN NEXT;
  END IF;
END;
$function$;

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
      -- exclusions structurelles : ignorer les chemins techniques et invalides
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
    -- la synchronisation de publication a eu plusieurs occasions de passer
    AND v.first_seen < now() - interval '8 days';

  IF v_n >= 1 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j, vus depuis > 8 j) sans catégorie Wix dans page_taxonomy — les visites restent comptées mais leur classement éditorial est incomplet. Vérifier les chemins (page réelle, redirection ou URL tronquée), leur catégorie Wix et le dernier workflow wix-taxonomy-sync (inventaire quotidien). Une synchro réussie peut conserver une URL sans catégorie ; ne pas déduire un secret manquant de cette seule alerte. Concernés : %s',
        v_n, left(coalesce(v_ex, ''), 400)
      );
  END IF;
END;
$function$;
