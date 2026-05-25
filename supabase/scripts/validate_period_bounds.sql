-- Validation manuelle — bornes cooked_period_bounds (heure Paris)
-- SQL Editor → Run. Vérifier visuellement les colonnes (pas d'erreur = OK).

SELECT period_kind_out, label_fr, n_start, n_end, prev_start, prev_end, day_count
FROM public.cooked_period_bounds('today');

SELECT period_kind_out, label_fr, n_start, n_end, prev_start, prev_end, day_count
FROM public.cooked_period_bounds('week');

SELECT period_kind_out, label_fr, n_start, n_end, prev_start, prev_end, day_count
FROM public.cooked_period_bounds('month');

SELECT period_kind_out, label_fr, n_start, n_end, prev_start, prev_end, day_count
FROM public.cooked_period_bounds('rolling_28');

SELECT period_kind_out, label_fr, n_start, n_end, prev_start, prev_end, day_count
FROM public.cooked_period_bounds('rolling_90');

-- Semaine : n_start doit être un lundi, n_end = aujourd'hui (Paris)
-- Mois : n_start = 1er du mois courant
