-- B2 — dashboard_intervention_effect : lecture avant/après honnête d'une intervention
-- site_change sur une page. Marée du site soustraite, confiance affichée. Lit
-- gsc_path_daily en LIVE (une page à la fois) — aucun snapshot/cron, ne touche pas au CPI.
--   pré  = 28 j GSC finissant à p_day-1
--   post = p_day .. gsc_last_data_day(), plafonné à 28 j
--   effet net = (ratio clics/j page ÷ ratio clics/j site) − 1
-- Garde-fous : pré < 10 clics -> base_trop_faible ; jamais de division par zéro ;
-- article < 60 j d'âge GSC -> article_jeune ; confidence par days_post.
CREATE OR REPLACE FUNCTION public.dashboard_intervention_effect(p_path text, p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_gsc_last   date := public.gsc_last_data_day();
  v_pre_start  date := p_day - 28;
  v_pre_end    date := p_day - 1;
  v_post_start date := p_day;
  v_post_end   date := LEAST(public.gsc_last_data_day(), p_day + 27);
  v_days_post  int  := GREATEST(0, (LEAST(public.gsc_last_data_day(), p_day + 27) - p_day) + 1);
  v_pre_clics  numeric := 0; v_pre_imp  numeric := 0; v_pre_posw  numeric := 0;
  v_post_clics numeric := 0; v_post_imp numeric := 0; v_post_posw numeric := 0;
  v_site_pre   numeric := 0; v_site_post numeric := 0;
  v_first_gsc  date;  v_age_gsc int;  v_jeune boolean;
  v_ppd_pre numeric; v_ppd_post numeric; v_spd_pre numeric; v_spd_post numeric;
  v_page_ratio numeric; v_site_ratio numeric; v_effet numeric;
  v_pos_pre numeric; v_pos_post numeric;
  v_conf text; v_base_faible boolean; v_measurable boolean;
BEGIN
  SELECT COALESCE(sum(clicks),0), COALESCE(sum(impressions),0), COALESCE(sum(position*impressions),0)
    INTO v_pre_clics, v_pre_imp, v_pre_posw
  FROM gsc_path_daily WHERE path = p_path AND day BETWEEN v_pre_start AND v_pre_end;

  IF v_days_post > 0 THEN
    SELECT COALESCE(sum(clicks),0), COALESCE(sum(impressions),0), COALESCE(sum(position*impressions),0)
      INTO v_post_clics, v_post_imp, v_post_posw
    FROM gsc_path_daily WHERE path = p_path AND day BETWEEN v_post_start AND v_post_end;
  END IF;

  SELECT COALESCE(sum(clicks),0) INTO v_site_pre FROM gsc_path_daily WHERE day BETWEEN v_pre_start AND v_pre_end;
  IF v_days_post > 0 THEN
    SELECT COALESCE(sum(clicks),0) INTO v_site_post FROM gsc_path_daily WHERE day BETWEEN v_post_start AND v_post_end;
  END IF;

  SELECT min(day) INTO v_first_gsc FROM gsc_path_daily WHERE path = p_path AND impressions > 0;
  v_age_gsc := CASE WHEN v_first_gsc IS NULL THEN NULL ELSE (p_day - v_first_gsc) END;
  v_jeune   := COALESCE(v_age_gsc < 60, true);

  v_conf := CASE
    WHEN v_days_post < 7  THEN 'trop_tot'
    WHEN v_days_post < 14 THEN 'indicatif'
    WHEN v_days_post < 28 THEN 'fiable'
    ELSE 'verdict' END;

  v_base_faible := (v_pre_clics < 10);

  v_ppd_pre  := v_pre_clics / 28.0;
  v_spd_pre  := v_site_pre  / 28.0;
  v_ppd_post := CASE WHEN v_days_post > 0 THEN v_post_clics::numeric / v_days_post ELSE NULL END;
  v_spd_post := CASE WHEN v_days_post > 0 THEN v_site_post::numeric / v_days_post ELSE NULL END;
  v_pos_pre  := CASE WHEN v_pre_imp  > 0 THEN v_pre_posw  / v_pre_imp  ELSE NULL END;
  v_pos_post := CASE WHEN v_post_imp > 0 THEN v_post_posw / v_post_imp ELSE NULL END;

  -- Mesurable seulement à partir de J+7, base pré suffisante, dénominateurs non nuls.
  v_measurable := (v_days_post >= 7) AND (NOT v_base_faible) AND (v_ppd_pre > 0) AND (v_spd_pre > 0) AND (v_spd_post > 0);
  IF v_measurable THEN
    v_page_ratio := v_ppd_post / v_ppd_pre;
    v_site_ratio := v_spd_post / v_spd_pre;
    v_effet := CASE WHEN v_site_ratio > 0 THEN (v_page_ratio / v_site_ratio) - 1 ELSE NULL END;
  END IF;

  RETURN jsonb_build_object(
    'path', p_path,
    'day', p_day,
    'gsc_last', v_gsc_last,
    'days_post', v_days_post,
    'confidence', v_conf,
    'base_trop_faible', v_base_faible,
    'article_jeune', v_jeune,
    'age_gsc_jours', v_age_gsc,
    'pre_total_clics', round(v_pre_clics)::int,
    'page_clics_jour_pre',  round(v_ppd_pre, 2),
    'page_clics_jour_post', CASE WHEN v_ppd_post IS NOT NULL THEN round(v_ppd_post, 2) END,
    'pos_pre',  CASE WHEN v_pos_pre  IS NOT NULL THEN round(v_pos_pre, 1) END,
    'pos_post', CASE WHEN v_pos_post IS NOT NULL THEN round(v_pos_post, 1) END,
    'clics_pct',     CASE WHEN v_measurable THEN round((v_page_ratio - 1) * 100) END,
    'maree_pct',     CASE WHEN v_measurable THEN round((v_site_ratio - 1) * 100) END,
    'effet_net_pct', CASE WHEN v_measurable AND v_effet IS NOT NULL THEN round(v_effet * 100) END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.dashboard_intervention_effect(text, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_intervention_effect(text, date) TO service_role;
