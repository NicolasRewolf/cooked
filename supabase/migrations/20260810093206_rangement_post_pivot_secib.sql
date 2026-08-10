-- ============================================================================
-- Rangement post-pivot SECIB (10/08/2026)
-- ============================================================================

-- 1. Tables d'audit CPI périmées — suppression documentée dans CLAUDE.md
--    (échéances ~19/07 et ~03/08/2026), en retard depuis le contrôle du 05/08.
--    Les restatements eux-mêmes sont annotés dans `annotations` ; cpi_daily
--    porte l'état restaté. Ces photos n'ont plus d'usage.
drop table if exists cpi_pre_restatement_20260712;
drop table if exists cpi_pre_restatement_20260727;

-- 2. Le VACUUM FULL « one-shot » de l'audit du 26/07/2026 était programmé
--    `0 2 26 7 *` : rejeu silencieux chaque 26 juillet à 02:00, avec lock
--    exclusif de events pendant plusieurs minutes. Désarmé.
select cron.unschedule('events-vacuum-full-audit-20260726');

-- 3. Alerte de fraîcheur GBP — le trou qui a laissé deux pannes muettes
--    (30/07→04/08, puis 06/08→10/08 constatée ce jour). Lag normal de
--    consolidation Google ≈ 4 j (le script coupe la queue rembourrée à zéro) :
--    warn au-delà de 7 j, critical (→ push ntfy) au-delà de 14 j.
create or replace function public.alert_rule_gbp_gap()
 returns table(kind text, severity text, detail text)
 language plpgsql
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
declare
  v_last date := null;
  v_age  int;
begin
  select max(day) into v_last from public.gbp_daily;
  if v_last is null then
    return query select 'gbp_gap'::text, 'warn'::text,
      'gbp_daily est vide — ingestion GBP jamais passée ?'::text;
    return;
  end if;
  v_age := (now() at time zone 'Europe/Paris')::date - v_last;
  if v_age > 14 then
    return query select 'gbp_gap'::text, 'critical'::text,
      format('gbp_daily : dernier jour %s (J-%s) — cron GitHub gbp-daily-ingest mort ? Reauth ADC probable (voir scripts/gbp_ingest.py).',
             to_char(v_last, 'DD/MM/YYYY'), v_age);
  elsif v_age > 7 then
    return query select 'gbp_gap'::text, 'warn'::text,
      format('gbp_daily : dernier jour %s (J-%s, normal ≈ J-4/5) — vérifier le cron gbp-daily-ingest (reauth ADC ?).',
             to_char(v_last, 'DD/MM/YYYY'), v_age);
  end if;
end;
$function$;

create or replace function public.cooked_alerts_refresh()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
DECLARE
  r record;
  v_added int := 0;
BEGIN
  FOR r IN
    SELECT * FROM public.alert_rule_pipeline_dead()
    UNION ALL SELECT * FROM public.alert_rule_cron_failed()
    UNION ALL SELECT * FROM public.alert_rule_cpi_stale()
    UNION ALL SELECT * FROM public.alert_rule_double_embed_suspect()
    UNION ALL SELECT * FROM public.alert_rule_rpc_health()
    UNION ALL SELECT * FROM public.alert_rule_form_attribution_degraded()
    UNION ALL SELECT * FROM public.alert_rule_gsc_lag()
    UNION ALL SELECT * FROM public.alert_rule_gsc_gap()
    UNION ALL SELECT * FROM public.alert_rule_gbp_gap()
    UNION ALL SELECT * FROM public.alert_rule_cpi_drop()
    UNION ALL SELECT * FROM public.alert_rule_dfs_stale()
    UNION ALL SELECT * FROM public.alert_rule_tracker_drift()
  LOOP
    v_added := v_added + public.raise_cooked_alert(r.kind, r.severity, r.detail);
  END LOOP;
  RETURN v_added;
END;
$function$;

revoke execute on function public.alert_rule_gbp_gap() from anon, authenticated;
