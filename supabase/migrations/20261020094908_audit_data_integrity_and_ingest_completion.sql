-- Audit du 20/10/2026 : corrections de mesure et fermeture des lots GSC.
-- Autorisation Nicolas : « Prends le contrôle et corrige tout ! ».
-- Aucun backfill brut ni réécriture d'historique CPI. Les snapshots dérivés seront
-- recalculés après une ingestion GSC complète avec le nouveau protocole.
BEGIN;


-- F13 : dernier lot explicitement terminé, jamais la seule table pages.
-- Le verrou 782026 est partagé avec cooked_refresh_after_gsc. Begin ne peut
-- autoriser des écritures pendant un refresh ; un refresh voit running et saute.
CREATE TABLE public.gsc_ingest_batches (
  batch_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id uuid NOT NULL UNIQUE,
  day_start date NOT NULL,
  day_end date NOT NULL,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  status text NOT NULL DEFAULT 'running' CHECK (status IN ('running','completed','failed')),
  row_counts jsonb,
  CHECK (day_start <= day_end),
  CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);
ALTER TABLE public.gsc_ingest_batches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.gsc_ingest_batches FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.gsc_ingest_batches TO service_role;
REVOKE ALL ON SEQUENCE public.gsc_ingest_batches_batch_no_seq FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.gsc_ingest_batches IS
  'Lots GSC : begin avant toute écriture, complete après les trois tables ; un lot incomplet bloque le refresh. Métadonnées sans contenu de requête ni PII.';

CREATE OR REPLACE FUNCTION public.gsc_ingest_begin(p_run_id uuid, p_start date, p_end date)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_existing public.gsc_ingest_batches%ROWTYPE;
BEGIN
  IF p_run_id IS NULL OR p_start IS NULL OR p_end IS NULL OR p_start > p_end THEN
    RAISE EXCEPTION 'invalid GSC batch id or date range' USING ERRCODE = '22023';
  END IF;
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RAISE EXCEPTION 'GSC refresh is running; retry the full ingestion later' USING ERRCODE = '55P03';
  END IF;
  SELECT * INTO v_existing FROM public.gsc_ingest_batches WHERE run_id=p_run_id;
  IF FOUND THEN
    IF v_existing.status='running' AND v_existing.day_start=p_start AND v_existing.day_end=p_end
       AND v_existing.batch_no=(SELECT max(batch_no) FROM public.gsc_ingest_batches) THEN
      RETURN p_run_id; -- retry après réponse réseau perdue : idempotent
    END IF;
    RAISE EXCEPTION 'GSC batch id already used; start a new full batch' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.gsc_ingest_batches WHERE status='running') THEN
    RAISE EXCEPTION 'another GSC ingestion is running; stop it before marking its batch failed' USING ERRCODE='55P03';
  END IF;
  INSERT INTO public.gsc_ingest_batches(run_id,day_start,day_end) VALUES(p_run_id,p_start,p_end);
  RETURN p_run_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.gsc_ingest_begin(uuid,date,date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gsc_ingest_begin(uuid,date,date) TO service_role;


CREATE OR REPLACE FUNCTION public.gsc_ingest_fail(p_run_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','pg_catalog'
AS $function$
DECLARE v_batch public.gsc_ingest_batches%ROWTYPE;
BEGIN
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RAISE EXCEPTION 'GSC refresh is running; retry failure marker later' USING ERRCODE='55P03';
  END IF;
  SELECT * INTO v_batch FROM public.gsc_ingest_batches WHERE run_id=p_run_id;
  IF NOT FOUND OR v_batch.status='completed' THEN
    RAISE EXCEPTION 'only a running or already failed GSC batch may fail' USING ERRCODE='22023';
  END IF;
  UPDATE public.gsc_ingest_batches SET status='failed' WHERE run_id=p_run_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.gsc_ingest_fail(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gsc_ingest_fail(uuid) TO service_role;


CREATE OR REPLACE FUNCTION public.form_submission_counts_for_period(p_start date,p_end date)
RETURNS TABLE(day date,submissions bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','pg_catalog'
AS $function$
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_start>p_end OR p_end-p_start>=93 THEN
    RAISE EXCEPTION 'form count window must contain 1 to 93 inclusive calendar days' USING ERRCODE='22023';
  END IF;
  RETURN QUERY
    SELECT ds.d::date,coalesce(c.n,0)::bigint
    FROM generate_series(p_start::timestamp,p_end::timestamp,interval '1 day') ds(d)
    LEFT JOIN (
      SELECT public.paris_date(e.occurred_at) AS d,count(*) AS n
      FROM public.events_human e WHERE e.name='form_submit'
        AND e.occurred_at>=public.cooked_paris_ts_start(p_start)
        AND e.occurred_at<public.cooked_paris_ts_end_exclusive(p_end)
      GROUP BY public.paris_date(e.occurred_at)
    ) c ON c.d=ds.d::date
    ORDER BY ds.d;
END;
$function$;

REVOKE ALL ON FUNCTION public.form_submission_counts_for_period(date,date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.form_submission_counts_for_period(date,date) TO service_role;


CREATE OR REPLACE FUNCTION public.gsc_ingest_complete(p_run_id uuid, p_row_counts jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_latest public.gsc_ingest_batches%ROWTYPE; v_key text; v_total numeric := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RAISE EXCEPTION 'GSC refresh is running; retry batch completion later' USING ERRCODE = '55P03';
  END IF;
  IF p_row_counts IS NULL OR jsonb_typeof(p_row_counts) <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_row_counts)) <> 3 THEN
    RAISE EXCEPTION 'row counts must contain exactly the three GSC tables' USING ERRCODE = '22023';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['gsc_path_daily','gsc_query_daily','gsc_query_page_daily'] LOOP
    IF NOT (p_row_counts ? v_key) OR jsonb_typeof(p_row_counts->v_key) <> 'number'
       OR (p_row_counts->>v_key) !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'invalid row count for %', v_key USING ERRCODE = '22023';
    END IF;
    v_total := v_total + (p_row_counts->>v_key)::numeric;
  END LOOP;
  IF v_total=0 THEN
    RAISE EXCEPTION 'cannot mark an entirely empty GSC batch complete' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_latest FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF NOT FOUND OR v_latest.run_id IS DISTINCT FROM p_run_id OR v_latest.status NOT IN ('running','completed') THEN
    RAISE EXCEPTION 'only the latest running GSC batch may complete' USING ERRCODE = '22023';
  END IF;
  IF v_latest.status='completed' THEN
    IF v_latest.row_counts=p_row_counts THEN RETURN; END IF;
    RAISE EXCEPTION 'completed GSC batch has different row counts' USING ERRCODE = '22023';
  END IF;
  UPDATE public.gsc_ingest_batches SET status='completed', completed_at=clock_timestamp(), row_counts=p_row_counts
    WHERE run_id=p_run_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.gsc_ingest_complete(uuid,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gsc_ingest_complete(uuid,jsonb) TO service_role;


CREATE OR REPLACE FUNCTION public.cooked_refresh_after_gsc_pending()
RETURNS TABLE(pending boolean, reason text, last_ingest timestamptz, last_complete timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_latest public.gsc_ingest_batches%ROWTYPE; v_refreshed_id uuid;
BEGIN
  SELECT * INTO v_latest FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  SELECT c.value::timestamptz INTO last_complete FROM public.cooked_config c
    WHERE c.key='last_full_refresh_after_gsc_at';
  SELECT c.value::uuid INTO v_refreshed_id FROM public.cooked_config c
    WHERE c.key='last_full_refresh_gsc_batch_id';
  last_ingest := v_latest.completed_at;
  IF v_latest.run_id IS NULL THEN
    pending:=false; reason:='aucun lot GSC complet : lancer une ingestion complète des trois tables';
  ELSIF v_latest.status <> 'completed' THEN
    pending:=false;
    reason:=format('lot GSC %s incomplet depuis le %s ; refresh bloqué jusqu''à reprise complète',
                   v_latest.run_id,to_char(v_latest.started_at AT TIME ZONE 'Europe/Paris','DD/MM HH24:MI'));
  ELSIF v_refreshed_id=v_latest.run_id THEN
    pending:=false;
    reason:=format('lot GSC %s suivi d''un refresh complet le %s',v_latest.run_id,
                   to_char(last_complete AT TIME ZONE 'Europe/Paris','DD/MM HH24:MI'));
  ELSE
    pending:=true;
    reason:=format('lot GSC complet du %s non suivi d''un refresh complet',
                   to_char(v_latest.completed_at AT TIME ZONE 'Europe/Paris','DD/MM HH24:MI'));
  END IF;
  RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.cooked_refresh_after_gsc_pending() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_refresh_after_gsc_pending() TO service_role;


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
      -- Begin prend le même verrou : aucune ingestion conforme ne peut écrire
      -- pendant ce refresh. Le lot exact consommé est mémorisé, pas une horloge.
      INSERT INTO public.cooked_config (key, value, updated_at)
      VALUES ('last_full_refresh_after_gsc_at', clock_timestamp()::text, now()),
             ('last_full_refresh_gsc_batch_id',
               (SELECT run_id::text FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1), now())
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


CREATE OR REPLACE FUNCTION public.alert_rule_refresh_after_gsc_stale()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_pending record;
  v_batch public.gsc_ingest_batches%ROWTYPE;
  v_hour    integer := extract(hour FROM (now() AT TIME ZONE 'UTC'))::int;
BEGIN
  SELECT * INTO v_batch FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF v_batch.status IN ('running','failed') AND v_batch.started_at < now() - interval '3 hours' THEN
    kind:='refresh_after_gsc_stale'; severity:='critical';
    detail:=format('Lot GSC %s incomplet depuis le %s : refresh volontairement bloqué. Vérifier le workflow puis relancer une ingestion complète des trois tables ; ne pas forcer le marqueur.',
      v_batch.run_id,to_char(v_batch.started_at AT TIME ZONE 'Europe/Paris','DD/MM HH24:MI'));
    RETURN NEXT;
    RETURN;
  END IF;
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


-- F14 : une observation par document×métrique. Les anciens trackers sans
-- measurement_id restent une observation par événement ; pas de dédup inventée.
CREATE OR REPLACE FUNCTION public.cooked_web_vitals_window(p_from timestamptz,p_to timestamptz)
RETURNS TABLE(id uuid,path text,device_type text,props jsonb,occurred_at timestamptz)
LANGUAGE sql STABLE SET search_path TO 'public','pg_catalog'
AS $function$
  SELECT DISTINCT ON (
    CASE WHEN nullif(e.props->>'measurement_id','') IS NOT NULL
      THEN 'document:' || (e.props->>'measurement_id') ELSE 'event:' || e.id::text END,
    e.props->>'metric')
    e.id,e.path,e.device_type,e.props,e.occurred_at
  FROM public.events_human e
  WHERE e.name='web_vitals' AND e.occurred_at>=p_from AND e.occurred_at<p_to
  ORDER BY
    CASE WHEN nullif(e.props->>'measurement_id','') IS NOT NULL
      THEN 'document:' || (e.props->>'measurement_id') ELSE 'event:' || e.id::text END,
    e.props->>'metric',
    CASE WHEN e.props->>'revision' ~ '^[0-9]{1,9}$' THEN (e.props->>'revision')::int ELSE 0 END DESC,
    e.occurred_at DESC,e.id DESC;
$function$;

REVOKE ALL ON FUNCTION public.cooked_web_vitals_window(timestamptz,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_web_vitals_window(timestamptz,timestamptz) TO service_role;


CREATE OR REPLACE FUNCTION public.cooked_page_index(p_days integer DEFAULT 28)
 RETURNS TABLE(path text, ptype text, grade text, cpi integer, cpi_raw integer, momentum numeric, momentum_badge text, gate numeric, zc numeric, zr numeric, zl numeric, zv numeric, clics_perdus integer, n_org bigint, couv_gsc_pct integer, convertit boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- T-05 (mission 02/09/2026, #106 — d-03/d-07/f-04) : UNE fenêtre pour tout le score. Côté GSC : p_days jours clos à
-- gsc_last_data_day() (avant : borne sur la date serveur, soit 24 jours de données réelles sur 28 nominaux, lag Google J-4).
-- Côté Cooked : les MÊMES jours Paris, bornés par cooked_paris_ts_start/_end_exclusive (avant : 28 × 24 h glissantes, borne
-- qui glissait avec l'heure du run — deux snapshots consécutifs étaient séparés de 18 à 34 h). Le score d'un jour donné
-- est désormais reproductible. T-09 (#110) : le terme zv (conversion_journeys) est lui aussi clos à gsc_last_data_day() —
-- plus aucune borne d'horloge dans le score ; url passée à classify_channel (gclid ⇒ paid, o-14).
WITH w AS (
  SELECT g.g_end,
         public.cooked_paris_ts_start(g.g_end - (p_days - 1)) AS t0,
         public.cooked_paris_ts_end_exclusive(g.g_end)        AS t1
  FROM (SELECT public.gsc_last_data_day() AS g_end) g
),
fit AS (
  SELECT regr_slope(ln(ctr), ln(pos)) AS pente, regr_intercept(ln(ctr), ln(pos)) AS icept
  FROM (SELECT round(position)::int pos, (sum(clicks)+1.0)/(sum(impressions)+20.0) ctr
        FROM public.gsc_query_page_daily WHERE day > (SELECT g_end FROM w) - 90 AND NOT public.gsc_is_branded(query)
        GROUP BY 1 HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions) >= 200) b
),
capq AS (SELECT g.path, sum(g.impressions) i_qpd,
    sum(g.impressions * least(greatest(exp(f.icept + f.pente*ln(greatest(g.position,1.0))),0.0005),0.5)) e_qpd
  FROM public.gsc_query_page_daily g, fit f WHERE g.day > (SELECT g_end FROM w) - p_days AND NOT public.gsc_is_branded(g.query) GROUP BY g.path),
capb AS (SELECT path, sum(clicks) o_b, sum(impressions) i_b FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - p_days AND public.gsc_is_branded(query) GROUP BY path),
capp AS (SELECT path, sum(clicks) o_full, sum(impressions) i_full FROM public.gsc_path_daily WHERE day > (SELECT g_end FROM w) - p_days GROUP BY path),
cap AS (SELECT p.path, greatest(p.o_full - coalesce(b.o_b,0),0)::numeric AS o,
    CASE WHEN coalesce(q.i_qpd,0)>0 THEN q.e_qpd*(greatest(p.i_full-coalesce(b.i_b,0),0)::numeric/q.i_qpd) ELSE NULL END AS e,
    q.i_qpd, greatest(p.i_full-coalesce(b.i_b,0),0) AS i_nb
  FROM capp p LEFT JOIN capq q ON q.path=p.path LEFT JOIN capb b ON b.path=p.path),
firstpv AS (SELECT DISTINCT ON (session_id) session_id, eh.path,
    public.classify_channel(referrer_hostname, utm_source, utm_medium,'www.jplouton-avocat.fr', url) chan
  FROM public.events_human eh WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) ORDER BY session_id, occurred_at),
orge AS (SELECT session_id, firstpv.path FROM firstpv WHERE chan LIKE 'organic%'),
norg AS (SELECT orge.path, count(*) n_org FROM orge GROUP BY orge.path),
spv AS (SELECT session_id, count(*) pv FROM public.events_human WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) GROUP BY session_id),
pex AS (SELECT e.session_id, e.path,
    max((e.props->>'duration_seconds')::numeric) d,
    max(coalesce((e.props->>'max_scroll')::numeric,0)) s
  FROM public.events_human e
  WHERE e.name='page_exit' AND e.occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w)
  GROUP BY e.session_id, e.path),
ex2 AS (SELECT o.path, public.cooked_page_type(o.path) ptype, px.d,
    coalesce(px.s,0) s,
    (px.d >= 15 OR coalesce(s2.pv,1) >= 2) retained
  FROM orge o JOIN pex px ON px.session_id=o.session_id AND px.path=o.path
  LEFT JOIN spv s2 ON s2.session_id=o.session_id),
thr AS (SELECT ptype, percentile_cont(0.5) WITHIN GROUP (ORDER BY d) tau, percentile_cont(0.5) WITHIN GROUP (ORDER BY s) sig FROM ex2 WHERE retained GROUP BY ptype),
reads AS (SELECT e.path, max(e.ptype) ptype, count(*) n, count(*) FILTER (WHERE retained) r,
    count(*) FILTER (WHERE retained AND d >= t.tau AND s >= t.sig) k FROM ex2 e JOIN thr t ON t.ptype=e.ptype GROUP BY e.path),
tmeans AS (SELECT ptype, coalesce(sum(r)::numeric/nullif(sum(n),0),0.5) rho, coalesce(sum(k)::numeric/nullif(sum(r),0),0.25) q FROM reads GROUP BY ptype),
ebk AS (
  SELECT t.ptype, t.rho, t.q,
    CASE WHEN er.np>=5 AND er.v>0 AND er.v < t.rho*(1-t.rho) THEN least(greatest(t.rho*(1-t.rho)/er.v - 1, 5), 200) ELSE 20 END kappa_ret,
    CASE WHEN el.np>=5 AND el.v>0 AND el.v < t.q*(1-t.q) THEN least(greatest(t.q*(1-t.q)/el.v - 1, 5), 200) ELSE 20 END kappa_lec
  FROM tmeans t
  LEFT JOIN (SELECT ptype, var_samp(r::numeric/n) v, count(*) np FROM reads WHERE n>=10 GROUP BY ptype) er ON er.ptype=t.ptype
  LEFT JOIN (SELECT ptype, var_samp(k::numeric/nullif(r,0)) v, count(*) np FROM reads WHERE r>=10 GROUP BY ptype) el ON el.ptype=t.ptype
),
jx AS (SELECT * FROM public.conversion_journeys(p_days, (SELECT g_end FROM w)) WHERE entry_channel LIKE 'organic%'),
direct AS (SELECT entry_path path, count(*)::numeric v FROM jx WHERE entry_path IS NOT NULL GROUP BY 1),
assist AS (SELECT jp.path, sum(1.0/greatest(j.pages_count,1)) v FROM jx j CROSS JOIN LATERAL unnest(j.journey) jp(path) WHERE jp.path <> j.entry_path GROUP BY jp.path),
book AS (SELECT o.path, 0.25*count(*)::numeric v FROM orge o
  JOIN public.events_human b ON b.session_id=o.session_id AND b.path=o.path AND b.name='cta_booking_click'
  WHERE b.occurred_at >= (SELECT t0 FROM w) AND b.occurred_at < (SELECT t1 FROM w)
  GROUP BY o.path),
convv AS (SELECT n.path, n.n_org, coalesce(d.v,0)+coalesce(a.v,0)+coalesce(b.v,0) val,
    coalesce(d.v,0)+coalesce(a.v,0) macro_val
  FROM norg n LEFT JOIN direct d ON d.path=n.path LEFT JOIN assist a ON a.path=n.path LEFT JOIN book b ON b.path=n.path),
tconv AS (SELECT public.cooked_page_type(convv.path) ptype, coalesce(sum(val)/nullif(sum(convv.n_org),0),0) nu FROM convv GROUP BY 1),
xs AS (
  SELECT r.path, r.ptype, c.n_org, c.val, coalesce(cap.o,0) o, cap.e, coalesce(cap.i_qpd,0) i_qpd, coalesce(cap.i_nb,0) i_nb,
    coalesce(ln((coalesce(cap.o,0)+3)/(cap.e+3)),0) x_cap,
    ln( least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999) / (1-least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999)) ) x_ret,
    ln( least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999) / (1-least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999)) ) x_lec,
    ln( (c.val + 30*tc.nu + 0.05)/(c.n_org+30) ) x_conv
  FROM reads r JOIN convv c ON c.path=r.path LEFT JOIN cap ON cap.path=r.path
  JOIN ebk tm ON tm.ptype=r.ptype JOIN tconv tc ON tc.ptype=r.ptype
  WHERE c.n_org >= 5 AND r.n >= 3
),
medt AS (SELECT ptype, count(*) cnt, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs GROUP BY ptype),
madt AS (SELECT x.ptype,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-m.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-m.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-m.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-m.mv)),0.15) sv FROM xs x JOIN medt m ON m.ptype=x.ptype GROUP BY x.ptype),
medg AS (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs),
madg AS (SELECT greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-g.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-g.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-g.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-g.mv)),0.15) sv FROM xs x, medg g),
-- T-06 (mission 02/09/2026, f-01, option (b) — décision Nicolas 03/09/2026) : les clics du momentum viennent de la source
-- COMPLÈTE gsc_path_daily, moins les clics brandés que Google révèle dans gsc_query_page_daily (≈ total non brandé).
-- Avant (25/07/2026) : gsc_query_page_daily non brandé seul = 16 à 28 % des clics réels d'une page ; 15 des 47 pages
-- fiables avaient un momentum de direction inverse à leurs clics. Le terme position (p1/p0) reste sur les requêtes
-- révélées non brandées : la position n'a de sens que requête par requête.
momf AS (SELECT path,
    coalesce(sum(clicks) FILTER (WHERE day > (SELECT g_end FROM w) - p_days),0) c1,
    coalesce(sum(clicks) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days),0) c0
  FROM public.gsc_path_daily
  WHERE day > (SELECT g_end FROM w) - 2*p_days
  GROUP BY path),
momb AS (SELECT path,
    coalesce(sum(clicks) FILTER (WHERE day > (SELECT g_end FROM w) - p_days),0) b1,
    coalesce(sum(clicks) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days),0) b0
  FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - 2*p_days AND public.gsc_is_branded(query)
  GROUP BY path),
momp AS (SELECT path,
    avg(position) FILTER (WHERE day > (SELECT g_end FROM w) - p_days) p1,
    avg(position) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days) p0
  FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - 2*p_days AND NOT public.gsc_is_branded(query)
  GROUP BY path),
mom AS (SELECT f.path,
    greatest(f.c1 - coalesce(b.b1,0), 0) c1,
    greatest(f.c0 - coalesce(b.b0,0), 0) c0,
    p.p1, p.p0
  FROM momf f LEFT JOIN momb b ON b.path = f.path LEFT JOIN momp p ON p.path = f.path),
site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom),
lcp AS (SELECT eh.path, percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric) lcp75
  FROM public.cooked_web_vitals_window((SELECT t0 FROM w),(SELECT t1 FROM w)) eh
  WHERE props->>'metric'='LCP' AND device_type='mobile' GROUP BY eh.path),
scored AS (
  SELECT x.path, x.ptype, x.n_org, round(greatest(coalesce(x.e,0)-x.o,0))::int clics_perdus,
    CASE WHEN coalesce(x.i_nb,0)>0 THEN round(100.0*x.i_qpd/x.i_nb)::int ELSE 0 END couv,
    round(least(greatest((x.x_cap - CASE WHEN mt.cnt>=15 THEN mt.mc ELSE mg.mc END)/(CASE WHEN mt.cnt>=15 THEN dt.sc ELSE dg.sc END),-3),3)::numeric,1) zc,
    round(least(greatest((x.x_ret - CASE WHEN mt.cnt>=15 THEN mt.mr ELSE mg.mr END)/(CASE WHEN mt.cnt>=15 THEN dt.sr ELSE dg.sr END),-3),3)::numeric,1) zr,
    round(least(greatest((x.x_lec - CASE WHEN mt.cnt>=15 THEN mt.ml ELSE mg.ml END)/(CASE WHEN mt.cnt>=15 THEN dt.sl ELSE dg.sl END),-3),3)::numeric,1) zl,
    round(least(greatest((x.x_conv - CASE WHEN mt.cnt>=15 THEN mt.mv ELSE mg.mv END)/(CASE WHEN mt.cnt>=15 THEN dt.sv ELSE dg.sv END),-3),3)::numeric,1) zv,
    round(exp(least(greatest(
      (1 - 1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (-0.08*coalesce(m.p1-m.p0,0))
      + (1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (ln((coalesce(m.c1,0)+5.0)/(coalesce(m.c0,0)+5.0)) - ln((s.s1+50.0)/(s.s0+50.0)))
    ,-0.336),0.336))::numeric,2) mm,
    round((1 - 0.15*least(greatest((coalesce(l.lcp75,2500)-2500)/2500.0,0),1))::numeric,2) gg,
    CASE
      WHEN x.n_org >= 200 AND coalesce(x.e,0) >= 40 THEN 'S'
      WHEN x.n_org >= 100 AND coalesce(x.e,0) >= 20 THEN 'A'
      WHEN x.n_org >= 30 AND coalesce(x.e,0) >= 5 THEN 'B'
      ELSE 'C'
    END grade,
    coalesce(cv.macro_val, 0) > 0 AS convertit
  FROM xs x LEFT JOIN medt mt ON mt.ptype=x.ptype LEFT JOIN madt dt ON dt.ptype=x.ptype
  CROSS JOIN medg mg CROSS JOIN madg dg LEFT JOIN mom m ON m.path=x.path CROSS JOIN site s LEFT JOIN lcp l ON l.path=x.path
  LEFT JOIN convv cv ON cv.path=x.path
)
SELECT scored.path, scored.ptype, scored.grade,
  least(100, round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int) cpi,
  round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int cpi_raw,
  mm momentum, (CASE WHEN mm>=1.15 THEN '↗' WHEN mm<=0.87 THEN '↘' ELSE '→' END) momentum_badge,
  gg gate, zc, zr, zl, zv, clics_perdus, n_org, couv couv_gsc_pct, convertit
FROM scored
$function$;
REVOKE ALL ON FUNCTION public.cooked_page_index(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cooked_page_index(integer) TO service_role;


CREATE OR REPLACE FUNCTION public.dashboard_article_detail(p_path text, period_kind text DEFAULT 'rolling_28'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '45s'
AS $function$
DECLARE
  lns date; lne date; lps date; lpe date;
  gns date; gne date; gps date; gpe date;
  result jsonb;
BEGIN
  SELECT b.n_start,b.n_end,b.prev_start,b.prev_end INTO lns,lne,lps,lpe FROM cooked_period_bounds(period_kind,'live_j1') b;
  SELECT b.n_start,b.n_end,b.prev_start,b.prev_end INTO gns,gne,gps,gpe FROM cooked_period_bounds(period_kind,'gsc') b;

  SELECT jsonb_build_object(
    'path', p_path,
    'meta', (SELECT jsonb_build_object(
        'theme', pt.theme, 'category', pt.category,
        'naissance_google', (SELECT min(day) FROM gsc_path_daily g WHERE g.path=p_path AND g.impressions>0),
        'first_tracker_day', (SELECT min(public.paris_date(e.occurred_at)) FROM events_human e WHERE e.path=p_path AND e.name='pageview'),
        'age_jours', (public.paris_today() - (SELECT min(day) FROM gsc_path_daily g WHERE g.path=p_path AND g.impressions>0))::int
      ) FROM page_taxonomy pt WHERE pt.path=p_path),
    'gsc', (SELECT jsonb_build_object(
        'clicks', COALESCE(sum(clicks),0), 'impressions', COALESCE(sum(impressions),0),
        'position', round((sum(position*impressions)/nullif(sum(impressions),0))::numeric,1),
        'ctr_pct', CASE WHEN COALESCE(sum(impressions),0)>0 THEN round(100.0*sum(clicks)/sum(impressions),2) END,
        'ctr_expected', NULL::numeric,
        'clicks_prev', (SELECT COALESCE(sum(clicks),0) FROM gsc_path_daily g2 WHERE g2.path=p_path AND g2.day BETWEEN gps AND gpe)
      ) FROM gsc_path_daily g WHERE g.path=p_path AND g.day BETWEEN gns AND gne),
    'gsc_daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', ds.d, 'clicks', COALESCE(g.clicks,0), 'impressions', COALESCE(g.impressions,0)) ORDER BY ds.d), '[]'::jsonb)
      FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
      LEFT JOIN (SELECT day, sum(clicks) clicks, sum(impressions) impressions FROM gsc_path_daily WHERE path=p_path AND day BETWEEN gns AND gne GROUP BY day) g ON g.day=ds.d),
    'visitors_daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', ds.d, 'v', COALESCE(v.n,0)) ORDER BY ds.d), '[]'::jsonb)
      FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
      LEFT JOIN (SELECT public.paris_date(e.occurred_at) d, count(DISTINCT e.anonymous_id) n
                 FROM events_human e
                 WHERE e.path=p_path AND e.name='pageview'
                   AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
                   AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
                   AND e.occurred_at >= public.cooked_paris_ts_start(lns)
                   AND e.occurred_at <  public.cooked_paris_ts_end_exclusive(lne)
                 GROUP BY 1) v ON v.d=ds.d),
    'top_queries', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'query', q.query, 'clicks', q.clicks, 'impressions', q.impressions, 'position', q.pos,
        'volume_fr', dfs.search_volume, 'cpc', dfs.cpc) ORDER BY q.impressions DESC), '[]'::jsonb)
      FROM (SELECT query, sum(clicks) clicks, sum(impressions) impressions, round((sum(position*impressions)/nullif(sum(impressions),0))::numeric,1) pos
            FROM gsc_query_page_daily WHERE path=p_path AND day BETWEEN gns AND gne AND NOT public.gsc_is_branded(query)
            GROUP BY query ORDER BY sum(impressions) DESC LIMIT 10) q
      LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=q.query AND dfs.location_code=2250),
    'cpi', (SELECT to_jsonb(c) - 'created_at' FROM cpi_daily c WHERE c.path=p_path AND c.day=(SELECT max(day) FROM cpi_daily) ),
    'cpi_series', (SELECT COALESCE(jsonb_agg(jsonb_build_object('d', day, 'cpi', cpi, 'cpi_version', cpi_version) ORDER BY day), '[]'::jsonb)
      FROM cpi_daily WHERE path=p_path),
    'assisted', (SELECT jsonb_build_object('n', s.assisted_contacts, 'prev', s.assisted_prev)
      FROM dashboard_resources_assisted_snapshot s WHERE s.path=p_path AND s.window_kind=period_kind),
    'bounds', jsonb_build_object('cooked_start', lns, 'cooked_end', lne, 'gsc_start', gns, 'gsc_end', gne)
  ) INTO result;
  RETURN result;
END $function$;
REVOKE ALL ON FUNCTION public.dashboard_article_detail(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_article_detail(text,text) TO service_role;


GRANT EXECUTE ON FUNCTION public.dashboard_article_detail(text,text) TO cooked_ci_ro;

CREATE OR REPLACE FUNCTION public.refresh_dashboard_snapshots(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text;
  lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int;
  cpi_day date;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_resources_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_kpis_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_trend_snapshot WHERE window_kind = ANY(windows);
  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'clean', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);
    DROP TABLE IF EXISTS _ev;
    CREATE TEMP TABLE _ev ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.referrer_hostname AS ref,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        e.d
      FROM _cooked_ev e
      JOIN page_taxonomy pt ON pt.path = e.path AND pt.category='ressource'
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com';
    DROP TABLE IF EXISTS _evc;
    CREATE TEMP TABLE _evc ON COMMIT DROP AS SELECT * FROM _ev;
    ANALYZE _evc;
    INSERT INTO public.dashboard_resources_snapshot
    WITH res AS (SELECT pt.path, pt.theme FROM page_taxonomy pt WHERE pt.category='ressource'),
    dwx AS (
      SELECT path,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY dur)) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY scr)) AS scroll
      FROM (
        SELECT path, session_id, max(dur) AS dur, max(scr) AS scr
        FROM _evc
        WHERE name='page_exit' AND d BETWEEN lns AND lne
          AND coalesce(ref,'') NOT ILIKE '%linkedin%' AND coalesce(ref,'') NOT ILIKE '%facebook%'
        GROUP BY path, session_id
      ) a GROUP BY path
    ),
    cooked AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv
      FROM _evc GROUP BY path
    ),
    gsc AS (SELECT m.path, m.clicks_total, m.impressions_total, m.position_avg, m.ctr_pct
            FROM gsc_path_metrics(gns,gne) m JOIN res ON res.path=m.path),
    gscp AS (SELECT m.path, m.clicks_total AS clicks_prev FROM gsc_path_metrics(gps,gpe) m JOIN res ON res.path=m.path),
    cpi_d AS (SELECT path, cpi, grade, momentum FROM cpi_daily WHERE day = cpi_day),
    gis AS (SELECT path, potentiel, convertit FROM cpi_gisement),
    bestq AS (
      SELECT DISTINCT ON (q.path) q.path, q.query, q.clicks FROM (
        SELECT qp.path, qp.query, SUM(qp.clicks) clicks, SUM(qp.impressions) impr
        FROM gsc_query_page_daily qp JOIN res ON res.path=qp.path
        WHERE qp.day BETWEEN gns AND gne AND NOT public.gsc_is_branded(qp.query)
        GROUP BY qp.path, qp.query) q
      ORDER BY q.path, q.clicks DESC, q.impr DESC
    ),
    contacts AS (SELECT mc.path, mc.contacts, mc.booking_intent FROM macro_contacts_by_path(lns,lne) mc JOIN res ON res.path=mc.path),
    fi AS (SELECT g.path, MIN(g.day) first_impr FROM gsc_path_daily g
           WHERE g.impressions>0 AND g.path IN (SELECT path FROM res) GROUP BY g.path),
    fv AS (SELECT e.path, MIN(public.paris_date(e.occurred_at)) first_view
           FROM events_human e
           WHERE e.name='pageview' AND e.path IN (SELECT path FROM res)
           GROUP BY e.path)
    SELECT w, res.path, res.theme,
      COALESCE(c.uv,0), COALESCE(c.pv,0), dw.dwell, dw.scroll,
      COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
      bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
      COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
      fi.first_impr, fv.first_view,
      (lpt - LEAST(COALESCE(fi.first_impr,fv.first_view), COALESCE(fv.first_view,fi.first_impr)))::int,
      CASE WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 1.5 THEN 'A'
           WHEN ld>0 AND COALESCE(c.uv,0)::numeric/ld >= 0.5 THEN 'B' ELSE 'C' END,
      lns, lne, gns, gne, now(),
      COALESCE(c.uv_prev,0)::int, COALESCE(gp.clicks_prev,0)::int,
      cd.cpi, cd.grade, cd.momentum, gi.potentiel, gi.convertit,
      NULL::numeric
    FROM res
    LEFT JOIN cooked c ON c.path=res.path
    LEFT JOIN dwx dw ON dw.path=res.path
    LEFT JOIN gsc g ON g.path=res.path
    LEFT JOIN gscp gp ON gp.path=res.path
    LEFT JOIN cpi_d cd ON cd.path=res.path
    LEFT JOIN gis gi ON gi.path=res.path
    LEFT JOIN bestq bq ON bq.path=res.path
    LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=bq.query AND dfs.location_code=2250
    LEFT JOIN contacts ct ON ct.path=res.path
    LEFT JOIN fi ON fi.path=res.path
    LEFT JOIN fv ON fv.path=res.path;
    INSERT INTO public.dashboard_kpis_snapshot
      (window_kind, label_fr, cooked_start, cooked_end, gsc_start, gsc_end, gsc_last_day, lag_days,
       is_partial, visitors_n, visitors_prev, pageviews_n, pageviews_prev, contacts_n, contacts_prev,
       gsc_clicks_n, gsc_clicks_prev, gsc_impressions_n, gsc_impressions_prev, refreshed_at,
       current_day_partial, no_prev_baseline)
    SELECT w, lbl, lns, lne, gns, gne, glast, glag,
      ((lne >= lpt) OR (tracker_first_seen_global() > lpe::timestamptz)),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evc WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evc WHERE d BETWEEN lps AND lpe),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne),
      (SELECT COUNT(*) FROM _evc WHERE name='pageview' AND d BETWEEN lps AND lpe),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lns,lne) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lps,lpe) mc JOIN page_taxonomy pt ON pt.path=mc.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gns,gne) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN page_taxonomy pt ON pt.path=m.path AND pt.category='ressource'),
      now(), (lne >= lpt), (tracker_first_seen_global() > lpe::timestamptz);
    INSERT INTO public.dashboard_trend_snapshot
      (window_kind, visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily, refreshed_at)
    SELECT w,
      (SELECT array_agg(COALESCE(v.uv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') uv FROM _evc WHERE d BETWEEN lns AND lne GROUP BY d) v ON v.d = ds.d),
      (SELECT array_agg(COALESCE(p.pv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT d, COUNT(*) pv FROM _evc WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) p ON p.d = ds.d),
      (SELECT array_agg(COALESCE(ct.ct,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp, lne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (
           SELECT public.paris_date(e.occurred_at) d, COUNT(*) ct
           FROM events_human e JOIN page_taxonomy pt ON pt.path=e.path AND pt.category='ressource'
           WHERE e.name IN ('cta_phone_click','form_submit')
             AND (e.name='cta_phone_click' OR form_submit_counts_as_macro(e.props))
             AND public.paris_date(e.occurred_at) BETWEEN lns AND lne
           GROUP BY 1
         ) ct ON ct.d = ds.d),
      (SELECT array_agg(COALESCE(gd.clicks,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT day, SUM(clicks) clicks FROM gsc_path_daily
                    WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM page_taxonomy WHERE category='ressource') GROUP BY day) gd ON gd.day = ds.d),
      (SELECT array_agg(COALESCE(gd.impr,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp, gne::timestamp, interval '1 day')::date d) ds
         LEFT JOIN (SELECT day, SUM(impressions) impr FROM gsc_path_daily
                    WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM page_taxonomy WHERE category='ressource') GROUP BY day) gd ON gd.day = ds.d),
      now();
  END LOOP;
END $function$;
REVOKE ALL ON FUNCTION public.refresh_dashboard_snapshots(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_snapshots(text) TO service_role;


CREATE OR REPLACE PROCEDURE public.cooked_events_window(IN p_occurred_from timestamp with time zone, IN p_occurred_to timestamp with time zone, IN p_grain text DEFAULT 'human'::text, IN p_site text DEFAULT 'main'::text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $procedure$
BEGIN
  IF p_grain NOT IN ('raw', 'clean', 'human') THEN
    RAISE EXCEPTION 'cooked_events_window: grain must be raw|clean|human, got %', p_grain;
  END IF;
  IF p_site NOT IN ('main', 'outremer') THEN
    RAISE EXCEPTION 'cooked_events_window: site must be main|outremer, got %', p_site;
  END IF;

  DROP TABLE IF EXISTS _cooked_ev;
  DROP TABLE IF EXISTS _cooked_ev_raw;

  IF p_grain = 'raw' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at, e.url,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at, e.url,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    END IF;

  ELSIF p_grain = 'clean' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at, e.url,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          )
          AND NOT (
            e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
          );
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at, e.url,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          )
          AND NOT (
            e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
          );
    END IF;

  ELSIF p_site = 'main' THEN
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at, e.url,
             public.paris_date(e.occurred_at) AS d
      FROM public.events_main e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to
        AND NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
        )
        AND NOT (
          e.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(e.props)
        )
        AND NOT (
          e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
        )
        AND NOT (
          e.name IN (
            'cta_phone_click', 'cta_booking_click', 'cta_anchor_click',
            'click_internal', 'click_outbound'
          )
          AND EXISTS (
            SELECT 1 FROM public.events_main dup
            WHERE dup.session_id = e.session_id
              AND dup.name = e.name
              AND dup.path IS NOT DISTINCT FROM e.path
              AND date_trunc('second', dup.occurred_at) = date_trunc('second', e.occurred_at)
              AND (dup.props->>'anchor') IS NOT DISTINCT FROM (e.props->>'anchor')
              AND dup.id < e.id
          )
        );

  ELSE
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at, e.url,
             public.paris_date(e.occurred_at) AS d
      FROM public.events_outremer e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to
        AND NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
        )
        AND NOT (
          e.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(e.props)
        )
        AND NOT (
          e.name = 'pageview' AND public.cooked_is_spam_referrer(e.referrer_hostname)
        );
  END IF;

  ANALYZE _cooked_ev;
END;
$procedure$;
REVOKE ALL ON PROCEDURE public.cooked_events_window(timestamptz,timestamptz,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.cooked_events_window(timestamptz,timestamptz,text,text) TO service_role;


CREATE OR REPLACE FUNCTION public.refresh_dashboard_expertises_snapshots(p_window text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int; cpi_day date;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_expertises_snapshot       WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_kpis_snapshot  WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_trend_snapshot WHERE window_kind = ANY(windows);

  DROP TABLE IF EXISTS _xp;
  CREATE TEMP TABLE _xp ON COMMIT DROP AS
    SELECT * FROM (VALUES
      ('/defense-penale/droit-penal'),
      ('/defense-penale/droit-penal-des-affaires'),
      ('/defense-penale/proces-criminel'),
      ('/defense-penale/trafic-de-stupefiant'),
      ('/defense-penale/violences-conjugales-et-feminicides'),
      ('/indemnisation-des-victimes/accidents-de-la-route'),
      ('/indemnisation-des-victimes/accidents-de-la-vie-courante'),
      ('/indemnisation-des-victimes/accidents-et-erreurs-medicales'),
      ('/indemnisation-des-victimes/droit-et-accidents-du-travail'),
      ('/indemnisation-des-victimes/victimes-de-delits-ou-crimes'),
      ('/droit-des-contrats-et-des-personnes/droit-de-la-famille'),
      ('/droit-des-contrats-et-des-personnes/droit-de-la-famille/avocat-divorce-bordeaux'),
      ('/droit-des-contrats-et-des-personnes/defense-des-consommateurs'),
      ('/droit-des-contrats-et-des-personnes/droit-assurances-particuliers-professionnels')
    ) v(path);
  ANALYZE _xp;

  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'clean', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);
    DROP TABLE IF EXISTS _evx;
    CREATE TEMP TABLE _evx ON COMMIT DROP AS
      SELECT e.anonymous_id, e.session_id, e.path, e.name, e.occurred_at,
        (e.props->>'duration_seconds')::numeric AS dur, (e.props->>'max_scroll')::numeric AS scr,
        e.d
      FROM _cooked_ev e JOIN _xp ON _xp.path=e.path
      WHERE e.name IN ('pageview','page_exit')
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com';
    ANALYZE _evx;

    DROP TABLE IF EXISTS _fp;
    CREATE TEMP TABLE _fp ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
        public.classify_channel(e.referrer_hostname,e.utm_source,e.utm_medium,'www.jplouton-avocat.fr',e.url) AS chan
      FROM _cooked_ev e
      WHERE e.name='pageview'
        AND e.session_id IN (SELECT DISTINCT session_id FROM _evx WHERE name='pageview' AND d BETWEEN lns AND lne)
        AND e.d BETWEEN lns AND lne
      ORDER BY e.session_id, e.occurred_at;
    ANALYZE _fp;

    INSERT INTO public.dashboard_expertises_snapshot (
      window_kind, path, theme, unique_visitors, pageviews, dwell_median_s, scroll_median,
      gsc_clicks, gsc_impressions, gsc_position_avg, gsc_ctr_pct,
      best_query, best_query_clicks, best_query_volume_fr, best_query_cpc,
      contacts, booking_intent, first_impression_day, first_tracker_day, days_live,
      confidence, cooked_start, cooked_end, gsc_start, gsc_end, refreshed_at,
      unique_visitors_prev, gsc_clicks_prev, cpi, cpi_grade, momentum, potentiel, convertit,
      ctr_expected, paid_share_pct)
    WITH
    reads AS (
      SELECT fp.entry_path AS path,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.dur)) AS dwell,
        ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY a.scr)) AS scroll
      FROM _fp fp
      JOIN (SELECT session_id, path, max(dur) dur, max(scr) scr FROM _evx WHERE name='page_exit' GROUP BY session_id, path) a
        ON a.session_id=fp.session_id AND a.path=fp.entry_path
      WHERE fp.chan LIKE 'organic%' AND fp.entry_path IN (SELECT path FROM _xp)
      GROUP BY fp.entry_path
    ),
    vis AS (
      SELECT path,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS uv,
        COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview' AND d BETWEEN lps AND lpe) AS uv_prev,
        COUNT(*) FILTER (WHERE name='pageview' AND d BETWEEN lns AND lne) AS pv
      FROM _evx GROUP BY path
    ),
    pgchan AS (
      SELECT ev.path,
        COUNT(DISTINCT ev.session_id) AS tot,
        COUNT(DISTINCT ev.session_id) FILTER (WHERE fp.chan='paid') AS paid
      FROM _evx ev JOIN _fp fp ON fp.session_id=ev.session_id
      WHERE ev.name='pageview' AND ev.d BETWEEN lns AND lne
      GROUP BY ev.path
    ),
    gsc AS (SELECT m.path,m.clicks_total,m.impressions_total,m.position_avg,m.ctr_pct
            FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
    gscp AS (SELECT m.path,m.clicks_total AS clicks_prev FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
    cpi_d AS (SELECT path,cpi,grade,momentum FROM cpi_daily WHERE day=cpi_day),
    gis AS (SELECT path,potentiel,convertit FROM cpi_gisement),
    bestq AS (
      SELECT DISTINCT ON (q.path) q.path,q.query,q.clicks FROM (
        SELECT qp.path,qp.query,SUM(qp.clicks) clicks,SUM(qp.impressions) impr
        FROM gsc_query_page_daily qp JOIN _xp ON _xp.path=qp.path
        WHERE qp.day BETWEEN gns AND gne AND NOT public.gsc_is_branded(qp.query)
        GROUP BY qp.path,qp.query) q
      ORDER BY q.path,q.clicks DESC,q.impr DESC
    ),
    contacts AS (SELECT mc.path,mc.contacts,mc.booking_intent FROM macro_contacts_by_path(lns,lne) mc JOIN _xp ON _xp.path=mc.path)
    SELECT w, x.path,
      (SELECT theme FROM page_taxonomy pt WHERE pt.path=x.path),
      COALESCE(v.uv,0), COALESCE(v.pv,0), r.dwell, r.scroll,
      COALESCE(g.clicks_total,0), COALESCE(g.impressions_total,0), g.position_avg, g.ctr_pct,
      bq.query, bq.clicks, dfs.search_volume, dfs.cpc,
      COALESCE(ct.contacts,0), COALESCE(ct.booking_intent,0),
      NULL::date, NULL::date, NULL::int,
      CASE WHEN ld>0 AND COALESCE(v.uv,0)::numeric/ld >= 1.5 THEN 'A'
           WHEN ld>0 AND COALESCE(v.uv,0)::numeric/ld >= 0.5 THEN 'B' ELSE 'C' END,
      lns, lne, gns, gne, now(),
      COALESCE(v.uv_prev,0)::int, COALESCE(gp.clicks_prev,0)::int,
      cd.cpi, cd.grade, cd.momentum, gi.potentiel, gi.convertit,
      NULL::numeric,
      CASE WHEN pc.tot>0 THEN ROUND(100.0*pc.paid/pc.tot,1) END
    FROM _xp x
    LEFT JOIN vis v      ON v.path=x.path
    LEFT JOIN reads r    ON r.path=x.path
    LEFT JOIN pgchan pc  ON pc.path=x.path
    LEFT JOIN gsc g      ON g.path=x.path
    LEFT JOIN gscp gp    ON gp.path=x.path
    LEFT JOIN cpi_d cd   ON cd.path=x.path
    LEFT JOIN gis gi     ON gi.path=x.path
    LEFT JOIN bestq bq   ON bq.path=x.path
    LEFT JOIN dfs_keyword_volume dfs ON dfs.keyword=bq.query AND dfs.location_code=2250
    LEFT JOIN contacts ct ON ct.path=x.path;

    INSERT INTO public.dashboard_expertises_kpis_snapshot (
      window_kind, label_fr, cooked_start, cooked_end, gsc_start, gsc_end, gsc_last_day, lag_days,
      is_partial, visitors_n, visitors_prev, pageviews_n, pageviews_prev, contacts_n, contacts_prev,
      gsc_clicks_n, gsc_clicks_prev, gsc_impressions_n, gsc_impressions_prev, refreshed_at,
      current_day_partial, no_prev_baseline, paid_entries_n, organic_entries_n, total_entries_n)
    SELECT w, lbl, lns, lne, gns, gne, glast, glag,
      ((lne >= lpt) OR (tracker_first_seen_global() > lpe::timestamptz)),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lps AND lpe),
      (SELECT COUNT(*) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lns AND lne),
      (SELECT COUNT(*) FILTER (WHERE name='pageview') FROM _evx WHERE d BETWEEN lps AND lpe),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lns,lne) mc JOIN _xp ON _xp.path=mc.path),
      (SELECT COALESCE(SUM(mc.contacts),0) FROM macro_contacts_by_path(lps,lpe) mc JOIN _xp ON _xp.path=mc.path),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.clicks_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gns,gne) m JOIN _xp ON _xp.path=m.path),
      (SELECT COALESCE(SUM(m.impressions_total),0) FROM gsc_path_metrics(gps,gpe) m JOIN _xp ON _xp.path=m.path),
      now(), (lne >= lpt), (tracker_first_seen_global() > lpe::timestamptz),
      (SELECT COUNT(*) FILTER (WHERE chan='paid')          FROM _fp),
      (SELECT COUNT(*) FILTER (WHERE chan LIKE 'organic%') FROM _fp),
      (SELECT COUNT(*)                                     FROM _fp);

    INSERT INTO public.dashboard_expertises_trend_snapshot (
      window_kind, visitors_daily, pageviews_daily, contacts_daily, gsc_clicks_daily, gsc_impressions_daily, refreshed_at)
    SELECT w,
      (SELECT array_agg(COALESCE(v.uv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT d,COUNT(DISTINCT anonymous_id) FILTER (WHERE name='pageview') uv FROM _evx WHERE d BETWEEN lns AND lne GROUP BY d) v ON v.d=ds.d),
      (SELECT array_agg(COALESCE(p.pv,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT d,COUNT(*) pv FROM _evx WHERE name='pageview' AND d BETWEEN lns AND lne GROUP BY d) p ON p.d=ds.d),
      (SELECT array_agg(COALESCE(ct.ct,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(lns::timestamp,lne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (
           SELECT public.paris_date(e.occurred_at) d, COUNT(*) ct
           FROM events_human e JOIN _xp ON _xp.path=e.path
           WHERE e.name IN ('cta_phone_click','form_submit')
             AND (e.name='cta_phone_click' OR form_submit_counts_as_macro(e.props))
             AND public.paris_date(e.occurred_at) BETWEEN lns AND lne
           GROUP BY 1
         ) ct ON ct.d=ds.d),
      (SELECT array_agg(COALESCE(gd.clicks,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp,gne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT day,SUM(clicks) clicks FROM gsc_path_daily WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM _xp) GROUP BY day) gd ON gd.day=ds.d),
      (SELECT array_agg(COALESCE(gd.impr,0)::numeric ORDER BY ds.d)
         FROM (SELECT generate_series(gns::timestamp,gne::timestamp,interval '1 day')::date d) ds
         LEFT JOIN (SELECT day,SUM(impressions) impr FROM gsc_path_daily WHERE day BETWEEN gns AND gne AND path IN (SELECT path FROM _xp) GROUP BY day) gd ON gd.day=ds.d),
      now();
  END LOOP;
END $function$;
REVOKE ALL ON FUNCTION public.refresh_dashboard_expertises_snapshots(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_expertises_snapshots(text) TO service_role;


CREATE OR REPLACE FUNCTION public.behavior_pages_for_period(date_from timestamp with time zone, date_to timestamp with time zone)
 RETURNS TABLE(path text, sessions bigint, pages_per_session numeric, avg_session_duration_s numeric, bounce_rate numeric, bounce_rate_pct numeric, scroll_depth_avg numeric, scroll_complete_pct numeric, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, ttfb_p75_ms numeric, outbound_clicks bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH we AS (
    SELECT * FROM public.events_human
    WHERE occurred_at >= date_from AND occurred_at < date_to
  ),
  ss AS (
    SELECT session_id,
      count(*) FILTER (WHERE name = 'pageview') AS pages_viewed,
      extract(epoch FROM max(occurred_at) - min(occurred_at))::numeric AS session_seconds
    FROM we GROUP BY session_id
  ),
  sp AS (
    SELECT DISTINCT e.path, e.session_id
    FROM we e
    WHERE e.name = 'pageview' AND e.path IS NOT NULL
  ),
  per_path_session_stats AS (
    SELECT sp.path,
      avg(ss.pages_viewed)::numeric AS pages_per_session,
      avg(ss.session_seconds)::numeric AS avg_session_seconds
    FROM sp JOIN ss ON ss.session_id = sp.session_id
    GROUP BY sp.path
  ),
  cwv AS (
    SELECT path,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'LCP'))::numeric AS lcp_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'INP'))::numeric AS inp_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'CLS'))::numeric AS cls_p75,
      (percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'TTFB'))::numeric AS ttfb_p75
    FROM public.cooked_web_vitals_window(date_from,date_to)
    WHERE path IS NOT NULL
    GROUP BY path
  ),
  oc AS (
    SELECT path, count(*) AS clicks
    FROM we
    WHERE name = 'click_outbound' AND path IS NOT NULL
    GROUP BY path
  ),
  base AS (SELECT * FROM public.seo_pages_overview(date_from, date_to))
  SELECT b.path, b.sessions,
    coalesce(round(pp.pages_per_session, 2), 0),
    coalesce(round(pp.avg_session_seconds, 0), 0),
    coalesce(round(b.bounce_rate, 4), 0),      -- T-03 (d-01) : fraction 0-1 déjà produite par seo_pages_overview
    coalesce(round(b.bounce_rate_pct, 2), 0),  -- T-03 (d-01) : pourcentage 0-100
    b.scroll_avg, b.scroll_complete_pct,
    cwv.lcp_p75, cwv.inp_p75, cwv.cls_p75, cwv.ttfb_p75,
    coalesce(oc.clicks, 0)::bigint
  FROM base b
  LEFT JOIN per_path_session_stats pp ON pp.path = b.path
  LEFT JOIN cwv ON cwv.path = b.path
  LEFT JOIN oc ON oc.path = b.path;
$function$;
REVOKE ALL ON FUNCTION public.behavior_pages_for_period(timestamptz,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.behavior_pages_for_period(timestamptz,timestamptz) TO service_role;


CREATE OR REPLACE FUNCTION public.gsc_page_performance(target_path text, period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(path text, gsc_clicks bigint, gsc_impressions bigint, gsc_position_avg numeric, gsc_ctr_pct numeric, cooked_sessions bigint, cooked_views bigint, cooked_unique_visitors bigint, cooked_bounce_rate numeric, cooked_dwell_avg_s numeric, cooked_scroll_median numeric, cooked_phone_clicks bigint, cooked_form_submits bigint, cooked_contacts bigint, cooked_booking_intent bigint, cooked_pogo_rate numeric, cooked_google_sessions bigint, lcp_p75_ms numeric, inp_p75_ms numeric, cls_p75 numeric, top_referrer text, device_split jsonb)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT * FROM public.cooked_period_bounds(period_kind, 'cross') LIMIT 1
  ),
  b AS (SELECT n_start, n_end FROM bounds),
  ts AS (
    SELECT
      public.cooked_paris_ts_start(b.n_start) AS date_from,
      public.cooked_paris_ts_end_exclusive(b.n_end) AS date_to
    FROM b
  ),
  cp AS (SELECT public.canonical_path(target_path) AS p),
  g AS (
    SELECT
      coalesce(sum(gd.clicks), 0)::bigint AS clicks_total,
      coalesce(sum(gd.impressions), 0)::bigint AS impressions_total,
      CASE WHEN sum(gd.impressions) > 0
           THEN round((sum(gd.position * gd.impressions) / sum(gd.impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN sum(gd.impressions) > 0
           THEN round((100.0 * sum(gd.clicks) / sum(gd.impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM public.gsc_path_daily gd, cp, b
    WHERE gd.path = cp.p AND gd.day >= b.n_start AND gd.day <= b.n_end
  ),
  cooked AS (
    SELECT o.*
    FROM public.seo_pages_overview((SELECT date_from FROM ts), (SELECT date_to FROM ts)) o, cp
    WHERE o.path = cp.p
    LIMIT 1
  ),
  mc AS (
    SELECT m.*
    FROM public.macro_contacts_by_path((SELECT n_start FROM b), (SELECT n_end FROM b)) m, cp
    WHERE m.path = cp.p
  ),
  pogo AS (
    SELECT pr.pogo_rate
    FROM public.pogo_rates_for_period(
      (SELECT date_from FROM ts),
      (SELECT date_to FROM ts)
    ) pr, cp
    WHERE pr.path = cp.p
    LIMIT 1
  ),
  google_sess AS (
    SELECT count(DISTINCT e.session_id)::bigint AS n
    FROM public.events_human e, cp, b, ts
    WHERE e.path = cp.p
      AND e.name = 'pageview'
      AND e.device_type IS DISTINCT FROM 'server'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      AND (
        e.referrer_hostname LIKE '%google.%'
        OR (e.utm_source = 'google' AND e.utm_medium IN ('organic', 'cpc'))
      )
  ),
  ref_top AS (
    SELECT e.referrer_hostname AS ref, count(*) AS cnt
    FROM public.events_human e, cp, ts
    WHERE e.path = cp.p AND e.name = 'pageview'
      AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      AND e.referrer_hostname IS NOT NULL
    GROUP BY e.referrer_hostname
    ORDER BY cnt DESC
    LIMIT 1
  ),
  dev AS (
    SELECT jsonb_object_agg(device_type, cnt) AS split
    FROM (
      SELECT coalesce(e.device_type, 'unknown') AS device_type, count(*)::bigint AS cnt
      FROM public.events_human e, cp, ts
      WHERE e.path = cp.p AND e.name = 'pageview'
        AND e.occurred_at >= ts.date_from AND e.occurred_at < ts.date_to
      GROUP BY e.device_type
    ) d
  ),
  cwv AS (
    SELECT
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'LCP') AS lcp,
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'INP') AS inp,
      percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric)
        FILTER (WHERE props->>'metric' = 'CLS') AS cls
    FROM public.cooked_web_vitals_window((SELECT date_from FROM ts),(SELECT date_to FROM ts)) e, cp
    WHERE e.path = cp.p
  )
  SELECT
    cp.p,
    coalesce(g.clicks_total, 0),
    coalesce(g.impressions_total, 0),
    g.position_avg,
    g.ctr_pct,
    coalesce(cooked.sessions, 0),
    coalesce(cooked.views, 0),
    coalesce(cooked.unique_visitors, 0),
    cooked.bounce_rate_pct,   -- T-03 (d-04) : même unité (0-100) que pages_overview_unified et seo_url_snapshot
    cooked.avg_dwell_seconds,
    cooked.scroll_median,
    coalesce(mc.phone_clicks, 0),
    coalesce(mc.form_submits, 0),
    coalesce(mc.contacts, 0),
    coalesce(mc.booking_intent, 0),
    pogo.pogo_rate,
    coalesce(google_sess.n, 0),
    cwv.lcp,
    cwv.inp,
    cwv.cls,
    ref_top.ref,
    dev.split
  FROM cp
    LEFT JOIN g ON true
    LEFT JOIN cooked ON true
    LEFT JOIN mc ON true
    LEFT JOIN pogo ON true
    LEFT JOIN google_sess ON true
    LEFT JOIN ref_top ON true
    LEFT JOIN dev ON true
    LEFT JOIN cwv ON true;
$function$;
REVOKE ALL ON FUNCTION public.gsc_page_performance(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gsc_page_performance(text,text) TO service_role;


CREATE OR REPLACE FUNCTION public.refresh_seo_url_snapshot()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  now_ts timestamptz := now();
begin
  perform public.refresh_bot_fingerprints();
  perform public.refresh_noise_sessions();

  call public.cooked_events_window(
    now_ts - interval '365 days',
    now_ts,
    'human',
    'main'
  );

  drop table if exists _eh;
  create temp table _eh on commit drop as
    select id, anonymous_id, session_id, path, name, occurred_at,
           referrer_hostname, utm_source, utm_medium, device_type, props
    from _cooked_ev;
  analyze _eh;

  delete from public.seo_url_snapshot;

  insert into public.seo_url_snapshot
  with
    all_paths as (
      select distinct path from _eh
      where path is not null and occurred_at >= now_ts - interval '365 days'
    ),
    o7 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '7 days'   and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    o28 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '28 days'  and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    o90 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '90 days'  and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    o365 as (
      with we as (select * from _eh where occurred_at >= now_ts - interval '365 days' and occurred_at < now_ts),
      pv as (select path, count(*) as views, count(distinct anonymous_id) as unique_visitors, count(distinct session_id) as sessions
             from we where name='pageview' and path is not null group by path),
      ss as (select session_id, min(occurred_at) as session_start, max(occurred_at) as session_end,
                    count(*) filter (where name='pageview') as pages_viewed,
                    (array_agg(path order by occurred_at)      filter (where name='pageview'))[1] as entry_path,
                    (array_agg(path order by occurred_at desc) filter (where name='pageview'))[1] as exit_path
             from we group by session_id),
      sp as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) filter (where name='page_exit') as dwell,
                    coalesce(max((props->>'percent')::numeric) filter (where name='scroll_depth'),0) as max_scroll
             from we where path is not null group by session_id, path),
      scroll_dwell as (select path, avg(dwell)::numeric as avg_dwell, avg(max_scroll)::numeric as scroll_avg,
                    (percentile_cont(0.5) within group (order by max_scroll))::numeric as scroll_median,
                    (100.0*count(*) filter (where max_scroll>=100)/nullif(count(*),0))::numeric as scroll_complete_pct
             from sp group by path),
      entry_exit as (select path, sum(is_entry)::bigint as entry_count, sum(is_exit)::bigint as exit_count, sum(is_bounce)::bigint as bounce_count
             from (select ss.entry_path as path,1 as is_entry,0 as is_exit,
                          case when ss.pages_viewed=1 and extract(epoch from (ss.session_end-ss.session_start))<10 then 1 else 0 end as is_bounce
                   from ss where ss.entry_path is not null
                   union all select ss.exit_path,0,1,0 from ss where ss.exit_path is not null) u group by path),
      oc as (select path, count(*) as clicks from we where name='click_outbound' and path is not null group by path)
      select pv.path, pv.views::bigint, pv.unique_visitors::bigint, pv.sessions::bigint,
        coalesce(round((100.0*ee.bounce_count/nullif(ee.entry_count,0))::numeric,2),0) as bounce_rate,
        coalesce(round(sd.avg_dwell,1),0) as avg_dwell_seconds, coalesce(round(sd.scroll_avg,1),0) as scroll_avg,
        coalesce(round(sd.scroll_median,1),0) as scroll_median, coalesce(round(sd.scroll_complete_pct,1),0) as scroll_complete_pct,
        coalesce(ee.entry_count,0)::bigint as entry_count, coalesce(ee.exit_count,0)::bigint as exit_count, coalesce(oc.clicks,0)::bigint as outbound_clicks
      from pv left join scroll_dwell sd on sd.path=pv.path left join entry_exit ee on ee.path=pv.path left join oc on oc.path=pv.path
    ),
    cwv as (
      select path,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='LCP'))::numeric  as lcp_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='INP'))::numeric  as inp_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='CLS'))::numeric  as cls_p75,
        (percentile_cont(0.75) within group (order by (props->>'value')::numeric) filter (where props->>'metric'='TTFB'))::numeric as ttfb_p75
      from public.cooked_web_vitals_window(now_ts - interval '28 days',now_ts) where path is not null group by path
    ),
    top_ref as (select distinct on (path) path, referrer_hostname as top_referrer from (
        select path, referrer_hostname, count(*) as c from _eh
        where name='pageview' and path is not null and referrer_hostname is not null and occurred_at >= now_ts - interval '28 days'
        group by path, referrer_hostname) r order by path, c desc),
    top_src as (select distinct on (path) path, utm_source as top_source from (
        select path, utm_source, count(*) as c from _eh
        where name='pageview' and path is not null and utm_source is not null and occurred_at >= now_ts - interval '28 days'
        group by path, utm_source) r order by path, c desc),
    top_med as (select distinct on (path) path, utm_medium as top_medium from (
        select path, utm_medium, count(*) as c from _eh
        where name='pageview' and path is not null and utm_medium is not null and occurred_at >= now_ts - interval '28 days'
        group by path, utm_medium) r order by path, c desc),
    dev as (select path, jsonb_object_agg(device_type, pct) as split from (
        select path, device_type, round((100.0*count(*)/sum(count(*)) over (partition by path))::numeric,1) as pct
        from _eh where name='pageview' and path is not null and device_type is not null and occurred_at >= now_ts - interval '28 days'
        group by path, device_type) d group by path),
    phone_counts as (select path,
        count(*) filter (where occurred_at >= now_ts - interval '7 days')   as p7,
        count(*) filter (where occurred_at >= now_ts - interval '28 days')  as p28,
        count(*) filter (where occurred_at >= now_ts - interval '90 days')  as p90,
        count(*) filter (where occurred_at >= now_ts - interval '365 days') as p365
      from _eh where name='cta_phone_click' and path is not null and occurred_at >= now_ts - interval '365 days' group by path),
    booking_counts as (select path,
        count(*) filter (where occurred_at >= now_ts - interval '7 days')   as b7,
        count(*) filter (where occurred_at >= now_ts - interval '28 days')  as b28,
        count(*) filter (where occurred_at >= now_ts - interval '90 days')  as b90,
        count(*) filter (where occurred_at >= now_ts - interval '365 days') as b365
      from _eh where name='cta_booking_click' and path is not null and occurred_at >= now_ts - interval '365 days' group by path),
    pogo as (
      with google_entries as (select distinct session_id, path from _eh
             where name='pageview' and referrer_hostname like '%google%'
               and occurred_at >= now_ts - interval '28 days' and occurred_at < now_ts),
      session_pages as (select session_id, count(*) as pages from _eh
             where name='pageview' and occurred_at >= now_ts - interval '28 days' and occurred_at < now_ts group by session_id),
      session_exit as (select session_id, path,
                    max((props->>'duration_seconds')::numeric) as dwell_s,
                    max((props->>'max_scroll')::numeric)       as scroll
             from _eh where name='page_exit' and occurred_at >= now_ts - interval '28 days' and occurred_at < now_ts
             group by session_id, path)
      select g.path, count(*)::bigint as google_sessions,
        count(*) filter (where sp.pages=1 and (se.dwell_s<10 or se.dwell_s is null))::bigint as pogo_sticks,
        count(*) filter (where sp.pages=1 and ((se.dwell_s<10 and se.scroll<5) or se.dwell_s is null))::bigint as hard_pogo,
        round(100.0*count(*) filter (where sp.pages=1 and (se.dwell_s<10 or se.dwell_s is null))/nullif(count(*),0),1) as pogo_rate
      from google_entries g
      left join session_pages sp on sp.session_id=g.session_id
      left join session_exit  se on se.session_id=g.session_id and se.path=g.path
      group by g.path
    ),
    device_sessions as (select path,
        count(distinct session_id) filter (where device_type='mobile')  as mob_s,
        count(distinct session_id) filter (where device_type='desktop') as dsk_s
      from _eh where name='pageview' and path is not null and occurred_at >= now_ts - interval '28 days' group by path),
    device_cta as (select path,
        count(*) filter (where device_type='mobile')  as mob_cta,
        count(*) filter (where device_type='desktop') as dsk_cta
      from _eh where name in ('cta_phone_click','cta_booking_click') and path is not null and occurred_at >= now_ts - interval '28 days' group by path)
  select
    p.path,
    coalesce(o7.views,0), coalesce(o7.unique_visitors,0), coalesce(o7.sessions,0), coalesce(o7.bounce_rate,0),
    coalesce(o7.avg_dwell_seconds,0), coalesce(o7.scroll_avg,0), coalesce(o7.scroll_median,0), coalesce(o7.scroll_complete_pct,0),
    coalesce(o7.entry_count,0), coalesce(o7.exit_count,0), coalesce(o7.outbound_clicks,0),
    coalesce(o28.views,0), coalesce(o28.unique_visitors,0), coalesce(o28.sessions,0), coalesce(o28.bounce_rate,0),
    coalesce(o28.avg_dwell_seconds,0), coalesce(o28.scroll_avg,0), coalesce(o28.scroll_median,0), coalesce(o28.scroll_complete_pct,0),
    coalesce(o28.entry_count,0), coalesce(o28.exit_count,0), coalesce(o28.outbound_clicks,0),
    coalesce(o90.views,0), coalesce(o90.unique_visitors,0), coalesce(o90.sessions,0), coalesce(o90.bounce_rate,0),
    coalesce(o90.avg_dwell_seconds,0), coalesce(o90.scroll_avg,0), coalesce(o90.scroll_median,0), coalesce(o90.scroll_complete_pct,0),
    coalesce(o90.entry_count,0), coalesce(o90.exit_count,0), coalesce(o90.outbound_clicks,0),
    coalesce(o365.views,0), coalesce(o365.unique_visitors,0), coalesce(o365.sessions,0), coalesce(o365.bounce_rate,0),
    coalesce(o365.avg_dwell_seconds,0), coalesce(o365.scroll_avg,0), coalesce(o365.scroll_median,0), coalesce(o365.scroll_complete_pct,0),
    coalesce(o365.entry_count,0), coalesce(o365.exit_count,0), coalesce(o365.outbound_clicks,0),
    cwv.lcp_p75, cwv.inp_p75, cwv.cls_p75, cwv.ttfb_p75,
    top_ref.top_referrer, top_src.top_source, top_med.top_medium, dev.split,
    now_ts,
    coalesce(phone_counts.p7,0)::bigint, coalesce(phone_counts.p28,0)::bigint, coalesce(phone_counts.p90,0)::bigint, coalesce(phone_counts.p365,0)::bigint,
    coalesce(booking_counts.b7,0)::bigint, coalesce(booking_counts.b28,0)::bigint, coalesce(booking_counts.b90,0)::bigint, coalesce(booking_counts.b365,0)::bigint,
    coalesce(pogo.google_sessions,0)::bigint, coalesce(pogo.pogo_sticks,0)::bigint, coalesce(pogo.hard_pogo,0)::bigint, pogo.pogo_rate,
    coalesce(device_sessions.mob_s,0)::bigint, coalesce(device_sessions.dsk_s,0)::bigint,
    case when coalesce(device_sessions.mob_s,0)>0 then round(100.0*coalesce(device_cta.mob_cta,0)/device_sessions.mob_s,2) else null end,
    case when coalesce(device_sessions.dsk_s,0)>0 then round(100.0*coalesce(device_cta.dsk_cta,0)/device_sessions.dsk_s,2) else null end
  from all_paths p
    left join o7      on o7.path     = p.path
    left join o28     on o28.path    = p.path
    left join o90     on o90.path    = p.path
    left join o365    on o365.path   = p.path
    left join cwv     on cwv.path    = p.path
    left join top_ref on top_ref.path = p.path
    left join top_src on top_src.path = p.path
    left join top_med on top_med.path = p.path
    left join dev     on dev.path    = p.path
    left join phone_counts   on phone_counts.path   = p.path
    left join booking_counts on booking_counts.path = p.path
    left join pogo            on pogo.path            = p.path
    left join device_sessions on device_sessions.path = p.path
    left join device_cta      on device_cta.path      = p.path;
end;
$function$;
REVOKE ALL ON FUNCTION public.refresh_seo_url_snapshot() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_seo_url_snapshot() TO service_role;


CREATE OR REPLACE FUNCTION public.refresh_noise_sessions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET lock_timeout TO '15s'
 SET statement_timeout TO '300s'
AS $function$
begin
  CALL public.cooked_events_window(
    now() - interval '48 hours',
    now(),
    'raw',
    'main'
  );

  delete from public.noise_sessions
  where session_id in (
    select distinct session_id from _cooked_ev
    where session_id is not null
  );

  DROP TABLE IF EXISTS _no_bots;
  CREATE TEMP TABLE _no_bots ON COMMIT DROP AS
    SELECT e.id, e.anonymous_id, e.session_id, e.name, e.referrer_hostname,
           e.user_agent, e.device_type, e.occurred_at
    FROM _cooked_ev e
    WHERE NOT EXISTS (
      SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
    );
  ANALYZE _no_bots;

  insert into public.noise_sessions (session_id, reason)
  select
    session_id,
    'prefetch: 0 ref + 0 tick + 0 scroll + 0 intentional action + 1 pv + <10s'
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
  group by session_id
  having max(referrer_hostname) is null
     and count(*) filter (where name = 'engagement_tick') = 0
     and count(*) filter (where name = 'scroll_depth')    = 0
     and count(*) filter (where name IN ('cta_phone_click','cta_booking_click','cta_anchor_click',
                                         'click_internal','click_outbound','form_submit')) = 0
     and count(*) filter (where name = 'pageview')        = 1
     and extract(epoch from (max(occurred_at) - min(occurred_at))) < 10
  on conflict (session_id) do nothing;

  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'ua_bot: ' || (
      case
        -- T-04 (mission 02/09/2026, a-01) : UA littéral « pc » (bot Baidu) et SEBot-WA — miroir de BOT_UA_RE (Edge v28)
        when lower(user_agent) = 'pc'                   then 'pc'
        when user_agent ilike '%sebot%'                 then 'sebot'
        when user_agent ilike '%headless%'              then 'headless'
        when user_agent ilike '%googlebot%'             then 'googlebot'
        when user_agent ilike '%bingbot%'               then 'bingbot'
        when user_agent ilike '%applebot%'              then 'applebot'
        when user_agent ilike '%duckduckbot%'           then 'duckduckbot'
        when user_agent ilike '%yandexbot%'             then 'yandexbot'
        when user_agent ilike '%baiduspider%'           then 'baiduspider'
        when user_agent ilike '%gptbot%'                then 'gptbot'
        when user_agent ilike '%claudebot%'             then 'claudebot'
        when user_agent ilike '%perplexitybot%'         then 'perplexitybot'
        when user_agent ilike '%chatgpt-user%'          then 'chatgpt-user'
        when user_agent ilike '%googleother%'           then 'googleother'
        when user_agent ilike '%semrushbot%'            then 'semrushbot'
        when user_agent ilike '%ahrefsbot%'             then 'ahrefsbot'
        when user_agent ilike '%mj12bot%'               then 'mj12bot'
        when user_agent ilike '%dotbot%'                then 'dotbot'
        when user_agent ilike '%petalbot%'              then 'petalbot'
        when user_agent ilike '%bytespider%'            then 'bytespider'
        when user_agent ilike '%lighthouse%'            then 'lighthouse'
        when user_agent ilike '%pingdom%'               then 'pingdom'
        when user_agent ilike '%uptimerobot%'           then 'uptimerobot'
        when user_agent ilike '%gtmetrix%'              then 'gtmetrix'
        when user_agent ilike '%facebookexternalhit%'   then 'facebookexternalhit'
        when user_agent ilike '%linkedinbot%'           then 'linkedinbot'
        when user_agent ilike '%twitterbot%'            then 'twitterbot'
        when user_agent ilike '%discordbot%'            then 'discordbot'
        when user_agent ilike '%telegrambot%'           then 'telegrambot'
        when user_agent ilike '%slackbot%'              then 'slackbot'
        when user_agent ilike '%whatsapp/%'             then 'whatsapp-preview'
        when user_agent ilike '%crawler%'               then 'crawler'
        when user_agent ilike '%spider%'                then 'spider'
        when user_agent ilike '%axios/%'                then 'axios'
        when user_agent ilike '%curl/%'                 then 'curl'
        when user_agent ilike '%wget%'                  then 'wget'
        when user_agent ilike '%python%'                then 'python'
        when user_agent ilike '%go-http%'               then 'go-http'
        when user_agent ilike '%node-fetch%'            then 'node-fetch'
        when user_agent ilike '%httpclient%'            then 'httpclient'
        when user_agent ilike '%java/%'                 then 'java-http'
        else 'unknown'
      end
    )
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
    and user_agent is not null
    and (
         lower(user_agent) = 'pc'
      or user_agent ilike '%sebot%'
      or user_agent ilike '%headless%'
      or user_agent ilike '%googlebot%'
      or user_agent ilike '%bingbot%'
      or user_agent ilike '%applebot%'
      or user_agent ilike '%duckduckbot%'
      or user_agent ilike '%yandexbot%'
      or user_agent ilike '%baiduspider%'
      or user_agent ilike '%gptbot%'
      or user_agent ilike '%claudebot%'
      or user_agent ilike '%perplexitybot%'
      or user_agent ilike '%chatgpt-user%'
      or user_agent ilike '%googleother%'
      or user_agent ilike '%semrushbot%'
      or user_agent ilike '%ahrefsbot%'
      or user_agent ilike '%mj12bot%'
      or user_agent ilike '%dotbot%'
      or user_agent ilike '%petalbot%'
      or user_agent ilike '%bytespider%'
      or user_agent ilike '%lighthouse%'
      or user_agent ilike '%pingdom%'
      or user_agent ilike '%uptimerobot%'
      or user_agent ilike '%gtmetrix%'
      or user_agent ilike '%facebookexternalhit%'
      or user_agent ilike '%linkedinbot%'
      or user_agent ilike '%twitterbot%'
      or user_agent ilike '%discordbot%'
      or user_agent ilike '%telegrambot%'
      or user_agent ilike '%slackbot%'
      or user_agent ilike '%whatsapp/%'
      or user_agent ilike '%crawler%'
      or user_agent ilike '%spider%'
      or user_agent ilike '%axios/%'
      or user_agent ilike '%curl/%'
      or user_agent ilike '%wget%'
      or user_agent ilike '%python%'
      or user_agent ilike '%go-http%'
      or user_agent ilike '%node-fetch%'
      or user_agent ilike '%httpclient%'
      or user_agent ilike '%java/%'
    )
  on conflict (session_id) do nothing;

  -- T-04 (mission 02/09/2026, a-01 / c-06 / d-05) : referrer spam (cooked_is_spam_referrer) — la session entière
  -- est du bruit, quel que soit l'UA. Jusqu'ici seules les RPC filtraient ce referrer ; events_human ne le voyait pas.
  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'spam_referrer: ' || referrer_hostname
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
    and name = 'pageview'
    and public.cooked_is_spam_referrer(referrer_hostname)
  on conflict (session_id) do nothing;
end;
$function$;
REVOKE ALL ON FUNCTION public.refresh_noise_sessions() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_noise_sessions() TO service_role;


CREATE OR REPLACE FUNCTION public.alert_rule_page_taxonomy_gap()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_n  bigint;
  v_ex text;
BEGIN
  WITH vus AS (
    SELECT e.path, count(*) FILTER (WHERE e.name = 'pageview') AS pv, min(e.occurred_at) AS first_seen
    FROM public.events_human e
    WHERE e.path LIKE '/post/%'
      AND e.occurred_at > now() - interval '30 days'
      -- mêmes exclusions structurelles que refresh_page_taxonomy_heuristic (T-19)
      AND e.path NOT LIKE '%/preview/%'   -- previews Wix avec token
      AND e.path !~ 'https?://'           -- URLs concaténées par erreur
      AND e.path !~ '[ÃÂ]'                -- mojibake (double encodage)
      AND e.path !~ '%'                   -- restes d'URL-encoding
      AND length(e.path) <= 140
      -- T-15 (e-07) : un article = /post/<un seul segment de slug>, sans parenthèse ;
      -- exclut les URL de point focal d'image Wix (/post/fp_0.50_0.50/<hex>~mv2.png)
      AND e.path ~ '^/post/[^/()]+$'
      AND e.path !~ '/fp_[0-9.]+_[0-9.]+/'
    GROUP BY e.path
    HAVING count(*) FILTER (WHERE e.name = 'pageview') >= 5
  )
  SELECT count(*), string_agg(v.path, ', ' ORDER BY v.pv DESC)
    INTO v_n, v_ex
  FROM vus v
  LEFT JOIN public.page_taxonomy t ON t.path = v.path
  WHERE (t.path IS NULL OR t.category IS NULL)
    -- la synchro hebdomadaire (wix-taxonomy-sync) a eu au moins une occasion de passer
    AND v.first_seen < now() - interval '8 days';

  IF v_n >= 1 THEN
    RETURN QUERY SELECT
      'page_taxonomy_gap'::text,
      CASE WHEN v_n >= 10 THEN 'critical' ELSE 'warn' END::text,
      format(
        '%s article(s) avec du trafic (≥ 5 vues/30 j, vus depuis > 8 j) sans catégorie Wix dans page_taxonomy — toute lecture par catégorie (dashboard Articles Ressources, content_performance, contrat éditorial) les ignore. Vérifier les chemins (page réelle, redirection ou URL tronquée), leur catégorie Wix et le dernier workflow wix-taxonomy-sync (lundi 05:00 UTC). Une synchro réussie peut conserver une URL sans catégorie ; ne pas déduire un secret manquant de cette seule alerte. Concernés : %s',
        v_n, left(coalesce(v_ex, ''), 400)
      );
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.alert_rule_page_taxonomy_gap() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_page_taxonomy_gap() TO service_role;


CREATE OR REPLACE FUNCTION public.site_seo_funnel(period_kind text DEFAULT 'rolling_28'::text)
 RETURNS TABLE(period_start date, period_end date, impressions bigint, clicks bigint, google_sessions bigint, macro_contacts bigint, impr_to_click_pct numeric, click_to_session_pct numeric, session_to_contact_pct numeric, overall_impr_to_contact_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'site_seo_funnel is deprecated: its former rates mixed incompatible acquisition scopes'
    USING ERRCODE='0A000', HINT='Use public.seo_to_contact_funnel(days_back, p_end), with its explicit organic_entries, contacts and window bounds.';
END;
$function$;
REVOKE ALL ON FUNCTION public.site_seo_funnel(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.site_seo_funnel(text) TO service_role;


COMMENT ON FUNCTION public.site_seo_funnel(text) IS 'Deprecated 20/10/2026: use seo_to_contact_funnel; no silent alias of organic_entries as google_sessions.';

-- Les 8 helpers SQL purs INVOKER sans search_path restent inlinables.
-- Voir C6b et mission-2026-09-02 : SET search_path désactive l'inlining de
-- paris_date/paris_today et rend idx_events_paris_date inutilisable. Les appels
-- internes métier sont qualifiés et leurs appelants DEFINER pinent search_path.
-- Leurs avertissements advisor sont documentés, sans privilège supplémentaire.


-- I10 : badge macro corrigé, CWV au grain document avec mises à jour.
-- Le modèle CPI et son poids de booking restent inchangés. Les médianes
-- Ressources et positions de fiche sont corrigées hors calcul du score.
INSERT INTO public.cooked_config(key,value,updated_at)
VALUES('cpi_definition_version','2.2.6',now())
ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at;
INSERT INTO public.annotations(day,kind,label,paths)
VALUES(date '2026-10-20','autre',
'Restatement du 20/10/2026 (définition CPI 2.2.6) : badge convertit réservé aux contacts macro organiques directs/assistés ; le score conserve 0,25 × intentions de rendez-vous, désormais bornées à la même fenêtre close que ses autres composantes (exclusion des clics hors période appartenant à une même session). CWV : une observation finale par document et métrique, révisions dédupliquées ; le tracker corrigé attribue les sorties SPA à leur page réelle. Hors CPI : médianes Ressources sans referrer réintégrées, positions des fiches pondérées par impressions, identifiants Ads des Expertises pris en compte. Fenêtre canonique, pondérations du score et contacts bruts inchangés ; application de la borne de fenêtre réparée pour les intentions de rendez-vous. Historique conservé, ne pas interpréter la rupture comme un gain ou un decay.',NULL);
COMMIT;
