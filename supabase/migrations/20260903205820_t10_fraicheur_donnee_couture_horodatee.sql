-- T-10 (mission 02/09/2026, #111) — fraîcheur mesurée sur la donnée, couture horodatée.
-- Constats g-03 (P1), c-02 (P1), c-04, e-06 (partie registre). Invariant I7.
--
-- Mesure avant (03/09/2026 23:00 Paris) :
--   · freshness_contract.dashboard_resources_snapshot lisait paris_date(max(refreshed_at)) : un
--     instantané recalculé à chaque séquence sur des données arrêtées à J-2 restait « frais ».
--     Le 28/08 la séquence est partie à 19:00 UTC : la home a affiché J-2 en vert toute la journée.
--   · identity_stitch : DELETE + INSERT nocturne sans horodatage ; seule trace = cron.job_run_details
--     (30 j : 30 succès, 17-25 s) ; une couture vidée serait « succeeded » ; aucune alerte, aucun
--     contrat ; cooked_config sans clé identity_stitch_* (5 clés).
--   · Couverture mesurée à 22:50 Paris : J-1 (02/09) 429/429 sessions humaines cousues ;
--     J-2 416/416 (requête 0,5 s).
--   · page_taxonomy hors registre (dernière synchro Wix 31/08 11:05, 437/456 lignes catégorisées).
--
-- Changement :
--   1. registre : dashboard_resources_snapshot mesuré sur max(cooked_end) — la FIN DES DONNÉES,
--      plus l'heure du calcul. Lag normal 1 j (J-1 après la séquence de l'après-midi) ; warn à 3 j
--      (deux séquences manquées), critical à 5 j. Le grain horaire (« J-2 après 16 h ») reste aux
--      alertes T-11 (gsc_ingest_missed, refresh_after_gsc_stale). page_taxonomy entre au registre.
--   2. refresh_identity_stitch() horodate sa fin dans cooked_config (identity_stitch_refreshed_at,
--      identity_stitch_rows) ; clé amorcée depuis le dernier succès du cron.
--   3. alert_rule_identity_stitch() : table vide (critical) ; horodatage absent (critical), > 30 h
--      (warn), > 54 h (critical) ; sessions humaines de J-1 hors couture après la reconstruction du
--      jour (warn).
--   4. contract-tests I7 identity_stitch_couvre_j2 (= 0) et identity_stitch_horodatee (= 1).
--   5. Dashboard (hors SQL, même PR) : FreshnessBanner passe orange sur la fin des données
--      (cooked_end à J-3, ou J-2 après 16 h Paris), plus seulement sur l'âge du calcul.
-- Constat de cadrage c-04 (jour en cours non cousu) : depuis T-08/T-09 aucun consommateur en
-- périmètre ne lit identity_stitch sur le jour en cours (conversion_journeys, assisted_*,
-- seo_to_contact_funnel : fenêtres closes à J-1). site_kpis_compare / cooked_pages_snapshot
-- (lens live) comptent des sessions brutes sans couture : commentaire posé, contrat inchangé.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Registre de fraîcheur
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.freshness_contract SET
  label               = 'Snapshots dashboard (ressources) — fin des données site',
  last_point_sql      = 'SELECT max(cooked_end) FROM public.dashboard_resources_snapshot',
  normal_lag_days     = 1,
  warn_after_days     = 2,
  critical_after_days = 4,
  repair_hint         = 'cooked_end = dernier jour Paris clos couvert par le snapshot (attendu J-1 après la séquence, J-2 le matin). À J-3 : deux séquences cooked_refresh_after_gsc manquées — lire refresh_runs, cooked_refresh_after_gsc_pending() et les alertes gsc_ingest_missed / refresh_after_gsc_stale ; relancer : SELECT public.cooked_refresh_after_gsc();'
WHERE source = 'dashboard_resources_snapshot';

INSERT INTO public.freshness_contract
  (source, label, last_point_sql, cadence, normal_lag_days, warn_after_days, critical_after_days,
   gap_relation, gap_day_column, gap_window_days, repair_hint, enabled)
VALUES
  ('page_taxonomy', 'Taxonomie des pages (catégorie Wix Blog)',
   'SELECT public.paris_date(max(updated_at)) FROM public.page_taxonomy',
   'weekly', 7, 21, NULL, NULL, NULL, NULL,
   'Aucune ligne de page_taxonomy touchée depuis 3 semaines : la synchro API Wix Blog n''a pas été rejouée (pas de cron avant T-15). Le mode de défaillance réel = ABSENCE DE LIGNE pour un article publié (voir page_taxonomy_gap) : rejouer la synchro, puis migration nommée pour l''upsert.',
   true)
ON CONFLICT (source) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Couture horodatée
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_identity_stitch(p_days integer DEFAULT 90)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '420s'
AS $function$
DECLARE
  t0 timestamptz := now() - make_interval(days => p_days);  -- c6c:allow (fenêtre de topologie, pas un chiffre business ; inchangé depuis le 12/07/2026)
BEGIN
  -- Paires (aid, sid) observées. Lecture d'events BRUT, assumée et
  -- volontaire : (a) c'est de la topologie d'identité, pas un chiffre
  -- business — les ids étant aléatoires par navigateur, les sessions
  -- bots forment leurs propres composantes sans polluer celles des
  -- humains ; (b) scanner events_human (anti-joins bots/bruit) coûte
  -- >100 s sur 28 j — prohibitif ici, les consommateurs business
  -- continuent de lire events_human et joignent la couture ensuite.
  DROP TABLE IF EXISTS _st_pairs;
  CREATE TEMP TABLE _st_pairs ON COMMIT DROP AS
    SELECT DISTINCT anonymous_id AS a, session_id AS s
    FROM events
    WHERE occurred_at >= t0
      AND anonymous_id NOT LIKE 'webhook-%'
      AND session_id  NOT LIKE 'webhook-%'
      AND anonymous_id !~ '^[0-9a-f]{32}$';
  ANALYZE _st_pairs;

  -- Label propagation alternée sid→aid→sid. Convergence mesurée à
  -- 2 itérations sur 28 j de prod (12/07/2026) ; 3 par marge.
  DROP TABLE IF EXISTS _st_l0; DROP TABLE IF EXISTS _st_a1;
  DROP TABLE IF EXISTS _st_l1; DROP TABLE IF EXISTS _st_a2;
  DROP TABLE IF EXISTS _st_l2; DROP TABLE IF EXISTS _st_a3;
  DROP TABLE IF EXISTS _st_l3;
  CREATE TEMP TABLE _st_l0 ON COMMIT DROP AS
    SELECT s, min(a) AS lbl FROM _st_pairs GROUP BY s;
  CREATE TEMP TABLE _st_a1 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l0 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l1 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a1 x ON x.a = p.a GROUP BY p.s;
  CREATE TEMP TABLE _st_a2 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l1 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l2 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a2 x ON x.a = p.a GROUP BY p.s;
  CREATE TEMP TABLE _st_a3 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l2 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l3 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a3 x ON x.a = p.a GROUP BY p.s;

  DELETE FROM identity_stitch;
  INSERT INTO identity_stitch (kind, key, visitor_key)
    SELECT 'sid', s, lbl FROM _st_l3
    UNION ALL
    SELECT 'aid', a, lbl FROM _st_a3;

  -- T-10 (03/09/2026) : horodatage de la couture. Lu par alert_rule_identity_stitch()
  -- et le contract-test identity_stitch_horodatee. Une couture vidée ou non reconstruite
  -- n'est plus un « succeeded » muet.
  INSERT INTO cooked_config (key, value, updated_at)
  VALUES ('identity_stitch_refreshed_at', now()::text, now()),
         ('identity_stitch_rows', (SELECT count(*) FROM identity_stitch)::text, now())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;
END $function$;

-- Amorce : dernier succès connu du cron (la reconstruction du 03/09 05:40 Paris), pour ne pas
-- sonner « sans horodatage » jusqu'à demain.
INSERT INTO public.cooked_config (key, value, updated_at)
SELECT 'identity_stitch_refreshed_at', max(d.end_time)::text, now()
FROM cron.job_run_details d
JOIN cron.job j ON j.jobid = d.jobid
WHERE j.jobname = 'refresh-identity-stitch' AND d.status = 'succeeded'
HAVING max(d.end_time) IS NOT NULL
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.cooked_config (key, value, updated_at)
SELECT 'identity_stitch_rows', count(*)::text, now() FROM public.identity_stitch
ON CONFLICT (key) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Règle d'alerte (ramassée par cooked_alerts_refresh() : préfixe alert_rule_, 0 argument)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.alert_rule_identity_stitch()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_rows  bigint;
  v_at    timestamptz;
  v_age_h numeric;
  v_j1    date;
  v_tot   bigint;
  v_miss  bigint;
BEGIN
  SELECT count(*) INTO v_rows FROM public.identity_stitch;
  IF v_rows = 0 THEN
    kind := 'identity_stitch_empty'; severity := 'critical';
    detail := 'identity_stitch est VIDE : conversion_journeys, assisted_contacts_by_entry_path, seo_to_contact_funnel et les snapshots dashboard retombent sur la session brute (contacts assistés sous-comptés). Relancer : SELECT public.refresh_identity_stitch(90); puis lire cron.job_run_details du job refresh-identity-stitch.';
    RETURN NEXT; RETURN;
  END IF;

  SELECT nullif(btrim(value), '')::timestamptz INTO v_at
  FROM public.cooked_config WHERE key = 'identity_stitch_refreshed_at';

  IF v_at IS NULL THEN
    kind := 'identity_stitch_stale'; severity := 'critical';
    detail := format('Couture d''identité sans horodatage (clé cooked_config.identity_stitch_refreshed_at absente) : %s lignes d''âge inconnu. Relancer : SELECT public.refresh_identity_stitch(90);', v_rows);
    RETURN NEXT; RETURN;
  END IF;

  v_age_h := extract(epoch FROM (now() - v_at)) / 3600.0;
  IF v_age_h > 30 THEN
    kind := 'identity_stitch_stale';
    severity := CASE WHEN v_age_h > 54 THEN 'critical' ELSE 'warn' END;
    detail := format('Couture d''identité reconstruite il y a %s h (dernière : %s Paris, %s lignes) — attendue chaque nuit à 05:40 Paris (cron refresh-identity-stitch). conversion_journeys, assisted_contacts_by_entry_path et seo_to_contact_funnel lisent une couture périmée. Relancer : SELECT public.refresh_identity_stitch(90);',
                     round(v_age_h), to_char(v_at AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI'), v_rows);
    RETURN NEXT; RETURN;
  END IF;

  -- Couverture : une fois la reconstruction du jour faite, chaque session humaine de J-1
  -- (hors webhook, hors aid 32-hex — jamais cousu, garde-fou du 12/07/2026) doit être cousue.
  IF public.paris_date(v_at) = public.paris_today() THEN
    v_j1 := public.paris_today() - 1;
    WITH s AS (
      SELECT DISTINCT session_id
      FROM public.events_human
      WHERE public.paris_date(occurred_at) = v_j1
        AND anonymous_id NOT LIKE 'webhook-%'
        AND anonymous_id !~ '^[0-9a-f]{32}$'
    )
    SELECT count(*),
           count(*) FILTER (WHERE NOT EXISTS (
             SELECT 1 FROM public.identity_stitch i WHERE i.kind = 'sid' AND i.key = s.session_id))
    INTO v_tot, v_miss
    FROM s;

    IF v_miss > 0 THEN
      kind := 'identity_stitch_coverage'; severity := 'warn';
      detail := format('%s session(s) humaine(s) de J-1 (%s) sur %s hors couture après la reconstruction de %s Paris : refresh_identity_stitch lit events brut sur %s — vérifier que la reconstruction a bien couvert la journée (durée, timeout 420 s) ; relancer : SELECT public.refresh_identity_stitch(90);',
                       v_miss, to_char(v_j1, 'DD/MM/YYYY'), v_tot,
                       to_char(v_at AT TIME ZONE 'Europe/Paris', 'HH24:MI'),
                       '90 j glissants');
      RETURN NEXT;
    END IF;
  END IF;
END $function$;

REVOKE ALL ON FUNCTION public.alert_rule_identity_stitch() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_identity_stitch() TO service_role;
REVOKE ALL ON FUNCTION public.refresh_identity_stitch(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_identity_stitch(integer) TO service_role;

COMMENT ON FUNCTION public.site_kpis_compare(text) IS
  'Lens live : la fenêtre inclut le jour en cours (heure Paris). Grain = session brute (pas de couture d''identité) — ne pas comparer ses contacts à conversion_journeys (fenêtre close à J-1, visite recousue).';
COMMENT ON FUNCTION public.cooked_pages_snapshot(text, integer) IS
  'Lens live : la fenêtre inclut le jour en cours. Grain = session brute, sans couture d''identité.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Contract-tests I7 (corps prod du 03/09/2026 + 2 entrées)
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
      ,
      -- I7 (T-10, 03/09/2026) : la couture d'identité est horodatée et couvre 100 % des sessions
      -- humaines de J-2 (reconstruite à 05:40 Paris, contrôlée ici à 05:30 : J-1 n'est pas encore cousue).
      ('identity_stitch_couvre_j2',
       $q$select count(*) from (select distinct session_id from public.events_human
            where public.paris_date(occurred_at) = public.paris_today() - 2
              and anonymous_id not like 'webhook-%' and anonymous_id !~ '^[0-9a-f]{32}$') s
          where not exists (select 1 from public.identity_stitch i
                            where i.kind = 'sid' and i.key = s.session_id)$q$,
       NULL, 0),
      ('identity_stitch_horodatee',
       $q$select count(*) from public.cooked_config
          where key = 'identity_stitch_refreshed_at'
            and value::timestamptz > now() - interval '30 hours'$q$,
       NULL, 1)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;

REVOKE ALL ON FUNCTION public.run_rpc_contract_tests() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_rpc_contract_tests() TO service_role;
