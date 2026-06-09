-- Sprint 37 (09/06/2026) — monitoring actif : table alerts + refresh horaire
-- (voir docs/ROADMAP-sprint38-handoff.md §2.5). cooked_alerts_refresh()
-- vérifie : pipeline vivant, récidive double-embed, santé des 3 RPCs S37
-- (complète les contract tests nightly), attribution dégradée, retard GSC.
-- Anti-spam : pas de doublon de même kind non-acké < 24 h.
-- Première requête de chaque session agent :
--   select * from alerts where not acked order by created_at desc;
-- Cron : cooked-alerts-hourly, '15 * * * *'.
-- NB : SQL identique à la migration appliquée en prod le 09/06/2026.

create table if not exists public.alerts (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  kind text not null,
  severity text not null check (severity in ('info','warn','critical')),
  detail text,
  acked boolean not null default false
);
revoke all on public.alerts from anon, authenticated;
grant select, insert, update on public.alerts to service_role;

create or replace function public.raise_cooked_alert(p_kind text, p_sev text, p_detail text)
returns int language plpgsql security definer
set search_path = public, pg_catalog as $$
begin
  if exists (
    select 1 from public.alerts
    where kind = p_kind and not acked
      and created_at > now() - interval '24 hours'
  ) then return 0; end if;
  insert into public.alerts (kind, severity, detail) values (p_kind, p_sev, p_detail);
  return 1;
end; $$;
revoke execute on function public.raise_cooked_alert(text,text,text) from public, anon, authenticated;
grant execute on function public.raise_cooked_alert(text,text,text) to service_role;

create or replace function public.cooked_alerts_refresh()
returns int language plpgsql security definer
set search_path = public, pg_catalog as $$
declare
  v_n bigint; v_tot bigint; v_pct numeric; v_lag int;
  v_added int := 0; v_start timestamptz; v_fn text;
begin
  select count(*) into v_n from public.events
  where received_at > now() - interval '60 minutes';
  if v_n = 0 then
    v_added := v_added + public.raise_cooked_alert('pipeline_dead', 'critical',
      'Aucun event reçu depuis 60 min — tracker ou Edge track en panne ?');
  end if;

  select coalesce(sum(c) - count(*), 0) into v_n from (
    select count(*) as c from public.events
    where occurred_at > now() - interval '24 hours'
      and name in ('cta_phone_click','cta_booking_click','cta_anchor_click','click_internal')
    group by session_id, name, path, date_trunc('second', occurred_at), props->>'anchor'
  ) d;
  if v_n >= 5 then
    v_added := v_added + public.raise_cooked_alert('double_embed_suspect', 'warn',
      format('%s clics dupliqués même-seconde sur 24h — snippet en double dans Wix Custom Code ?', v_n));
  end if;

  foreach v_fn in array array['form_submits_attributed','conversion_journeys','content_performance']
  loop
    v_start := clock_timestamp();
    begin
      execute format('select count(*) from public.%I(7)', v_fn) into v_n;
      insert into public.rpc_health (rpc_name, status, rows_returned, duration_ms)
      values (v_fn, 'ok', v_n, extract(epoch from (clock_timestamp() - v_start)) * 1000);
    exception when others then
      insert into public.rpc_health (rpc_name, status, detail, duration_ms)
      values (v_fn, 'failed', SQLERRM, extract(epoch from (clock_timestamp() - v_start)) * 1000);
      v_added := v_added + public.raise_cooked_alert('rpc_failed_' || v_fn, 'critical', SQLERRM);
    end;
  end loop;

  select count(*) filter (where props->>'cooked_aid' is null), count(*)
    into v_n, v_tot
  from public.events
  where name = 'form_submit' and occurred_at > now() - interval '7 days';
  if v_tot >= 5 then
    v_pct := round(100.0 * v_n / v_tot, 0);
    if v_pct > 30 then
      v_added := v_added + public.raise_cooked_alert('form_attribution_degraded', 'warn',
        format('%s %% des form_submit sans cooked_aid sur 7j (%s/%s) — champs cachés Wix manquants ou tracker pas à jour ?', v_pct, v_n, v_tot));
    end if;
  end if;

  select (current_date - public.gsc_last_data_day()) into v_lag;
  if v_lag > 3 then
    v_added := v_added + public.raise_cooked_alert('gsc_lag', 'warn',
      format('Dernière donnée GSC : J-%s — ingestion en panne ?', v_lag));
  end if;

  return v_added;
end; $$;
revoke execute on function public.cooked_alerts_refresh() from public, anon, authenticated;
grant execute on function public.cooked_alerts_refresh() to service_role;

select cron.schedule('cooked-alerts-hourly', '15 * * * *',
  $cron$ select public.cooked_alerts_refresh(); $cron$);
