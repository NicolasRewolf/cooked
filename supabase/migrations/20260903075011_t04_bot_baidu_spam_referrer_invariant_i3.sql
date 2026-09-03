-- T-04 (mission 02/09/2026, issue #105) — constats a-01 (P0), a-02, c-06, d-05 ; invariant I3.
-- Un robot (user_agent littéral « pc », referrer m.baidu.com — 85 985 lignes / 7 252 sessions depuis le 07/05/2026,
-- 13,6 % des pageviews et 16,9 % des sessions d'events_human sur 28 j au 03/09/2026) échappait aux deux filets :
-- la taxonomie ua_bot (aucun motif ne matche « pc ») et la règle heuristique de bruit (il a un referrer et des ticks).
-- Les RPC publiées et le CPI le filtraient déjà (cooked_is_spam_referrer) ; la vue de base, non.
-- 1. refresh_noise_sessions : motifs « pc » (exact, insensible à la casse) et « sebot » (SEBot-WA, 554 lignes) dans
--    la taxonomie ua_bot — miroir de BOT_UA_RE de l'Edge track v28 ; nouvelle règle « spam_referrer » (session entière).
-- 2. Rattrapage : les sessions historiques du robot entrent dans noise_sessions (masquage, INSERT dans une table
--    dérivée — AUCUN DELETE dans events : « T-04 sans purge », validation Nicolas du 02/09/2026).
-- 3. classify_channel v4 : referrer spam → canal 'spam' (au lieu de 'referral', dont il faisait 94 %).
-- 4. alert_rule_spam_in_events_human (warn, 24 h, seuil 1 %) + 2 contract-tests (spam_share_events_human,
--    classify_channel_spam) dans run_rpc_contract_tests — invariant I3.
-- Restatement : oui, ad hoc uniquement (sessions/visiteurs 28 j −16,9 %) ; RPC publiées et CPI inchangés.
-- Annotation posée dans une migration séparée après vérification.
-- Corps générés depuis la prod (rpcs.sql = prod, md5 vérifiés) par substitutions ciblées.

CREATE OR REPLACE FUNCTION public.refresh_noise_sessions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET lock_timeout TO '15s'
 SET statement_timeout TO '300s'
AS $function$
begin
  CALL public.cooked_events_window(
    now() - interval '48 hours',
    now(),
    'raw',
    'main'
  );

  delete from public.noise_sessions
  where session_id in (
    select distinct session_id from _cooked_ev
    where session_id is not null
  );

  DROP TABLE IF EXISTS _no_bots;
  CREATE TEMP TABLE _no_bots ON COMMIT DROP AS
    SELECT e.id, e.anonymous_id, e.session_id, e.name, e.referrer_hostname,
           e.user_agent, e.device_type, e.occurred_at
    FROM _cooked_ev e
    WHERE NOT EXISTS (
      SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
    );
  ANALYZE _no_bots;

  insert into public.noise_sessions (session_id, reason)
  select
    session_id,
    'prefetch: 0 ref + 0 tick + 0 scroll + 1 pv + <10s'
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
  group by session_id
  having max(referrer_hostname) is null
     and count(*) filter (where name = 'engagement_tick') = 0
     and count(*) filter (where name = 'scroll_depth')    = 0
     and count(*) filter (where name = 'pageview')        = 1
     and extract(epoch from (max(occurred_at) - min(occurred_at))) < 10
  on conflict (session_id) do nothing;

  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'ua_bot: ' || (
      case
        -- T-04 (mission 02/09/2026, a-01) : UA littéral « pc » (bot Baidu) et SEBot-WA — miroir de BOT_UA_RE (Edge v28)
        when lower(user_agent) = 'pc'                   then 'pc'
        when user_agent ilike '%sebot%'                 then 'sebot'
        when user_agent ilike '%headless%'              then 'headless'
        when user_agent ilike '%googlebot%'             then 'googlebot'
        when user_agent ilike '%bingbot%'               then 'bingbot'
        when user_agent ilike '%applebot%'              then 'applebot'
        when user_agent ilike '%duckduckbot%'           then 'duckduckbot'
        when user_agent ilike '%yandexbot%'             then 'yandexbot'
        when user_agent ilike '%baiduspider%'           then 'baiduspider'
        when user_agent ilike '%gptbot%'                then 'gptbot'
        when user_agent ilike '%claudebot%'             then 'claudebot'
        when user_agent ilike '%perplexitybot%'         then 'perplexitybot'
        when user_agent ilike '%chatgpt-user%'          then 'chatgpt-user'
        when user_agent ilike '%googleother%'           then 'googleother'
        when user_agent ilike '%semrushbot%'            then 'semrushbot'
        when user_agent ilike '%ahrefsbot%'             then 'ahrefsbot'
        when user_agent ilike '%mj12bot%'               then 'mj12bot'
        when user_agent ilike '%dotbot%'                then 'dotbot'
        when user_agent ilike '%petalbot%'              then 'petalbot'
        when user_agent ilike '%bytespider%'            then 'bytespider'
        when user_agent ilike '%lighthouse%'            then 'lighthouse'
        when user_agent ilike '%pingdom%'               then 'pingdom'
        when user_agent ilike '%uptimerobot%'           then 'uptimerobot'
        when user_agent ilike '%gtmetrix%'              then 'gtmetrix'
        when user_agent ilike '%facebookexternalhit%'   then 'facebookexternalhit'
        when user_agent ilike '%linkedinbot%'           then 'linkedinbot'
        when user_agent ilike '%twitterbot%'            then 'twitterbot'
        when user_agent ilike '%discordbot%'            then 'discordbot'
        when user_agent ilike '%telegrambot%'           then 'telegrambot'
        when user_agent ilike '%slackbot%'              then 'slackbot'
        when user_agent ilike '%whatsapp/%'             then 'whatsapp-preview'
        when user_agent ilike '%crawler%'               then 'crawler'
        when user_agent ilike '%spider%'                then 'spider'
        when user_agent ilike '%axios/%'                then 'axios'
        when user_agent ilike '%curl/%'                 then 'curl'
        when user_agent ilike '%wget%'                  then 'wget'
        when user_agent ilike '%python%'                then 'python'
        when user_agent ilike '%go-http%'               then 'go-http'
        when user_agent ilike '%node-fetch%'            then 'node-fetch'
        when user_agent ilike '%httpclient%'            then 'httpclient'
        when user_agent ilike '%java/%'                 then 'java-http'
        else 'unknown'
      end
    )
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
    and user_agent is not null
    and (
         lower(user_agent) = 'pc'
      or user_agent ilike '%sebot%'
      or user_agent ilike '%headless%'
      or user_agent ilike '%googlebot%'
      or user_agent ilike '%bingbot%'
      or user_agent ilike '%applebot%'
      or user_agent ilike '%duckduckbot%'
      or user_agent ilike '%yandexbot%'
      or user_agent ilike '%baiduspider%'
      or user_agent ilike '%gptbot%'
      or user_agent ilike '%claudebot%'
      or user_agent ilike '%perplexitybot%'
      or user_agent ilike '%chatgpt-user%'
      or user_agent ilike '%googleother%'
      or user_agent ilike '%semrushbot%'
      or user_agent ilike '%ahrefsbot%'
      or user_agent ilike '%mj12bot%'
      or user_agent ilike '%dotbot%'
      or user_agent ilike '%petalbot%'
      or user_agent ilike '%bytespider%'
      or user_agent ilike '%lighthouse%'
      or user_agent ilike '%pingdom%'
      or user_agent ilike '%uptimerobot%'
      or user_agent ilike '%gtmetrix%'
      or user_agent ilike '%facebookexternalhit%'
      or user_agent ilike '%linkedinbot%'
      or user_agent ilike '%twitterbot%'
      or user_agent ilike '%discordbot%'
      or user_agent ilike '%telegrambot%'
      or user_agent ilike '%slackbot%'
      or user_agent ilike '%whatsapp/%'
      or user_agent ilike '%crawler%'
      or user_agent ilike '%spider%'
      or user_agent ilike '%axios/%'
      or user_agent ilike '%curl/%'
      or user_agent ilike '%wget%'
      or user_agent ilike '%python%'
      or user_agent ilike '%go-http%'
      or user_agent ilike '%node-fetch%'
      or user_agent ilike '%httpclient%'
      or user_agent ilike '%java/%'
    )
  on conflict (session_id) do nothing;

  -- T-04 (mission 02/09/2026, a-01 / c-06 / d-05) : referrer spam (cooked_is_spam_referrer) — la session entière
  -- est du bruit, quel que soit l'UA. Jusqu'ici seules les RPC filtraient ce referrer ; events_human ne le voyait pas.
  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'spam_referrer: ' || referrer_hostname
  from _no_bots
  where session_id is not null
    and device_type is distinct from 'server'
    and name = 'pageview'
    and public.cooked_is_spam_referrer(referrer_hostname)
  on conflict (session_id) do nothing;
end;
$function$;

-- Rattrapage historique (masquage, pas de suppression) : 7 365 sessions attendues au 03/09/2026 09:50 Paris
-- (7 252 « pc »/Baidu + 113 SEBot-WA ; 27 déjà présentes). Lecture d'events brut assumée : c'est le filet lui-même.
insert into public.noise_sessions (session_id, reason)
select distinct
  e.session_id,
  case
    when lower(e.user_agent) = 'pc'     then 'ua_bot: pc'
    when e.user_agent ilike '%sebot%'   then 'ua_bot: sebot'
    else 'spam_referrer: ' || e.referrer_hostname
  end
from public.events e
where e.session_id is not null
  and e.device_type is distinct from 'server'
  and (lower(e.user_agent) = 'pc'
       or e.user_agent ilike '%sebot%'
       or (e.name = 'pageview' and public.cooked_is_spam_referrer(e.referrer_hostname)))
on conflict (session_id) do nothing;

CREATE OR REPLACE FUNCTION public.classify_channel(ref text, utm_source text, utm_medium text, self_host text DEFAULT 'jplouton-avocat.fr'::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when ref ilike '%' || self_host || '%' then null
    -- T-04 (mission 02/09/2026, d-05) : referrer spam → canal 'spam' (94 % du canal referral était le bot Baidu).
    when public.cooked_is_spam_referrer(ref) then 'spam'
    when lower(utm_medium) in ('cpc','paid','ppc')
      or lower(utm_source) like '%google%ads%' then 'paid'
    -- Fiche Google Business : posée AVANT la branche google.*, sinon le
    -- referrer (google.com / maps) la ferait tomber dans organic_google.
    -- Le lien de la fiche est `/?utm_source=gmb`; 'gbp' couvre la variante
    -- Google Business Profile vue dans les données.
    when lower(utm_source) like 'gmb%' or lower(utm_source) like 'gbp%'
      then 'gmb'
    when ref ilike '%claude.ai%' or ref ilike '%perplexity.ai%'
      or ref ilike '%chatgpt.com%' or ref ilike '%chat.openai.com%'
      or ref ilike '%gemini.google.com%' or ref ilike '%copilot.microsoft.com%'
      or ref ilike '%grok.com%' or ref = 'x.ai' or ref ilike '%meta.ai%'
      or ref ilike '%chat.mistral.ai%' or ref ilike '%chat.deepseek.com%'
      or lower(utm_source) in ('chatgpt.com','openai','perplexity','perplexity.ai',
                               'claude.ai','gemini','copilot')
      then 'organic_ai'
    when ref ilike '%google.%' then 'organic_google'
    when ref ilike '%yahoo.%' or ref ilike '%ecosia.org%' or ref ilike '%brave.com%'
      or ref ilike '%lilo.org%' or ref ilike '%duckduckgo.%' or ref ilike '%qwant.%'
      or ref ilike '%bing.%'
      then 'organic_other'
    when ref ilike '%facebook.%' or ref ilike '%instagram.%' or ref ilike '%linkedin.%'
      or ref = 't.co' or ref ilike '%twitter.%' or ref = 'x.com'
      or ref ilike '%snapchat.%' or ref ilike '%threads.%' or ref ilike '%tiktok.%'
      or ref ilike '%youtube.%'
      then 'social'
    when ref is null or ref = '' then 'direct'
    else 'referral'
  end;
$function$;

CREATE OR REPLACE FUNCTION public.alert_rule_spam_in_events_human()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
-- T-04 (mission 02/09/2026, invariant I3) : le filet ua_bot / spam_referrer laisse-t-il passer du robot dans
-- events_human ? Fenêtre 24 h (horaire), warn dès 1 % des pageviews (garde ≥ 50 pageviews et ≥ 5 spam).
-- Découverte automatiquement par cooked_alerts_refresh() (préfixe alert_rule_, 0 argument).
DECLARE
  v_pv   bigint;
  v_spam bigint;
  v_pct  numeric;
BEGIN
  SELECT count(*) FILTER (WHERE name = 'pageview'),
         count(*) FILTER (WHERE name = 'pageview'
                            AND (lower(user_agent) = 'pc' OR user_agent ILIKE '%sebot%'
                                 OR public.cooked_is_spam_referrer(referrer_hostname)))
    INTO v_pv, v_spam
  FROM public.events_human
  WHERE occurred_at > now() - interval '24 hours';

  IF coalesce(v_pv, 0) >= 50 AND coalesce(v_spam, 0) >= 5 THEN
    v_pct := round(100.0 * v_spam / v_pv, 1);
    IF v_pct >= 1 THEN
      RETURN QUERY SELECT
        'spam_in_events_human'::text,
        'warn'::text,
        format('%s pageviews de robot / referrer spam sur %s dans events_human (24 h) = %s %% (seuil 1 %%). '
               || 'Le filet ua_bot / spam_referrer laisse passer : vérifier la version Edge (props->>''_v''), '
               || 'ingest_drops et le cron refresh_noise_filters_hourly (T-04, mission 02/09/2026).',
               v_spam, v_pv, v_pct)::text;
    END IF;
  END IF;
END;
$function$;

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
       NULL, 0)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;

  -- Retention 90j
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;

-- Convention ACL des règles d'alerte : postgres=X | service_role=X (R5, T-01).
revoke execute on function public.alert_rule_spam_in_events_human() from public, anon, authenticated;
