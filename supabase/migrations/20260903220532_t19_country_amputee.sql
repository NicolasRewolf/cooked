-- T-19 / T-21 (mission 02/09/2026, #120 ← #122) — colonne events.country amputée.
-- Décision Nicolas (tri du 03/09/2026, commentaire de #120 : « décision : amputer events.country
-- (drop de la colonne + CookedEventRow) »). Décision §7.2 : capture morte depuis le 02/06/2026
-- (commit 3ba987d), 0 consommateur.
--
-- Mesure avant (04/09/2026 00:15 Paris) : aucune fonction public ne référence `country`
-- (pg_proc.prosrc ~ '\mcountry\M' → 0) ; 5 vues la projettent (events_main, events_no_bots,
-- events_human, events_outremer, events_human_outremer) — ce sont les seules dépendances.
-- Hygiène relevée au passage : events_human portait des GRANT INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/
-- TRIGGER pour anon et authenticated (default privileges) — retirés ; SELECT à service_role seulement.
--
-- Méthode : les vues sont recréées à l'identique sans `country` (security_invoker, commentaires,
-- privilèges), dans l'ordre des dépendances ; lock_timeout court pour ne jamais bloquer l'ingestion.

SET LOCAL lock_timeout = '15s';

DROP VIEW public.events_human_outremer;
DROP VIEW public.events_outremer;
DROP VIEW public.events_human;
DROP VIEW public.events_no_bots;
DROP VIEW public.events_main;

ALTER TABLE public.events DROP COLUMN country;

CREATE VIEW public.events_main WITH (security_invoker = true) AS
  SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer, referrer_hostname,
         utm_source, utm_medium, utm_campaign, utm_term, utm_content, user_agent, device_type, os, browser,
         viewport_width, viewport_height, props, occurred_at, received_at
  FROM public.events e
  WHERE public.cooked_is_main_site(hostname, props);
COMMENT ON VIEW public.events_main IS 'Events du site principal uniquement — exclut outremer.jplouton-avocat.fr.';

CREATE VIEW public.events_no_bots WITH (security_invoker = true) AS
  SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer, referrer_hostname,
         utm_source, utm_medium, utm_campaign, utm_term, utm_content, user_agent, device_type, os, browser,
         viewport_width, viewport_height, props, occurred_at, received_at
  FROM public.events_main e
  WHERE NOT EXISTS (SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id);

CREATE VIEW public.events_human WITH (security_invoker = true) AS
  SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer, referrer_hostname,
         utm_source, utm_medium, utm_campaign, utm_term, utm_content, user_agent, device_type, os, browser,
         viewport_width, viewport_height, props, occurred_at, received_at
  FROM public.events_no_bots e
  WHERE NOT EXISTS (SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id)
    AND NOT (name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(props))
    AND NOT (
      name = ANY (ARRAY['cta_phone_click', 'cta_booking_click', 'cta_anchor_click', 'click_internal', 'click_outbound'])
      AND EXISTS (
        SELECT 1 FROM public.events_main d
        WHERE d.session_id = e.session_id AND d.name = e.name
          AND NOT d.path IS DISTINCT FROM e.path
          AND date_trunc('second', d.occurred_at) = date_trunc('second', e.occurred_at)
          AND NOT (d.props ->> 'anchor') IS DISTINCT FROM (e.props ->> 'anchor')
          AND d.id < e.id
      )
    );

CREATE VIEW public.events_outremer WITH (security_invoker = true) AS
  SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer, referrer_hostname,
         utm_source, utm_medium, utm_campaign, utm_term, utm_content, user_agent, device_type, os, browser,
         viewport_width, viewport_height, props, occurred_at, received_at
  FROM public.events e
  WHERE public.cooked_site_scope(hostname, props) = 'outremer';
COMMENT ON VIEW public.events_outremer IS 'Events outre-mer uniquement — base des futures analyses DOM-TOM.';

CREATE VIEW public.events_human_outremer WITH (security_invoker = true) AS
  SELECT id, anonymous_id, session_id, name, url, path, hostname, title, referrer, referrer_hostname,
         utm_source, utm_medium, utm_campaign, utm_term, utm_content, user_agent, device_type, os, browser,
         viewport_width, viewport_height, props, occurred_at, received_at
  FROM public.events_outremer e
  WHERE NOT EXISTS (SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id)
    AND NOT EXISTS (SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id)
    AND NOT (name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(props));
COMMENT ON VIEW public.events_human_outremer IS 'Base canonique analyses outre-mer (hors bots/bruit/chrome anchors).';

REVOKE ALL ON public.events_main, public.events_no_bots, public.events_human,
              public.events_outremer, public.events_human_outremer FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.events_main, public.events_no_bots, public.events_human,
                public.events_outremer, public.events_human_outremer TO service_role;
