-- Heure murale Paris : les jours de 23/25 heures ne changent pas le cadran.
CREATE OR REPLACE FUNCTION public.cooked_paris_hour(p_ts timestamp with time zone)
RETURNS integer LANGUAGE sql STABLE
SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT extract(hour FROM p_ts AT TIME ZONE 'Europe/Paris')::integer;
$function$;

REVOKE ALL ON FUNCTION public.cooked_paris_hour(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_paris_hour(timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.alert_rule_volume_floor()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_today date := public.paris_today();
  v_hour_now int;
  v_prev_hour int;
  v_prev_day date;
  t0 timestamptz;
  t1 timestamptz;
  v_n bigint;
  v_med numeric;
BEGIN
  v_hour_now := public.cooked_paris_hour(now());
  v_prev_hour := v_hour_now - 1;
  v_prev_day := v_today;
  IF v_prev_hour < 0 THEN
    v_prev_hour := 23;
    v_prev_day := v_today - 1;
  END IF;
  IF v_prev_hour < 9 OR v_prev_hour > 18 THEN
    RETURN;
  END IF;

  -- Construire l'heure murale avant conversion en instant absolu.
  -- Minuit Paris + N heures écoulées se décale les jours de 23/25 heures.
  t0 := (v_prev_day::timestamp + make_interval(hours => v_prev_hour))
        AT TIME ZONE 'Europe/Paris';
  t1 := t0 + interval '1 hour';

  SELECT count(*) FILTER (WHERE name = 'pageview') INTO v_n
  FROM public.events_human
  WHERE occurred_at >= t0 AND occurred_at < t1;

  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY n) INTO v_med
  FROM (
    SELECT count(*) FILTER (WHERE e.name = 'pageview') AS n
    FROM public.events_human e
    WHERE e.occurred_at >= public.cooked_paris_ts_start(v_prev_day - 7)
      AND e.occurred_at < public.cooked_paris_ts_start(v_prev_day)
      AND public.cooked_paris_hour(e.occurred_at) = v_prev_hour
    GROUP BY public.paris_date(e.occurred_at)
  ) s;

  IF coalesce(v_med, 0) >= 30 AND coalesce(v_n, 0) < 0.5 * v_med THEN
    RETURN QUERY SELECT
      'volume_floor'::text,
      'warn'::text,
      format(
        'Pageviews %sh Paris : %s vs médiane 7 j %s (−%s %%). Heure habituellement ≥ 30.',
        v_prev_hour, v_n, round(v_med),
        round(100.0 * (1 - v_n / nullif(v_med, 0)))
      )::text;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.alert_rule_volume_floor() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_volume_floor() TO service_role;
