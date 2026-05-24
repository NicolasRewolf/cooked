-- ⚠️ DÉPRÉCIÉ (28/05/2026) — utiliser supabase/migrations/20260527120000_form_submit_exclude_recruitment.sql
-- Voir supabase/scripts/README.md
-- Coller dans Supabase → SQL Editor → Run
-- (après migration périodes déjà appliquée)

-- Contenu = fichier 20260527120000_form_submit_exclude_recruitment.sql
-- Sprint 33+ (27/05/2026) — Typologie formulaire + exclusion candidatures
--
-- Champ Wix `objet_de_ma_demande` = typologie du problème (pas de PII).
-- Les soumissions « Nous rejoindre (candidature) » restent en base pour
-- audit mais ne comptent plus dans form_submit / contacts macro.

CREATE OR REPLACE FUNCTION public.form_submit_counts_as_macro(props jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN props IS NULL THEN true
    WHEN lower(trim(coalesce(props->>'objet_de_ma_demande', ''))) LIKE '%nous rejoindre%' THEN false
    WHEN coalesce(props->>'counts_as_macro', 'true') = 'false' THEN false
    ELSE true
  END;
$$;

COMMENT ON FUNCTION public.form_submit_counts_as_macro(jsonb) IS
  'true si le form_submit compte en contact business (exclut objet « Nous rejoindre (candidature) »).';

REVOKE EXECUTE ON FUNCTION public.form_submit_counts_as_macro(jsonb) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.form_submit_counts_as_macro(jsonb) TO service_role;


-- macro_contacts_by_path : form_submit filtré
CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(
  start_date date,
  end_date   date
)
RETURNS TABLE (
  path             text,
  phone_clicks     bigint,
  form_submits     bigint,
  contacts         bigint,
  booking_intent   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    e.path,
    count(*) FILTER (WHERE e.name = 'cta_phone_click')::bigint,
    count(*) FILTER (
      WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
    )::bigint,
    (
      count(*) FILTER (WHERE e.name = 'cta_phone_click')
      + count(*) FILTER (
          WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
        )
    )::bigint,
    count(*) FILTER (
      WHERE e.name = 'cta_booking_click' AND e.device_type != 'server'
    )::bigint
  FROM public.events_human e
  WHERE e.path IS NOT NULL
    AND (
      e.name = 'cta_phone_click'
      OR (e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props))
      OR (e.name = 'cta_booking_click' AND e.device_type != 'server')
    )
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= start_date
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= end_date
  GROUP BY e.path;
$$;


-- site_kpis_compare : form_submit filtré
CREATE OR REPLACE FUNCTION public.site_kpis_compare(p_period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  period_kind                 text,
  period_label_fr             text,
  period_n_start              date,
  period_n_end                date,
  tracker_first_seen          date,
  is_partial_period           boolean,
  sessions_n                  bigint,
  pageviews_n                 bigint,
  phone_clicks_n              bigint,
  form_submits_n              bigint,
  macro_conversions_n         bigint,
  period_prev_start           date,
  period_prev_end             date,
  sessions_prev               bigint,
  pageviews_prev              bigint,
  phone_clicks_prev           bigint,
  form_submits_prev           bigint,
  macro_conversions_prev      bigint,
  sessions_delta_pct          numeric,
  pageviews_delta_pct         numeric,
  phone_clicks_delta_pct      numeric,
  form_submits_delta_pct      numeric,
  macro_conversions_delta_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
  v_first_seen date;
  v_sessions_n      bigint;
  v_pageviews_n     bigint;
  v_phone_n         bigint;
  v_form_n          bigint;
  v_sessions_prev   bigint;
  v_pageviews_prev  bigint;
  v_phone_prev      bigint;
  v_form_prev       bigint;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(p_period_kind) LIMIT 1;

  v_first_seen := (public.tracker_first_seen_global() AT TIME ZONE 'Europe/Paris')::date;

  SELECT
    count(DISTINCT session_id) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (WHERE name = 'cta_phone_click'),
    count(*) FILTER (
      WHERE name = 'form_submit' AND public.form_submit_counts_as_macro(props)
    )
  INTO v_sessions_n, v_pageviews_n, v_phone_n, v_form_n
  FROM public.events_human
  WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
    AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end;

  SELECT
    count(DISTINCT session_id) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (
      WHERE name = 'pageview' AND device_type IS DISTINCT FROM 'server'
    ),
    count(*) FILTER (WHERE name = 'cta_phone_click'),
    count(*) FILTER (
      WHERE name = 'form_submit' AND public.form_submit_counts_as_macro(props)
    )
  INTO v_sessions_prev, v_pageviews_prev, v_phone_prev, v_form_prev
  FROM public.events_human
  WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.prev_start
    AND (occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.prev_end;

  RETURN QUERY SELECT
    b.period_kind_out,
    b.label_fr,
    b.n_start,
    b.n_end,
    v_first_seen,
    (v_first_seen IS NOT NULL AND b.n_start < v_first_seen),
    coalesce(v_sessions_n, 0)::bigint,
    coalesce(v_pageviews_n, 0)::bigint,
    coalesce(v_phone_n, 0)::bigint,
    coalesce(v_form_n, 0)::bigint,
    (coalesce(v_phone_n, 0) + coalesce(v_form_n, 0))::bigint,
    b.prev_start,
    b.prev_end,
    coalesce(v_sessions_prev, 0)::bigint,
    coalesce(v_pageviews_prev, 0)::bigint,
    coalesce(v_phone_prev, 0)::bigint,
    coalesce(v_form_prev, 0)::bigint,
    (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0))::bigint,
    CASE WHEN v_sessions_prev > 0
         THEN round((100.0 * (v_sessions_n - v_sessions_prev) / v_sessions_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN v_pageviews_prev > 0
         THEN round((100.0 * (v_pageviews_n - v_pageviews_prev) / v_pageviews_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN v_phone_prev > 0
         THEN round((100.0 * (v_phone_n - v_phone_prev) / v_phone_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN v_form_prev > 0
         THEN round((100.0 * (v_form_n - v_form_prev) / v_form_prev)::numeric, 2)
         ELSE NULL END,
    CASE WHEN (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0)) > 0
         THEN round(
           (100.0 * ((coalesce(v_phone_n, 0) + coalesce(v_form_n, 0))
                   - (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0)))
            / (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0)))::numeric, 2)
         ELSE NULL END;
END;
$$;


-- site_seo_funnel : macro_contacts filtré
CREATE OR REPLACE FUNCTION public.site_seo_funnel(period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  period_start                date,
  period_end                  date,
  impressions                 bigint,
  clicks                      bigint,
  google_sessions             bigint,
  macro_contacts              bigint,
  impr_to_click_pct           numeric,
  click_to_session_pct        numeric,
  session_to_contact_pct      numeric,
  overall_impr_to_contact_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
  v_impressions bigint;
  v_clicks bigint;
  v_google_sessions bigint;
  v_macro bigint;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind) LIMIT 1;

  SELECT
    coalesce(sum(g.impressions), 0)::bigint,
    coalesce(sum(g.clicks), 0)::bigint
  INTO v_impressions, v_clicks
  FROM public.gsc_path_daily g
  WHERE g.day >= b.n_start AND g.day <= b.n_end;

  SELECT count(DISTINCT e.session_id) FILTER (
           WHERE e.name = 'pageview'
             AND e.device_type IS DISTINCT FROM 'server'
             AND (
               e.referrer_hostname LIKE '%google.%'
               OR (e.utm_source = 'google' AND e.utm_medium IN ('organic', 'cpc'))
             )
         )::bigint INTO v_google_sessions
  FROM public.events_human e
  WHERE (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end;

  SELECT (
    count(*) FILTER (WHERE e.name = 'cta_phone_click')
    + count(*) FILTER (
        WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
      )
  )::bigint INTO v_macro
  FROM public.events_human e
  WHERE (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
    AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end;

  RETURN QUERY SELECT
    b.n_start,
    b.n_end,
    v_impressions,
    v_clicks,
    v_google_sessions,
    v_macro,
    CASE WHEN v_impressions > 0
         THEN round((100.0 * v_clicks / v_impressions)::numeric, 2) ELSE NULL END,
    CASE WHEN v_clicks > 0
         THEN round((100.0 * v_google_sessions / v_clicks)::numeric, 2) ELSE NULL END,
    CASE WHEN v_google_sessions > 0
         THEN round((100.0 * v_macro / v_google_sessions)::numeric, 2) ELSE NULL END,
    CASE WHEN v_impressions > 0
         THEN round((100.0 * v_macro / v_impressions)::numeric, 4) ELSE NULL END;
END;
$$;


-- cooked_pages_compare : contacts filtrés
CREATE OR REPLACE FUNCTION public.cooked_pages_compare(period_kind text DEFAULT 'rolling_28')
RETURNS TABLE (
  path                       text,
  sessions_n                 bigint,
  sessions_prev              bigint,
  sessions_delta_pct         numeric,
  contacts_n                 bigint,
  contacts_prev              bigint,
  contacts_delta_pct         numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b RECORD;
  v_first_seen date;
  v_has_prev   boolean;
BEGIN
  SELECT * INTO b FROM public.cooked_period_bounds(period_kind) LIMIT 1;
  v_first_seen := (public.tracker_first_seen_global() AT TIME ZONE 'Europe/Paris')::date;
  v_has_prev := v_first_seen IS NOT NULL AND v_first_seen <= b.prev_start;

  RETURN QUERY
  WITH n_agg AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total,
      (
        count(*) FILTER (WHERE e.name = 'cta_phone_click')
        + count(*) FILTER (
            WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
          )
      )::bigint AS contacts_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.n_start
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.n_end
    GROUP BY e.path
  ),
  prev_agg AS (
    SELECT e.path AS p,
      count(DISTINCT e.session_id) FILTER (
        WHERE e.name = 'pageview' AND e.device_type IS DISTINCT FROM 'server'
      )::bigint AS sessions_total,
      (
        count(*) FILTER (WHERE e.name = 'cta_phone_click')
        + count(*) FILTER (
            WHERE e.name = 'form_submit' AND public.form_submit_counts_as_macro(e.props)
          )
      )::bigint AS contacts_total
    FROM public.events_human e
    WHERE e.path IS NOT NULL AND v_has_prev
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date >= b.prev_start
      AND (e.occurred_at AT TIME ZONE 'Europe/Paris')::date <= b.prev_end
    GROUP BY e.path
  ),
  paths AS (SELECT n_agg.p FROM n_agg UNION SELECT prev_agg.p FROM prev_agg)
  SELECT
    paths.p,
    coalesce(n.sessions_total, 0),
    CASE WHEN v_has_prev THEN coalesce(pr.sessions_total, 0) ELSE NULL END,
    CASE WHEN v_has_prev AND coalesce(pr.sessions_total, 0) > 0
         THEN round((100.0 * (coalesce(n.sessions_total, 0) - pr.sessions_total) / pr.sessions_total)::numeric, 2)
         ELSE NULL END,
    coalesce(n.contacts_total, 0),
    CASE WHEN v_has_prev THEN coalesce(pr.contacts_total, 0) ELSE NULL END,
    CASE WHEN v_has_prev AND coalesce(pr.contacts_total, 0) > 0
         THEN round((100.0 * (coalesce(n.contacts_total, 0) - pr.contacts_total) / pr.contacts_total)::numeric, 2)
         ELSE NULL END
  FROM paths
    LEFT JOIN n_agg n ON n.p = paths.p
    LEFT JOIN prev_agg pr ON pr.p = paths.p;
END;
$$;
