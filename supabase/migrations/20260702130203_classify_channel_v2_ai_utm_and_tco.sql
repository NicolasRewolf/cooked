-- T-15 (audit 02/07/2026) — classify_channel v2. IMMUTABLE, appliquée à la
-- lecture → correction RÉTROACTIVE des canaux. RESTATEMENT : ~60 pageviews/90j
-- basculent de direct/social/referral vers organic_ai.
--
-- DÉVIATION vs plan (contre-vérification données 90j, prime sur le plan) :
--   - T-15.2 Yahoo : CADUC. referrer_hostname est TOUJOURS un hôte nu
--     (fr.search.yahoo.com…), jamais une URL avec RU= → le self-host ne matche
--     jamais en sous-chaîne, Yahoo tombe déjà en organic_other. Vérifié 90j :
--     0 referrer avec '://', 0 hôte non-self contenant 'jplouton'. NE PAS
--     "réparer" ce faux bug une 2e fois.
--   - T-15.3 t.co : les '%t.co%' étaient tous des faux-positifs de sous-chaîne
--     (qwant/chatgpt/microsoft…) déjà classés par des branches antérieures →
--     0 vrai lien t.co sur 90j. On durcit quand même en EXACT (défensif) +
--     snapchat/twitter/x explicites (sinon snapchat perdrait 'social').
-- Fix réel : T-15.1 — IA détectée aussi via utm_source (~60 pv organiques IA
--   arrivaient sans referrer IA) + referrers IA ajoutés (grok/x.ai/meta.ai/
--   mistral/deepseek).
CREATE OR REPLACE FUNCTION public.classify_channel(ref text, utm_source text, utm_medium text, self_host text DEFAULT 'jplouton-avocat.fr'::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when ref ilike '%' || self_host || '%' then null
    when lower(utm_medium) in ('cpc','paid','ppc')
      or lower(utm_source) like '%google%ads%' then 'paid'
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
