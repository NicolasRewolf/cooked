-- cooked_events_window : projection minimale + passe unique en grain `human`.
--
-- PROBLÈME
-- --------
-- La procédure matérialisait `SELECT e.*` (25 colonnes) dans une table temporaire,
-- et le grain `human` du site `main` le faisait DEUX FOIS : `_cooked_ev_raw`
-- (copie intégrale de la fenêtre) puis `_cooked_ev` (copie filtrée de la copie).
--
-- Mesuré en prod le 25/07/2026, fenêtre 90 jours (2 379 919 lignes) :
--     poids des 25 colonnes ............ 1 587 Mo
--     poids des 12 colonnes réellement
--       lues par les consommateurs .....   799 Mo
--     poids des 13 colonnes jamais lues     700 Mo  (44 %)
--
-- Conséquence : le cron horaire `cooked-refresh-after-gsc` (jobid 46) échouait
-- toutes les heures depuis le 24/07/2026 11:00 sur
--     could not write to file "base/pgsql_tmp/..." : No space left on device
-- et les snapshots dashboard étaient gelés depuis le 23/07/2026 11:00.
-- Aggravant : `temp_file_limit = -1` sur cette instance — un débordement remplit
-- le disque de la base au lieu de faire échouer proprement la requête.
--
-- INVENTAIRE DES CONSOMMATEURS (vérifié en prod, pas déduit)
-- ---------------------------------------------------------
-- 5 routines lisent `_cooked_ev` : refresh_dashboard_snapshots,
-- refresh_dashboard_expertises_snapshots, refresh_dashboard_resources_assisted,
-- refresh_seo_url_snapshot, refresh_noise_sessions.
--
-- Colonnes citées par au moins une d'entre elles (12) — CONSERVÉES :
--     id, anonymous_id, session_id, name, path, referrer_hostname,
--     utm_source, utm_medium, user_agent, device_type, props, occurred_at
--   (+ la colonne calculée `d` = paris_date(occurred_at), inchangée)
--
-- Colonnes citées par aucune (13) — RETIRÉES :
--     url, title, referrer, hostname, browser, os, country, received_at,
--     utm_campaign, utm_content, utm_term, viewport_width, viewport_height
--
-- `user_agent` (275 Mo/90 j) est conservée : `refresh_noise_sessions` s'en sert
-- pour la détection headless. Elle n'appelle la procédure qu'en grain `raw` sur
-- 48 h, mais la forme de la table temporaire est volontairement IDENTIQUE quel
-- que soit le grain — un consommateur ne doit pas avoir à savoir par quel grain
-- il a été appelé.
--
-- Aucun consommateur ne fait `SELECT *` ni `_cooked_ev.*` (vérifié par regex sur
-- les 5 corps) : réduire la projection ne casse aucune référence positionnelle.
--
-- PASSE UNIQUE
-- ------------
-- Le grain `human`/`main` construisait `_cooked_ev_raw` uniquement pour filtrer
-- dessus. Or aucun de ses prédicats ne dépend de la table intermédiaire : la
-- sous-requête de déduplication lit `public.events_main`, pas la temporaire.
-- Les deux passes sont donc fusionnées en une seule, ce qui supprime la copie
-- intégrale intermédiaire.
--
-- SÉMANTIQUE INCHANGÉE
-- --------------------
-- Mêmes lignes en sortie, mêmes valeurs, mêmes prédicats, même ordre de filtres.
-- Le grain `human` du site `outremer` conserve son absence de déduplication
-- (comportement d'origine, délibérément préservé).
-- L'alias de la sous-requête de dédup passe de `d` à `dup` pour ne pas prêter à
-- confusion avec la colonne calculée `d`.

CREATE OR REPLACE PROCEDURE public.cooked_events_window(
  IN p_occurred_from timestamptz,
  IN p_occurred_to   timestamptz,
  IN p_grain         text DEFAULT 'human',
  IN p_site          text DEFAULT 'main'
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
  -- Vestige de l'ancienne implémentation à deux passes : plus jamais créé.
  DROP TABLE IF EXISTS _cooked_ev_raw;

  IF p_grain = 'raw' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_main e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    ELSE
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
        FROM public.events_outremer e
        WHERE e.occurred_at >= p_occurred_from
          AND e.occurred_at < p_occurred_to;
    END IF;

  ELSIF p_grain = 'clean' THEN
    IF p_site = 'main' THEN
      CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
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
        SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
               e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
               e.device_type, e.props, e.occurred_at,
               public.paris_date(e.occurred_at) AS d
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
    -- Grain `human`, site principal : passe UNIQUE (auparavant deux copies).
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at,
             public.paris_date(e.occurred_at) AS d
      FROM public.events_main e
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
        )
        AND NOT (
          e.name IN (
            'cta_phone_click', 'cta_booking_click', 'cta_anchor_click',
            'click_internal', 'click_outbound'
          )
          AND EXISTS (
            SELECT 1 FROM public.events_main dup
            WHERE dup.session_id = e.session_id
              AND dup.name = e.name
              AND dup.path IS NOT DISTINCT FROM e.path
              AND date_trunc('second', dup.occurred_at) = date_trunc('second', e.occurred_at)
              AND (dup.props->>'anchor') IS NOT DISTINCT FROM (e.props->>'anchor')
              AND dup.id < e.id
          )
        );

  ELSE
    -- Grain `human`, sous-site outremer : pas de déduplication (inchangé).
    CREATE TEMP TABLE _cooked_ev ON COMMIT DROP AS
      SELECT e.id, e.anonymous_id, e.session_id, e.name, e.path,
             e.referrer_hostname, e.utm_source, e.utm_medium, e.user_agent,
             e.device_type, e.props, e.occurred_at,
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
  'Materialise la fenetre d evenements dans la table temporaire _cooked_ev (grain raw|clean|human, site main|outremer). Projection MINIMALE : 12 colonnes + d. Ne JAMAIS revenir a SELECT e.* — les 13 colonnes retirees (url, title, referrer, hostname, browser, os, country, received_at, utm_campaign/content/term, viewport_*) pesaient 700 Mo sur une fenetre de 90 jours et ont sature le disque le 24/07/2026. Ajouter une colonne ici exige de verifier qu au moins un des 5 consommateurs la lit.';
