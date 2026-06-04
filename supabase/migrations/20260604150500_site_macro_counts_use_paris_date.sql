-- Sprint 36+ (04/06/2026) — Pilote : 1re conversion d'un call-site vers la
-- couture paris_date() (cf. 20260604150000_paris_date_seam.sql).
--
-- POURQUOI site_macro_counts comme pilote
-- ---------------------------------------
-- C'est le compteur macro SITE-WIDE (cta_phone_click + form_submit), le
-- chiffre business remonté à Me Plouton. Vérification triviale : 3 entiers
-- en sortie, comparés avant/après sur la même fenêtre. Refactor PUR : on
-- remplace les 2 casts (occurred_at AT TIME ZONE 'Europe/Paris')::date par
-- paris_date(occurred_at), rien d'autre ne bouge (mêmes attributs STABLE
-- SECURITY DEFINER + SET search_path, même logique, mêmes FILTER).
--
-- ÉQUIVALENCE PROUVÉE
-- ------------------
-- paris_date() est IMMUTABLE/non-STRICT/sans SET -> le planner l'inline en
-- l'expression brute, plan EXPLAIN identique au caractère près (vérifié le
-- 04/06/2026). L'index idx_events_paris_date reste utilisé À TRAVERS la vue
-- events_human (prédicat poussé sous la vue). Sortie avant conversion sur
-- 06/05→04/06/2026 : phone=97, form=50, macro=147 — doit rester identique.

CREATE OR REPLACE FUNCTION public.site_macro_counts(start_date date, end_date date)
 RETURNS TABLE(phone_clicks bigint, form_submits bigint, macro_conversions bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint,
    count(*) FILTER (
      WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
    )::bigint,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (
          WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
        )
    )::bigint
  FROM public.events_human e
  WHERE public.paris_date(e.occurred_at) >= start_date
    AND public.paris_date(e.occurred_at) <= end_date;
$function$;
