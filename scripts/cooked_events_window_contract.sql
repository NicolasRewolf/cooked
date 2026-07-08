-- Contrat C1 — cooked_events_window (sans meta-commandes psql)
BEGIN;

DO $$
DECLARE
  v_from timestamptz;
  v_to timestamptz;
  n_view bigint;
  n_win bigint;
BEGIN
  v_from := public.cooked_paris_ts_start(public.paris_today() - 1);
  v_to := public.cooked_paris_ts_end_exclusive(public.paris_today() - 1);

  SELECT count(*) INTO n_view
  FROM public.events_human e
  WHERE e.occurred_at >= v_from AND e.occurred_at < v_to;

  CALL public.cooked_events_window(v_from, v_to, 'human', 'main');
  SELECT count(*) INTO n_win FROM _cooked_ev;

  IF n_view IS DISTINCT FROM n_win THEN
    RAISE EXCEPTION 'human grain mismatch: events_human=% _cooked_ev=%', n_view, n_win;
  END IF;
  RAISE NOTICE 'PASS human grain: % rows', n_win;
END $$;

DO $$
DECLARE
  v_from timestamptz;
  v_to timestamptz;
  n_manual bigint;
  n_win bigint;
BEGIN
  v_from := public.cooked_paris_ts_start(public.paris_today() - 1);
  v_to := public.cooked_paris_ts_end_exclusive(public.paris_today() - 1);

  SELECT count(*) INTO n_manual
  FROM public.events_main e
  WHERE e.occurred_at >= v_from AND e.occurred_at < v_to
    AND NOT EXISTS (SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id)
    AND NOT EXISTS (SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id);

  CALL public.cooked_events_window(v_from, v_to, 'clean', 'main');
  SELECT count(*) INTO n_win FROM _cooked_ev;

  IF n_manual IS DISTINCT FROM n_win THEN
    RAISE EXCEPTION 'clean grain mismatch: manual=% _cooked_ev=%', n_manual, n_win;
  END IF;
  RAISE NOTICE 'PASS clean grain: % rows', n_win;
END $$;

DO $$
DECLARE
  bad bigint;
BEGIN
  CALL public.cooked_events_window(
    public.cooked_paris_ts_start(public.paris_today() - 7),
    public.cooked_paris_ts_end_exclusive(public.paris_today() - 1),
    'human',
    'main'
  );
  SELECT count(*) INTO bad
  FROM _cooked_ev
  WHERE d IS DISTINCT FROM public.paris_date(occurred_at);
  IF bad > 0 THEN
    RAISE EXCEPTION 'd column mismatch on % rows', bad;
  END IF;
  RAISE NOTICE 'PASS d column aligns with paris_date()';
END $$;

ROLLBACK;
