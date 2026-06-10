-- Sprint 38 (10/06/2026) — cpi_movers : la dérivée du CPI + alerte cpi_drop
-- (backlog #2 de la reprise CPI ; cf. docs/cpi-cooked-page-index.md).
--
-- Vue cpi_movers : compare le DERNIER snapshot de cpi_daily au snapshot le
-- plus récent dans la fenêtre [J-14, J-7] (absorbe les trous de cron sans
-- comparer à un point trop vieux ; ecart_jours est exposé). Vide tant que
-- cpi_daily n'a pas ~7 j d'historique — premier rendu attendu ~17/06/2026.
-- FULL OUTER JOIN : une page qui SORT du scoring (n_org<5 → statut 'disparu')
-- est souvent le decay le plus avancé, ne pas la perdre. Les deltas par
-- composante (delta_zc/zr/zl/zv, delta_momentum) portent le diagnostic :
-- le CPI trie, les z diagnostiquent — la dérivée suit la même grille.
-- fiable = grade A/B aux DEUX dates (les variations de grade C = bruit EB).
--
-- Alerte cpi_drop (bloc 6 de cooked_alerts_refresh) : ≥1 page fiable en
-- chute ≥ 15 pts → 1 alerte warn agrégée (compte + top 3). Seuil v1 raisonné
-- (≈ une bande de la grille de lecture) ; recalibrer sur ~2×MAD des deltas
-- 7j observés quand cpi_daily aura ≥ 4 semaines d'historique.
-- NB : SQL identique à la migration appliquée en prod le 10/06/2026
-- (testée par insert fictif J-7 + rollback : 30 drops détectés, 1 alerte
-- agrégée, vue vide à l'état réel 1-snapshot).

CREATE OR REPLACE VIEW public.cpi_movers
WITH (security_invoker = true) AS
WITH bounds AS (
  SELECT l.d1, r.d0
  FROM (SELECT max(day) AS d1 FROM public.cpi_daily) l
  CROSS JOIN LATERAL (
    SELECT max(day) AS d0 FROM public.cpi_daily
    WHERE day BETWEEN l.d1 - 14 AND l.d1 - 7
  ) r
  WHERE r.d0 IS NOT NULL
),
now_rows AS (
  SELECT c.* FROM public.cpi_daily c JOIN bounds b ON c.day = b.d1
),
ref_rows AS (
  SELECT c.* FROM public.cpi_daily c JOIN bounds b ON c.day = b.d0
)
SELECT
  b.d1 AS day_now,
  b.d0 AS day_ref,
  (b.d1 - b.d0) AS ecart_jours,
  coalesce(n.path, p.path) AS path,
  coalesce(n.ptype, p.ptype) AS ptype,
  CASE WHEN p.path IS NULL THEN 'nouveau'
       WHEN n.path IS NULL THEN 'disparu'
       ELSE 'present' END AS statut,
  n.cpi AS cpi_now,
  p.cpi AS cpi_ref,
  (n.cpi - p.cpi) AS delta_cpi,
  n.grade AS grade_now,
  p.grade AS grade_ref,
  coalesce(n.grade IN ('A','B') AND p.grade IN ('A','B'), false) AS fiable,
  round(n.zc - p.zc, 1) AS delta_zc,
  round(n.zr - p.zr, 1) AS delta_zr,
  round(n.zl - p.zl, 1) AS delta_zl,
  round(n.zv - p.zv, 1) AS delta_zv,
  round(n.momentum - p.momentum, 2) AS delta_momentum,
  n.momentum AS momentum_now,
  n.n_org AS n_org_now,
  n.clics_perdus AS clics_perdus_now
FROM now_rows n
FULL OUTER JOIN ref_rows p ON p.path = n.path
CROSS JOIN bounds b
ORDER BY delta_cpi ASC NULLS LAST;

REVOKE ALL ON public.cpi_movers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.cpi_movers TO service_role;

-- cooked_alerts_refresh : blocs 1-5 inchangés (copie exacte de la prod,
-- vérifiée par md5 avant réécriture), bloc 6 cpi_drop ajouté.
create or replace function public.cooked_alerts_refresh()
returns int language plpgsql security definer
set search_path = public, pg_catalog as $$
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

  -- 2. Récidive double-embed : clics dupliqués même-seconde
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
end; $$;
revoke execute on function public.cooked_alerts_refresh() from public, anon, authenticated;
grant execute on function public.cooked_alerts_refresh() to service_role;
