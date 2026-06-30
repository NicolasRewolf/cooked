-- Perf : matérialisation events_human en temp table (pattern dashboard 20260629124448).
-- AVANT ~671 s (15-20 scans de la vue events_human avec anti-joins + self-join dédup).
-- APRÈS ~210 s, dominé par le préambule refresh_noise_sessions/bot_fingerprints ; le snapshot
-- lui-même n'est plus le goulot. Contrat 70 colonnes inchangé (vérifié : pogo/visiteurs/tél.
-- identiques avant/après à <0,2 % près = dérive de fenêtre, pas de régression).
-- Ne touche PAS refresh_bot_fingerprints/refresh_noise_sessions (pas de TRUNCATE réintroduit).
-- NB pogo : corps aligné sur le live pogo_rates_for_period (Sprint 30) — session_exit dédupliquée
-- (max + group by session_id,path) + gestion dwell_s IS NULL. (Le brouillon du doc
-- REFACTOR-refresh-seo-url-snapshot-perf.md avait un inline pré-S30 qui aurait régressé les
-- métriques pogo — bug détecté en revue de code et corrigé ici avant application.)
create or replace function public.refresh_seo_url_snapshot()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  now_ts timestamptz := now();
begin
  perform public.refresh_bot_fingerprints();
  perform public.refresh_noise_sessions();

  drop table if exists _eh_raw;
  create temp table _eh_raw on commit drop as
    select id, anonymous_id, session_id, path, name, occurred_at,
           referrer_hostname, utm_source, utm_medium, device_type, props
    from public.events
    where occurred_at >= now_ts - interval '365 days';
  analyze _eh_raw;

  drop table if exists _eh;
  create temp table _eh on commit drop as
    select r.*
    from _eh_raw r
    where not exists (select 1 from public.bot_fingerprints b where b.anonymous_id = r.anonymous_id)
      and not exists (select 1 from public.noise_sessions n where n.session_id = r.session_id)
      and not (r.name = 'cta_anchor_click' and public.cooked_is_chrome_anchor(r.props))
      and not (
        r.name in ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal','click_outbound')
        and exists (
          select 1 from public.events d
          where d.session_id = r.session_id
            and d.name = r.name
            and d.path is not distinct from r.path
            and date_trunc('second', d.occurred_at) = date_trunc('second', r.occurred_at)
            and (d.props->>'anchor') is not distinct from (r.props->>'anchor')
            and d.id < r.id
        )
      );
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
      from _eh where name='web_vitals' and path is not null and occurred_at >= now_ts - interval '28 days' group by path
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
$$;

revoke execute on function public.refresh_seo_url_snapshot() from public;
revoke execute on function public.refresh_seo_url_snapshot() from anon;
revoke execute on function public.refresh_seo_url_snapshot() from authenticated;
grant  execute on function public.refresh_seo_url_snapshot() to service_role;

-- Plafond porté à 600s par la migration 20260630093809 (mesure réelle 210s > « quelques s »).
alter function public.refresh_seo_url_snapshot() set statement_timeout = '300s';
