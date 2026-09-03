-- T-11 (mission 02/09/2026, #112) — refresh aval robuste à la dérive du cron GitHub
-- + durée par étape. Constats e-02 (P1) et h-05 (P2). Invariant I9.
--
-- Mesure avant (03/09/2026 17:20 Paris) :
--   · gsc-daily-ingest est planifié 06:00 UTC ; départs réels : 27/08 17:15, 28/08 18:07,
--     29/08 12:11, 30/08 11:07, 31/08 12:31, 01/09 11:54, 03/09 10:35 (+4 à +12 h, côté
--     ordonnanceur GitHub). L'aval (`0 8-20 * * *` UTC) était gardé par « ingestion du
--     jour Paris » : le 28/08 la séquence est partie à 19:00 UTC, un tick avant la
--     fermeture de la fenêtre. Passé 20:00 UTC, le jour de cpi_daily était perdu.
--   · durée de la séquence (cron.job_run_details, 30 j) : p50 ≈ 1 600 s, max 2 166 s
--     (05/08) pour un budget de 2 400 s ; le 26/07, 7 runs consécutifs à 2 400 s (timeout).
--     Aucune durée par étape : pg_cron ne conserve que « 1 row ».
--
-- Changement :
--   1. table `refresh_runs` (une ligne par étape + une ligne `_total` par run) ;
--   2. garde « ingestion plus récente que le dernier refresh complet » (marqueur
--      `last_full_refresh_after_gsc_at`), isolée dans `cooked_refresh_after_gsc_pending()` ;
--   3. fenêtre cron `0 6-21 * * *` UTC — 21:00 UTC = 23:00 Paris l'été : dernier tick qui
--      reste dans le jour Paris (cpi_daily.day = paris_today()). 22 ou 23 UTC daterait le
--      snapshot au lendemain ;
--   4. alertes : `gsc_ingest_missed` = « en retard » dès 12:00 UTC ; `refresh_after_gsc_stale`
--      (critical) si une ingestion de plus de 3 h n'est pas suivie d'un refresh complet ;
--      `refresh_budget` (warn) si un run dépasse 80 % du budget déclaré ;
--   5. deux contract-tests I9 dans run_rpc_contract_tests.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Journal des runs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.refresh_runs (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id            uuid        NOT NULL,
  orchestrator      text        NOT NULL DEFAULT 'cooked_refresh_after_gsc',
  step_no           integer     NOT NULL,   -- 0 = ligne « _total »
  step              text        NOT NULL,   -- fonction appelée, ou « _total »
  started_at        timestamptz NOT NULL,
  finished_at       timestamptz NOT NULL,
  duration_ms       integer     NOT NULL,
  ok                boolean     NOT NULL,
  sqlstate          text,
  error             text,
  trigger_ingest_at timestamptz             -- max(ingested_at) GSC qui a déclenché la séquence
);
CREATE INDEX IF NOT EXISTS refresh_runs_started_at_idx ON public.refresh_runs (started_at DESC);
ALTER TABLE public.refresh_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.refresh_runs FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.refresh_runs TO service_role;
COMMENT ON TABLE public.refresh_runs IS
  'T-11 (03/09/2026) — durée par étape de cooked_refresh_after_gsc + ligne _total par run. '
  'Lire : SELECT * FROM refresh_runs ORDER BY started_at DESC. Rétention 400 j.';

-- Budget déclaré = le SET statement_timeout de la commande cron (à changer ensemble).
INSERT INTO public.cooked_config (key, value, updated_at)
VALUES ('refresh_after_gsc_budget_s', '2400', now())
ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. La garde, testable seule (lue aussi par l'alerte refresh_after_gsc_stale)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cooked_refresh_after_gsc_pending()
RETURNS TABLE(pending boolean, reason text, last_ingest timestamptz, last_complete timestamptz)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN
  SELECT max(g.ingested_at) INTO last_ingest FROM public.gsc_path_daily g;

  SELECT c.value::timestamptz INTO last_complete
  FROM public.cooked_config c
  WHERE c.key = 'last_full_refresh_after_gsc_at';

  IF last_ingest IS NULL THEN
    pending := false;
    reason  := 'aucune ingestion GSC en base';
  ELSIF last_complete IS NOT NULL AND last_complete >= last_ingest THEN
    pending := false;
    reason  := format('séquence complète le %s après l''ingestion du %s',
                      to_char(last_complete AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'),
                      to_char(last_ingest   AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'));
  ELSE
    pending := true;
    reason  := format('ingestion GSC du %s non suivie d''un refresh complet (dernier complet : %s)',
                      to_char(last_ingest AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'),
                      coalesce(to_char(last_complete AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'), 'jamais'));
  END IF;
  RETURN NEXT;
END;
$function$;
REVOKE ALL ON FUNCTION public.cooked_refresh_after_gsc_pending() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_refresh_after_gsc_pending() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. L'orchestrateur : garde par marqueur, journal par étape
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cooked_refresh_after_gsc()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_pending  record;
  v_run_id   uuid        := gen_random_uuid();
  v_run_t0   timestamptz := clock_timestamp();
  v_t0       timestamptz;
  v_t1       timestamptz;
  v_steps constant text[] := ARRAY[
    'cooked_cpi_snapshot',
    'refresh_dashboard_snapshots',
    'refresh_dashboard_expertises_snapshots',
    'refresh_dashboard_resources_assisted',
    'refresh_dashboard_assisted_quarter'
  ];
  v_step     text;
  v_i        integer;
  v_failures text[] := array[]::text[];
  v_detail   text;
  v_err      text;
  v_state    text;
BEGIN
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RETURN 'skip: un refresh est déjà en cours';
  END IF;

  -- T-11 : plus de garde « ingestion du jour ». On repart dès qu'une ingestion GSC est
  -- plus récente que le dernier refresh complet, quelle que soit l'heure d'arrivée.
  SELECT * INTO v_pending FROM public.cooked_refresh_after_gsc_pending();
  IF NOT v_pending.pending THEN
    RETURN 'skip: ' || v_pending.reason;
  END IF;

  FOR v_i IN 1..cardinality(v_steps) LOOP
    v_step := v_steps[v_i];
    v_t0   := clock_timestamp();
    BEGIN
      EXECUTE format('SELECT public.%I()', v_step);
      v_t1 := clock_timestamp();
      INSERT INTO public.refresh_runs
        (run_id, step_no, step, started_at, finished_at, duration_ms, ok, trigger_ingest_at)
      VALUES
        (v_run_id, v_i, v_step, v_t0, v_t1,
         (extract(epoch FROM (v_t1 - v_t0)) * 1000)::int, true, v_pending.last_ingest);
    EXCEPTION WHEN OTHERS OR query_canceled THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
      v_t1     := clock_timestamp();
      v_detail := format('%s [%s]: %s', v_step, v_state, v_err);
      IF v_state = '57014' AND v_i < cardinality(v_steps) THEN
        v_detail := v_detail || format(' — étapes non lancées (budget timeout épuisé) : %s',
                                       array_to_string(v_steps[v_i + 1:], ', '));
      END IF;
      v_failures := v_failures || v_detail;

      BEGIN
        INSERT INTO public.refresh_runs
          (run_id, step_no, step, started_at, finished_at, duration_ms, ok, sqlstate, error, trigger_ingest_at)
        VALUES
          (v_run_id, v_i, v_step, v_t0, v_t1,
           (extract(epoch FROM (v_t1 - v_t0)) * 1000)::int, false, v_state, left(v_err, 500),
           v_pending.last_ingest);
      EXCEPTION WHEN OTHERS OR query_canceled THEN
        NULL;
      END;

      BEGIN
        PERFORM public.raise_cooked_alert(
          'refresh_step_failed_' || v_step, 'critical',
          format('Refresh après GSC — %s. Les étapes réussies sont conservées ; retry complet au prochain tick horaire (cron cooked-refresh-after-gsc, 6h-21h UTC). Durées : SELECT * FROM refresh_runs ORDER BY started_at DESC.',
                 v_detail));
      EXCEPTION WHEN OTHERS OR query_canceled THEN
        NULL;
      END;

      IF v_state = '57014' THEN
        EXIT;
      END IF;
    END;
  END LOOP;

  v_t1 := clock_timestamp();
  BEGIN
    INSERT INTO public.refresh_runs
      (run_id, step_no, step, started_at, finished_at, duration_ms, ok, error, trigger_ingest_at)
    VALUES
      (v_run_id, 0, '_total', v_run_t0, v_t1,
       (extract(epoch FROM (v_t1 - v_run_t0)) * 1000)::int,
       cardinality(v_failures) = 0,
       nullif(array_to_string(v_failures, ' | '), ''),
       v_pending.last_ingest);
    DELETE FROM public.refresh_runs WHERE started_at < now() - interval '400 days';
  EXCEPTION WHEN OTHERS OR query_canceled THEN
    NULL;
  END;

  IF cardinality(v_failures) = 0 THEN
    BEGIN
      -- now() = début de la transaction, volontairement : une ingestion arrivée PENDANT
      -- la séquence reste « plus récente que le dernier refresh complet » → rejouée.
      INSERT INTO public.cooked_config (key, value, updated_at)
      VALUES ('last_full_refresh_after_gsc_at', now()::text, now())
      ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
    EXCEPTION WHEN OTHERS OR query_canceled THEN
      NULL;
    END;

    RETURN format('ok: séquence complète en %s s après ingestion du %s',
                  round(extract(epoch FROM (v_t1 - v_run_t0))),
                  to_char(v_pending.last_ingest AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'));
  END IF;

  RETURN format('partiel: %s', array_to_string(v_failures, ' | '));
END;
$function$;
REVOKE ALL ON FUNCTION public.cooked_refresh_after_gsc() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_refresh_after_gsc() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Fenêtre cron 6h-21h UTC (même commande, même budget)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT cron.unschedule('cooked-refresh-after-gsc');
SELECT cron.schedule(
  'cooked-refresh-after-gsc',
  '0 6-21 * * *',
  $cmd$SET statement_timeout='2400s'; SELECT public.cooked_refresh_after_gsc();$cmd$
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Alertes
-- ─────────────────────────────────────────────────────────────────────────────
-- 5a. gsc_ingest_missed : « en retard » dès 12:00 UTC (l'ingestion est attendue à 06:00 UTC).
CREATE OR REPLACE FUNCTION public.alert_rule_gsc_ingest_missed()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last_ingest timestamptz;
BEGIN
  -- Le cron GitHub est planifié 06:00 UTC et dérive de +4 à +12 h (constat e-02) :
  -- on ne juge qu'à partir de 12:00 UTC, heure du cron (UTC), pas heure Paris.
  IF (now() AT TIME ZONE 'UTC')::time < time '12:00' THEN
    RETURN;
  END IF;
  SELECT max(g.ingested_at) INTO v_last_ingest FROM public.gsc_path_daily g;
  IF public.paris_date(v_last_ingest) IS DISTINCT FROM public.paris_today() THEN
    kind := 'gsc_ingest_missed'; severity := 'warn';
    detail := format(
      'Ingestion GSC en retard : attendue à 06:00 UTC, toujours absente à %s UTC (dernière : %s). '
      'Si rien à 18:00 UTC : gh workflow run gsc-daily-ingest.yml. '
      'L''aval (cooked-refresh-after-gsc) repartira seul à l''heure suivante, jusqu''à 21:00 UTC.',
      to_char(now() AT TIME ZONE 'UTC', 'HH24:MI'),
      coalesce(to_char(v_last_ingest AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI'), 'jamais'));
    RETURN NEXT;
  END IF;
END;
$function$;

-- 5b. refresh_after_gsc_stale : une ingestion de plus de 3 h sans refresh complet derrière.
CREATE OR REPLACE FUNCTION public.alert_rule_refresh_after_gsc_stale()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_pending record;
  v_hour    integer := extract(hour FROM (now() AT TIME ZONE 'UTC'))::int;
BEGIN
  -- Jugé dans la fenêtre du cron aval (6h-21h UTC), après au moins deux ticks.
  IF v_hour < 8 OR v_hour > 23 THEN
    RETURN;
  END IF;
  SELECT * INTO v_pending FROM public.cooked_refresh_after_gsc_pending();
  IF v_pending.pending AND v_pending.last_ingest < now() - interval '3 hours'
     AND NOT EXISTS (
       SELECT 1 FROM public.alerts a
       WHERE a.kind LIKE 'refresh_step_failed_%'
         AND a.created_at > now() - interval '6 hours')
  THEN
    kind := 'refresh_after_gsc_stale'; severity := 'critical';
    detail := format(
      '%s — le cron cooked-refresh-after-gsc (0 6-21 * * * UTC) n''a pas suivi. '
      'Vérifier cron.job (actif ?) et refresh_runs ; relancer : SELECT public.cooked_refresh_after_gsc();',
      v_pending.reason);
    RETURN NEXT;
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.alert_rule_refresh_after_gsc_stale() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_refresh_after_gsc_stale() TO service_role;

-- 5c. refresh_budget : le dernier run (48 h) a consommé ≥ 80 % du budget déclaré.
CREATE OR REPLACE FUNCTION public.alert_rule_refresh_budget()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_budget_s integer;
  v_run      record;
  v_steps    text;
BEGIN
  SELECT nullif(btrim(c.value), '')::int INTO v_budget_s
  FROM public.cooked_config c WHERE c.key = 'refresh_after_gsc_budget_s';
  IF v_budget_s IS NULL THEN
    RETURN;
  END IF;

  SELECT r.run_id, r.started_at, r.duration_ms, r.ok INTO v_run
  FROM public.refresh_runs r
  WHERE r.step = '_total' AND r.started_at > now() - interval '48 hours'
  ORDER BY r.started_at DESC
  LIMIT 1;

  IF v_run.run_id IS NULL OR v_run.duration_ms < v_budget_s * 1000 * 0.8 THEN
    RETURN;
  END IF;

  SELECT string_agg(format('%s %s s%s', s.step, round(s.duration_ms / 1000.0),
                           CASE WHEN s.ok THEN '' ELSE ' ✗' END),
                    ', ' ORDER BY s.step_no)
    INTO v_steps
  FROM public.refresh_runs s
  WHERE s.run_id = v_run.run_id AND s.step_no > 0;

  kind := 'refresh_budget'; severity := 'warn';
  detail := format(
    'Refresh après GSC du %s : %s s = %s %% du budget de %s s (%s). '
    'Au-delà de 100 %% les étapes restantes sautent (retex 26/07). Étapes : %s.',
    to_char(v_run.started_at AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI'),
    round(v_run.duration_ms / 1000.0),
    round(100.0 * v_run.duration_ms / (v_budget_s * 1000)),
    v_budget_s,
    CASE WHEN v_run.ok THEN 'complet' ELSE 'partiel' END,
    coalesce(v_steps, '—'));
  RETURN NEXT;
END;
$function$;
REVOKE ALL ON FUNCTION public.alert_rule_refresh_budget() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_refresh_budget() TO service_role;

-- 5d. Les deux repair_hint du registre qui citaient des jobs fantômes (h-05 / T-14).
UPDATE public.freshness_contract
SET repair_hint = 'Étape 1 de cooked_refresh_after_gsc (cron cooked-refresh-after-gsc, 0 6-21 * * * UTC, ~25 min). Lire refresh_runs et cooked_refresh_after_gsc_pending() ; relancer : SELECT public.cooked_refresh_after_gsc();'
WHERE source = 'cpi_daily';
UPDATE public.freshness_contract
SET repair_hint = 'Étapes 2-5 de cooked_refresh_after_gsc (cron cooked-refresh-after-gsc, 0 6-21 * * * UTC). Lire refresh_runs et cooked_refresh_after_gsc_pending() ; relancer : SELECT public.cooked_refresh_after_gsc();'
WHERE source = 'dashboard_resources_snapshot';

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Contract-tests I9 (run_rpc_contract_tests redéfinie : corps prod + 2 entrées)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.run_rpc_contract_tests()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '900s'
AS $function$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('snapshot_pages_export',
       $q$select count(*) from public.snapshot_pages_export() where refreshed_at is not null$q$,
       1, NULL),
      ('site_context_export',
       $q$select count(*) from public.site_context_export() where global_sessions_28d > 0$q$,
       NULL, 1),
      ('cta_breakdown_for_path',
       $q$select count(*) from public.cta_breakdown_for_path('/', 28)
          where cta_type in ('phone', 'email', 'booking')
            and placement in ('header', 'footer', 'body', 'sticky')$q$,
       NULL, NULL),
      ('outbound_destinations_for_path',
       $q$select count(*) from public.outbound_destinations_for_path('/', 28)$q$,
       NULL, NULL),
      ('behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())$q$,
       NULL, NULL),
      ('engagement_density_for_path',
       $q$select count(*) from public.engagement_density_for_path('/', 28)$q$,
       NULL, NULL),
      ('tracker_first_seen_global',
       $q$select count(*) from (select public.tracker_first_seen_global() v) s where s.v is not null$q$,
       NULL, 1),
      ('refresh_pipeline_health',
       $q$select count(*) from public.refresh_pipeline_health()$q$,
       NULL, 1),
      ('page_reads',
       $q$select count(*) from public.page_reads(7) where source = 'page_exit'$q$,
       1, NULL),
      ('units_behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),
      ('units_seo_pages_overview',
       $q$select count(*) from public.seo_pages_overview(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),
      ('units_cooked_bounce_rate_range',
       $q$select count(*) from (
            select cooked_bounce_rate from public.gsc_page_performance('/', 'rolling_28')
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u where cooked_bounce_rate > 100 or cooked_bounce_rate < 0$q$,
       NULL, 0),
      ('units_cooked_bounce_rate_unit',
       $q$select case when count(*) >= 20 and max(cooked_bounce_rate) <= 1 then 1 else 0 end from (
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u$q$,
       NULL, 0),
      ('spam_share_events_human',
       $q$select case when count(*) filter (where name = 'pageview') >= 100
                    and 100.0 * count(*) filter (where name = 'pageview'
                          and (lower(user_agent) = 'pc' or user_agent ilike '%sebot%'
                               or public.cooked_is_spam_referrer(referrer_hostname)))
                        / count(*) filter (where name = 'pageview') >= 1
                  then 1 else 0 end
          from public.events_human where occurred_at > now() - interval '7 days'$q$,
       NULL, 0),
      ('classify_channel_spam',
       $q$select count(*) from (values ('m.baidu.com'), ('baidu.com')) v(h)
          where public.classify_channel(v.h, null, null, 'www.jplouton-avocat.fr') <> 'spam'$q$,
       NULL, 0),
      ('gsc_pages_overview_28d_alignes',
       $q$select abs(coalesce((select sum(gsc_clicks_28d) from public.gsc_pages_overview(100000)), 0)
                 - coalesce((select sum(g.clicks) from public.gsc_path_daily g,
                               public.cooked_period_bounds('rolling_28', 'gsc') b
                             where g.day between b.n_start and b.n_end), 0))$q$,
       NULL, 0),
      ('cpi_sans_horloge',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'now\(\)|current_date|current_timestamp|localtimestamp', 'gi')$q$,
       NULL, 0),
      ('contacts_28j_une_fenetre',
       $q$with b as (select n_start, n_end from public.cooked_period_bounds('rolling_28', 'live_j1')),
               s as (select sm.macro_conversions as n from b, public.site_macro_counts(b.n_start, b.n_end) sm),
               m as (select coalesce(sum(contacts), 0) as n from public.macro_contacts_by_path(28)),
               j as (select count(*) as n from public.conversion_journeys(28))
          select abs((select n from s) - (select n from m)) + abs((select n from s) - (select n from j))$q$,
       NULL, 0),
      ('funnel_meme_total_que_journeys',
       $q$with b as (select n_end from public.cooked_period_bounds('rolling_28', 'cross'))
          select abs(coalesce((select sum(contacts) from public.seo_to_contact_funnel(28)), 0)
                   - (select count(*) from b, public.conversion_journeys(28, b.n_end) j
                      where j.entry_channel like 'organic%' and j.entry_path is not null))$q$,
       NULL, 0),
      ('classify_channel_gclid_paid',
       $q$select count(*) from (values
            ('www.google.com', 'gmb', null, 'https://www.jplouton-avocat.fr/?utm_source=gmb&gclid=abc'),
            ('www.google.com', null, null, 'https://www.jplouton-avocat.fr/defense-penale?gbraid=xyz'),
            (null, null, null, 'https://www.jplouton-avocat.fr/?wbraid=k')) v(r, s, m, u)
          where public.classify_channel(v.r, v.s, v.m, 'www.jplouton-avocat.fr', v.u) is distinct from 'paid'$q$,
       NULL, 0),
      ('cpi_momentum_source_complete',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'momf AS \(SELECT path,.*?FROM public\.gsc_path_daily', 'g')$q$,
       1, NULL),
      ('potentiel_sans_momentum_gate',
       $q$select count(*) from public.cpi_opportunite_contact o
          where o.potentiel is distinct from round(public.cpi_compose(o.zc, o.zr, o.zl, 0, 1, 1, true))::int$q$,
       NULL, 0),
      ('assistes_plus_non_attribuables_eq_site',
       $q$with b as (select n_start, n_end from public.cooked_period_bounds('rolling_28', 'live_j1')),
               s as (select sm.macro_conversions as n from b, public.site_macro_counts(b.n_start, b.n_end) sm),
               a as (select coalesce(sum(contacts), 0) as n
                     from public.assisted_contacts_by_entry_path((select n_start from b), (select n_end from b)))
          select abs((select n from s) - (select n from a))$q$,
       NULL, 0),
      ('dashboard_annotations',
       $q$select count(*) from public.dashboard_annotations('rolling_28')$q$,
       NULL, NULL),
      ('dashboard_article_detail',
       $q$select count(*) from (select public.dashboard_article_detail('/post/abandon-de-poste-quels-risques', 'rolling_28') v) s where s.v ? 'path'$q$,
       NULL, 1),
      ('dashboard_assisted_quarter',
       $q$select count(*) from (select public.dashboard_assisted_quarter() v) s where (s.v->>'value') is not null$q$,
       NULL, 1),
      ('dashboard_expertises_kpis',
       $q$select count(*) from public.dashboard_expertises_kpis('rolling_28')$q$,
       NULL, NULL),
      ('dashboard_expertises_overview',
       $q$select count(*) from public.dashboard_expertises_overview('rolling_28', 20)$q$,
       NULL, NULL),
      ('dashboard_expertises_trend',
       $q$select count(*) from public.dashboard_expertises_trend('rolling_28')$q$,
       NULL, NULL),
      ('dashboard_honoraires_funnel',
       $q$select count(*) from public.dashboard_honoraires_funnel('rolling_28')$q$,
       NULL, NULL),
      ('dashboard_intervention_effect',
       $q$select count(*) from (select public.dashboard_intervention_effect('/', date '2026-09-01') v) s$q$,
       NULL, NULL),
      ('dashboard_resources_assisted',
       $q$select count(*) from public.dashboard_resources_assisted('rolling_28')$q$,
       NULL, NULL),
      ('dashboard_resources_cohorts',
       $q$select count(*) from (select public.dashboard_resources_cohorts() v) s where s.v is not null$q$,
       NULL, 1),
      ('dashboard_resources_kpis',
       $q$select count(*) from public.dashboard_resources_kpis('rolling_28')$q$,
       NULL, NULL),
      ('dashboard_resources_overview',
       $q$select count(*) from public.dashboard_resources_overview('rolling_28', 20)$q$,
       NULL, NULL),
      ('dashboard_resources_trend',
       $q$select count(*) from public.dashboard_resources_trend('rolling_28')$q$,
       NULL, NULL),
      ('dashboard_seo_by_query',
       $q$select count(*) from public.dashboard_seo_by_query('rolling_28', 'ressource', 0, 20)$q$,
       NULL, NULL),
      ('dashboard_seo_kpis',
       $q$select count(*) from public.dashboard_seo_kpis('rolling_28', 'ressource')$q$,
       NULL, NULL)
      ,
      -- I9 (T-11, 03/09/2026) : chaque ingestion GSC est suivie d'un refresh complet journalisé.
      ('refresh_runs_after_ingest',
       $q$select count(*) from public.refresh_runs
          where step = '_total' and ok and started_at > now() - interval '36 hours'$q$,
       1, NULL),
      ('refresh_after_gsc_not_pending',
       $q$select count(*) from public.cooked_refresh_after_gsc_pending() p
          where p.pending and p.last_ingest < now() - interval '6 hours'$q$,
       NULL, 0)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;
