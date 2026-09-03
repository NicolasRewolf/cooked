-- T-18 (mission 02/09/2026, #119) — formulaires : page_source et typologie surveillés par formulaire.
-- Constats b-01 (P1), b-05 (P2). Invariant I4.
--
-- Mesure avant (04/09/2026 01:40 Paris, events_human, form_submit, 180 j) :
--   « Prise de contact site-web » 252 (dont 230 avec un espace final dans form_id) : 18 sans page_source
--   (7 %), 30 sans objet ; « Formulaire Divorce » 3/3 sans page_source ni objet ; « Demande dossier en
--   cours » 1/1. Un contact sans path est compté au total site mais invisible par page
--   (pages_overview_unified : INNER JOIN) ; un contact sans objet est compté macro par défaut.
--   alert_rule_form_attribution_degraded ne regardait que cooked_aid (7 j, seuil 30 %).
--
-- Changement : la règle surveille aussi, par formulaire et sur 28 j (webhook seulement, hors backfill) :
--   · part sans page_source (path NULL) > 10 % avec ≥ 3 envois, ou tout formulaire à 100 % sans page ;
--   · part sans objet_de_ma_demande > 10 % avec ≥ 3 envois.
--   Le seuil cooked_aid (7 j, 30 %) est conservé.

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
    detail := format('Formulaires Wix sans page_source ou sans objet sur 28 j — un contact sans page_source est compté au total site mais invisible par page ; sans objet, il est compté macro par défaut (candidature ?). Câbler les champs cachés `page_source` (seedé par masterPage) et « Objet de ma demande » sur le formulaire (action Nicolas, T-18). %s', v_forms);
    RETURN NEXT;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.alert_rule_form_attribution_degraded() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_form_attribution_degraded() TO service_role;
