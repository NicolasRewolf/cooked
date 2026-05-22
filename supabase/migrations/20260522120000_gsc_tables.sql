-- Sprint 31-32 (21-22/05/2026) — Google Search Console tables + path contract
-- Appliquer via Supabase SQL editor ou `supabase db push` si CLI lié.
-- Source de vérité schéma GSC (ne pas dupliquer dans views.sql).

-- Path canonique partagé Cooked × GSC :
--   decode (events Sprint 13) + NFC + strip trailing slash sauf /
-- Edge track canonicalPath() et scripts/gsc_common.canonical_path() alignés.
-- Pour l'historique events pré-NFC : canonical_path(events.path) à la jointure.

CREATE OR REPLACE FUNCTION public.canonical_path(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN char_length(n) > 1 AND right(n, 1) = '/' THEN left(n, char_length(n) - 1)
    ELSE COALESCE(NULLIF(n, ''), '/')
  END
  FROM (SELECT normalize(COALESCE(p, ''), NFC) AS n) AS s;
$$;

COMMENT ON FUNCTION public.canonical_path(text) IS
  'Jointure Cooked × GSC : NFC + slash final. events.path déjà percent-decoded (Sprint 13).';

CREATE TABLE IF NOT EXISTS public.gsc_path_daily (
  day           date NOT NULL,
  path          text NOT NULL,
  impressions   integer NOT NULL CHECK (impressions >= 0),
  clicks        integer NOT NULL CHECK (clicks >= 0),
  position      numeric(6,2) NOT NULL CHECK (position > 0),
  ctr           numeric(7,6) NOT NULL CHECK (ctr >= 0 AND ctr <= 1),
  ingested_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (day, path)
);
CREATE INDEX IF NOT EXISTS gsc_path_daily_path_idx ON public.gsc_path_daily(path);
CREATE INDEX IF NOT EXISTS gsc_path_daily_day_idx  ON public.gsc_path_daily(day DESC);
ALTER TABLE public.gsc_path_daily ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.gsc_query_daily (
  day           date NOT NULL,
  query         text NOT NULL,
  impressions   integer NOT NULL CHECK (impressions >= 0),
  clicks        integer NOT NULL CHECK (clicks >= 0),
  position      numeric(6,2) NOT NULL CHECK (position > 0),
  ctr           numeric(7,6) NOT NULL CHECK (ctr >= 0 AND ctr <= 1),
  ingested_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (day, query)
);
CREATE INDEX IF NOT EXISTS gsc_query_daily_query_idx ON public.gsc_query_daily(query);
CREATE INDEX IF NOT EXISTS gsc_query_daily_day_idx   ON public.gsc_query_daily(day DESC);
ALTER TABLE public.gsc_query_daily ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.gsc_query_page_daily (
  day           date NOT NULL,
  path          text NOT NULL,
  query         text NOT NULL,
  impressions   integer NOT NULL CHECK (impressions >= 0),
  clicks        integer NOT NULL CHECK (clicks >= 0),
  position      numeric(6,2) NOT NULL CHECK (position > 0),
  ctr           numeric(7,6) NOT NULL CHECK (ctr >= 0 AND ctr <= 1),
  ingested_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (day, path, query)
);
CREATE INDEX IF NOT EXISTS gsc_query_page_daily_path_idx  ON public.gsc_query_page_daily(path);
CREATE INDEX IF NOT EXISTS gsc_query_page_daily_query_idx ON public.gsc_query_page_daily(query);
CREATE INDEX IF NOT EXISTS gsc_query_page_daily_day_idx   ON public.gsc_query_page_daily(day DESC);
ALTER TABLE public.gsc_query_page_daily ENABLE ROW LEVEL SECURITY;
