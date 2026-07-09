-- Régression C1 fin — équivalence détection bruit 48h (old events_no_bots vs new _no_bots)
BEGIN;

DO $$
DECLARE
  n_prefetch_old bigint;
  n_prefetch_new bigint;
  n_ua_old bigint;
  n_ua_new bigint;
BEGIN
  SELECT count(*) INTO n_prefetch_old
  FROM (
    SELECT session_id
    FROM public.events_no_bots
    WHERE session_id IS NOT NULL
      AND device_type IS DISTINCT FROM 'server'
      AND occurred_at > now() - interval '48 hours'
    GROUP BY session_id
    HAVING max(referrer_hostname) IS NULL
       AND count(*) FILTER (WHERE name = 'engagement_tick') = 0
       AND count(*) FILTER (WHERE name = 'scroll_depth') = 0
       AND count(*) FILTER (WHERE name = 'pageview') = 1
       AND extract(epoch FROM (max(occurred_at) - min(occurred_at))) < 10
  ) s;

  CALL public.cooked_events_window(now() - interval '48 hours', now(), 'raw', 'main');
  DROP TABLE IF EXISTS _no_bots;
  CREATE TEMP TABLE _no_bots ON COMMIT DROP AS
    SELECT e.session_id, e.name, e.referrer_hostname, e.user_agent, e.device_type, e.occurred_at
    FROM _cooked_ev e
    WHERE NOT EXISTS (
      SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
    );

  SELECT count(*) INTO n_prefetch_new
  FROM (
    SELECT session_id
    FROM _no_bots
    WHERE session_id IS NOT NULL
      AND device_type IS DISTINCT FROM 'server'
    GROUP BY session_id
    HAVING max(referrer_hostname) IS NULL
       AND count(*) FILTER (WHERE name = 'engagement_tick') = 0
       AND count(*) FILTER (WHERE name = 'scroll_depth') = 0
       AND count(*) FILTER (WHERE name = 'pageview') = 1
       AND extract(epoch FROM (max(occurred_at) - min(occurred_at))) < 10
  ) s;

  IF n_prefetch_old IS DISTINCT FROM n_prefetch_new THEN
    RAISE EXCEPTION 'prefetch mismatch: old=% new=%', n_prefetch_old, n_prefetch_new;
  END IF;

  SELECT count(DISTINCT session_id) INTO n_ua_old
  FROM public.events_no_bots
  WHERE session_id IS NOT NULL
    AND device_type IS DISTINCT FROM 'server'
    AND user_agent IS NOT NULL
    AND occurred_at > now() - interval '48 hours'
    AND (
         user_agent ILIKE '%headless%'
      OR user_agent ILIKE '%googlebot%'
      OR user_agent ILIKE '%bingbot%'
    );

  SELECT count(DISTINCT session_id) INTO n_ua_new
  FROM _no_bots
  WHERE session_id IS NOT NULL
    AND device_type IS DISTINCT FROM 'server'
    AND user_agent IS NOT NULL
    AND (
         user_agent ILIKE '%headless%'
      OR user_agent ILIKE '%googlebot%'
      OR user_agent ILIKE '%bingbot%'
    );

  IF n_ua_old IS DISTINCT FROM n_ua_new THEN
    RAISE EXCEPTION 'ua_bot sample mismatch: old=% new=%', n_ua_old, n_ua_new;
  END IF;

  RAISE NOTICE 'PASS noise 48h equivalence: prefetch=% ua_sample=%', n_prefetch_old, n_ua_old;
END $$;

ROLLBACK;
