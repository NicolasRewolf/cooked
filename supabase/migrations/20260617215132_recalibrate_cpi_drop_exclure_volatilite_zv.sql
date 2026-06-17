-- 17/06/2026 — recalibre l'alerte cpi_drop (bloc 6 de cooked_alerts_refresh).
-- Diagnostic du 17/06 : cpi_drop sonnait sur des chutes portées UNIQUEMENT par
-- la volatilité du zv (conversion) — un contact qui sort de la fenêtre 28j fait
-- plonger une page de ~50 pts (ex. nullité-dépistage : zv +2,2→−2,0, CPI 100→41)
-- sans que la page ait réellement "décliné". On n'alerte désormais QUE si la
-- chute s'accompagne d'un vrai signal de déclin : momentum en baisse (≤ −0,10)
-- OU capture en baisse (delta_zc ≤ −0,5). Le reste de la fonction est inchangé.
-- Validé : exclut nullité-dépistage (Δmom −0,04, ΔzV −4,0), garde accident-médical
-- (Δmom −0,31) et ma-procédure (Δmom −0,34). Seuils v1, à recalibrer au J+28 (08/07).
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

  -- 2. Double-embed (sessions distinctes avec pageview/web_vitals dupliqués même-seconde)
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

  -- 3. Santé des RPCs Sprint 37
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

  -- 4. Attribution dégradée
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

  -- 6. Chute de CPI fiable sur ~7j (cpi_movers) : VRAI decay précoce uniquement.
  -- Recalibré 17/06/2026 : condition de cause ajoutée (momentum OU capture en
  -- baisse) pour exclure les chutes de pure volatilité conversion (zv). Le
  -- diagnostic détaillé vit dans les delta_z de la vue. Seuils v1 → J+28.
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
        and (coalesce(delta_momentum,0) <= -0.10 or coalesce(delta_zc,0) <= -0.5)
    ) m;
    if v_n >= 1 then
      v_added := v_added + public.raise_cooked_alert('cpi_drop', 'warn',
        format('%s page(s) fiable(s) en vrai decay sur ~7j (momentum/capture en baisse, volatilité conversion exclue) : %s%s — diagnostiquer via cpi_movers (delta_zc/zr/zl/zv)',
          v_n, v_detail,
          case when v_n > 3 then format(' … et %s autre(s)', v_n - 3) else '' end));
    end if;
  exception when others then
    v_added := v_added + public.raise_cooked_alert('cpi_movers_failed', 'critical', SQLERRM);
  end;

  return v_added;
end; $function$;
