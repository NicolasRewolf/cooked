-- C1 fin (09/07/2026) — refresh_noise_sessions + refresh_dashboard_resources_assisted
-- adoptent cooked_events_window() au lieu de scanner events_main / events_human inline.

CREATE OR REPLACE FUNCTION public.refresh_noise_sessions()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET lock_timeout TO '15s'
 SET statement_timeout TO '300s'
AS $function$
begin
  -- Matérialise events_main × fenêtre 48h une fois (grain raw — pas anti-bruit ici :
  -- cette fonction ALIMENTE noise_sessions).
  CALL public.cooked_events_window(
    now() - interval '48 hours',
    now(),
    'raw',
    'main'
  );

  -- NON monotone (un visiteur qui revient annule le "prefetch") → on ne peut
  -- pas juste ne-plus-DELETE. On retraite uniquement les sessions actives sur
  -- 48h : delete-recent puis reinsert. Les sessions plus anciennes sont
  -- settled (aucun nouvel event) → leur classification est conservée.
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

  -- 1) prefetch / preload : 1 pageview, 0 engagement, < 10 s, sans referrer
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

  -- 2) user-agents de bots connus (fenêtre déjà bornée via _no_bots)
  insert into public.noise_sessions (session_id, reason)
  select distinct
    session_id,
    'ua_bot: ' || (
      case
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
         user_agent ilike '%headless%'
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
end;
$function$;

CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300s'
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

    CALL public.cooked_events_window(
      public.cooked_paris_ts_start(lps),
      public.cooked_paris_ts_end_exclusive(lne),
      'human',
      'main'
    );

    -- 1er pageview GLOBAL de chaque session sur le span [lps..lne] (hors Baidu)
    DROP TABLE IF EXISTS _fpv;
    CREATE TEMP TABLE _fpv ON COMMIT DROP AS
      SELECT DISTINCT ON (e.session_id) e.session_id, e.path AS entry_path, e.d AS entry_d
      FROM _cooked_ev e
      WHERE e.name='pageview'
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com'
      ORDER BY e.session_id, e.occurred_at;
    CREATE INDEX ON _fpv(session_id);
    ANALYZE _fpv;

    -- contacts macro datés (appels par session ; formulaires par cooked_sid)
    DROP TABLE IF EXISTS _ct;
    CREATE TEMP TABLE _ct ON COMMIT DROP AS
      SELECT e.session_id AS sid, e.d
      FROM _cooked_ev e
      WHERE e.name='cta_phone_click'
      UNION ALL
      SELECT e.props->>'cooked_sid', e.d
      FROM _cooked_ev e
      WHERE e.name='form_submit' AND form_submit_counts_as_macro(e.props)
        AND e.props->>'cooked_sid' IS NOT NULL;
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
