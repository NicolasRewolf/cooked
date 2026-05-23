-- Sprint 33+ (24/05/2026) — Funnel SEO site-wide
--
-- 4 étapes du parcours acquisition organique Google :
--   1. Impressions GSC      (gsc_path_daily.impressions sommé)
--   2. Clics GSC            (gsc_path_daily.clicks sommé)
--   3. Visites Google Cooked (events_human, referrer Google)
--   4. Contacts macro        (cta_phone_click + form_submit)
--
-- Permet de localiser la friction principale : entre quel couple
-- d'étapes le drop-off est anormal.
--
-- Note : clics GSC ≈ visites Google Cooked en théorie. Un gros écart
-- (>30 %) suggère un trou tracker (Edge bloqué, AdBlock, sessions
-- multi-pages collapsées différemment) ou un définition utm/referrer
-- non-aligné.

CREATE OR REPLACE FUNCTION public.site_seo_funnel(
  period_days integer DEFAULT 28
)
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
  v_today  date := (now() at time zone 'Europe/Paris')::date;
  v_start  date := v_today - (period_days - 1);
  v_end    date := v_today;
  v_impressions bigint;
  v_clicks bigint;
  v_google_sessions bigint;
  v_macro bigint;
begin
  -- 1+2. GSC (impressions, clicks)
  select
    coalesce(sum(impressions), 0)::bigint,
    coalesce(sum(clicks), 0)::bigint
  into v_impressions, v_clicks
  from public.gsc_path_daily
  where day >= v_start and day <= v_end;

  -- 3. Visites Google Cooked (sessions distinctes avec referrer Google
  --    OU utm_source=google et utm_medium=organic)
  select count(distinct session_id) filter (
    where name = 'pageview'
      and device_type is distinct from 'server'
      and (
        referrer_hostname like '%google.%'
        or (utm_source = 'google' and utm_medium in ('organic', 'cpc'))
      )
  )::bigint into v_google_sessions
  from public.events_human
  where (occurred_at at time zone 'Europe/Paris')::date >= v_start
    and (occurred_at at time zone 'Europe/Paris')::date <= v_end;

  -- 4. Contacts macro (phone + form_submit)
  select (
    count(*) filter (where name = 'cta_phone_click') +
    count(*) filter (where name = 'form_submit')
  )::bigint into v_macro
  from public.events_human
  where (occurred_at at time zone 'Europe/Paris')::date >= v_start
    and (occurred_at at time zone 'Europe/Paris')::date <= v_end;

  return query select
    v_start,
    v_end,
    v_impressions,
    v_clicks,
    v_google_sessions,
    v_macro,
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
  'Sprint 33+ (24/05/2026) : funnel acquisition Google site-wide. Impressions → clics GSC → visites Google Cooked → contacts macro. Drop-off entre chaque étape.';

REVOKE EXECUTE ON FUNCTION public.site_seo_funnel(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_seo_funnel(integer) TO service_role;
