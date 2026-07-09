-- Contrat C2 — règles alerte testables isolément + driver
BEGIN;

DO $$
DECLARE
  v_rules text[] := ARRAY[
    'alert_rule_pipeline_dead',
    'alert_rule_double_embed_suspect',
    'alert_rule_rpc_health',
    'alert_rule_form_attribution_degraded',
    'alert_rule_gsc_lag',
    'alert_rule_gsc_gap',
    'alert_rule_cpi_drop',
    'alert_rule_dfs_stale',
    'alert_rule_tracker_drift'
  ];
  v_fn text;
  v_cnt int;
BEGIN
  FOREACH v_fn IN ARRAY v_rules LOOP
    EXECUTE format('SELECT count(*) FROM public.%I()', v_fn) INTO v_cnt;
    RAISE NOTICE 'PASS % — callable (% rows)', v_fn, v_cnt;
  END LOOP;
END $$;

-- Driver : ne doit pas planter (retour entier ≥ 0)
DO $$
DECLARE v_added int;
BEGIN
  SELECT public.cooked_alerts_refresh() INTO v_added;
  IF v_added < 0 THEN
    RAISE EXCEPTION 'cooked_alerts_refresh returned %', v_added;
  END IF;
  RAISE NOTICE 'PASS cooked_alerts_refresh — added=%', v_added;
END $$;

ROLLBACK;
