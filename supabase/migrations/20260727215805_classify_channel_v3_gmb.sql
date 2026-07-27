-- Bloc 1 / B1 — classify_channel v3 : la fiche Google Business devient un canal.
--
-- Constat du 27/07/2026. Les clics du Local Pack arrivent sur
-- `/?utm_source=gmb` avec un referrer en google.*, donc la branche
-- `when ref ilike '%google.%' then 'organic_google'` les avalait :
-- classify_channel ne testait utm_source que pour le paid et l'IA.
--
-- Ampleur mesuree sur toute l'histoire du tracking (depuis le 06/05/2026,
-- premier jour de capture) : 672 sessions, dont 667 (99,3 %) sur la home.
-- Sur 28 j (29/06 -> 26/07) : 137 des 306 entrees "organiques" de `/`
-- etaient du GMB, soit 44,8 %.
--
-- Ecart de performance qui etait masque par la moyenne :
--   fiche Google Business     163 sessions ->   6 contacts = 3,68 %
--   organique SEO reel     11 079 sessions ->  63 contacts = 0,57 %
--   autres canaux           6 196 sessions -> 110 contacts = 1,78 %
--
-- 'gmb' ne matche pas `LIKE 'organic%'` : cooked_page_index,
-- conversion_journeys et seo_to_contact_funnel cessent donc de compter ce
-- trafic comme du SEO. C'est un RESTATEMENT assume et annote, pas une
-- degradation : il corrige un chiffre qui etait faux.
--
-- Impact mesure apres application : n_org de `/` passe de 305 a 164,
-- donc grade S -> A. Son zv baisse egalement (les contacts entres par la
-- fiche sortent du numerateur organique).
--
-- L'option "nommer le canal organic_gmb pour rester capte par les filtres
-- organic% et ne rien restater" a ete ecartee : elle aurait rendu le canal
-- visible tout en laissant la contamination dans le CPI.

-- 1. Filet de securite : photo du dernier cpi_daily avant restatement,
--    meme dispositif que cpi_pre_restatement_20260712. A supprimer vers
--    le 03/08/2026.
CREATE TABLE IF NOT EXISTS public.cpi_pre_restatement_20260727 AS
SELECT * FROM public.cpi_daily
WHERE day = (SELECT max(day) FROM public.cpi_daily);

COMMENT ON TABLE public.cpi_pre_restatement_20260727 IS
  'Photo de cpi_daily avant le restatement GMB du 27/07/2026 (classify_channel v3). Table d audit temporaire — supprimer vers le 03/08/2026.';

-- 2. classify_channel v3.
CREATE OR REPLACE FUNCTION public.classify_channel(
  ref text, utm_source text, utm_medium text,
  self_host text DEFAULT 'jplouton-avocat.fr'::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when ref ilike '%' || self_host || '%' then null
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

COMMENT ON FUNCTION public.classify_channel(text,text,text,text) IS
  'v3 (27/07/2026) : ajout du canal gmb (fiche Google Business), pose AVANT la '
  'branche google.* — sans quoi le referrer google.* la classait organic_google. '
  '672 sessions concernees depuis le 06/05/2026, dont 99,3 % sur la home. '
  'gmb ne matche PAS organic%% : le trafic fiche sort donc du CPI, de '
  'conversion_journeys et de seo_to_contact_funnel. Restatement annote le 27/07.';

-- 3. Journal des evenements hors-site.
INSERT INTO public.annotations (day, kind, label, paths)
VALUES (
  public.paris_today(),
  'site_change',
  'Restatement CPI — classify_channel v3 : le trafic de la fiche Google Business '
  '(utm_source=gmb) sort du canal organic_google. 137 des 306 entrees organiques '
  'de la home sur 28 j etaient du GMB (44,8 %). Attendu : n_org de / passe de ~305 '
  'a ~169 (grade S -> A) et son zv baisse. Un avant/apres 27/07 sur la home dans '
  'cpi_daily n est PAS un decay. Photo dans cpi_pre_restatement_20260727.',
  ARRAY['/']
);
