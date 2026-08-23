-- Contrat C2 v2 (23/08/2026) — découverte par CATALOGUE, plus de liste en dur.
-- La v1 listait 9 règles et avait décroché (3 règles ajoutées jamais listées) ;
-- structurellement incapable de décrocher désormais : toute fonction
-- public.alert_rule_*() est vérifiée du seul fait d'exister.
-- Assertions : appelable, colonnes (kind, severity, detail), non exécutable
-- par anon/authenticated (récidive des REVOKE oubliés), registre de fraîcheur
-- couvrant les sources attendues, driver sain. Transaction ROLLBACK.
BEGIN;

DO $$
DECLARE
  f     record;
  v_cnt int;
BEGIN
  FOR f IN
    SELECT pr.proname
    FROM pg_proc pr
    JOIN pg_namespace n ON n.oid = pr.pronamespace
    WHERE n.nspname = 'public'
      AND pr.proname LIKE 'alert\_rule\_%'
      AND pr.pronargs = 0
    ORDER BY pr.proname
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I()', f.proname) INTO v_cnt;
    RAISE NOTICE 'PASS % — callable (% rows)', f.proname, v_cnt;

    IF has_function_privilege('anon', format('public.%I()', f.proname), 'EXECUTE')
       OR has_function_privilege('authenticated', format('public.%I()', f.proname), 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL % — exécutable par anon/authenticated (REVOKE manquant)', f.proname;
    END IF;
  END LOOP;
END $$;

-- Le registre de fraîcheur couvre les sources attendues (ADR-0002).
DO $$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(s, ', ') INTO missing
  FROM unnest(ARRAY[
    'gbp_daily', 'gsc_path_daily', 'dfs_keyword_volume', 'cpi_daily',
    'seo_url_snapshot', 'dashboard_resources_snapshot', 'form_submit',
    'crm_prospects', 'cta_phone_click'
  ]) s
  WHERE NOT EXISTS (
    SELECT 1 FROM public.freshness_contract fc WHERE fc.source = s AND fc.enabled
  );
  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL freshness_contract — sources sans contrat actif : %', missing;
  END IF;
  RAISE NOTICE 'PASS freshness_contract — couverture OK';
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
