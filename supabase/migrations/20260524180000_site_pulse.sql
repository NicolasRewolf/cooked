-- Sprint 33+ (24/05/2026) — site_pulse cross-source
--
-- Version site-wide du Pulse par page (migration 20260524160000) :
-- on calcule les totaux site-wide N vs N-1 pour GSC et Cooked sur les
-- fenêtres respectives, puis on en déduit le quadrant global.
--
-- Pourquoi pas réutiliser pages_pulse() en agrégeant ? On peut, mais
-- une RPC dédiée évite de matérialiser 480 rows juste pour les sommer.
-- Aussi : le quadrant agrégé n'est pas la somme des quadrants — il
-- vient des deltas des totaux, qui ne s'additionnent pas comme ça.
--
-- Toutes bornes en heure Paris. Garde-fou pro-ratage Cooked (retour
-- prev = null si historique insuffisant).

CREATE OR REPLACE FUNCTION public.site_pulse(
  gsc_period           integer DEFAULT 28,
  cooked_period        integer DEFAULT 7,
  delta_threshold_pct  numeric DEFAULT 5.0
)
RETURNS TABLE (
  gsc_period_start            date,
  gsc_period_end              date,
  cooked_period_start         date,
  cooked_period_end           date,
  gsc_clicks_n                bigint,
  gsc_clicks_prev             bigint,
  gsc_delta_pct               numeric,
  cooked_sessions_n           bigint,
  cooked_sessions_prev        bigint,
  cooked_sessions_delta_pct   numeric,
  quadrant                    text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_today           date := (now() at time zone 'Europe/Paris')::date;
  v_gsc_n_start     date := v_today - (gsc_period - 1);
  v_gsc_n_end       date := v_today;
  v_gsc_prev_start  date := v_gsc_n_start - gsc_period;
  v_gsc_prev_end    date := v_gsc_n_start - 1;
  v_ck_n_start      date := v_today - (cooked_period - 1);
  v_ck_n_end        date := v_today;
  v_ck_prev_start   date := v_ck_n_start - cooked_period;
  v_ck_prev_end     date := v_ck_n_start - 1;
  v_first_seen      date := (public.tracker_first_seen_global() at time zone 'Europe/Paris')::date;
  v_has_prev_cooked boolean := v_first_seen is not null and v_first_seen <= v_ck_prev_start;
  v_gsc_n           bigint;
  v_gsc_prev        bigint;
  v_ck_n            bigint;
  v_ck_prev         bigint;
  v_gsc_delta       numeric;
  v_ck_delta        numeric;
  v_gsc_dir         text;
  v_ck_dir          text;
  v_quadrant        text;
begin
  -- GSC totaux
  select coalesce(sum(clicks), 0)::bigint into v_gsc_n
  from public.gsc_path_daily
  where day >= v_gsc_n_start and day <= v_gsc_n_end;

  select coalesce(sum(clicks), 0)::bigint into v_gsc_prev
  from public.gsc_path_daily
  where day >= v_gsc_prev_start and day <= v_gsc_prev_end;

  -- Cooked totaux
  select count(distinct session_id) filter (
           where name = 'pageview' and device_type is distinct from 'server'
         )::bigint into v_ck_n
  from public.events_human
  where (occurred_at at time zone 'Europe/Paris')::date >= v_ck_n_start
    and (occurred_at at time zone 'Europe/Paris')::date <= v_ck_n_end;

  if v_has_prev_cooked then
    select count(distinct session_id) filter (
             where name = 'pageview' and device_type is distinct from 'server'
           )::bigint into v_ck_prev
    from public.events_human
    where (occurred_at at time zone 'Europe/Paris')::date >= v_ck_prev_start
      and (occurred_at at time zone 'Europe/Paris')::date <= v_ck_prev_end;
  else
    v_ck_prev := null;
  end if;

  -- Deltas
  v_gsc_delta := case when v_gsc_prev > 0
                      then round((100.0 * (v_gsc_n - v_gsc_prev) / v_gsc_prev)::numeric, 2)
                      else null end;
  v_ck_delta  := case when v_ck_prev is not null and v_ck_prev > 0
                      then round((100.0 * (v_ck_n - v_ck_prev) / v_ck_prev)::numeric, 2)
                      else null end;

  -- Directions par axe (mêmes seuils que pages_pulse)
  v_gsc_dir := case
                 when v_gsc_delta is null then 'flat'
                 when v_gsc_delta >=  delta_threshold_pct then 'up'
                 when v_gsc_delta <= -delta_threshold_pct then 'down'
                 else 'flat'
               end;
  v_ck_dir  := case
                 when v_ck_delta is null then 'flat'
                 when v_ck_delta >=  delta_threshold_pct then 'up'
                 when v_ck_delta <= -delta_threshold_pct then 'down'
                 else 'flat'
               end;

  -- Quadrant (mêmes règles que pages_pulse — flat sur 1 axe = rabattu up)
  v_quadrant := case
    when (v_gsc_n = 0 and coalesce(v_gsc_prev, 0) = 0) then 'no_signal'
    when (v_ck_n = 0 and coalesce(v_ck_prev, 0) = 0 and v_ck_prev is not null) then 'no_signal'
    when v_ck_prev is null then 'no_signal'
    when v_gsc_dir = 'flat' and v_ck_dir = 'flat' then 'neutral'
    when v_gsc_dir = 'up'   and v_ck_dir = 'up'   then 'up_up'
    when v_gsc_dir = 'up'   and v_ck_dir = 'flat' then 'up_up'
    when v_gsc_dir = 'up'   and v_ck_dir = 'down' then 'up_down'
    when v_gsc_dir = 'flat' and v_ck_dir = 'up'   then 'up_up'
    when v_gsc_dir = 'flat' and v_ck_dir = 'down' then 'up_down'
    when v_gsc_dir = 'down' and v_ck_dir = 'up'   then 'down_up'
    when v_gsc_dir = 'down' and v_ck_dir = 'flat' then 'down_up'
    when v_gsc_dir = 'down' and v_ck_dir = 'down' then 'down_down'
    else 'neutral'
  end;

  return query select
    v_gsc_n_start, v_gsc_n_end,
    v_ck_n_start,  v_ck_n_end,
    v_gsc_n, v_gsc_prev, v_gsc_delta,
    v_ck_n,  v_ck_prev,  v_ck_delta,
    v_quadrant;
end;
$$;

COMMENT ON FUNCTION public.site_pulse(integer, integer, numeric) IS
  'Sprint 33+ (24/05/2026) : Pulse cross-source site-wide. Totaux GSC clics 28v28 et Cooked sessions 7v7, quadrant global. Cohérent avec pages_pulse (mêmes seuils et règles flat).';

REVOKE EXECUTE ON FUNCTION public.site_pulse(integer, integer, numeric) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.site_pulse(integer, integer, numeric) TO service_role;
