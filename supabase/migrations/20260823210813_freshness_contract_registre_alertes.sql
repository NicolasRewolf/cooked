-- ═══════════════════════════════════════════════════════════════════════════
-- Chantier 1 (revue d'architecture du 22/08/2026) — le contrat de fraîcheur
-- devient un REGISTRE : une ligne de données par source, UNE règle générique.
-- ADR-0002. Déclencheur : deux pannes silencieuses (webhook forms mort le
-- 11/08 sans alerte ; cron GBP mort le 08/08, poussé sur ntfy à J+14).
--
-- Contenu :
--   1. Table public.freshness_contract (service_role only) — le registre.
--   2. alert_rule_freshness() — fraîcheur (<source>_stale), trous
--      (<source>_gap), table vide ; remplace 5 règles copiées-collées.
--   3. alert_rule_warn_escalation() — un warn ininterrompu ≥ 5 jours devient
--      critical (décision Nicolas 22/08). Acker la dernière alerte du kind
--      stoppe l'escalade ET le re-push (acked redevient porteur de sens).
--   4. raise_cooked_alert : dédup par (kind, severity) — l'escalade
--      warn→critical n'attend plus l'expiration de la fenêtre 24 h ; le push
--      d'un critical est supprimé si la dernière alerte du kind est ackée.
--   5. cooked_alerts_refresh : découverte dynamique des alert_rule_* par
--      catalogue + isolation par règle (une règle qui plante n'annule plus
--      le tick : elle devient elle-même une alerte).
--   6. DROP des règles absorbées (gbp_gap, gsc_gap, dfs_stale, cpi_stale,
--      gsc_lag→gsc_ingest_missed, dashboard_check_stale + son cron).
--   7. Le registre : 13 sources sous contrat, dont les invisibles de la
--      panne A (form_submit, crm_prospects, cta_phone_click).
--   8. SET statement_timeout sur cooked-alerts-hourly (le watchdog était
--      tuable par le mode de panne qui a tué run_rpc_contract_tests 23 j).
--   9. REVOKE systématique sur toutes les alert_rule_* (récidive close).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Le registre ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.freshness_contract (
  source              text PRIMARY KEY,
  label               text NOT NULL,
  -- Fragment SQL renvoyant UNE date : le dernier jour (Paris) de donnée.
  -- Exécuté par alert_rule_freshness (SECURITY DEFINER) — la table est
  -- service_role only, au même titre qu'une migration.
  last_point_sql      text NOT NULL,
  cadence             text NOT NULL DEFAULT 'daily',   -- documentaire : daily|weekly|event
  normal_lag_days     int  NOT NULL DEFAULT 0,
  warn_after_days     int  NOT NULL,
  critical_after_days int,                             -- NULL = jamais critical par l'âge
  gap_relation        text,                            -- si non NULL : détection de trous
  gap_day_column      text,
  gap_window_days     int,
  repair_hint         text,
  enabled             boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.freshness_contract ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.freshness_contract FROM PUBLIC, anon, authenticated;

-- ── 2. La règle générique ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.alert_rule_freshness()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  c         record;
  v_last    date;
  v_age     int;
  v_sev     text;
  v_missing int;
  v_days    text;
BEGIN
  FOR c IN SELECT * FROM public.freshness_contract WHERE enabled ORDER BY source LOOP
    BEGIN
      EXECUTE c.last_point_sql INTO v_last;

      IF v_last IS NULL THEN
        kind := c.source || '_stale'; severity := 'critical';
        detail := format('%s : aucune donnée (table vide ?). %s',
                         c.label, coalesce(c.repair_hint, ''));
        RETURN NEXT;
        CONTINUE;
      END IF;

      v_age := public.paris_today() - v_last;
      v_sev := CASE
        WHEN c.critical_after_days IS NOT NULL AND v_age > c.critical_after_days THEN 'critical'
        WHEN v_age > c.warn_after_days THEN 'warn'
        ELSE NULL
      END;

      IF v_sev IS NOT NULL THEN
        kind := c.source || '_stale'; severity := v_sev;
        detail := format(
          '%s : dernier jour de donnée %s (J-%s ; lag normal ~J-%s, warn > %s j%s). %s',
          c.label, to_char(v_last, 'DD/MM/YYYY'), v_age, c.normal_lag_days,
          c.warn_after_days,
          CASE WHEN c.critical_after_days IS NOT NULL
               THEN ', critical > ' || c.critical_after_days || ' j' ELSE '' END,
          coalesce(c.repair_hint, ''));
        RETURN NEXT;
      END IF;

      -- Trous à l'intérieur de la série, sur [last_point - fenêtre, last_point].
      IF c.gap_relation IS NOT NULL AND c.gap_day_column IS NOT NULL
         AND c.gap_window_days IS NOT NULL THEN
        EXECUTE format(
          'SELECT count(*)::int, string_agg(to_char(d.d::date, %L), '', '' ORDER BY d.d) '
          'FROM generate_series(%L::date, %L::date, interval ''1 day'') d(d) '
          'LEFT JOIN (SELECT DISTINCT %I AS day FROM public.%I '
          '           WHERE %I BETWEEN %L AND %L) t ON t.day = d.d::date '
          'WHERE t.day IS NULL',
          'DD/MM', v_last - c.gap_window_days, v_last,
          c.gap_day_column, c.gap_relation, c.gap_day_column,
          v_last - c.gap_window_days, v_last
        ) INTO v_missing, v_days;
        IF v_missing > 0 THEN
          kind := c.source || '_gap'; severity := 'warn';
          detail := format('%s : %s jour(s) manquant(s) entre le %s et le %s : %s',
                           c.label, v_missing,
                           to_char(v_last - c.gap_window_days, 'DD/MM'),
                           to_char(v_last, 'DD/MM'), left(v_days, 300));
          RETURN NEXT;
        END IF;
      END IF;

    EXCEPTION WHEN others THEN
      kind := c.source || '_contract_failed'; severity := 'critical';
      detail := format('Contrat de fraîcheur « %s » en échec : %s',
                       c.source, left(SQLERRM, 300));
      RETURN NEXT;
    END;
  END LOOP;
END;
$function$;

-- ── 3. Escalade générique warn → critical (+5 jours) ────────────────────────
-- Tous kinds confondus (fraîcheur, cpi_drop, tracker_drift, …). Critère :
-- warn émis dans les dernières 26 h ET l'épisode dure depuis ≥ 5 jours
-- (un warn entre J-6 et J-5, ≥ 4 warns sur 5 j — les règles réémettent
-- ~1/jour tant que la condition tient). Acker N'IMPORTE quelle alerte du
-- kind depuis 5 j suspend l'escalade (« vu, je gère »).
CREATE OR REPLACE FUNCTION public.alert_rule_warn_escalation()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  SELECT a.kind,
         'critical'::text,
         'Escalade : warn actif depuis ≥ 5 jours sans acquittement — ' || a.detail
  FROM (
    SELECT DISTINCT ON (kind) kind, detail
    FROM public.alerts
    WHERE severity = 'warn' AND created_at > now() - interval '26 hours'
    ORDER BY kind, created_at DESC
  ) a
  WHERE EXISTS (
      SELECT 1 FROM public.alerts w
      WHERE w.kind = a.kind AND w.severity = 'warn'
        AND w.created_at BETWEEN now() - interval '6 days' AND now() - interval '5 days')
    AND (SELECT count(*) FROM public.alerts w
         WHERE w.kind = a.kind AND w.severity = 'warn'
           AND w.created_at > now() - interval '5 days') >= 4
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts c
      WHERE c.kind = a.kind AND c.severity = 'critical'
        AND c.created_at > now() - interval '26 hours')
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts k
      WHERE k.kind = a.kind AND k.acked
        AND k.created_at > now() - interval '5 days');
$function$;

-- ── 4. raise_cooked_alert : dédup (kind, severity) + respect de l'ack ──────
CREATE OR REPLACE FUNCTION public.raise_cooked_alert(p_kind text, p_sev text, p_detail text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_topic      text;
  v_last_acked boolean;
begin
  -- Dédup par (kind, severity) — et non plus par kind seul : le passage
  -- warn→critical d'un même kind s'insère (et pousse) immédiatement au lieu
  -- d'attendre jusqu'à 24 h l'expiration de la fenêtre du warn.
  if exists (
    select 1 from public.alerts
    where kind = p_kind
      and severity = p_sev
      and created_at > now() - interval '24 hours'
  ) then
    return 0;
  end if;

  -- La dernière alerte du kind est-elle acquittée ? (à lire AVANT l'insert)
  select a.acked into v_last_acked
  from public.alerts a
  where a.kind = p_kind
  order by a.created_at desc
  limit 1;

  insert into public.alerts (kind, severity, detail) values (p_kind, p_sev, p_detail);

  -- Push ntfy : critical uniquement, et pas si l'épisode est acquitté
  -- (l'insert a toujours lieu — seule la notification se tait).
  if p_sev = 'critical' and coalesce(v_last_acked, false) = false then
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
      null;
    end;
  end if;

  return 1;
end;
$function$;

-- ── 5. Le driver : découverte dynamique + isolation par règle ───────────────
-- Une nouvelle règle est active du seul fait d'exister (fin des 4 éditions) ;
-- une règle qui plante n'annule plus le tick entier — elle devient une
-- alerte <règle>_crashed. alert_rule_warn_escalation passe en dernier
-- (ordre alphabétique) et voit donc les warns du tick courant.
CREATE OR REPLACE FUNCTION public.cooked_alerts_refresh()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  p       record;
  r       record;
  v_added int := 0;
BEGIN
  FOR p IN
    SELECT pr.proname
    FROM pg_proc pr
    JOIN pg_namespace n ON n.oid = pr.pronamespace
    WHERE n.nspname = 'public'
      AND pr.proname LIKE 'alert\_rule\_%'
      AND pr.pronargs = 0
    ORDER BY pr.proname
  LOOP
    BEGIN
      FOR r IN EXECUTE format('SELECT kind, severity, detail FROM public.%I()', p.proname) LOOP
        v_added := v_added + public.raise_cooked_alert(r.kind, r.severity, r.detail);
      END LOOP;
    EXCEPTION WHEN others THEN
      v_added := v_added + public.raise_cooked_alert(
        p.proname || '_crashed', 'critical',
        format('La règle %s a levé une exception : %s', p.proname, left(SQLERRM, 300)));
    END;
  END LOOP;
  RETURN v_added;
END;
$function$;

-- ── 6. Absorption des règles copiées-collées ────────────────────────────────
DROP FUNCTION IF EXISTS public.alert_rule_gbp_gap();
DROP FUNCTION IF EXISTS public.alert_rule_gsc_gap();
DROP FUNCTION IF EXISTS public.alert_rule_dfs_stale();
DROP FUNCTION IF EXISTS public.alert_rule_cpi_stale();
DROP FUNCTION IF EXISTS public.alert_rule_gsc_lag();
DROP FUNCTION IF EXISTS public.dashboard_check_stale();

-- La branche « l'ingestion GSC n'est pas passée ce matin » de gsc_lag portait
-- sur l'EXÉCUTION, pas la donnée — conservée telle quelle (horloge C6) en
-- attendant le chantier 2 (battement d'exécution), qui l'absorbera.
CREATE OR REPLACE FUNCTION public.alert_rule_gsc_ingest_missed()
RETURNS TABLE(kind text, severity text, detail text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_last_ingest date;
BEGIN
  -- Le cron GSC tourne à 06:00 UTC ; on ne juge qu'après 13:00 Paris.
  IF (now() AT TIME ZONE 'Europe/Paris')::time < time '13:00' THEN  -- garde HORAIRE Paris : paris_today() ne porte pas l'heure (C6 ok)
    RETURN;
  END IF;
  SELECT public.paris_date(max(ingested_at)) INTO v_last_ingest
  FROM public.gsc_path_daily;
  IF v_last_ingest IS DISTINCT FROM public.paris_today() THEN
    kind := 'gsc_ingest_missed'; severity := 'warn';
    detail := format(
      'Ingestion GSC absente aujourd''hui (dernière : %s) — vérifier le workflow gsc-daily-ingest.',
      coalesce(to_char(v_last_ingest, 'DD/MM/YYYY'), 'jamais'));
    RETURN NEXT;
  END IF;
END;
$function$;

DO $$
BEGIN
  PERFORM cron.unschedule('dashboard-stale-check');
EXCEPTION WHEN others THEN NULL;
END $$;

-- ── 7. Le registre : 13 sources sous contrat ────────────────────────────────
INSERT INTO public.freshness_contract
  (source, label, last_point_sql, cadence, normal_lag_days,
   warn_after_days, critical_after_days,
   gap_relation, gap_day_column, gap_window_days, repair_hint, enabled)
VALUES
  ('gbp_daily', 'Appels fiche Google (GBP)',
   'SELECT max(day) FROM public.gbp_daily',
   'daily', 4, 7, 14, NULL, NULL, NULL,
   'Reauth ADC probable : gcloud auth application-default login --scopes=business.manage,cloud-platform (les DEUX), puis re-pousser GBP_CREDENTIALS_B64 et relancer gbp-daily-ingest.', true),

  ('gsc_path_daily', 'Search Console (clics/impressions par page)',
   'SELECT max(day) FROM public.gsc_path_daily',
   'daily', 3, 6, 10, 'gsc_path_daily', 'day', 90,
   'Vérifier le workflow gsc-daily-ingest (secret GSC_CREDENTIALS_B64) ; relancer avec --months 2 pour reboucher.', true),

  ('gsc_query_daily', 'Search Console (requêtes)',
   'SELECT max(day) FROM public.gsc_query_daily',
   'daily', 3, 6, 12, NULL, NULL, NULL,
   'Même ingest que gsc_path_daily (gsc-daily-ingest).', true),

  ('gsc_query_page_daily', 'Search Console (requête × page)',
   'SELECT max(day) FROM public.gsc_query_page_daily',
   'daily', 3, 6, 12, NULL, NULL, NULL,
   'Même ingest que gsc_path_daily (gsc-daily-ingest).', true),

  ('dfs_keyword_volume', 'Volumes DataForSEO',
   'SELECT public.paris_date(max(last_synced_at)) FROM public.dfs_keyword_volume',
   'weekly', 7, 10, 21, NULL, NULL, NULL,
   'Vérifier le workflow dfs-weekly-sync (DFS_USERNAME/DFS_PASSWORD) ou relancer dfs_sync.py --limit 500 en CI.', true),

  ('cpi_daily', 'Snapshot CPI quotidien',
   'SELECT max(day) FROM public.cpi_daily',
   'daily', 1, 1, 2, 'cpi_daily', 'day', 7,
   'Vérifier le job pg_cron cooked-cpi-daily-snapshot (07:30 UTC) et cooked_cpi_snapshot().', true),

  ('seo_url_snapshot', 'Snapshot SEO nocturne',
   'SELECT public.paris_date(max(refreshed_at)) FROM public.seo_url_snapshot',
   'daily', 1, 1, 2, NULL, NULL, NULL,
   'Vérifier le job pg_cron refresh_seo_url_snapshot (03:00 UTC) — retex timeouts : SET statement_timeout dans la COMMANDE cron.', true),

  ('dashboard_resources_snapshot', 'Snapshots dashboard (ressources)',
   'SELECT public.paris_date(max(refreshed_at)) FROM public.dashboard_resources_snapshot',
   'daily', 1, 1, 3, NULL, NULL, NULL,
   'Vérifier les jobs pg_cron refresh-dashboard-* (04:00-04:16 UTC) et cooked-refresh-after-gsc.', true),

  ('form_submit', 'Formulaires (webhook Wix → events)',
   'SELECT public.paris_date(max(occurred_at)) FROM public.events WHERE name = ''form_submit''',
   'event', 0, 2, 4, NULL, NULL, NULL,
   'Vérifier l''automation Wix « ⚠️ Cooked analytics — form → webhook » (supprimée une fois le 11/08/2026 !), puis rejouer la réconciliation (scripts/wix_forms_import.py + backfill events).', true),

  ('crm_prospects', 'Prospects (pont SECIB)',
   'SELECT public.paris_date(max(occurred_at)) FROM public.crm_prospects',
   'event', 0, 2, 4, NULL, NULL, NULL,
   'Jumeau de form_submit : si form_submit est frais mais pas crm_prospects, la capture prospect du webhook v13 est cassée (logs form-webhook).', true),

  ('cta_phone_click', 'Clics téléphone (tracker)',
   'SELECT public.paris_date(max(occurred_at)) FROM public.events WHERE name = ''cta_phone_click''',
   'event', 0, 2, 4, NULL, NULL, NULL,
   'Le flux global events est-il vivant (pipeline_dead) ? Si oui : tracker déployé cassé sur les CTA — vérifier expected_tracker_version et le Custom Code Wix.', true),

  ('math_visit_sequences_snapshot', 'Snapshots analyse mathématique',
   'SELECT public.paris_date(max(computed_at)) FROM public.math_visit_sequences_snapshot',
   'weekly', 7, 9, 16, NULL, NULL, NULL,
   'Vérifier le job pg_cron math-refresh-snapshots-weekly (dimanche 05:10 UTC).', true),

  ('secib_dossiers', 'Dossiers SECIB',
   'SELECT public.paris_date(max(synced_at)) FROM public.secib_dossiers',
   'daily', 1, 3, 7, NULL, NULL, NULL,
   'Cron SECIB à créer après signature du devis SECIB+ (ROADMAP #9) — contrat pré-armé, désactivé d''ici là.', false)
ON CONFLICT (source) DO NOTHING;

-- ── 8. statement_timeout sur les crons d'alerte (retex run_rpc_contract_tests
--       mort 23 jours au timeout par défaut de 120 s) ──────────────────────
DO $$
DECLARE
  jid bigint;
BEGIN
  SELECT jobid INTO jid FROM cron.job WHERE jobname = 'cooked-alerts-hourly';
  IF jid IS NOT NULL THEN
    PERFORM cron.alter_job(jid,
      command => 'SET statement_timeout = ''300s''; SELECT public.cooked_alerts_refresh();');
  END IF;
END $$;

-- ── 9. ACL : aucune alert_rule_* ni le registre exposés à anon/authenticated
--       (récidive des REVOKE oubliés — close par balayage systématique) ────
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT pr.proname
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
    WHERE n.nspname = 'public' AND pr.proname LIKE 'alert\_rule\_%' AND pr.pronargs = 0
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I() FROM PUBLIC, anon, authenticated', f.proname);
  END LOOP;
  REVOKE ALL ON FUNCTION public.cooked_alerts_refresh() FROM PUBLIC, anon, authenticated;
  REVOKE ALL ON FUNCTION public.raise_cooked_alert(text, text, text) FROM PUBLIC, anon, authenticated;
END $$;
