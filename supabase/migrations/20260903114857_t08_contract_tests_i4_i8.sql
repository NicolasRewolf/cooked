-- T-08 — contract-tests I4 / I8.
-- 4. Contract-tests I4 / I8.
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

      -- Ajoute le 28/07/2026 : le module Lecture (CONTEXT.md § Lecture).
      -- Cout d'ajout d'un test au contrat : une ligne. C'etait tout l'objet
      -- de ce depliage. `source` doit rester 'page_exit' tant que la
      -- reconstruction engagement_tick n'est pas decidee et annotee.
      ('page_reads',
       $q$select count(*) from public.page_reads(7) where source = 'page_exit'$q$,
       1, NULL),

      -- T-03 (mission 02/09/2026, invariant I5) : contrat d'unités — *_rate ∈ [0,1], *_pct ∈ [0,100],
      -- et un même nom de colonne = une même unité. exact_rows = 0 : aucune ligne ne doit violer.
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

      -- Un lot de ≥ 20 pages dont le max ≤ 1 = une fraction 0-1 publiée sous un nom en pourcentage.
      ('units_cooked_bounce_rate_unit',
       $q$select case when count(*) >= 20 and max(cooked_bounce_rate) <= 1 then 1 else 0 end from (
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u$q$,
       NULL, 0),

      -- T-04 (mission 02/09/2026, invariant I3) : part de pageviews de robot / referrer spam dans events_human
      -- < 1 % sur 7 j (1 si violation, 0 sinon ; garde ≥ 100 pageviews). Avant T-04 : 13,6 % (03/09/2026).
      ('spam_share_events_human',
       $q$select case when count(*) filter (where name = 'pageview') >= 100
                    and 100.0 * count(*) filter (where name = 'pageview'
                          and (lower(user_agent) = 'pc' or user_agent ilike '%sebot%'
                               or public.cooked_is_spam_referrer(referrer_hostname)))
                        / count(*) filter (where name = 'pageview') >= 1
                  then 1 else 0 end
          from public.events_human where occurred_at > now() - interval '7 days'$q$,
       NULL, 0),

      -- T-04 (invariant I3) : classify_channel renvoie 'spam' pour tout referrer spam (0 écart attendu).
      ('classify_channel_spam',
       $q$select count(*) from (values ('m.baidu.com'), ('baidu.com')) v(h)
          where public.classify_channel(v.h, null, null, 'www.jplouton-avocat.fr') <> 'spam'$q$,
       NULL, 0),

      -- T-05 (mission 02/09/2026, invariant I4) : « 28 j » GSC = 28 jours clos à gsc_last_data_day(). Écart attendu 0.
      ('gsc_pages_overview_28d_alignes',
       $q$select abs(coalesce((select sum(gsc_clicks_28d) from public.gsc_pages_overview(100000)), 0)
                 - coalesce((select sum(g.clicks) from public.gsc_path_daily g,
                               public.cooked_period_bounds('rolling_28', 'gsc') b
                             where g.day between b.n_start and b.n_end), 0))$q$,
       NULL, 0),

      -- T-05 (invariants I4/I10) : aucune borne d'horloge dans le CPI — ses fenêtres sont closes à gsc_last_data_day()
      -- et le score d'un jour est reproductible. 0 occurrence attendue de now()/current_date/… dans le corps.
      ('cpi_sans_horloge',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'now\(\)|current_date|current_timestamp|localtimestamp', 'gi')$q$,
       NULL, 0),

      -- T-09 (mission 02/09/2026, invariant I4) : « contacts macro 28 j » = UN chiffre. site_macro_counts sur les bornes
      -- live_j1 = Σ macro_contacts_by_path(28) = conversion_journeys(28) (téléphone + formulaires macro). Écart attendu 0.
      ('contacts_28j_une_fenetre',
       $q$with b as (select n_start, n_end from public.cooked_period_bounds('rolling_28', 'live_j1')),
               s as (select sm.macro_conversions as n from b, public.site_macro_counts(b.n_start, b.n_end) sm),
               m as (select coalesce(sum(contacts), 0) as n from public.macro_contacts_by_path(28)),
               j as (select count(*) as n from public.conversion_journeys(28))
          select abs((select n from s) - (select n from m)) + abs((select n from s) - (select n from j))$q$,
       NULL, 0),

      -- T-09 (I4) : le funnel SEO et conversion_journeys comptent les mêmes contacts organiques sur la même fenêtre (cross).
      ('funnel_meme_total_que_journeys',
       $q$with b as (select n_end from public.cooked_period_bounds('rolling_28', 'cross'))
          select abs(coalesce((select sum(contacts) from public.seo_to_contact_funnel(28)), 0)
                   - (select count(*) from b, public.conversion_journeys(28, b.n_end) j
                      where j.entry_channel like 'organic%' and j.entry_path is not null))$q$,
       NULL, 0),

      -- T-09 (o-14) : un identifiant de clic Ads dans l'URL d'atterrissage prime sur utm_source=gmb et sur le referrer.
      ('classify_channel_gclid_paid',
       $q$select count(*) from (values
            ('www.google.com', 'gmb', null, 'https://www.jplouton-avocat.fr/?utm_source=gmb&gclid=abc'),
            ('www.google.com', null, null, 'https://www.jplouton-avocat.fr/defense-penale?gbraid=xyz'),
            (null, null, null, 'https://www.jplouton-avocat.fr/?wbraid=k')) v(r, s, m, u)
          where public.classify_channel(v.r, v.s, v.m, 'www.jplouton-avocat.fr', v.u) is distinct from 'paid'$q$,
       NULL, 0),

      -- T-06 (mission 02/09/2026, invariants I4/I10) : le momentum du CPI lit la source COMPLÈTE des clics
      -- (gsc_path_daily) — la CTE `mom` doit s'appuyer sur momf ← gsc_path_daily. 1 occurrence attendue au minimum.
      ('cpi_momentum_source_complete',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'momf AS \(SELECT path,.*?FROM public\.gsc_path_daily', 'g')$q$,
       1, NULL),

      -- T-06 (f-07) : le `potentiel` de cpi_opportunite_contact est hors conversion ET hors momentum/gate
      -- (cpi_compose(zc, zr, zl, 0, 1, 1, true)). 0 ligne du dernier cpi_daily en désaccord attendue.
      ('potentiel_sans_momentum_gate',
       $q$select count(*) from public.cpi_opportunite_contact o
          where o.potentiel is distinct from round(public.cpi_compose(o.zc, o.zr, o.zl, 0, 1, 1, true))::int$q$,
       NULL, 0),

      -- T-08 (mission 02/09/2026, invariant I4) : Σ assistés + (non attribuable) = site_macro_counts
      -- sur la même fenêtre live_j1. Écart attendu 0 (avant T-08 : 191 − 179 = 12, les forms sans id).
      ('assistes_plus_non_attribuables_eq_site',
       $q$with b as (select n_start, n_end from public.cooked_period_bounds('rolling_28', 'live_j1')),
               s as (select sm.macro_conversions as n from b, public.site_macro_counts(b.n_start, b.n_end) sm),
               a as (select coalesce(sum(contacts), 0) as n
                     from public.assisted_contacts_by_entry_path((select n_start from b), (select n_end from b)))
          select abs((select n from s) - (select n from a))$q$,
       NULL, 0),

      -- T-08 (I8) : les 15 RPC dashboard_* sont sous contrat (durée enregistrée dans rpc_health).
      -- La plupart lisent un snapshot ; budget implicite = le timeout de run_rpc_contract_tests (900 s).
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
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;

  -- Retention 90j
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;
