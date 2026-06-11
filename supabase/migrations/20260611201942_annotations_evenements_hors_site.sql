-- Sprint 38 reprise (11/06/2026) — table annotations : événements hors-site
-- (passages TV, presse, changements site, campagnes) qui expliquent les pics
-- de trafic. Consommée à terme par le momentum CPI pour neutraliser les
-- journées exceptionnelles ; en attendant, sert de mémoire d'analyse.
CREATE TABLE public.annotations (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  day date NOT NULL,
  kind text NOT NULL DEFAULT 'media'
    CHECK (kind IN ('media','presse','site_change','campagne','autre')),
  label text NOT NULL,
  -- paths concernés si l'événement est localisé (ex. le post de l'affaire) ;
  -- NULL = effet site-wide
  paths text[] DEFAULT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.annotations IS
  'Événements hors-site datés (TV, presse, refonte, campagne) pour contextualiser les pics de trafic et, à terme, neutraliser le momentum CPI.';

CREATE INDEX annotations_day_idx ON public.annotations (day);
