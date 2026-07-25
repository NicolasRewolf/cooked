-- Observabilité : surveiller l'exécution des crons, la fraîcheur du CPI,
-- et rendre l'acquittement des alertes possible.
--
-- CONTEXTE (revue d'architecture du 25/07/2026, cause racine R1)
-- -------------------------------------------------------------
-- Le 24/07/2026, le cron `cooked-refresh-after-gsc` a échoué toutes les heures
-- pendant 14 heures (disque plein) et `run_rpc_contract_tests` échouait déjà
-- depuis 21 jours. Aucune alerte n'a été levée, et `refresh_pipeline_health()`
-- répondait `healthy` : les 9 règles `alert_rule_*` ne lisent JAMAIS
-- `cron.job_run_details`. L'incident a été découvert par hasard, à l'occasion
-- d'un audit.
--
-- Trois défauts distincts sont corrigés ici.
--
-- 1. AUCUNE SURVEILLANCE DE L'EXÉCUTION DES TÂCHES
--    -> alert_rule_cron_failed() : le dernier run d'un job actif est en échec.
--    -> alert_rule_cpi_stale()   : cpi_daily a pris du retard.
--    Le CPI mérite sa propre règle : c'est la seule donnée irrécupérable du
--    système (cooked_page_index lit now(), sans paramètre de date de fin —
--    un jour non calculé l'est définitivement). 9 jours ont déjà été perdus.
--
-- 2. ACQUITTER UNE ALERTE LA RÉ-ARME
--    La dédup de raise_cooked_alert exigeait `not acked` :
--        if exists (select 1 from alerts
--                   where kind = p_kind and not acked
--                     and created_at > now() - interval '24 hours')
--    Donc acquitter faisait réapparaître l'alerte au tick horaire suivant.
--    Acquitter était puni ; le canal est mort de lui-même (23 alertes non
--    acquittées, la plus ancienne du 30/06/2026). La dédup porte désormais sur
--    `kind` seul : acquitter fait taire jusqu'au lendemain, et si la condition
--    persiste au-delà de 24 h l'alerte revient — ce qui est le comportement
--    voulu.
--
-- 3. latest_rpc_health() AFFIRME `ok` SUR UNE MESURE PÉRIMÉE
--    Elle renvoyait le dernier état connu sans jamais dire son âge en clair.
--    Résultat : `ok` affiché sur un instantané du 04/07 alors que les contract
--    tests échouaient depuis 21 jours — le réflexe prescrit par CONTRIBUTING.md
--    donnait un feu vert explicite à une régression. Le statut devient `stale`
--    au-delà de 48 h.
--
-- CE QUE CETTE MIGRATION NE FAIT PAS
-- ----------------------------------
-- Le push ntfy n'est pas modifié : `pg_net` est installé, `cooked_config.ntfy_topic`
-- est renseigné, et 4 règles savent déjà émettre `critical`. Mais AUCUNE alerte
-- `critical` n'a jamais été levée (les 52 lignes d'`alerts` sont des `warn`), donc
-- le chemin n'a jamais été exercé et son état réel est INCONNU. Il se teste, il ne
-- se répare pas à l'aveugle — protocole de test dans le commentaire final.
-- Les deux nouvelles règles émettent `critical`, ce qui exercera ce chemin dès la
-- prochaine panne réelle.

-- ── 1. Dernier run d'un cron actif en échec ────────────────────────────────
CREATE OR REPLACE FUNCTION public.alert_rule_cron_failed()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'cron', 'pg_catalog'
AS $function$
DECLARE v_list text;
BEGIN
  -- Dernier run de chaque job actif ; on ne retient que les échecs récents
  -- (7 jours) pour ne pas alerter éternellement sur un job abandonné.
  SELECT string_agg(
           x.jobname || ' (' || to_char(x.start_time AT TIME ZONE 'Europe/Paris', 'DD/MM HH24:MI')
           || ' — ' || left(regexp_replace(coalesce(x.return_message, 'sans message'), '\s+', ' ', 'g'), 90) || ')',
           ' | ' ORDER BY x.start_time DESC)
    INTO v_list
  FROM (
    SELECT j.jobname, d.status, d.return_message, d.start_time
    FROM cron.job j
    JOIN LATERAL (
      SELECT dd.status, dd.return_message, dd.start_time
      FROM cron.job_run_details dd
      WHERE dd.jobid = j.jobid
      ORDER BY dd.start_time DESC
      LIMIT 1
    ) d ON true
    WHERE j.active
      AND d.status = 'failed'
      AND d.start_time > now() - interval '7 days'
  ) x;

  IF v_list IS NOT NULL THEN
    RETURN QUERY SELECT
      'cron_failed'::text,
      'critical'::text,
      ('Tâche(s) planifiée(s) en échec au dernier passage : ' || v_list)::text;
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.alert_rule_cron_failed() IS
  'Alerte si le DERNIER run d un cron actif est en echec (fenetre 7 jours). Comble le trou qui a laisse cooked-refresh-after-gsc echouer 14 h et run_rpc_contract_tests 21 jours sans signal.';

-- ── 2. cpi_daily en retard ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.alert_rule_cpi_stale()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last date;
  v_lag  int;
BEGIN
  SELECT max(day) INTO v_last FROM public.cpi_daily;

  IF v_last IS NULL THEN
    RETURN QUERY SELECT 'cpi_stale'::text, 'critical'::text,
      'cpi_daily est vide — le snapshot CPI n a jamais tourné.'::text;
    RETURN;
  END IF;

  v_lag := public.paris_today() - v_last;  -- foyer unique, cf. contrat C6

  -- 1 jour de retard est normal (le snapshot suit l ingestion GSC du jour).
  IF v_lag >= 2 THEN
    RETURN QUERY SELECT
      'cpi_stale'::text,
      'critical'::text,
      ('cpi_daily s arrête au ' || to_char(v_last, 'DD/MM/YYYY') || ' (' || v_lag
       || ' jours de retard) — un jour de CPI non calculé est perdu définitivement.')::text;
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.alert_rule_cpi_stale() IS
  'Alerte si cpi_daily a au moins 2 jours de retard. Le CPI est la seule donnee irrecuperable du systeme : cooked_page_index lit now() et n a pas de parametre de date de fin, un jour manque ne se rattrape pas.';

-- ── 3. Brancher les deux règles ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cooked_alerts_refresh()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  r record;
  v_added int := 0;
BEGIN
  FOR r IN
    SELECT * FROM public.alert_rule_pipeline_dead()
    UNION ALL SELECT * FROM public.alert_rule_cron_failed()
    UNION ALL SELECT * FROM public.alert_rule_cpi_stale()
    UNION ALL SELECT * FROM public.alert_rule_double_embed_suspect()
    UNION ALL SELECT * FROM public.alert_rule_rpc_health()
    UNION ALL SELECT * FROM public.alert_rule_form_attribution_degraded()
    UNION ALL SELECT * FROM public.alert_rule_gsc_lag()
    UNION ALL SELECT * FROM public.alert_rule_gsc_gap()
    UNION ALL SELECT * FROM public.alert_rule_cpi_drop()
    UNION ALL SELECT * FROM public.alert_rule_dfs_stale()
    UNION ALL SELECT * FROM public.alert_rule_tracker_drift()
  LOOP
    v_added := v_added + public.raise_cooked_alert(r.kind, r.severity, r.detail);
  END LOOP;
  RETURN v_added;
END;
$function$;

-- ── 4. Acquitter ne doit plus ré-armer ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.raise_cooked_alert(p_kind text, p_sev text, p_detail text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_topic text;
begin
  -- Dédup sur `kind` SEUL (et non plus `kind AND not acked`) : acquitter une
  -- alerte ne la fait plus réapparaître au tick suivant. Si la condition
  -- persiste au-delà de 24 h, une nouvelle alerte est levée — voulu.
  if exists (
    select 1 from public.alerts
    where kind = p_kind
      and created_at > now() - interval '24 hours'
  ) then
    return 0;
  end if;

  insert into public.alerts (kind, severity, detail) values (p_kind, p_sev, p_detail);

  -- Push ntfy : uniquement sur un VRAI insert + severity critical + topic non-vide.
  -- Entièrement défensif : toute erreur est avalée, l'alerte reste posée, retour = 1.
  if p_sev = 'critical' then
    begin
      select nullif(btrim(value), '') into v_topic
      from public.cooked_config where key = 'ntfy_topic';

      if v_topic is not null then
        perform net.http_post(
          url     := 'https://ntfy.sh/',
          body    := jsonb_build_object(
                       'topic',    v_topic,
                       'title',    'Cooked : alerte critique',
                       'message',  left(coalesce(p_detail, p_kind), 4000),
                       'priority', 5,
                       'tags',     jsonb_build_array('rotating_light')
                     ),
          headers := '{"Content-Type": "application/json"}'::jsonb
        );
      end if;
    exception when others then
      null; -- ne jamais laisser le push casser l'alerte
    end;
  end if;

  return 1;
end;
$function$;

-- ── 5. latest_rpc_health() dit son âge ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.latest_rpc_health()
RETURNS TABLE(rpc_name text, status text, detail text, rows_returned bigint,
              duration_ms numeric, checked_at timestamp with time zone, age_minutes numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  select distinct on (h.rpc_name)
    h.rpc_name,
    -- Une mesure de plus de 48 h ne prouve plus rien : le contract test tourne
    -- toutes les nuits. Au-delà, le statut devient `stale` plutôt que de
    -- réafficher un `ok` périmé (cas réel : `ok` du 04/07 affiché pendant
    -- 21 jours d échecs consécutifs).
    case when h.checked_at < now() - interval '48 hours'
         then 'stale'
         else h.status
    end as status,
    case when h.checked_at < now() - interval '48 hours'
         then 'mesure du ' || to_char(h.checked_at AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI')
              || ' — le contract test n a pas tourné depuis, statut réel inconnu. Dernier état connu : '
              || coalesce(h.status, 'null') || '. ' || coalesce(h.detail, '')
         else h.detail
    end as detail,
    h.rows_returned,
    h.duration_ms,
    h.checked_at,
    round(extract(epoch from (now() - h.checked_at)) / 60, 1) as age_minutes
  from public.rpc_health h
  order by h.rpc_name, h.checked_at desc;
$function$;

-- ── 6. Vider le stock d'alertes rendu ininterprétable par l'ancien bug ─────
-- Les 23 alertes non acquittées décrivent des conditions soit résolues
-- aujourd'hui (dashboard gelé, CPI en retard), soit répétées à l'identique
-- chaque jour faute de pouvoir être acquittées. On acquitte tout ce qui a plus
-- de 24 h ; avec la dédup corrigée, toute condition encore vraie ré-alertera
-- au prochain passage horaire.
UPDATE public.alerts
SET acked = true
WHERE NOT acked
  AND created_at < now() - interval '24 hours';

-- ── PROTOCOLE DE TEST DU PUSH ntfy (à jouer une fois, manuellement) ────────
--   SELECT public.raise_cooked_alert('ntfy_selftest', 'critical', 'Test du canal');
--   SELECT id, status_code, created FROM net._http_response ORDER BY id DESC LIMIT 3;
--   UPDATE public.alerts SET acked = true WHERE kind = 'ntfy_selftest';
-- Un status_code 200 prouve que le canal fonctionne. Aucune ligne dans
-- net._http_response = le push n'est jamais parti.
