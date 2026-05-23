-- Sprint 33+ (24/05/2026) — fix ambiguïté site_seo_funnel
--
-- La première version (20260524260000) référait `impressions` sans
-- alias dans le corps PL/pgSQL → conflit avec la colonne du
-- RETURNS TABLE qui porte le même nom. Erreur 42702 au runtime.
--
-- Fix : alias g.* / e.* sur tous les SELECT internes pour
-- désambiguïser. Aucun changement de signature ni de comportement.

CREATE OR REPLACE FUNCTION public.site_seo_funnel(period_days integer DEFAULT 28)
RETURNS TABLE (
  period_start              date,
  period_end                date,
  impressions               bigint,
  clicks                    bigint,
  google_sessions           bigint,
  macro_contacts            bigint,
  impr_to_click_pct         numeric,
  click_to_session_pct      numeric,
  session_to_contact_pct    numeric,
  overall_impr_to_contact_pct numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_today date := (now() at time zone 'Europe/Paris')::date;
  v_start date := v_today - (period_days - 1);
  v_end   date := v_today;
  v_impressions     bigint;
  v_clicks          bigint;
  v_google_sessions bigint;
  v_macro           bigint;
begin
  -- Alias g.* pour éviter l'ambiguïté avec les colonnes du RETURNS TABLE
  select coalesce(sum(g.impressions), 0)::bigint, coalesce(sum(g.clicks), 0)::bigint
  into v_impressions, v_clicks
  from public.gsc_path_daily g
  where g.day >= v_start and g.day <= v_end;

  select count(distinct e.session_id) filter (
    where e.name = 'pageview'
      and e.device_type is distinct from 'server'
      and (
        e.referrer_hostname like '%google.%'
        or (e.utm_source = 'google' and e.utm_medium in ('organic', 'cpc'))
      )
  )::bigint into v_google_sessions
  from public.events_human e
  where (e.occurred_at at time zone 'Europe/Paris')::date >= v_start
    and (e.occurred_at at time zone 'Europe/Paris')::date <= v_end;

  select (
    count(*) filter (where e.name = 'cta_phone_click') +
    count(*) filter (where e.name = 'form_submit')
  )::bigint into v_macro
  from public.events_human e
  where (e.occurred_at at time zone 'Europe/Paris')::date >= v_start
    and (e.occurred_at at time zone 'Europe/Paris')::date <= v_end;

  return query select
    v_start, v_end,
    v_impressions, v_clicks, v_google_sessions, v_macro,
    case when v_impressions > 0
         then round((100.0 * v_clicks / v_impressions)::numeric, 2)
         else null end,
    case when v_clicks > 0
         then round((100.0 * v_google_sessions / v_clicks)::numeric, 2)
         else null end,
    case when v_google_sessions > 0
         then round((100.0 * v_macro / v_google_sessions)::numeric, 2)
         else null end,
    case when v_impressions > 0
         then round((100.0 * v_macro / v_impressions)::numeric, 4)
         else null end;
end;
$$;

COMMENT ON FUNCTION public.site_seo_funnel(integer) IS
  'Sprint 33+ (24/05/2026) v2 : funnel acquisition Google site-wide. Aliases g./e. pour désambiguïser.';

REVOKE EXECUTE ON FUNCTION public.site_seo_funnel(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_seo_funnel(integer) TO service_role;
