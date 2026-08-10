-- C6 — alert_rule_gbp_gap utilisait un cast Paris brut ((now() at time zone
-- 'Europe/Paris')::date), attrapé par la gate paris-date-contract sur la PR
-- de rangement. Corrigé : paris_today(), la couture contractuelle.
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
  v_age := public.paris_today() - v_last;
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
