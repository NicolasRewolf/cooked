-- T-09 (mission 02/09/2026, #110) — étape 2/3 : UNE fenêtre « N jours » pour les contacts, UN grain par ratio.
--
-- Constats : d-02/c-05 (P1) « contacts macro 28 j » = 183 / 189 / 195 selon la RPC, 100 % imputable à la fenêtre (live = jour
-- en cours partiel, live_j1, gsc) et la réponse changeait avec l'heure de la question (`now() - make_interval`) ; d-06/c-01 (P1)
-- seo_to_contact_funnel divisait des contacts comptés sur le visiteur RECOUSU par des entrées comptées sur la session BRUTE,
-- sur trois fenêtres dont une en `current_date` UTC sans borne Google (24 j de GSC face à 28 j d'entrées) ; o-14 (P3)
-- classify_channel ignorait gclid/gbraid/wbraid (16 entrées/28 j taguées gmb + 3 direct portaient un identifiant Ads).
-- Récidive : Arch #1 (10/07) avait converti le dashboard aux bornes uniques mais laissé ces RPC ; désalignement du funnel
-- signalé le 25/07 et jamais corrigé (39 j).
--
-- Changement :
--   1. classify_channel v5 : 5e paramètre `url` (défaut NULL) ; un identifiant de clic Ads dans l'URL d'atterrissage ⇒ 'paid',
--      posé avant la branche gmb (décision Nicolas : paid prime). Les appels à 4 arguments gardent leur comportement.
--   2. form_submits_attributed(days_back, p_end) / conversion_journeys(days_back, p_end) : days_back jours Paris CLOS, ancrés
--      sur J-1 Paris via cooked_period_bounds('rolling_28','live_j1') (p_end pour aligner sur une autre borne close).
--      Statut macro des formulaires par form_submit_counts_as_macro(props) — une seule définition avec site_macro_counts.
--      Bornes exposées en sortie (window_start / window_end).
--   3. macro_contacts_by_path(days_back) : même ancre J-1 (avant : jour en cours inclus, lens live).
--   4. seo_to_contact_funnel(days_back, p_end) : les trois sources (GSC, entrées, contacts) sur la même fenêtre close à
--      gsc_last_data_day() (lens 'cross') ; dénominateur = entrées de VISITE RECOUSUE (identity_stitch, coupure 30 min — la clé
--      de conversion_journeys) ; FULL JOIN entrées/contacts (aucun contact n'est perdu si sa page d'entrée n'a pas d'entrée
--      organique comptée). Bornes exposées.
--   5. gsc_pages_overview : contacts sur les bornes GSC de la ligne (plus macro_contacts_by_path(28) = live).
--   6. cooked_page_index : terme zv sur la fenêtre du score — conversion_journeys(p_days, gsc_last_data_day()) ; le CPI n'a
--      plus aucune borne d'horloge. Restatement zv : photo « avant » dans cpi_pre_restatement_20260903 (colonne phase),
--      annotation dans la migration suivante (étape 3/3).
--   7. Invariant I4 : trois contract-tests (`contacts_28j_une_fenetre`, `funnel_meme_total_que_journeys`,
--      `classify_channel_gclid_paid`).
-- Corps de gsc_pages_overview, cooked_page_index et run_rpc_contract_tests générés depuis la prod (rpcs.sql, sha vérifié) par
-- substitutions ciblées ; les autres réécrits. Signatures modifiées ⇒ DROP + CREATE, ACL réappliquées à l'identique.

-- 1. classify_channel v5 : gclid/gbraid/wbraid ⇒ paid.
DROP FUNCTION public.classify_channel(text, text, text, text);

CREATE FUNCTION public.classify_channel(ref text, utm_source text, utm_medium text, self_host text DEFAULT 'jplouton-avocat.fr'::text, url text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when ref ilike '%' || self_host || '%' then null
    -- T-04 (mission 02/09/2026, d-05) : referrer spam → canal 'spam' (94 % du canal referral était le bot Baidu).
    when public.cooked_is_spam_referrer(ref) then 'spam'
    -- T-09 (mission 02/09/2026, o-14) : un identifiant de clic Ads (gclid / gbraid / wbraid) dans l'URL d'atterrissage
    -- = paid, quel que soit l'utm_source — décision « paid prime » sur le chevauchement paid/GMB (16 entrées/28 j
    -- taguées utm_source=gmb portaient un gclid). `url` est facultatif : les appels à 4 arguments sont inchangés.
    when url ~* '[?&](gclid|gbraid|wbraid)=' then 'paid'
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

REVOKE ALL ON FUNCTION public.classify_channel(text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.classify_channel(text, text, text, text, text) TO service_role;
COMMENT ON FUNCTION public.classify_channel(text, text, text, text, text) IS
  'Taxonomie unifiée des canaux (v5, T-09 03/09/2026) : self_host→NULL, spam, gclid/gbraid/wbraid dans url→paid, utm paid, gmb, organic_ai, organic_google, organic_other, social, direct, referral. url facultatif.';

-- 2a. form_submits_attributed : jours Paris clos, une seule définition du statut macro.
DROP FUNCTION public.form_submits_attributed(integer);
CREATE FUNCTION public.form_submits_attributed(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(event_id uuid, occurred_at timestamp with time zone, form_path text, objet text, counts_as_macro boolean, resolved_anonymous_id text, resolved_session_id text, attribution_method text, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-02) : fenêtre = days_back jours Paris CLOS, ancrés par défaut sur J-1 Paris
  -- (cooked_period_bounds, lens 'live_j1') ; p_end permet d'aligner sur une autre borne close (CPI : gsc_last_data_day()).
  -- Avant : `occurred_at > now() - make_interval(...)` — la réponse changeait avec l'heure de la question.
  -- Le statut macro passe par form_submit_counts_as_macro(props) : une seule définition avec site_macro_counts.
  -- Lecture de `events` brut assumée : les form_submit sont insérés server-side, jamais classés bot ni bruit.
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  forms as (
    select e.id, e.occurred_at, e.path,
      e.props->>'objet_de_ma_demande' as objet,
      public.form_submit_counts_as_macro(e.props) as counts_as_macro,
      nullif(e.props->>'cooked_aid','') as hf_aid,
      nullif(e.props->>'cooked_sid','') as hf_sid
    from public.events e
    where e.name = 'form_submit'
      and public.paris_date(e.occurred_at) between (select d_start from w) and (select d_end from w)
  ),
  temporal as (
    -- candidat unique : visiteurs browser actifs sur la page du form
    -- dans les 20 min avant → 3 min après le submit
    select f.id as form_id,
      (array_agg(distinct e.anonymous_id)) as aids,
      (array_agg(distinct e.session_id)) as sids
    from forms f
    join public.events_human e
      on e.path = coalesce(f.path, '/honoraires-rendez-vous')
     and e.device_type is distinct from 'server'
     and e.anonymous_id not like 'webhook-%'
     and e.occurred_at between f.occurred_at - interval '20 min'
                           and f.occurred_at + interval '3 min'
    where f.hf_aid is null
    group by f.id
    having count(distinct e.anonymous_id) = 1
  )
  select f.id, f.occurred_at, f.path, f.objet, f.counts_as_macro,
    coalesce(f.hf_aid, t.aids[1]),
    coalesce(f.hf_sid, t.sids[1]),
    case
      when f.hf_aid is not null then 'hidden_field'
      when t.aids[1] is not null then 'temporal_unique'
      else 'unresolved'
    end,
    w.d_start, w.d_end
  from forms f
  cross join w
  left join temporal t on t.form_id = f.id;
$function$;
REVOKE ALL ON FUNCTION public.form_submits_attributed(integer, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.form_submits_attributed(integer, date) TO service_role;

-- 2b. conversion_journeys v3 : mêmes bornes closes ; url passée à classify_channel.
DROP FUNCTION public.conversion_journeys(integer);
CREATE FUNCTION public.conversion_journeys(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(contact_kind text, occurred_at timestamp with time zone, contact_path text, objet text, anonymous_id text, attribution_method text, entry_path text, entry_channel text, pages_count integer, journey text[], device_type text, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-02) : fenêtre = days_back jours Paris CLOS ancrés sur J-1 (lens 'live_j1'), ou sur
  -- p_end (CPI : gsc_last_data_day()). Même fenêtre que form_submits_attributed(days_back, p_end), site_macro_counts et
  -- macro_contacts_by_path sur les mêmes bornes ⇒ un seul total de contacts (contract-test contacts_28j_une_fenetre).
  -- Avant : `occurred_at > now() - make_interval(...)`. Le parcours (visite recousue, coupure 30 min) est inchangé (v2, 12/07).
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'live_j1') b
  ),
  contacts as (
    select 'phone'::text as kind, e.occurred_at, e.path as contact_path,
      null::text as objet, e.anonymous_id, e.session_id, 'direct'::text as method
    from public.events_human e
    where e.name = 'cta_phone_click'
      and public.paris_date(e.occurred_at) between (select d_start from w) and (select d_end from w)
    union all
    select 'form', f.occurred_at, f.form_path, f.objet,
      f.resolved_anonymous_id, f.resolved_session_id, f.attribution_method
    from public.form_submits_attributed(days_back, p_end) f
    where f.counts_as_macro
  ),
  ck as (
    select c.*,
      coalesce(ss.visitor_key, sa.visitor_key,
               'sid:' || coalesce(c.session_id, c.anonymous_id, 'inconnu')) as vk
    from contacts c
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = c.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = c.anonymous_id
  ),
  -- sessions couvertes par chaque visiteur porteur de contact
  -- (fallback : la session brute du contact si la couture ne la connaît
  -- pas encore — sessions plus récentes que le dernier refresh du stitch)
  vsess as (
    select k.vk, st.key as sid
    from (select distinct vk from ck) k
    join public.identity_stitch st on st.kind = 'sid' and st.visitor_key = k.vk
    union
    select c.vk, c.session_id from ck c where c.session_id is not null
  )
  select s.kind, s.occurred_at, s.contact_path, s.objet, s.anonymous_id, s.method,
    s.journey[1],
    public.classify_channel(s.first_ref, s.first_utm_source, s.first_utm_medium, 'www.jplouton-avocat.fr', s.first_url),
    coalesce(array_length(s.journey, 1), 0),
    s.journey,
    s.dev,
    w.d_start, w.d_end
  from (
    select c.kind, c.occurred_at, c.contact_path, c.objet, c.anonymous_id, c.method,
      j.journey, j.first_ref, j.first_utm_source, j.first_utm_medium, j.first_url,
      (select e6.device_type from public.events_human e6
        where e6.session_id in (select v2.sid from vsess v2 where v2.vk = c.vk)
          and e6.device_type is distinct from 'server'
        limit 1) as dev
    from ck c
    left join lateral (
      with pv as (
        select e2.path, e2.occurred_at as t,
               e2.referrer_hostname, e2.utm_source, e2.utm_medium, e2.url
        from public.events_human e2
        where e2.name = 'pageview'
          and e2.session_id in (select v.sid from vsess v where v.vk = c.vk)
          and e2.occurred_at <= c.occurred_at + interval '3 min'
          and e2.occurred_at >= c.occurred_at - interval '6 hours'
      ),
      seg as (
        select pv.*,
          case when pv.t - lag(pv.t) over (order by pv.t) > interval '30 minutes'
               then pv.t end as brk
        from pv
      ),
      chain as (
        select * from seg
        where seg.t >= coalesce((select max(s2.brk) from seg s2), '-infinity'::timestamptz)
      )
      select
        (select array_agg(q.path order by q.first_seen)
           from (select ch.path, min(ch.t) as first_seen from chain ch group by ch.path) q) as journey,
        (select ch.referrer_hostname from chain ch order by ch.t limit 1) as first_ref,
        (select ch.utm_source from chain ch order by ch.t limit 1) as first_utm_source,
        (select ch.utm_medium from chain ch order by ch.t limit 1) as first_utm_medium,
        (select ch.url from chain ch order by ch.t limit 1) as first_url
    ) j on true
  ) s
  cross join w
  order by s.occurred_at desc;
$function$;
REVOKE ALL ON FUNCTION public.conversion_journeys(integer, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.conversion_journeys(integer, date) TO service_role;

-- 3. macro_contacts_by_path(days_back) : même ancre J-1 que conversion_journeys(days_back).
CREATE OR REPLACE FUNCTION public.macro_contacts_by_path(days_back integer)
 RETURNS TABLE(path text, phone_clicks bigint, form_submits bigint, contacts bigint, booking_intent bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-02) : days_back jours Paris CLOS ancrés sur J-1 (lens 'live_j1'), comme
  -- conversion_journeys(days_back). Avant : paris_today() - (days_back - 1) → paris_today() = jour en cours partiel.
  SELECT m.*
  FROM public.cooked_period_bounds('rolling_28', 'live_j1') b,
       LATERAL public.macro_contacts_by_path(b.n_end - (days_back - 1), b.n_end) m;
$function$;

-- 4. seo_to_contact_funnel v2 : une fenêtre (cross), un grain (visite recousue), aucun contact perdu.
DROP FUNCTION public.seo_to_contact_funnel(integer);
CREATE FUNCTION public.seo_to_contact_funnel(days_back integer DEFAULT 28, p_end date DEFAULT NULL::date)
 RETURNS TABLE(entry_path text, page_type text, theme text, gsc_impressions bigint, gsc_clicks bigint, top_queries text[], organic_entries bigint, contacts bigint, contacts_phone bigint, contacts_form bigint, contact_rate_pct numeric, window_start date, window_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  -- T-09 (mission 02/09/2026, #110 — d-06/c-01) : UNE fenêtre pour les trois sources (GSC, entrées, contacts) = days_back
  -- jours clos à gsc_last_data_day() (lens 'cross'), p_end pour surcharger. UN grain pour le ratio : le dénominateur compte
  -- les entrées de VISITE RECOUSUE (identity_stitch, coupure 30 min — la clé de conversion_journeys), plus la session brute.
  -- FULL JOIN entrées/contacts : un contact dont la page d'entrée n'a aucune entrée organique comptée reste visible
  -- (organic_entries = 0, taux NULL) au lieu de disparaître — Σ contacts = conversion_journeys organiques (contract-test).
  -- Avant : entrées sur session brute et `now()` glissant, GSC sur `current_date` UTC sans borne Google (24 j de données).
  with w as (
    select coalesce(p_end, b.n_end) as d_end,
           coalesce(p_end, b.n_end) - (days_back - 1) as d_start
    from public.cooked_period_bounds('rolling_28', 'cross') b
  ),
  pv as (
    select coalesce(ss.visitor_key, sa.visitor_key,
                    'sid:' || coalesce(e.session_id, e.anonymous_id, 'inconnu')) as vk,
           e.path, e.occurred_at as t, e.referrer_hostname, e.utm_source, e.utm_medium, e.url
    from public.events_human e
    left join public.identity_stitch ss on ss.kind = 'sid' and ss.key = e.session_id
    left join public.identity_stitch sa on sa.kind = 'aid' and sa.key = e.anonymous_id
    where e.name = 'pageview' and e.path is not null
      -- bornes en sous-requêtes scalaires (InitPlan) : un CROSS JOIN sur w faisait perdre l'index idx_events_paris_date
      and public.paris_date(e.occurred_at) between (select d_start from w) and (select d_end from w)
  ),
  entries as (
    select s.vk, s.path, s.referrer_hostname, s.utm_source, s.utm_medium, s.url
    from (
      select pv.*, lag(pv.t) over (partition by pv.vk order by pv.t) as prev_t
      from pv
    ) s
    where s.prev_t is null or s.t - s.prev_t > interval '30 minutes'
  ),
  organic as (
    select en.path as entry_path, count(*) as organic_entries
    from entries en
    where public.classify_channel(en.referrer_hostname, en.utm_source, en.utm_medium,
                                  'www.jplouton-avocat.fr', en.url) like 'organic%'
    group by en.path
  ),
  conv as (
    select j.entry_path,
      count(*) as contacts,
      count(*) filter (where j.contact_kind = 'phone') as contacts_phone,
      count(*) filter (where j.contact_kind = 'form')  as contacts_form
    from public.conversion_journeys(days_back, (select d_end from w)) j
    where j.entry_channel like 'organic%' and j.entry_path is not null
    group by j.entry_path
  ),
  gsc as (
    select g.path, sum(g.impressions) as impressions, sum(g.clicks) as clicks
    from public.gsc_path_daily g
    where g.day between (select d_start from w) and (select d_end from w)
    group by g.path
  ),
  topq as (
    select path, array_agg(query order by clicks desc) as top_queries
    from (
      select q.path, q.query, sum(q.clicks) as clicks,
        row_number() over (partition by q.path order by sum(q.clicks) desc) as rn
      from public.gsc_query_page_daily q
      where q.day between (select d_start from w) and (select d_end from w)
      group by q.path, q.query
    ) r where rn <= 3
    group by path
  ),
  pages as (
    select coalesce(o.entry_path, c.entry_path) as entry_path,
           coalesce(o.organic_entries, 0) as organic_entries,
           coalesce(c.contacts, 0) as contacts,
           coalesce(c.contacts_phone, 0) as contacts_phone,
           coalesce(c.contacts_form, 0) as contacts_form
    from organic o
    full join conv c on c.entry_path = o.entry_path
  )
  select
    p.entry_path, public.cooked_page_type(p.entry_path), t.theme,
    coalesce(g.impressions, 0), coalesce(g.clicks, 0), tq.top_queries,
    p.organic_entries, p.contacts, p.contacts_phone, p.contacts_form,
    round(100.0 * p.contacts / nullif(p.organic_entries, 0), 2),
    w.d_start, w.d_end
  from pages p
  cross join w
  left join gsc g   on g.path = p.entry_path
  left join topq tq on tq.path = p.entry_path
  left join public.page_taxonomy t on t.path = p.entry_path
  order by p.contacts desc, coalesce(g.clicks, 0) desc;
$function$;
REVOKE ALL ON FUNCTION public.seo_to_contact_funnel(integer, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.seo_to_contact_funnel(integer, date) TO service_role;

-- 5. gsc_pages_overview : contacts sur les bornes GSC de la ligne.

CREATE OR REPLACE FUNCTION public.gsc_pages_overview(max_rows integer DEFAULT 30)
 RETURNS TABLE(path text, gsc_clicks_28d bigint, gsc_impressions_28d bigint, gsc_position_avg_28d numeric, gsc_ctr_pct_28d numeric, cooked_sessions_28d bigint, cooked_dwell_avg_s_28d numeric, cooked_bounce_rate_28d numeric, cooked_phone_clicks_28d bigint, cooked_form_submits_28d bigint, cooked_contacts_28d bigint, cooked_booking_intent_28d bigint, cooked_pogo_rate_28d numeric, has_cooked_data boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- T-05 (mission 02/09/2026, #106 — d-03) : « 28 j » = 28 jours GSC clos à gsc_last_data_day() (lens 'gsc'), plus la
  -- fenêtre brute `paris_today() - 27` qui ne contenait que 24-25 jours de données (lag Google J-3/J-4 : −12 à −17 %
  -- de clics selon le jour). Récidive du 24/05/2026 (off-by-one corrigé, alignement GSC jamais fait).
  -- T-09 (#110 — d-02) : les contacts de la ligne sont comptés sur les MÊMES bornes GSC (macro_contacts_by_path(n_start,
  -- n_end)) — avant macro_contacts_by_path(28) = jour en cours inclus. seo_url_snapshot garde sa fenêtre nocturne propre.
  WITH b AS (
    SELECT n_start, n_end FROM public.cooked_period_bounds('rolling_28', 'gsc') LIMIT 1
  ),
  g AS (
    SELECT path,
      SUM(impressions)::bigint AS impressions_total,
      SUM(clicks)::bigint AS clicks_total,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((SUM(position * impressions) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS position_avg,
      CASE WHEN SUM(impressions) > 0
           THEN ROUND((100.0 * SUM(clicks) / SUM(impressions))::numeric, 2)
           ELSE NULL END AS ctr_pct
    FROM gsc_path_daily
    WHERE day BETWEEN (SELECT n_start FROM b) AND (SELECT n_end FROM b)
    GROUP BY path
  )
  SELECT
    g.path,
    g.clicks_total,
    g.impressions_total,
    g.position_avg,
    g.ctr_pct,
    COALESCE(s.sessions_28d, 0),
    s.avg_dwell_seconds_28d,
    s.bounce_rate_28d,
    COALESCE(mc.phone_clicks, 0),
    COALESCE(mc.form_submits, 0),
    COALESCE(mc.contacts, 0),
    COALESCE(mc.booking_intent, 0),
    s.pogo_rate_28d,
    (s.path IS NOT NULL)
  FROM g
  LEFT JOIN seo_url_snapshot s ON s.path = g.path
  LEFT JOIN macro_contacts_by_path((SELECT n_start FROM b), (SELECT n_end FROM b)) mc ON mc.path = g.path
  ORDER BY g.clicks_total DESC, g.impressions_total DESC
  LIMIT max_rows;
$function$;


-- 6. cooked_page_index : terme zv (conversion_journeys) sur la fenêtre du score.

CREATE OR REPLACE FUNCTION public.cooked_page_index(p_days integer DEFAULT 28)
 RETURNS TABLE(path text, ptype text, grade text, cpi integer, cpi_raw integer, momentum numeric, momentum_badge text, gate numeric, zc numeric, zr numeric, zl numeric, zv numeric, clics_perdus integer, n_org bigint, couv_gsc_pct integer, convertit boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- T-05 (mission 02/09/2026, #106 — d-03/d-07/f-04) : UNE fenêtre pour tout le score. Côté GSC : p_days jours clos à
-- gsc_last_data_day() (avant : borne sur la date serveur, soit 24 jours de données réelles sur 28 nominaux, lag Google J-4).
-- Côté Cooked : les MÊMES jours Paris, bornés par cooked_paris_ts_start/_end_exclusive (avant : 28 × 24 h glissantes, borne
-- qui glissait avec l'heure du run — deux snapshots consécutifs étaient séparés de 18 à 34 h). Le score d'un jour donné
-- est désormais reproductible. T-09 (#110) : le terme zv (conversion_journeys) est lui aussi clos à gsc_last_data_day() —
-- plus aucune borne d'horloge dans le score ; url passée à classify_channel (gclid ⇒ paid, o-14).
WITH w AS (
  SELECT g.g_end,
         public.cooked_paris_ts_start(g.g_end - (p_days - 1)) AS t0,
         public.cooked_paris_ts_end_exclusive(g.g_end)        AS t1
  FROM (SELECT public.gsc_last_data_day() AS g_end) g
),
fit AS (
  SELECT regr_slope(ln(ctr), ln(pos)) AS pente, regr_intercept(ln(ctr), ln(pos)) AS icept
  FROM (SELECT round(position)::int pos, (sum(clicks)+1.0)/(sum(impressions)+20.0) ctr
        FROM public.gsc_query_page_daily WHERE day > (SELECT g_end FROM w) - 90 AND NOT public.gsc_is_branded(query)
        GROUP BY 1 HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions) >= 200) b
),
capq AS (SELECT g.path, sum(g.impressions) i_qpd,
    sum(g.impressions * least(greatest(exp(f.icept + f.pente*ln(greatest(g.position,1.0))),0.0005),0.5)) e_qpd
  FROM public.gsc_query_page_daily g, fit f WHERE g.day > (SELECT g_end FROM w) - p_days AND NOT public.gsc_is_branded(g.query) GROUP BY g.path),
capb AS (SELECT path, sum(clicks) o_b, sum(impressions) i_b FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - p_days AND public.gsc_is_branded(query) GROUP BY path),
capp AS (SELECT path, sum(clicks) o_full, sum(impressions) i_full FROM public.gsc_path_daily WHERE day > (SELECT g_end FROM w) - p_days GROUP BY path),
cap AS (SELECT p.path, greatest(p.o_full - coalesce(b.o_b,0),0)::numeric AS o,
    CASE WHEN coalesce(q.i_qpd,0)>0 THEN q.e_qpd*(greatest(p.i_full-coalesce(b.i_b,0),0)::numeric/q.i_qpd) ELSE NULL END AS e,
    q.i_qpd, greatest(p.i_full-coalesce(b.i_b,0),0) AS i_nb
  FROM capp p LEFT JOIN capq q ON q.path=p.path LEFT JOIN capb b ON b.path=p.path),
firstpv AS (SELECT DISTINCT ON (session_id) session_id, eh.path,
    public.classify_channel(referrer_hostname, utm_source, utm_medium,'www.jplouton-avocat.fr', url) chan
  FROM public.events_human eh WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) ORDER BY session_id, occurred_at),
orge AS (SELECT session_id, firstpv.path FROM firstpv WHERE chan LIKE 'organic%'),
norg AS (SELECT orge.path, count(*) n_org FROM orge GROUP BY orge.path),
spv AS (SELECT session_id, count(*) pv FROM public.events_human WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) GROUP BY session_id),
pex AS (SELECT e.session_id, e.path,
    max((e.props->>'duration_seconds')::numeric) d,
    max(coalesce((e.props->>'max_scroll')::numeric,0)) s
  FROM public.events_human e
  WHERE e.name='page_exit' AND e.occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w)
  GROUP BY e.session_id, e.path),
ex2 AS (SELECT o.path, public.cooked_page_type(o.path) ptype, px.d,
    coalesce(px.s,0) s,
    (px.d >= 15 OR coalesce(s2.pv,1) >= 2) retained
  FROM orge o JOIN pex px ON px.session_id=o.session_id AND px.path=o.path
  LEFT JOIN spv s2 ON s2.session_id=o.session_id),
thr AS (SELECT ptype, percentile_cont(0.5) WITHIN GROUP (ORDER BY d) tau, percentile_cont(0.5) WITHIN GROUP (ORDER BY s) sig FROM ex2 WHERE retained GROUP BY ptype),
reads AS (SELECT e.path, max(e.ptype) ptype, count(*) n, count(*) FILTER (WHERE retained) r,
    count(*) FILTER (WHERE retained AND d >= t.tau AND s >= t.sig) k FROM ex2 e JOIN thr t ON t.ptype=e.ptype GROUP BY e.path),
tmeans AS (SELECT ptype, coalesce(sum(r)::numeric/nullif(sum(n),0),0.5) rho, coalesce(sum(k)::numeric/nullif(sum(r),0),0.25) q FROM reads GROUP BY ptype),
ebk AS (
  SELECT t.ptype, t.rho, t.q,
    CASE WHEN er.np>=5 AND er.v>0 AND er.v < t.rho*(1-t.rho) THEN least(greatest(t.rho*(1-t.rho)/er.v - 1, 5), 200) ELSE 20 END kappa_ret,
    CASE WHEN el.np>=5 AND el.v>0 AND el.v < t.q*(1-t.q) THEN least(greatest(t.q*(1-t.q)/el.v - 1, 5), 200) ELSE 20 END kappa_lec
  FROM tmeans t
  LEFT JOIN (SELECT ptype, var_samp(r::numeric/n) v, count(*) np FROM reads WHERE n>=10 GROUP BY ptype) er ON er.ptype=t.ptype
  LEFT JOIN (SELECT ptype, var_samp(k::numeric/nullif(r,0)) v, count(*) np FROM reads WHERE r>=10 GROUP BY ptype) el ON el.ptype=t.ptype
),
jx AS (SELECT * FROM public.conversion_journeys(p_days, (SELECT g_end FROM w)) WHERE entry_channel LIKE 'organic%'),
direct AS (SELECT entry_path path, count(*)::numeric v FROM jx WHERE entry_path IS NOT NULL GROUP BY 1),
assist AS (SELECT jp.path, sum(1.0/greatest(j.pages_count,1)) v FROM jx j CROSS JOIN LATERAL unnest(j.journey) jp(path) WHERE jp.path <> j.entry_path GROUP BY jp.path),
book AS (SELECT o.path, 0.25*count(*)::numeric v FROM orge o JOIN public.events_human b ON b.session_id=o.session_id AND b.path=o.path AND b.name='cta_booking_click' GROUP BY o.path),
convv AS (SELECT n.path, n.n_org, coalesce(d.v,0)+coalesce(a.v,0)+coalesce(b.v,0) val
  FROM norg n LEFT JOIN direct d ON d.path=n.path LEFT JOIN assist a ON a.path=n.path LEFT JOIN book b ON b.path=n.path),
tconv AS (SELECT public.cooked_page_type(convv.path) ptype, coalesce(sum(val)/nullif(sum(convv.n_org),0),0) nu FROM convv GROUP BY 1),
xs AS (
  SELECT r.path, r.ptype, c.n_org, c.val, coalesce(cap.o,0) o, cap.e, coalesce(cap.i_qpd,0) i_qpd, coalesce(cap.i_nb,0) i_nb,
    coalesce(ln((coalesce(cap.o,0)+3)/(cap.e+3)),0) x_cap,
    ln( least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999) / (1-least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999)) ) x_ret,
    ln( least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999) / (1-least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999)) ) x_lec,
    ln( (c.val + 30*tc.nu + 0.05)/(c.n_org+30) ) x_conv
  FROM reads r JOIN convv c ON c.path=r.path LEFT JOIN cap ON cap.path=r.path
  JOIN ebk tm ON tm.ptype=r.ptype JOIN tconv tc ON tc.ptype=r.ptype
  WHERE c.n_org >= 5 AND r.n >= 3
),
medt AS (SELECT ptype, count(*) cnt, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs GROUP BY ptype),
madt AS (SELECT x.ptype,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-m.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-m.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-m.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-m.mv)),0.15) sv FROM xs x JOIN medt m ON m.ptype=x.ptype GROUP BY x.ptype),
medg AS (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs),
madg AS (SELECT greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-g.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-g.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-g.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-g.mv)),0.15) sv FROM xs x, medg g),
mom AS (SELECT g.path,
    coalesce(sum(clicks) FILTER (WHERE day > (SELECT g_end FROM w) - p_days),0) c1,
    coalesce(sum(clicks) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days),0) c0,
    avg(position) FILTER (WHERE day > (SELECT g_end FROM w) - p_days) p1,
    avg(position) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days) p0
  FROM public.gsc_query_page_daily g
  WHERE g.day > (SELECT g_end FROM w) - 2*p_days AND NOT public.gsc_is_branded(g.query)
  GROUP BY g.path),
site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom),
lcp AS (SELECT eh.path, percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric) lcp75
  FROM public.events_human eh WHERE name='web_vitals' AND props->>'metric'='LCP' AND device_type='mobile'
    AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) GROUP BY eh.path),
scored AS (
  SELECT x.path, x.ptype, x.n_org, round(greatest(coalesce(x.e,0)-x.o,0))::int clics_perdus,
    CASE WHEN coalesce(x.i_nb,0)>0 THEN round(100.0*x.i_qpd/x.i_nb)::int ELSE 0 END couv,
    round(least(greatest((x.x_cap - CASE WHEN mt.cnt>=15 THEN mt.mc ELSE mg.mc END)/(CASE WHEN mt.cnt>=15 THEN dt.sc ELSE dg.sc END),-3),3)::numeric,1) zc,
    round(least(greatest((x.x_ret - CASE WHEN mt.cnt>=15 THEN mt.mr ELSE mg.mr END)/(CASE WHEN mt.cnt>=15 THEN dt.sr ELSE dg.sr END),-3),3)::numeric,1) zr,
    round(least(greatest((x.x_lec - CASE WHEN mt.cnt>=15 THEN mt.ml ELSE mg.ml END)/(CASE WHEN mt.cnt>=15 THEN dt.sl ELSE dg.sl END),-3),3)::numeric,1) zl,
    round(least(greatest((x.x_conv - CASE WHEN mt.cnt>=15 THEN mt.mv ELSE mg.mv END)/(CASE WHEN mt.cnt>=15 THEN dt.sv ELSE dg.sv END),-3),3)::numeric,1) zv,
    round(exp(least(greatest(
      (1 - 1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (-0.08*coalesce(m.p1-m.p0,0))
      + (1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (ln((coalesce(m.c1,0)+5.0)/(coalesce(m.c0,0)+5.0)) - ln((s.s1+50.0)/(s.s0+50.0)))
    ,-0.336),0.336))::numeric,2) mm,
    round((1 - 0.15*least(greatest((coalesce(l.lcp75,2500)-2500)/2500.0,0),1))::numeric,2) gg,
    CASE
      WHEN x.n_org >= 200 AND coalesce(x.e,0) >= 40 THEN 'S'
      WHEN x.n_org >= 100 AND coalesce(x.e,0) >= 20 THEN 'A'
      WHEN x.n_org >= 30 AND coalesce(x.e,0) >= 5 THEN 'B'
      ELSE 'C'
    END grade,
    coalesce(cv.val, 0) > 0 AS convertit
  FROM xs x LEFT JOIN medt mt ON mt.ptype=x.ptype LEFT JOIN madt dt ON dt.ptype=x.ptype
  CROSS JOIN medg mg CROSS JOIN madg dg LEFT JOIN mom m ON m.path=x.path CROSS JOIN site s LEFT JOIN lcp l ON l.path=x.path
  LEFT JOIN convv cv ON cv.path=x.path
)
SELECT scored.path, scored.ptype, scored.grade,
  least(100, round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int) cpi,
  round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int cpi_raw,
  mm momentum, (CASE WHEN mm>=1.15 THEN '↗' WHEN mm<=0.87 THEN '↘' ELSE '→' END) momentum_badge,
  gg gate, zc, zr, zl, zv, clics_perdus, n_org, couv couv_gsc_pct, convertit
FROM scored
$function$;


-- 7. run_rpc_contract_tests : invariant I4 (une notion = un chiffre) + o-14.

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
       NULL, 0),

      -- T-05 (mission 02/09/2026, invariant I4) : « 28 j » GSC = 28 jours clos à gsc_last_data_day(). Écart attendu 0.
      ('gsc_pages_overview_28d_alignes',
       $q$select abs(coalesce((select sum(gsc_clicks_28d) from public.gsc_pages_overview(100000)), 0)
                 - coalesce((select sum(g.clicks) from public.gsc_path_daily g,
                               public.cooked_period_bounds('rolling_28', 'gsc') b
                             where g.day between b.n_start and b.n_end), 0))$q$,
       NULL, 0),

      -- T-05 (invariants I4/I10) : aucune borne d'horloge dans le CPI — ses fenêtres sont closes à gsc_last_data_day()
      -- et le score d'un jour est reproductible. 0 occurrence attendue de now()/current_date/… dans le corps.
      ('cpi_sans_horloge',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'now\(\)|current_date|current_timestamp|localtimestamp', 'gi')$q$,
       NULL, 0),

      -- T-09 (mission 02/09/2026, invariant I4) : « contacts macro 28 j » = UN chiffre. site_macro_counts sur les bornes
      -- live_j1 = Σ macro_contacts_by_path(28) = conversion_journeys(28) (téléphone + formulaires macro). Écart attendu 0.
      ('contacts_28j_une_fenetre',
       $q$with b as (select n_start, n_end from public.cooked_period_bounds('rolling_28', 'live_j1')),
               s as (select sm.macro_conversions as n from b, public.site_macro_counts(b.n_start, b.n_end) sm),
               m as (select coalesce(sum(contacts), 0) as n from public.macro_contacts_by_path(28)),
               j as (select count(*) as n from public.conversion_journeys(28))
          select abs((select n from s) - (select n from m)) + abs((select n from s) - (select n from j))$q$,
       NULL, 0),

      -- T-09 (I4) : le funnel SEO et conversion_journeys comptent les mêmes contacts organiques sur la même fenêtre (cross).
      ('funnel_meme_total_que_journeys',
       $q$with b as (select n_end from public.cooked_period_bounds('rolling_28', 'cross'))
          select abs(coalesce((select sum(contacts) from public.seo_to_contact_funnel(28)), 0)
                   - (select count(*) from b, public.conversion_journeys(28, b.n_end) j
                      where j.entry_channel like 'organic%' and j.entry_path is not null))$q$,
       NULL, 0),

      -- T-09 (o-14) : un identifiant de clic Ads dans l'URL d'atterrissage prime sur utm_source=gmb et sur le referrer.
      ('classify_channel_gclid_paid',
       $q$select count(*) from (values
            ('www.google.com', 'gmb', null, 'https://www.jplouton-avocat.fr/?utm_source=gmb&gclid=abc'),
            ('www.google.com', null, null, 'https://www.jplouton-avocat.fr/defense-penale?gbraid=xyz'),
            (null, null, null, 'https://www.jplouton-avocat.fr/?wbraid=k')) v(r, s, m, u)
          where public.classify_channel(v.r, v.s, v.m, 'www.jplouton-avocat.fr', v.u) is distinct from 'paid'$q$,
       NULL, 0)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;

  -- Retention 90j
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;
