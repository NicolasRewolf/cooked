-- Accès couvrant limité aux pages vues du site principal.
-- Prédicat identique à cooked_is_main_site ; les filtres bots/bruit restent dans events_human.
-- Construction concurrente pour laisser la réception des événements active.
CREATE INDEX CONCURRENTLY idx_events_main_pageviews_cover
ON public.events (occurred_at)
INCLUDE (path, anonymous_id, session_id)
WHERE name = 'pageview'
  AND hostname IS DISTINCT FROM 'outremer.jplouton-avocat.fr'
  AND (props->>'cooked_site') IS DISTINCT FROM 'outremer';
