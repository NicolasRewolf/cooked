-- Sprint 33+ (22/05/2026) — RPC site_kpis_compare(period_days)
--
-- Construite pour la home business du dashboard : KPI macro (phone,
-- form_submit, macro = phone + form) + sessions + pageviews, sur la
-- fenêtre N (period_days derniers jours en heure Paris) et la fenêtre
-- précédente N-1 de même longueur, avec deltas en pourcentage.
--
-- Définition macro : phone_clicks + form_submits (cf. CLAUDE.md cooked).
-- form_submit a device_type='server', cta_phone_click n'a pas ce statut.
-- Lecture : events_human (vue filtrée bots + noise).
--
-- Toutes les bornes utilisent (occurred_at AT TIME ZONE 'Europe/Paris')::date
-- pour respecter le calendrier business français (règle dure CLAUDE.md).

CREATE OR REPLACE FUNCTION public.site_kpis_compare(period_days integer DEFAULT 28)
RETURNS TABLE (
  period_n_start              date,
  period_n_end                date,
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
declare
  v_today      date := (now() at time zone 'Europe/Paris')::date;
  v_n_start    date := v_today - (period_days - 1);
  v_n_end      date := v_today;
  v_prev_start date := v_n_start - period_days;
  v_prev_end   date := v_n_start - 1;
  v_sessions_n      bigint;
  v_pageviews_n     bigint;
  v_phone_n         bigint;
  v_form_n          bigint;
  v_sessions_prev   bigint;
  v_pageviews_prev  bigint;
  v_phone_prev      bigint;
  v_form_prev       bigint;
begin
  -- Window N
  select
    count(distinct session_id) filter (
      where name = 'pageview' and device_type is distinct from 'server'
    ),
    count(*) filter (
      where name = 'pageview' and device_type is distinct from 'server'
    ),
    count(*) filter (where name = 'cta_phone_click'),
    count(*) filter (where name = 'form_submit')
  into v_sessions_n, v_pageviews_n, v_phone_n, v_form_n
  from public.events_human
  where (occurred_at at time zone 'Europe/Paris')::date >= v_n_start
    and (occurred_at at time zone 'Europe/Paris')::date <= v_n_end;

  -- Window N-1 (même longueur, juste avant)
  select
    count(distinct session_id) filter (
      where name = 'pageview' and device_type is distinct from 'server'
    ),
    count(*) filter (
      where name = 'pageview' and device_type is distinct from 'server'
    ),
    count(*) filter (where name = 'cta_phone_click'),
    count(*) filter (where name = 'form_submit')
  into v_sessions_prev, v_pageviews_prev, v_phone_prev, v_form_prev
  from public.events_human
  where (occurred_at at time zone 'Europe/Paris')::date >= v_prev_start
    and (occurred_at at time zone 'Europe/Paris')::date <= v_prev_end;

  return query select
    v_n_start,
    v_n_end,
    coalesce(v_sessions_n,  0)::bigint,
    coalesce(v_pageviews_n, 0)::bigint,
    coalesce(v_phone_n,     0)::bigint,
    coalesce(v_form_n,      0)::bigint,
    (coalesce(v_phone_n, 0) + coalesce(v_form_n, 0))::bigint,
    v_prev_start,
    v_prev_end,
    coalesce(v_sessions_prev,  0)::bigint,
    coalesce(v_pageviews_prev, 0)::bigint,
    coalesce(v_phone_prev,     0)::bigint,
    coalesce(v_form_prev,      0)::bigint,
    (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0))::bigint,
    case when v_sessions_prev > 0
         then round((100.0 * (v_sessions_n - v_sessions_prev) / v_sessions_prev)::numeric, 2)
         else null end,
    case when v_pageviews_prev > 0
         then round((100.0 * (v_pageviews_n - v_pageviews_prev) / v_pageviews_prev)::numeric, 2)
         else null end,
    case when v_phone_prev > 0
         then round((100.0 * (v_phone_n - v_phone_prev) / v_phone_prev)::numeric, 2)
         else null end,
    case when v_form_prev > 0
         then round((100.0 * (v_form_n - v_form_prev) / v_form_prev)::numeric, 2)
         else null end,
    case when (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0)) > 0
         then round(
           (100.0 * ((coalesce(v_phone_n, 0) + coalesce(v_form_n, 0))
                   - (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0)))
            / (coalesce(v_phone_prev, 0) + coalesce(v_form_prev, 0)))::numeric, 2)
         else null end;
end;
$$;

COMMENT ON FUNCTION public.site_kpis_compare(integer) IS
  'Sprint 33+ : KPIs business N vs N-1 (sessions, pageviews, phone, form_submit, macro). Bornes en heure Paris.';

REVOKE EXECUTE ON FUNCTION public.site_kpis_compare(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_kpis_compare(integer) TO service_role;
