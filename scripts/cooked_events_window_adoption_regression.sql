-- Régression post-adoption C1 : refresh assisted + équivalence _eh SEO (1 jour)
BEGIN;

-- 1) refresh assisted rolling_28 (léger)
SELECT public.refresh_dashboard_resources_assisted('rolling_28');

SELECT count(*) AS assisted_rows,
       coalesce(sum(assisted_contacts), 0) AS sum_assisted
FROM public.dashboard_resources_assisted_snapshot
WHERE window_kind = 'rolling_28';

-- 2) équivalence matérialisation SEO sur 1 jour (human grain)
DO $$
DECLARE
  v_from timestamptz := public.cooked_paris_ts_start(public.paris_today() - 1);
  v_to   timestamptz := public.cooked_paris_ts_end_exclusive(public.paris_today() - 1);
  n_old bigint;
  n_new bigint;
BEGIN
  DROP TABLE IF EXISTS _eh_old;
  CREATE TEMP TABLE _eh_old ON COMMIT DROP AS
    SELECT r.id
    FROM (
      SELECT id, anonymous_id, session_id, name, path, props, occurred_at
      FROM public.events_main
      WHERE occurred_at >= v_from AND occurred_at < v_to
    ) r
    WHERE NOT EXISTS (SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = r.anonymous_id)
      AND NOT EXISTS (SELECT 1 FROM public.noise_sessions n WHERE n.session_id = r.session_id)
      AND NOT (r.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(r.props))
      AND NOT (
        r.name IN ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound')
        AND EXISTS (
          SELECT 1 FROM public.events_main d
          WHERE d.session_id = r.session_id AND d.name = r.name
            AND d.path IS NOT DISTINCT FROM r.path
            AND date_trunc('second', d.occurred_at) = date_trunc('second', r.occurred_at)
            AND (d.props->>'anchor') IS NOT DISTINCT FROM (r.props->>'anchor')
            AND d.id < r.id
        )
      );

  CALL public.cooked_events_window(v_from, v_to, 'human', 'main');
  SELECT count(*) INTO n_old FROM _eh_old;
  SELECT count(*) INTO n_new FROM _cooked_ev;
  IF n_old IS DISTINCT FROM n_new THEN
    RAISE EXCEPTION 'SEO _eh equivalence fail: old=% new=%', n_old, n_new;
  END IF;
  RAISE NOTICE 'PASS SEO _eh 1d equivalence: % rows', n_new;
END $$;

ROLLBACK;
