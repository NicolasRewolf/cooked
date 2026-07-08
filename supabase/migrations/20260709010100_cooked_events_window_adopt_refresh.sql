-- C1 adoption — refresh chauds consomment cooked_events_window + paris_date
CREATE OR REPLACE FUNCTION public.refresh_bot_fingerprints()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET lock_timeout TO '15s'
 SET statement_timeout TO '300s'
AS $function$
begin
  -- Monotone : un anonymous_id classé crawler le reste → on NE DELETE PAS,
  -- on ajoute seulement les nouveaux détectés sur la fenêtre 48h.
  insert into public.bot_fingerprints (anonymous_id, reason)
  select distinct on (sub.anonymous_id)
    sub.anonymous_id,
    format('crawl: %s pv, %s paths, 0 scroll on %s',
           sub.pvs, sub.distinct_paths, sub.day) as reason
  from (
    select e.anonymous_id, public.paris_date(e.occurred_at) as day,
      count(*) filter (where e.name = 'pageview') as pvs,
      count(*) filter (where e.name = 'scroll_depth') as scrolls,
      count(distinct e.path) filter (where e.name = 'pageview') as distinct_paths
    from public.events_main e
    where e.anonymous_id is not null
      and e.occurred_at > now() - interval '48 hours'
    group by e.anonymous_id, public.paris_date(e.occurred_at)
    having count(*) filter (where e.name = 'pageview') > 20
       and count(*) filter (where e.name = 'scroll_depth') = 0
  ) sub
  order by sub.anonymous_id, sub.day desc  -- 1 row per anonymous_id, latest day wins
  on conflict (anonymous_id) do nothing;
end;
$function$;

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
  v_shift int;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_resources_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_kpis_snapshot WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_trend_snapshot WHERE window_kind = ANY(windows);
  FOREACH w IN ARRAY windows LOOP
    SELECT label_fr, n_start, n_end, prev_start, prev_end, paris_today, day_count
      INTO lbl, lns, lne, lps, lpe, lpt, ld FROM cooked_period_bounds(w,'live');
    SELECT n_start, n_end, prev_start, prev_end, gsc_last_day, lag_days
      INTO gns, gne, gps, gpe, glast, glag FROM cooked_period_bounds(w,'gsc');
    -- T-16 #1 : ancrer la fin de fenêtre LIVE sur J-1 Paris (décale les 4 bornes)
    v_shift := lne - (public.paris_today() - 1);
    IF v_shift > 0 THEN
      lns := lns - v_shift; lne := lne - v_shift; lps := lps - v_shift; lpe := lpe - v_shift;
    END IF;
    ld := (lne - lns + 1)::int;
    CALL public.cooked_events_window(
      public.cooked_paris_ts_start(lps),
      public.cooked_paris_ts_end_exclusive(lne),
      'clean',
      'main'
    );
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
          AND ref NOT ILIKE '%linkedin%' AND ref NOT ILIKE '%facebook%'
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
        WHERE qp.day BETWEEN gns AND gne AND qp.query NOT ILIKE '%plouton%'
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
      CASE WHEN g.position_avg IS NOT NULL THEN ROUND(ctr_for_position(g.position_avg)*100, 2) END
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


CREATE OR REPLACE FUNCTION public.refresh_dashboard_expertises_snapshots(p_window text DEFAULT NULL)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '600s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date; lpt date; lbl text; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int; cpi_day date; v_shift int;
BEGIN
  SELECT max(day) INTO cpi_day FROM cpi_daily;
  DELETE FROM public.dashboard_expertises_snapshot       WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_kpis_snapshot  WHERE window_kind = ANY(windows);
  DELETE FROM public.dashboard_expertises_trend_snapshot WHERE window_kind = ANY(windows);

  DROP TABLE IF EXISTS _xp;
  -- T-20fix (03/07/2026) : scope = la liste OFFICIELLE des 14 pages expertise,
  -- validee par Nicolas. L'enumeration via page_taxonomy etait fausse : la table
  -- (heuristique par theme) ignorait droit-penal et proces-criminel (slugs sans
  -- mot-cle de theme) et incluait detention-provisoire + garde-a-vue, des pages
  -- RETIREES du site (301 verifies le 03/07 vers droit-penal / l'article GAV).
  -- Une nouvelle page expertise = l'ajouter ICI (decision business, pas heuristique).
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
    SELECT label_fr,n_start,n_end,prev_start,prev_end,paris_today,day_count
      INTO lbl,lns,lne,lps,lpe,lpt,ld FROM cooked_period_bounds(w,'live');
    SELECT n_start,n_end,prev_start,prev_end,gsc_last_day,lag_days
      INTO gns,gne,gps,gpe,glast,glag FROM cooked_period_bounds(w,'gsc');
    v_shift := lne - (public.paris_today() - 1);
    IF v_shift > 0 THEN lns:=lns-v_shift; lne:=lne-v_shift; lps:=lps-v_shift; lpe:=lpe-v_shift; END IF;
    ld := (lne - lns + 1)::int;

    CALL public.cooked_events_window(
      public.cooked_paris_ts_start(lps),
      public.cooked_paris_ts_end_exclusive(lne),
      'clean',
      'main'
    );
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

    -- canal GLOBAL d'acquisition (1er pageview de la session) pour les sessions
    -- expertise de la FENÊTRE COURANTE uniquement
    DROP TABLE IF EXISTS _fp;
    CREATE TEMP TABLE _fp ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
        public.classify_channel(e.referrer_hostname,e.utm_source,e.utm_medium,'www.jplouton-avocat.fr') AS chan
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
    reads AS (  -- lecture organique = atterrisseurs organiques DIRECTS sur la page (CPI), grain session×path max
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
    pgchan AS (  -- part paid de la page = sessions VOYANT la page (fenêtre courante) par canal global
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
        WHERE qp.day BETWEEN gns AND gne AND qp.query NOT ILIKE '%plouton%'
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
      CASE WHEN g.position_avg IS NOT NULL THEN ROUND(ctr_for_position(g.position_avg)*100,2) END,
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
END $function$;CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '300s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lns date; lne date; lps date; lpe date; v_shift int;
BEGIN
  DELETE FROM public.dashboard_resources_assisted_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    SELECT n_start,n_end,prev_start,prev_end INTO lns,lne,lps,lpe FROM cooked_period_bounds(w,'live');
    v_shift := lne - (public.paris_today() - 1);
    IF v_shift > 0 THEN lns:=lns-v_shift; lne:=lne-v_shift; lps:=lps-v_shift; lpe:=lpe-v_shift; END IF;

    -- 1er pageview GLOBAL de chaque session sur le span [lps..lne] (hors Baidu)
    DROP TABLE IF EXISTS _fpv;
    CREATE TEMP TABLE _fpv ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path,
             public.paris_date(e.occurred_at) AS entry_d
      FROM events_human e
      WHERE e.name='pageview'
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
        AND e.occurred_at >= public.cooked_paris_ts_start(lps)
        AND e.occurred_at <  public.cooked_paris_ts_end_exclusive(lne)
      ORDER BY e.session_id, e.occurred_at;
    CREATE INDEX ON _fpv(session_id);
    ANALYZE _fpv;

    -- contacts macro datés (appels par session ; formulaires par cooked_sid)
    DROP TABLE IF EXISTS _ct;
    CREATE TEMP TABLE _ct ON COMMIT DROP AS
      SELECT e.session_id AS sid, public.paris_date(e.occurred_at) AS d
      FROM events_human e
      WHERE e.name='cta_phone_click'
        AND e.occurred_at >= public.cooked_paris_ts_start(lps)
        AND e.occurred_at <  public.cooked_paris_ts_end_exclusive(lne)
      UNION ALL
      SELECT e.props->>'cooked_sid', public.paris_date(e.occurred_at)
      FROM events_human e
      WHERE e.name='form_submit' AND form_submit_counts_as_macro(e.props)
        AND e.props->>'cooked_sid' IS NOT NULL
        AND e.occurred_at >= public.cooked_paris_ts_start(lps)
        AND e.occurred_at <  public.cooked_paris_ts_end_exclusive(lne);
    ANALYZE _ct;

    INSERT INTO public.dashboard_resources_assisted_snapshot (window_kind, path, assisted_contacts, assisted_prev, refreshed_at)
    SELECT w, pt.path,
      COALESCE(cur.n,0), COALESCE(prv.n,0), now()
    FROM page_taxonomy pt
    LEFT JOIN (
      SELECT f.entry_path, count(*) AS n
      FROM _ct c JOIN _fpv f ON f.session_id=c.sid
      WHERE c.d BETWEEN lns AND lne
      GROUP BY f.entry_path
    ) cur ON cur.entry_path=pt.path
    LEFT JOIN (
      SELECT f.entry_path, count(*) AS n
      FROM _ct c JOIN _fpv f ON f.session_id=c.sid
      WHERE c.d BETWEEN lps AND lpe
      GROUP BY f.entry_path
    ) prv ON prv.entry_path=pt.path
    WHERE pt.category='ressource';
  END LOOP;
END $function$;
REVOKE ALL ON FUNCTION public.refresh_dashboard_resources_assisted(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_dashboard_resources_assisted(text) TO service_role;
