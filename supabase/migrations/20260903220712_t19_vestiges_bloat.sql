-- T-19 (mission 02/09/2026, #120) — budget de complexité : vestiges, dépréciations, bloat.
-- Autorisation : commentaire de Nicolas sur #120 (tri du 03/09/2026) — « Décision §7.4 donnée le 02/09 :
-- dépréciations de T-19 autorisées […] Chaque DROP = migration nommée + miroir + rpcs.sql régénéré ».
-- Constats d-08, h-07, h-08.
--
-- Mesure avant (04/09/2026 00:20 Paris) :
--   · page_reads(integer) et page_reads(timestamptz, timestamptz) : 0 appelant hors run_rpc_contract_tests
--     (annexes/routine_usage.md) ; la seconde était l'une des deux fonctions exposées à anon avant T-01.
--   · gsc_path_metrics_28d : vue vestige, 0 dépendant, 0 fonction, 0 usage repo hors views.sql.
--   · overloads `days_back` de macro_contacts_by_path / gsc_top_queries_for_path : 4 appelants RPC pour
--     macro_contacts_by_path(days_back) (fenêtre live_j1 depuis T-09) → période de grâce, pas de DROP.
--   · identity_stitch : 12 MB de heap pour 124 MB d'index (pkey 81 MB, visitor_idx 42 MB) — DELETE+INSERT
--     quotidien sans réindexation → REINDEX CONCURRENTLY exécuté hors migration (non transactionnel).
--   · gsc_path_daily / gsc_query_daily / gsc_query_page_daily : 10,4 / 10,5 / 10,9 % de tuples morts,
--     dernier autovacuum 17-23/08 (seuil par défaut 20 %).
--   · cooked_config.events_vacuum_full_scheduled = « 26/07/2026 04:00 Paris » : vestige du VACUUM FULL désarmé le 10/08.
--
-- Changement :
--   1. DROP page_reads ×2, gsc_path_metrics_28d ; contract-test page_reads retiré.
--   2. COMMENT « déprécié » sur les 2 overloads days_back (grâce jusqu'au 01/10/2026 : appelants à migrer
--      vers la forme period_kind / bornes, puis DROP dans une migration dédiée).
--   3. autovacuum resserré sur les 3 tables GSC (vacuum à 2 % de morts, analyze à 1 %).
--   4. DELETE de la clé vestige.
-- Non fait ici (décisions Nicolas) : DROP cpi_pre_restatement_20260903 (après lecture de la vérif J+1 du
-- 04/09) ; 2 doublons crm_prospects ; rétention CNIL 13 mois.

DROP FUNCTION IF EXISTS public.page_reads(integer);
DROP FUNCTION IF EXISTS public.page_reads(timestamp with time zone, timestamp with time zone);
DROP VIEW IF EXISTS public.gsc_path_metrics_28d;

COMMENT ON FUNCTION public.macro_contacts_by_path(integer) IS
  'DÉPRÉCIÉE (T-19, 04/09/2026) — période de grâce jusqu''au 01/10/2026 : utiliser macro_contacts_by_path(start_date, end_date) avec cooked_period_bounds(). Fenêtre = days_back jours Paris clos à J-1 (T-09).';
COMMENT ON FUNCTION public.gsc_top_queries_for_path(text, integer, integer) IS
  'DÉPRÉCIÉE (T-19, 04/09/2026) — période de grâce jusqu''au 01/10/2026 : utiliser gsc_top_queries_for_path(target_path, p_period_kind, max_rows).';

ALTER TABLE public.gsc_path_daily       SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.01);
ALTER TABLE public.gsc_query_daily      SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.01);
ALTER TABLE public.gsc_query_page_daily SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.01);

DELETE FROM public.cooked_config WHERE key = 'events_vacuum_full_scheduled';

-- Contract-tests : corps prod du 03/09/2026 (T-16) moins l'entrée page_reads.
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
      ,
      -- I8 (T-13, 03/09/2026) : budget de durée des RPC dashboard (mesuré sur ce même run —
      -- rpc_health est alimentée au fil des tests). 03/09 : article_detail 1,2 s (34 s max le 25/07),
      -- honoraires_funnel 1,6 s (12 s max mesuré en juillet), seo_by_query 2,8 s, les autres < 0,1 s.
      ('dashboard_rpc_budget',
       $q$select count(*) from public.rpc_health h
          where h.checked_at > now() - interval '30 minutes'
            and h.rpc_name like 'dashboard\_%'
            and h.duration_ms > case h.rpc_name
                                  when 'dashboard_article_detail'   then 20000
                                  when 'dashboard_honoraires_funnel' then 15000
                                  when 'dashboard_seo_by_query'      then 8000
                                  else 5000 end$q$,
       NULL, 0)
      ,
      -- I12 (T-16, 04/09/2026) : pont SECIB — la vue prod ne voit jamais le bac à sable ; le miroir de
      -- normalisation tient sur les vecteurs « (0) » ; pas de nouveau doublon prospect (2 connus le 03/09,
      -- nettoyage = décision Nicolas).
      ('pont_test_jamais_dans_prod',
       $q$select count(*) from public.pont_prospects_dossiers where secib_env is distinct from 'prod' and secib_env is not null$q$,
       NULL, 0),
      ('normalize_phone_vecteurs',
       $q$select count(*) from (values
            ('+33 (0)6 12 34 56 78', '+33612345678'), ('00 33 (0)6 12 34 56 78', '+33612345678'),
            ('06.12.34.56.78', '+33612345678'), ('+41 79 123 45 67', '+41791234567'), ('12345', null)) v(i, o)
          where public.cooked_normalize_phone_fr(v.i) is distinct from v.o$q$,
       NULL, 0),
      ('crm_prospects_doublons_email_minute',
       $q$select case when (select doublons_email_minute from public.pont_couverture where env = 'prod') > 2 then 1 else 0 end$q$,
       NULL, 0)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;

REVOKE ALL ON FUNCTION public.run_rpc_contract_tests() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_rpc_contract_tests() TO service_role;
