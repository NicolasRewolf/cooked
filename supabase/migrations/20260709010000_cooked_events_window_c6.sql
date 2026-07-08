-- C1 + C6 (09/07/2026) — cooked_events_window() + adoption paris_date sur les refresh chauds
--
-- C1 : une couture pour matérialiser le périmètre events (site × fenêtre × grain).
-- C6 : cooked_paris_ts_* + paris_date() à la place des casts bruts ; garde CI scripts/check_migration_paris_date.py
--
-- Contrat après CALL :
--   temp table _cooked_ev (ON COMMIT DROP) — colonnes events + d date (paris_date)
--   grain raw   : site scopé, fenêtre occurred_at
--   grain clean : raw + anti-bot + anti-bruit
--   grain human : équivalent events_human / events_human_outremer

-- ── C6 : bornes timestamptz d'une journée calendaire Paris ───────────────────

CREATE OR REPLACE FUNCTION public.cooked_paris_ts_start(p_day date)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT (p_day::timestamp AT TIME ZONE 'Europe/Paris');
$$;

COMMENT ON FUNCTION public.cooked_paris_ts_start(date) IS
  'Début inclusif d''une date calendaire Paris (timestamptz). Remplace (p_day::timestamp AT TIME ZONE ''Europe/Paris'').';

CREATE OR REPLACE FUNCTION public.cooked_paris_ts_end_exclusive(p_day date)
RETURNS timestamptz
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT ((p_day + 1)::timestamp AT TIME ZONE 'Europe/Paris');
$$;

COMMENT ON FUNCTION public.cooked_paris_ts_end_exclusive(date) IS
  'Fin exclusive d''une date calendaire Paris. Remplace ((p_day+1)::timestamp AT TIME ZONE ''Europe/Paris'').';

-- ── C1 : matérialisation unique du périmètre events ──────────────────────────

CREATE OR REPLACE PROCEDURE public.cooked_events_window(
  p_occurred_from timestamptz,
  p_occurred_to   timestamptz,
  p_grain         text DEFAULT 'human',
  p_site          text DEFAULT 'main'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $procedure$
BEGIN
  IF p_grain NOT IN ('raw', 'clean', 'human') THEN
    RAISE EXCEPTION 'cooked_events_window: grain must be raw|clean|human, got %', p_grain;
  END IF;
  IF p_site NOT IN ('main', 'outremer') THEN
    RAISE EXCEPTION 'cooked_events_window: site must be main|outremer, got %', p_site;
  END IF;

  DROP TABLE IF EXISTS _cooked_ev;

  IF p_grain = 'raw' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.*, public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.*, public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    END IF;

  ELSIF p_grain = 'clean' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.*, public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          );
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.*, public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to
          AND NOT EXISTS (
            SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
          );
    END IF;

  ELSIF p_site = 'main' THEN
    DROP TABLE IF EXISTS _cooked_ev_raw;
    CREATE TEMP TABLE _cooked_ev_raw ON COMMIT DROP AS
      SELECT e.*, public.paris_date(e.occurred_at) AS d
      FROM public.events_main e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to;
    ANALYZE _cooked_ev_raw;

    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT r.*
      FROM _cooked_ev_raw r
      WHERE NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = r.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = r.session_id
        )
        AND NOT (
          r.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(r.props)
        )
        AND NOT (
          r.name IN (
            'cta_phone_click', 'cta_booking_click', 'cta_anchor_click',
            'click_internal', 'click_outbound'
          )
          AND EXISTS (
            SELECT 1 FROM public.events_main d
            WHERE d.session_id = r.session_id
              AND d.name = r.name
              AND d.path IS NOT DISTINCT FROM r.path
              AND date_trunc('second', d.occurred_at) = date_trunc('second', r.occurred_at)
              AND (d.props->>'anchor') IS NOT DISTINCT FROM (r.props->>'anchor')
              AND d.id < r.id
          )
        );
    DROP TABLE IF EXISTS _cooked_ev_raw;

  ELSE
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT
        e.id, e.anonymous_id, e.session_id, e.name, e.url, e.path, e.hostname, e.title,
        e.referrer, e.referrer_hostname, e.utm_source, e.utm_medium, e.utm_campaign,
        e.utm_term, e.utm_content, e.user_agent, e.device_type, e.os, e.browser,
        e.viewport_width, e.viewport_height, e.country, e.props, e.occurred_at, e.received_at,
        public.paris_date(e.occurred_at) AS d
      FROM public.events_outremer e
      WHERE e.occurred_at >= p_occurred_from
        AND e.occurred_at < p_occurred_to
        AND NOT EXISTS (
          SELECT 1 FROM public.bot_fingerprints b WHERE b.anonymous_id = e.anonymous_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.noise_sessions n WHERE n.session_id = e.session_id
        )
        AND NOT (
          e.name = 'cta_anchor_click' AND public.cooked_is_chrome_anchor(e.props)
        );
  END IF;

  ANALYZE _cooked_ev;
END;
$procedure$;

COMMENT ON PROCEDURE public.cooked_events_window(timestamptz, timestamptz, text, text) IS
  'C1 — Matérialise _cooked_ev (temp). grain: raw|clean|human ; site: main|outremer.';

REVOKE ALL ON PROCEDURE public.cooked_events_window(timestamptz, timestamptz, text, text) FROM PUBLIC;
REVOKE ALL ON PROCEDURE public.cooked_events_window(timestamptz, timestamptz, text, text) FROM anon, authenticated;
GRANT EXECUTE ON PROCEDURE public.cooked_events_window(timestamptz, timestamptz, text, text) TO service_role;
