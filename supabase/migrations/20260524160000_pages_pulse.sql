-- Sprint 33+ (24/05/2026) — Pulse cross-source GSC × Cooked
--
-- Induire une notion de "progression / régression" par page malgré
-- les 17 jours d'historique Cooked (06/05/2026 → aujourd'hui).
--
-- Stratégie : combiner GSC 28v28 (robuste, 16 mois dispo) + Cooked
-- 7v7 (court terme, indicatif) en grille 2×2 par path :
--   up_up      SEO ↗ comportement ↗  → la machine tourne
--   up_down    SEO ↗ comportement ↘  → trafic monte, engagement baisse (alerte UX)
--   down_up    SEO ↘ comportement ↗  → audience qualifiée qui reste
--   down_down  SEO ↘ comportement ↘  → page en fin de vie
--   neutral    deltas < ±5 % sur les deux axes
--   no_signal  volume nul N et N-1 sur au moins un axe, ou pro-ratage
--
-- Convention "flat" : axe entre ±delta_threshold_pct est traité comme
-- stable et rabattu côté "up" — on n'invente pas de régression sur un
-- axe sans variation.
--
-- Toutes bornes en heure Paris (règle dure CLAUDE.md cooked).
-- Garde-fou pro-ratage via tracker_first_seen_global() côté Cooked.
--
-- NB : alias paths(p) et g.path / c.path pour éviter l'ambiguïté avec
-- le paramètre OUT `path` de RETURNS TABLE.


-- ============================================================
-- 1. gsc_pages_compare(period_days) — delta GSC par path
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_pages_compare(period_days integer DEFAULT 28)
RETURNS TABLE (
  path                    text,
  clicks_n                bigint,
  clicks_prev             bigint,
  clicks_delta_pct        numeric,
  impressions_n           bigint,
  impressions_prev        bigint,
  impressions_delta_pct   numeric,
  position_avg_n          numeric,
  position_avg_prev       numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
declare
  v_today      date := (now() at time zone 'Europe/Paris')::date;
  v_n_start    date := v_today - (period_days - 1);
  v_n_end      date := v_today;
  v_prev_start date := v_n_start - period_days;
  v_prev_end   date := v_n_start - 1;
begin
  return query
  with n_agg as (
    select g.path as p,
      sum(g.clicks)::bigint      as clicks_total,
      sum(g.impressions)::bigint as imp_total,
      case when sum(g.impressions) > 0
           then round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
           else null end as position_avg
    from public.gsc_path_daily g
    where g.day >= v_n_start and g.day <= v_n_end
    group by g.path
  ),
  prev_agg as (
    select g.path as p,
      sum(g.clicks)::bigint      as clicks_total,
      sum(g.impressions)::bigint as imp_total,
      case when sum(g.impressions) > 0
           then round((sum(g.position * g.impressions) / sum(g.impressions))::numeric, 2)
           else null end as position_avg
    from public.gsc_path_daily g
    where g.day >= v_prev_start and g.day <= v_prev_end
    group by g.path
  ),
  paths as (select n_agg.p from n_agg union select prev_agg.p from prev_agg)
  select
    paths.p,
    coalesce(n.clicks_total, 0),
    coalesce(pr.clicks_total, 0),
    case when coalesce(pr.clicks_total, 0) > 0
         then round((100.0 * (coalesce(n.clicks_total, 0) - pr.clicks_total) / pr.clicks_total)::numeric, 2)
         else null end,
    coalesce(n.imp_total, 0),
    coalesce(pr.imp_total, 0),
    case when coalesce(pr.imp_total, 0) > 0
         then round((100.0 * (coalesce(n.imp_total, 0) - pr.imp_total) / pr.imp_total)::numeric, 2)
         else null end,
    n.position_avg,
    pr.position_avg
  from paths
    left join n_agg n on n.p = paths.p
    left join prev_agg pr on pr.p = paths.p;
end;
$$;

COMMENT ON FUNCTION public.gsc_pages_compare(integer) IS
  'Sprint 33+ (24/05/2026) : delta GSC par path sur fenêtre N vs N-1 (heure Paris).';

REVOKE EXECUTE ON FUNCTION public.gsc_pages_compare(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_pages_compare(integer) TO service_role;


-- ============================================================
-- 2. cooked_pages_compare(period_days) — delta Cooked par path
-- ============================================================
CREATE OR REPLACE FUNCTION public.cooked_pages_compare(period_days integer DEFAULT 7)
RETURNS TABLE (
  path                       text,
  sessions_n                 bigint,
  sessions_prev              bigint,
  sessions_delta_pct         numeric,
  contacts_n                 bigint,
  contacts_prev              bigint,
  contacts_delta_pct         numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
declare
  v_today      date := (now() at time zone 'Europe/Paris')::date;
  v_n_start    date := v_today - (period_days - 1);
  v_n_end      date := v_today;
  v_prev_start date := v_n_start - period_days;
  v_prev_end   date := v_n_start - 1;
  -- Garde-fou pro-ratage : si l'historique tracker est insuffisant
  -- pour couvrir la fenêtre N-1, on retourne prev/delta = NULL plutôt
  -- que d'inventer un baseline biaisé (règle méthodologique CLAUDE.md).
  v_first_seen date := (public.tracker_first_seen_global() at time zone 'Europe/Paris')::date;
  v_has_prev   boolean := v_first_seen is not null and v_first_seen <= v_prev_start;
begin
  return query
  with n_agg as (
    select e.path as p,
      count(distinct e.session_id) filter (
        where e.name = 'pageview' and e.device_type is distinct from 'server'
      )::bigint as sessions_total,
      (count(*) filter (where e.name = 'cta_phone_click')
        + count(*) filter (where e.name = 'form_submit'))::bigint as contacts_total
    from public.events_human e
    where e.path is not null
      and (e.occurred_at at time zone 'Europe/Paris')::date >= v_n_start
      and (e.occurred_at at time zone 'Europe/Paris')::date <= v_n_end
    group by e.path
  ),
  prev_agg as (
    select e.path as p,
      count(distinct e.session_id) filter (
        where e.name = 'pageview' and e.device_type is distinct from 'server'
      )::bigint as sessions_total,
      (count(*) filter (where e.name = 'cta_phone_click')
        + count(*) filter (where e.name = 'form_submit'))::bigint as contacts_total
    from public.events_human e
    where e.path is not null and v_has_prev
      and (e.occurred_at at time zone 'Europe/Paris')::date >= v_prev_start
      and (e.occurred_at at time zone 'Europe/Paris')::date <= v_prev_end
    group by e.path
  ),
  paths as (select n_agg.p from n_agg union select prev_agg.p from prev_agg)
  select
    paths.p,
    coalesce(n.sessions_total, 0),
    case when v_has_prev then coalesce(pr.sessions_total, 0) else null end,
    case when v_has_prev and coalesce(pr.sessions_total, 0) > 0
         then round((100.0 * (coalesce(n.sessions_total, 0) - pr.sessions_total) / pr.sessions_total)::numeric, 2)
         else null end,
    coalesce(n.contacts_total, 0),
    case when v_has_prev then coalesce(pr.contacts_total, 0) else null end,
    case when v_has_prev and coalesce(pr.contacts_total, 0) > 0
         then round((100.0 * (coalesce(n.contacts_total, 0) - pr.contacts_total) / pr.contacts_total)::numeric, 2)
         else null end
  from paths
    left join n_agg n on n.p = paths.p
    left join prev_agg pr on pr.p = paths.p;
end;
$$;

COMMENT ON FUNCTION public.cooked_pages_compare(integer) IS
  'Sprint 33+ (24/05/2026) : delta Cooked par path N vs N-1 (heure Paris). Contacts = phone + form_submit (macro CLAUDE.md). Garde-fou pro-ratage via tracker_first_seen_global.';

REVOKE EXECUTE ON FUNCTION public.cooked_pages_compare(integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cooked_pages_compare(integer) TO service_role;


-- ============================================================
-- 3. pages_pulse(gsc_period, cooked_period, threshold) — orchestration
-- ============================================================
CREATE OR REPLACE FUNCTION public.pages_pulse(
  gsc_period           integer DEFAULT 28,
  cooked_period        integer DEFAULT 7,
  delta_threshold_pct  numeric DEFAULT 5.0
)
RETURNS TABLE (
  path                        text,
  gsc_clicks_n                bigint,
  gsc_clicks_prev             bigint,
  gsc_delta_pct               numeric,
  cooked_sessions_n           bigint,
  cooked_sessions_prev        bigint,
  cooked_sessions_delta_pct   numeric,
  quadrant                    text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  with g as (
    select gpc.*,
      case
        when gpc.clicks_delta_pct is null then 'flat'
        when gpc.clicks_delta_pct >=  delta_threshold_pct then 'up'
        when gpc.clicks_delta_pct <= -delta_threshold_pct then 'down'
        else 'flat'
      end as gsc_dir
    from public.gsc_pages_compare(gsc_period) gpc
  ),
  c as (
    select cpc.*,
      case
        when cpc.sessions_delta_pct is null then 'flat'
        when cpc.sessions_delta_pct >=  delta_threshold_pct then 'up'
        when cpc.sessions_delta_pct <= -delta_threshold_pct then 'down'
        else 'flat'
      end as cooked_dir
    from public.cooked_pages_compare(cooked_period) cpc
  ),
  pp as (select g.path as p from g union select c.path from c)
  select
    pp.p,
    coalesce(g.clicks_n, 0),
    coalesce(g.clicks_prev, 0),
    g.clicks_delta_pct,
    coalesce(c.sessions_n, 0),
    c.sessions_prev,
    c.sessions_delta_pct,
    case
      when (coalesce(g.clicks_n, 0) = 0 and coalesce(g.clicks_prev, 0) = 0) then 'no_signal'
      when (coalesce(c.sessions_n, 0) = 0 and coalesce(c.sessions_prev, 0) = 0 and c.sessions_prev is not null) then 'no_signal'
      when c.sessions_prev is null then 'no_signal'
      when g.gsc_dir = 'flat' and c.cooked_dir = 'flat' then 'neutral'
      when g.gsc_dir = 'up'   and c.cooked_dir = 'up'   then 'up_up'
      when g.gsc_dir = 'up'   and c.cooked_dir = 'flat' then 'up_up'
      when g.gsc_dir = 'up'   and c.cooked_dir = 'down' then 'up_down'
      when g.gsc_dir = 'flat' and c.cooked_dir = 'up'   then 'up_up'
      when g.gsc_dir = 'flat' and c.cooked_dir = 'down' then 'up_down'
      when g.gsc_dir = 'down' and c.cooked_dir = 'up'   then 'down_up'
      when g.gsc_dir = 'down' and c.cooked_dir = 'flat' then 'down_up'
      when g.gsc_dir = 'down' and c.cooked_dir = 'down' then 'down_down'
      else 'neutral'
    end as quadrant
  from pp
    left join g on g.path = pp.p
    left join c on c.path = pp.p;
$$;

COMMENT ON FUNCTION public.pages_pulse(integer, integer, numeric) IS
  'Sprint 33+ (24/05/2026) : Pulse cross-source par path = grille 2×2 (GSC 28v28 × Cooked 7v7). 6 quadrants : up_up, up_down, down_up, down_down, neutral, no_signal. Axe flat sur 1 axe rabattu vers up (on n''invente pas de régression).';

REVOKE EXECUTE ON FUNCTION public.pages_pulse(integer, integer, numeric) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.pages_pulse(integer, integer, numeric) TO service_role;
