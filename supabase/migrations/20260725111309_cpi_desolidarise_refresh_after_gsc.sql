-- Revue d'architecture 25/07/2026, tâche n°2 (cause racine R1) :
-- désolidariser le CPI de la transaction de refresh.
--
-- Avant : cooked_refresh_after_gsc() enchaînait 4 PERFORM dans un seul bloc,
-- CPI en DERNIER. Toute erreur d'une étape dashboard annulait la transaction
-- entière, donc le snapshot CPI — la seule donnée du système impossible à
-- recalculer a posteriori (cooked_page_index lit now()). C'est ainsi que
-- cpi_daily s'est troué de 9 jours en juillet.
--
-- Après :
--   1. cooked_cpi_snapshot() passe en PREMIER — la donnée irrécupérable
--      d'abord, les snapshots dashboard (reconstructibles à l'heure
--      suivante) ensuite. Effet de bord voulu : les snapshots dashboard
--      embarquent désormais le CPI du jour J (avant : J-1, puisque le CPI
--      s'écrivait après eux). Un décalage ponctuel des colonnes CPI du
--      dashboard le jour du déploiement n'est PAS un mouvement réel.
--   2. Chaque étape est isolée dans son propre bloc BEGIN…EXCEPTION
--      (sous-transaction) : l'échec d'une étape n'emporte plus les autres.
--      Le handler est « WHEN OTHERS OR query_canceled » car OTHERS seul
--      EXCLUT query_canceled/57014 (donc les statement_timeout — vérifié
--      empiriquement sur ce serveur le 25/07/2026) : sans cette clause, le
--      scénario historique « timeout dashboard emporte le CPI » persistait.
--   3. Un 57014 signifie que le budget de 2400 s posé par la commande du
--      cron 46 est CONSOMMÉ — l'alarme ne se réarme jamais en cours de
--      statement. On arrête donc la séquence immédiatement : les étapes
--      déjà réussies sont conservées, les restantes attendront le tick
--      suivant. Continuer aurait fait tourner les étapes restantes sans
--      aucune borne de temps, advisory lock tenu, panne muette.
--      Revers : pg_cancel_backend (57014 aussi) devient un « stop propre +
--      alerte », plus une annulation totale du run.
--   4. Le marqueur last_full_refresh_after_gsc_at n'est écrit que si les
--      4 étapes ont abouti : l'heure suivante rejoue la séquence complète
--      tant qu'une étape échoue. Tous les refreshers sont idempotents
--      (cpi_daily en ON CONFLICT (day, path), dashboards en
--      DELETE+INSERT) ; coût assumé : au pire 13 rejeux/jour (8h-20h),
--      l'alerte doit donc être traitée dans la journée.
--   5. Chaque étape en échec lève SA propre alerte critical
--      (kind granulaire refresh_step_failed_<étape>, dédup 24 h par kind
--      + push ntfy via raise_cooked_alert, SQLSTATE dans le détail) — le
--      job pg_cron reste 'succeeded' sur un échec partiel, sans cette
--      alerte l'échec serait invisible d'alert_rule_cron_failed. L'appel
--      d'alerte et l'écriture du marqueur sont eux-mêmes blindés : ils ne
--      peuvent jamais annuler le travail déjà committé en sous-transaction.
--   6. Le SET LOCAL statement_timeout = '600s' disparaît : il n'a jamais
--      rien borné — l'alarme du timeout est armée au démarrage du statement
--      top-level, la modifier en cours d'exécution est sans effet. Le vrai
--      budget reste le SET statement_timeout='2400s' du cron 46.

CREATE OR REPLACE FUNCTION public.cooked_refresh_after_gsc()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last_ingest   timestamptz;
  v_last_complete timestamptz;
  v_today_paris   date := public.paris_today();
  v_steps constant text[] := ARRAY[
    'cooked_cpi_snapshot',
    'refresh_dashboard_snapshots',
    'refresh_dashboard_expertises_snapshots',
    'refresh_dashboard_resources_assisted'
  ];
  v_step     text;
  v_i        integer;
  v_failures text[] := array[]::text[];
  v_detail   text;
  v_err      text;
  v_state    text;
BEGIN
  -- Un seul orchestrateur à la fois : lock de portée transaction, relâché
  -- automatiquement (y compris en cas d'erreur).
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RETURN 'skip: un refresh est déjà en cours';
  END IF;

  SELECT max(ingested_at) INTO v_last_ingest FROM public.gsc_path_daily;

  SELECT value::timestamptz INTO v_last_complete
  FROM public.cooked_config
  WHERE key = 'last_full_refresh_after_gsc_at';

  -- L'ingestion du jour n'a pas encore atterri : on repassera dans une heure.
  IF v_last_ingest IS NULL
     OR public.paris_date(v_last_ingest) < v_today_paris THEN
    RETURN 'skip: ingestion GSC du jour pas encore arrivée';
  END IF;

  -- La séquence COMPLÈTE a déjà tourné après cette ingestion : rien à faire.
  IF v_last_complete IS NOT NULL AND v_last_complete >= v_last_ingest THEN
    RETURN 'skip: séquence déjà complète après l''ingestion du jour';
  END IF;

  -- CPI en PREMIER : un jour manqué de cpi_daily est perdu pour toujours
  -- (cooked_page_index lit now()), un snapshot dashboard se reconstruit à
  -- l'identique une heure plus tard. Chaque étape est une sous-transaction :
  -- son échec — statement_timeout compris, d'où le OR query_canceled que
  -- OTHERS n'inclut pas — n'emporte ni les étapes déjà faites ni les
  -- suivantes.
  FOR v_i IN 1..cardinality(v_steps) LOOP
    v_step := v_steps[v_i];
    BEGIN
      EXECUTE format('SELECT public.%I()', v_step);
    EXCEPTION WHEN OTHERS OR query_canceled THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
      v_detail := format('%s [%s]: %s', v_step, v_state, v_err);
      IF v_state = '57014' AND v_i < cardinality(v_steps) THEN
        v_detail := v_detail || format(' — étapes non lancées (budget timeout épuisé) : %s',
                                       array_to_string(v_steps[v_i + 1:], ', '));
      END IF;
      v_failures := v_failures || v_detail;

      -- Alerte granulaire par étape (dédup 24 h par kind, push ntfy sur
      -- critical). Blindée : elle ne doit jamais annuler le travail déjà
      -- fait en sous-transaction.
      BEGIN
        PERFORM public.raise_cooked_alert(
          'refresh_step_failed_' || v_step, 'critical',
          format('Refresh après GSC — %s. Les étapes réussies sont conservées ; retry complet au prochain tick horaire (cron 46, 8h-20h).',
                 v_detail));
      EXCEPTION WHEN OTHERS OR query_canceled THEN
        NULL;
      END;

      -- Budget 2400 s consommé : l'alarme ne se réarme pas, continuer
      -- ferait tourner les étapes restantes sans borne de temps.
      IF v_state = '57014' THEN
        EXIT;
      END IF;
    END;
  END LOOP;

  IF cardinality(v_failures) = 0 THEN
    -- Marqueur de fin : écrit uniquement si les 4 étapes ont abouti — l'heure
    -- suivante rejoue donc la séquence complète tant qu'une étape échoue.
    -- Blindé : un raté du marqueur vaut un simple rejeu idempotent, pas
    -- l'annulation des 4 étapes.
    BEGIN
      INSERT INTO public.cooked_config (key, value, updated_at)
      VALUES ('last_full_refresh_after_gsc_at', now()::text, now())
      ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
    EXCEPTION WHEN OTHERS OR query_canceled THEN
      NULL;
    END;

    RETURN format('ok: séquence complète après ingestion du %s',
                  to_char(v_last_ingest AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'));
  END IF;

  RETURN format('partiel: %s', array_to_string(v_failures, ' | '));
END;
$function$;

-- CREATE OR REPLACE préserve les ACL déjà posées en prod (REVOKE du
-- 20260725062716), mais on les ré-affirme pour que cette migration — la
-- première définition in-repo de la fonction — soit auto-suffisante sur un
-- replay from-scratch (SECURITY.md:36).
REVOKE ALL ON FUNCTION public.cooked_refresh_after_gsc() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_refresh_after_gsc() TO service_role;
