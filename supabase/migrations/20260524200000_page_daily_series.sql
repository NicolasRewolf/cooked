-- Sprint 33+ (24/05/2026) — séries quotidiennes par page pour sparklines
--
-- Alimente le panneau "Tendance" sur la fiche /p/[slug] du dashboard :
--   2 sparklines (GSC clics 56j, Cooked sessions 14j) + badge Pulse grand.
--
-- 2 RPCs séparées plutôt qu'1 unifiée — typage TS plus clair, latence
-- équivalente via Promise.all côté Next.js.
--
-- Toutes bornes en heure Paris (règle dure CLAUDE.md cooked).
-- Les jours sans data retournent 0 (pas de gap dans la série, pour que
-- Recharts trace une ligne continue).


-- ============================================================
-- 1. gsc_page_daily_series(target_path, days_back) — clics GSC par jour
-- ============================================================
CREATE OR REPLACE FUNCTION public.gsc_page_daily_series(
  target_path text,
  days_back   integer DEFAULT 56
)
RETURNS TABLE (
  day      date,
  clicks   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  with cp as (select canonical_path(target_path) as p),
  series as (
    select gs::date as day
    from generate_series(
      (now() at time zone 'Europe/Paris')::date - (days_back - 1),
      (now() at time zone 'Europe/Paris')::date,
      interval '1 day'
    ) gs
  )
  select
    s.day,
    coalesce(sum(g.clicks), 0)::bigint as clicks
  from series s
    left join public.gsc_path_daily g
      on g.day = s.day
     and g.path = (select p from cp)
  group by s.day
  order by s.day;
$$;

COMMENT ON FUNCTION public.gsc_page_daily_series(text, integer) IS
  'Sprint 33+ (24/05/2026) : série quotidienne clics GSC par page sur N jours (sparkline fiche page). Jours sans data = 0.';

REVOKE EXECUTE ON FUNCTION public.gsc_page_daily_series(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.gsc_page_daily_series(text, integer) TO service_role;


-- ============================================================
-- 2. cooked_page_daily_series(target_path, days_back) — visites Cooked par jour
-- ============================================================
CREATE OR REPLACE FUNCTION public.cooked_page_daily_series(
  target_path text,
  days_back   integer DEFAULT 14
)
RETURNS TABLE (
  day        date,
  sessions   bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  with cp as (select canonical_path(target_path) as p),
  series as (
    select gs::date as day
    from generate_series(
      (now() at time zone 'Europe/Paris')::date - (days_back - 1),
      (now() at time zone 'Europe/Paris')::date,
      interval '1 day'
    ) gs
  )
  select
    s.day,
    coalesce(
      count(distinct e.session_id) filter (
        where e.name = 'pageview' and e.device_type is distinct from 'server'
      ),
      0
    )::bigint as sessions
  from series s
    left join public.events_human e
      on (e.occurred_at at time zone 'Europe/Paris')::date = s.day
     and e.path = (select p from cp)
  group by s.day
  order by s.day;
$$;

COMMENT ON FUNCTION public.cooked_page_daily_series(text, integer) IS
  'Sprint 33+ (24/05/2026) : série quotidienne visites Cooked par page sur N jours (sparkline fiche page). Jours sans data = 0.';

REVOKE EXECUTE ON FUNCTION public.cooked_page_daily_series(text, integer) FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cooked_page_daily_series(text, integer) TO service_role;
