-- Bloc 0 / A1 (suite) — rendre run_rpc_contract_tests resilient au timeout.
--
-- Verifie en prod le 27/07/2026 a 23:46 : les 8 RPC passent toutes, pour un
-- total de 146,5 s (site_context_export 60,5 s + behavior_pages_for_period
-- 57,9 s + tracker_first_seen_global 18,7 s + 5 autres). C'est au-dessus des
-- 120 s auxquelles le statement etait arme, d'ou l'echec quotidien depuis le
-- 04/07/2026 — 23 jours sans aucun contract test.
--
-- Cause aggravante : chaque test est protege par `exception when others`, mais
-- WHEN OTHERS ne rattrape PAS query_canceled (57014), le code que leve un
-- statement_timeout. Un seul RPC lent annulait donc la transaction entiere et
-- n'ecrivait AUCUNE ligne dans rpc_health.
--
-- Une fois le timeout declenche puis rattrape, le minuteur est desarme : les
-- tests suivants s'executent normalement. C'est le motif que
-- cooked_refresh_after_gsc applique deja et documente.
--
-- Verifie a 23:50 sous le timeout par defaut : behavior_pages_for_period
-- ressort en 'failed / canceling statement due to statement timeout', les 7
-- autres en 'ok', 8/8 lignes ecrites dans rpc_health.

DO $mig$
DECLARE
  v_def text;
  v_n   integer;
BEGIN
  SELECT pg_get_functiondef('public.run_rpc_contract_tests()'::regprocedure)
    INTO v_def;

  v_n := (length(v_def) - length(replace(v_def, 'exception when others then', '')))
         / length('exception when others then');

  IF v_n = 0 THEN
    RAISE NOTICE 'Aucun handler a convertir — migration deja appliquee.';
    RETURN;
  END IF;

  IF v_n <> 8 THEN
    RAISE EXCEPTION 'Attendu 8 handlers dans run_rpc_contract_tests, trouve % — '
                    'la fonction a change, migration interrompue.', v_n;
  END IF;

  v_def := replace(v_def,
                   'exception when others then',
                   'exception when others or query_canceled then');

  EXECUTE v_def;
  RAISE NOTICE '8 handlers convertis en "when others or query_canceled".';
END
$mig$;
