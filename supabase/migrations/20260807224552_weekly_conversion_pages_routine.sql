-- ═══════════════════════════════════════════════════════════════════════
-- Routine hebdomadaire « pages qui convertissent » (08/08/2026)
--
-- Grain : une ligne par conversion macro (appel = cta_phone_click, ou
-- formulaire envoye comptant comme macro), figee par semaine ISO
-- (lundi -> dimanche, Europe/Paris), avec les DEUX pages :
--   entry_path   = page d'entree de la visite recousue
--   contact_path = page ou l'action a eu lieu
-- CONTEXT.md : « sur la page » et « a l'entree » ne se somment jamais.
--
-- Pourquoi une table figee et pas un calcul a la volee : l'attribution a
-- l'entree passe par identity_stitch, qui ne garde que 90 jours glissants.
-- Sans photo hebdo, le leaderboard cumule se degraderait tout seul a mesure
-- que les semaines sortent de la fenetre de couture.
--
-- Contre-verifications passees AVANT ecriture (08/08/2026) :
--   * conversion_journeys ≡ site_macro_counts au contact pres (5 semaines,
--     06/07 -> 03/08 : 65/29/64/29/36 des deux cotes)
--   * entry_path ≡ assisted_contacts_by_entry_path page par page sur la
--     semaine du 27/07 ; ecart total <= 4/semaine, explique : la RPC
--     assisted exige cooked_sid/aid sur les formulaires, conversion_journeys
--     accepte aussi l'attribution temporal_unique.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.conversion_weekly (
  id                 bigserial PRIMARY KEY,
  week_start         date        NOT NULL,
  occurred_at        timestamptz NOT NULL,
  contact_kind       text        NOT NULL CHECK (contact_kind IN ('phone','form')),
  contact_path       text,
  entry_path         text,
  entry_channel      text,
  objet              text,
  device_type        text,
  attribution_method text,
  anonymous_id       text,
  pages_count        integer,
  journey            text[],
  snapshot_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.conversion_weekly IS
  'Photo hebdo figee des conversions macro (1 ligne = 1 conversion), avec page d''entree ET page de conversion. Ne contient que des semaines COMPLETES (lundi->dimanche Paris). Alimentee par cooked_weekly_conversions_snapshot(). La 1re semaine (04/05/2026) est partielle cote tracker : ingestion demarree le 06/05/2026 19:14.';

CREATE INDEX IF NOT EXISTS conversion_weekly_week_idx    ON public.conversion_weekly (week_start);
CREATE INDEX IF NOT EXISTS conversion_weekly_contact_idx ON public.conversion_weekly (contact_path);
CREATE INDEX IF NOT EXISTS conversion_weekly_entry_idx   ON public.conversion_weekly (entry_path);

ALTER TABLE public.conversion_weekly ENABLE ROW LEVEL SECURITY;

-- ── Ecriture : photo idempotente d'une semaine ─────────────────────────
CREATE OR REPLACE FUNCTION public.cooked_weekly_conversions_snapshot(p_week_start date DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '300s'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE 'Europe/Paris')::date;
  v_week  date;
  v_days  integer;
  v_rows  integer;
BEGIN
  -- defaut : la derniere semaine COMPLETE (lundi -> dimanche revolus)
  v_week := date_trunc('week',
              COALESCE(p_week_start::timestamp,
                       date_trunc('week', v_today::timestamp) - interval '7 days'))::date;

  IF v_week + 6 >= v_today THEN
    RAISE EXCEPTION 'semaine non terminee (% -> %), rien de fige', v_week, v_week + 6;
  END IF;

  -- fenetre a couvrir depuis maintenant, + 1 jour de marge
  v_days := (v_today - v_week) + 2;

  DELETE FROM public.conversion_weekly WHERE week_start = v_week;

  INSERT INTO public.conversion_weekly (
    week_start, occurred_at, contact_kind, contact_path, entry_path,
    entry_channel, objet, device_type, attribution_method, anonymous_id,
    pages_count, journey)
  SELECT v_week, j.occurred_at, j.contact_kind, j.contact_path, j.entry_path,
         j.entry_channel, j.objet, j.device_type, j.attribution_method,
         j.anonymous_id, j.pages_count, j.journey
  FROM public.conversion_journeys(v_days) j
  WHERE date_trunc('week', (j.occurred_at AT TIME ZONE 'Europe/Paris'))::date = v_week;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$function$;

-- ── Lecture 1 : le tableau de la semaine ───────────────────────────────
CREATE OR REPLACE FUNCTION public.weekly_conversions_report(p_week_start date DEFAULT NULL)
 RETURNS TABLE(semaine date, page_entree text, page_conversion text,
               appels bigint, formulaires bigint, conversions bigint, canaux text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH w AS (
    SELECT date_trunc('week',
             COALESCE(p_week_start::timestamp,
                      date_trunc('week', (now() AT TIME ZONE 'Europe/Paris')) - interval '7 days'))::date AS ws
  )
  SELECT c.week_start,
         COALESCE(c.entry_path,   '(entree inconnue)'),
         COALESCE(c.contact_path, '(page inconnue)'),
         count(*) FILTER (WHERE c.contact_kind = 'phone'),
         count(*) FILTER (WHERE c.contact_kind = 'form'),
         count(*),
         string_agg(DISTINCT COALESCE(c.entry_channel, 'inconnu'), ', ')
  FROM public.conversion_weekly c, w
  WHERE c.week_start = w.ws
  GROUP BY 1, 2, 3
  ORDER BY 6 DESC, 2, 3;
$function$;

-- ── Lecture 2 : le leaderboard cumule ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.conversions_leaderboard(p_since date DEFAULT NULL)
 RETURNS TABLE(page text, conversions_sur_la_page bigint, appels bigint,
               formulaires bigint, conversions_attribuees_entree bigint,
               semaines_actives bigint, premiere_semaine date, derniere_semaine date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH base AS (
    SELECT week_start, COALESCE(contact_path, '(page inconnue)') AS page,
           'sur'::text AS role, contact_kind
    FROM public.conversion_weekly
    WHERE week_start >= COALESCE(p_since, '-infinity'::date)
    UNION ALL
    SELECT week_start, COALESCE(entry_path, '(entree inconnue)'),
           'entree', contact_kind
    FROM public.conversion_weekly
    WHERE week_start >= COALESCE(p_since, '-infinity'::date)
  )
  SELECT page,
         count(*) FILTER (WHERE role = 'sur'),
         count(*) FILTER (WHERE role = 'sur' AND contact_kind = 'phone'),
         count(*) FILTER (WHERE role = 'sur' AND contact_kind = 'form'),
         count(*) FILTER (WHERE role = 'entree'),
         count(DISTINCT week_start),
         min(week_start), max(week_start)
  FROM base
  GROUP BY 1
  ORDER BY 2 DESC, 5 DESC, 1;
$function$;

-- ── Securite : Postgres accorde EXECUTE a PUBLIC a la creation ─────────
REVOKE ALL ON FUNCTION public.cooked_weekly_conversions_snapshot(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.weekly_conversions_report(date)          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.conversions_leaderboard(date)            FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.cooked_weekly_conversions_snapshot(date) TO service_role;
GRANT EXECUTE ON FUNCTION public.weekly_conversions_report(date)          TO service_role;
GRANT EXECUTE ON FUNCTION public.conversions_leaderboard(date)            TO service_role;
