-- 16/06/2026 — recalibre la détection double_embed de cooked_alerts_refresh().
-- Diagnostic du 16/06 : l'ancienne logique comptait les EVENTS dupliqués bruts
-- sur les clics (seuil 5) → un seul visiteur "tapeur frénétique" (ex. 21 clics
-- sur un bouton mobile en 10 s) suffisait à déclencher l'alerte. De plus les
-- clics sont pollués par du chrome capté à tort (bandeau cookies, <script>).
-- Nouvelle logique : on ne regarde que les events AUTOMATIQUES (pageview,
-- web_vitals) — qu'un humain ne peut pas "re-taper" — strictement dupliqués
-- même-seconde (props identiques), et on compte les SESSIONS distinctes.
-- Un vrai double-embed (snippet chargé 2x) double ces events sur BEAUCOUP de
-- sessions. Bruit de fond mesuré (14j) : 1–15 sessions/j (~1,3 %). Seuil = 30.
CREATE OR REPLACE FUNCTION public.cooked_alerts_refresh()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_n bigint; v_tot bigint; v_pct numeric; v_lag int;
  v_added int := 0; v_start timestamptz; v_fn text; v_detail text;
begin
  -- 1. Pipeline vivant
  select count(*) into v_n from public.events
  where received_at > now() - interval '60 minutes';
  if v_n = 0 then
    v_added := v_added + public.raise_cooked_alert('pipeline_dead', 'critical',
      'Aucun event reçu depuis 60 min — tracker ou Edge track en panne ?');
  end if;

  -- 2. Double-embed (snippet tracker chargé 2x). On compte les SESSIONS distinctes
  --    où un event AUTOMATIQUE (pageview / web_vitals) est strictement dupliqué
  --    même-seconde (props identiques). Rationale (diagnostic 16/06/2026) :
  --      - les CLICS sont un mauvais signal : un visiteur "tapeur frénétique" en
  --        génère des dizaines à lui seul (faux positifs), et le tracker capte
  --        parfois du chrome (cookies, <script>) comme cta_anchor ;
  --      - pageview/web_vitals sont émis par le tracker, jamais par l'utilisateur,
  --        donc un doublon = forcément 2 instances du tracker ;
  --      - on compte les SESSIONS distinctes, pas les events bruts.
  --    Bruit de fond observé (14j) : 1–15 sessions/j (~1,3 % des sessions).
  --    Seuil 30 = ~2x le max de fond → ne sonne que sur une vraie hausse systémique.
  select count(distinct session_id) into v_n from (
    select session_id
    from public.events
    where occurred_at > now() - interval '24 hours'
      and name in ('pageview','web_vitals')
    group by session_id, name, path, date_trunc('second', occurred_at), props::text
    having count(*) > 1
  ) d;
  if v_n >= 30 then
    v_added := v_added + public.raise_cooked_alert('double_embed_suspect', 'warn',
      format('%s sessions avec pageview/web_vitals dupliqués même-seconde sur 24h (fond normal ~8) — snippet tracker probablement en double dans Wix Custom Code', v_n));
  end if;

  -- 3. Santé des RPCs Sprint 37 (complète les contract tests nightly)
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

  -- 4. Attribution dégradée (pertinent après l'ajout des champs cachés Wix)
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

  -- 5. Retard GSC
  select (current_date - public.gsc_last_data_day()) into v_lag;
  if v_lag > 3 then
    v_added := v_added + public.raise_cooked_alert('gsc_lag', 'warn',
      format('Dernière donnée GSC : J-%s — ingestion en panne ?', v_lag));
  end if;

  -- 6. Chute de CPI fiable sur ~7j (Sprint 38, vue cpi_movers) : decay précoce.
  -- Le diagnostic vit dans les delta_z de la vue ; l'alerte ne fait que pointer.
  -- Seuil v1 : -15 pts (≈ une bande de la grille) — à recalibrer sur ~2×MAD
  -- des deltas observés quand cpi_daily aura 4 semaines d'historique.
  begin
    select count(*),
           string_agg(path || ' (' || cpi_ref || '→' || cpi_now || ')', ', ' order by rn)
             filter (where rn <= 3)
      into v_n, v_detail
    from (
      select path, cpi_ref, cpi_now,
             row_number() over (order by delta_cpi asc) as rn
      from public.cpi_movers
      where statut = 'present' and fiable and delta_cpi <= -15
    ) m;
    if v_n >= 1 then
      v_added := v_added + public.raise_cooked_alert('cpi_drop', 'warn',
        format('%s page(s) fiable(s) en chute de ≥15 pts de CPI sur ~7j : %s%s — diagnostiquer via cpi_movers (delta_zc/zr/zl/zv)',
          v_n, v_detail,
          case when v_n > 3 then format(' … et %s autre(s)', v_n - 3) else '' end));
    end if;
  exception when others then
    v_added := v_added + public.raise_cooked_alert('cpi_movers_failed', 'critical', SQLERRM);
  end;

  return v_added;
end; $function$;
