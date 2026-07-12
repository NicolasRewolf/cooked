-- ═══════════════════════════════════════════════════════════════════
-- Couture d'identité (identity_stitch) + contacts assistés v2
--
-- Contexte (12/07/2026) : le tracker (jusqu'à sprint40) faisait tourner
-- ses ids en cours de visite sur wipe/transition de storage : le sid,
-- relu dans le storage à chaque event, était re-minté au premier event
-- après le wipe ; l'aid, caché en closure et jamais ré-écrit, tournait à
-- la navigation suivante. Mesures prod (28 j, 14/06→11/07) : ~22 % des
-- sessions coupées en deux, 30,7 % de sessions orphelines (engagement
-- sans pageview), ~95 % des cta_phone_click sans amont visible. La
-- jointure « contact → première pageview de session » (dashboard
-- contacts assistés, conversion_journeys, funnel) était donc aveugle.
-- Le tracker sprint41 rend les ids auto-réparants (source tarie) ; cette
-- migration recolle le PASSÉ et blinde la lecture.
--
-- Principe : composantes connexes du graphe biparti aid↔sid (label
-- propagation). Un navigateur = des ids client aléatoires (rid()) qui ne
-- collisionnent pas entre visiteurs → recoller par transitivité est sûr.
-- Garde-fous validés en prod le 12/07/2026 :
--   • convergence en 2 itérations (3 exécutées par marge, 0 changement) ;
--   • aids de fallback serveur (32 hex, hash IP|UA|sel — partageables
--     entre visiteurs) exclus comme clé de couture ;
--   • identités 'webhook-%' (synthétiques form-webhook) exclues ;
--   • tailles saines : p99 ≤ 5 sids/composante, max 42 (revenants 28 j) ;
--   • 0 composante mélangeant plusieurs device_type sur les fenêtres
--     d'attribution des 141 phone clicks de la fenêtre de validation.
-- Gains mesurés (28 j) : entrée de visite connue pour 140/141 phone
-- clicks (99 % vs 54 %) ; contacts assistés attribuables à un article
-- « ressource » : 16 → 38. Cas d'école du 11/07 18:52 (form « Droit du
-- consommateur ») : entrée résolue = /post/arnaque-en-ligne-victime-
-- escroquerie-recours (Google organique), conforme au parcours réel.
--
-- La table est reconstruite par cron nocturne (03:40 UTC, avant les
-- refreshers dashboard de 04:00-04:16 UTC) sur 90 j glissants.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Table matérialisée ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.identity_stitch (
  kind        text NOT NULL CHECK (kind IN ('sid','aid')),
  key         text NOT NULL,
  visitor_key text NOT NULL,
  PRIMARY KEY (kind, key)
);
CREATE INDEX IF NOT EXISTS identity_stitch_visitor_idx
  ON public.identity_stitch (visitor_key);
ALTER TABLE public.identity_stitch ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.identity_stitch IS
  'Couture d''identité : session_id (kind=sid) et anonymous_id (kind=aid) → visitor_key (label de composante connexe du graphe aid↔sid). Reconstruite par refresh_identity_stitch(90) via cron nocturne. Répare la rotation d''ids du tracker ≤ sprint40 (sessions coupées). Ne JAMAIS coudre via un aid 32-hex (fallback serveur, partageable).';

-- ── 2. Refresh (label propagation, 3 itérations) ───────────────────
CREATE OR REPLACE FUNCTION public.refresh_identity_stitch(p_days int DEFAULT 90)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '420s'
AS $$
DECLARE
  t0 timestamptz := now() - make_interval(days => p_days);
BEGIN
  -- Paires (aid, sid) observées. Lecture d'events BRUT, assumée et
  -- volontaire : (a) c'est de la topologie d'identité, pas un chiffre
  -- business — les ids étant aléatoires par navigateur, les sessions
  -- bots forment leurs propres composantes sans polluer celles des
  -- humains ; (b) scanner events_human (anti-joins bots/bruit) coûte
  -- >100 s sur 28 j — prohibitif ici, les consommateurs business
  -- continuent de lire events_human et joignent la couture ensuite.
  DROP TABLE IF EXISTS _st_pairs;
  CREATE TEMP TABLE _st_pairs ON COMMIT DROP AS
    SELECT DISTINCT anonymous_id AS a, session_id AS s
    FROM events
    WHERE occurred_at >= t0
      AND anonymous_id NOT LIKE 'webhook-%'
      AND session_id  NOT LIKE 'webhook-%'
      AND anonymous_id !~ '^[0-9a-f]{32}$';
  ANALYZE _st_pairs;

  -- Label propagation alternée sid→aid→sid. Convergence mesurée à
  -- 2 itérations sur 28 j de prod (12/07/2026) ; 3 par marge.
  DROP TABLE IF EXISTS _st_l0; DROP TABLE IF EXISTS _st_a1;
  DROP TABLE IF EXISTS _st_l1; DROP TABLE IF EXISTS _st_a2;
  DROP TABLE IF EXISTS _st_l2; DROP TABLE IF EXISTS _st_a3;
  DROP TABLE IF EXISTS _st_l3;
  CREATE TEMP TABLE _st_l0 ON COMMIT DROP AS
    SELECT s, min(a) AS lbl FROM _st_pairs GROUP BY s;
  CREATE TEMP TABLE _st_a1 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l0 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l1 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a1 x ON x.a = p.a GROUP BY p.s;
  CREATE TEMP TABLE _st_a2 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l1 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l2 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a2 x ON x.a = p.a GROUP BY p.s;
  CREATE TEMP TABLE _st_a3 ON COMMIT DROP AS
    SELECT p.a, min(l.lbl) AS lbl FROM _st_pairs p JOIN _st_l2 l ON l.s = p.s GROUP BY p.a;
  CREATE TEMP TABLE _st_l3 ON COMMIT DROP AS
    SELECT p.s, min(x.lbl) AS lbl FROM _st_pairs p JOIN _st_a3 x ON x.a = p.a GROUP BY p.s;

  DELETE FROM identity_stitch;
  INSERT INTO identity_stitch (kind, key, visitor_key)
    SELECT 'sid', s, lbl FROM _st_l3
    UNION ALL
    SELECT 'aid', a, lbl FROM _st_a3;
END $$;

-- ── 3. Cron nocturne (avant les refreshers dashboard 04:00 UTC) ────
SELECT cron.schedule(
  'refresh-identity-stitch',
  '40 3 * * *',
  $$SET statement_timeout='420s'; SELECT public.refresh_identity_stitch(90);$$
);

-- ── 4. Contacts assistés v2 (entrée de VISITE recousue) ────────────
-- Contrat de sortie inchangé (window_kind, path, assisted_contacts,
-- assisted_prev, refreshed_at). Ce qui change : l'entrée d'un contact
-- n'est plus « première pageview de la session du contact » (aveugle
-- dès que le sid a tourné) mais « première pageview de la VISITE du
-- visiteur recousu » : pageviews du visitor_key segmentées en visites
-- (nouveau segment si trou > 30 min — même sémantique que la fenêtre
-- de session du tracker), le contact étant rattaché à la dernière
-- pageview qui le précède (≤ 6 h). Fallback sans couture : la session
-- brute du contact (comportement historique).
CREATE OR REPLACE FUNCTION public.refresh_dashboard_resources_assisted(p_window text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $function$
DECLARE
  windows text[] := CASE WHEN p_window IS NULL THEN ARRAY['rolling_28','rolling_90'] ELSE ARRAY[p_window] END;
  w text; lbl text; lns date; lne date; lps date; lpe date; lpt date; ld int;
  gns date; gne date; gps date; gpe date; glast date; glag int;
BEGIN
  DELETE FROM public.dashboard_resources_assisted_snapshot WHERE window_kind = ANY(windows);

  FOREACH w IN ARRAY windows LOOP
    CALL public.cooked_snapshot_window(w, 'human', lbl, lns, lne, lps, lpe, lpt, ld, gns, gne, gps, gpe, glast, glag);

    -- Pageviews avec identité recousue (fallback : session brute).
    DROP TABLE IF EXISTS _pvk;
    CREATE TEMP TABLE _pvk ON COMMIT DROP AS
      SELECT COALESCE(st.visitor_key, 'sid:' || e.session_id) AS vk,
             e.occurred_at AS t, e.path
      FROM _cooked_ev e
      LEFT JOIN identity_stitch st ON st.kind = 'sid' AND st.key = e.session_id
      WHERE e.name = 'pageview'
        AND e.referrer_hostname IS DISTINCT FROM 'm.baidu.com'
        AND e.referrer_hostname IS DISTINCT FROM 'baidu.com';

    -- Segmentation en visites : nouveau segment si trou > 30 min entre
    -- deux pageviews du même visiteur (sémantique fenêtre de session).
    DROP TABLE IF EXISTS _pvseg;
    CREATE TEMP TABLE _pvseg ON COMMIT DROP AS
      SELECT vk, t, path,
             sum(brk) OVER (PARTITION BY vk ORDER BY t) AS visit_n
      FROM (
        SELECT vk, t, path,
               CASE WHEN lag(t) OVER (PARTITION BY vk ORDER BY t) IS NULL
                      OR t - lag(t) OVER (PARTITION BY vk ORDER BY t) > interval '30 minutes'
                    THEN 1 ELSE 0 END AS brk
        FROM _pvk
      ) x;
    CREATE INDEX ON _pvseg (vk, t);
    ANALYZE _pvseg;

    DROP TABLE IF EXISTS _ventry;
    CREATE TEMP TABLE _ventry ON COMMIT DROP AS
      SELECT vk, visit_n, (array_agg(path ORDER BY t))[1] AS entry_path
      FROM _pvseg GROUP BY vk, visit_n;
    ANALYZE _ventry;

    -- Contacts macro avec leur visitor_key : phone (session de l'event),
    -- form (cooked_sid, puis cooked_aid si le sid manque — champs cachés).
    DROP TABLE IF EXISTS _ct;
    CREATE TEMP TABLE _ct ON COMMIT DROP AS
      SELECT e.occurred_at AS t, e.d,
             COALESCE(st.visitor_key, 'sid:' || e.session_id) AS vk
      FROM _cooked_ev e
      LEFT JOIN identity_stitch st ON st.kind = 'sid' AND st.key = e.session_id
      WHERE e.name = 'cta_phone_click'
      UNION ALL
      SELECT e.occurred_at, e.d,
             COALESCE(sts.visitor_key, sta.visitor_key,
                      'sid:' || (e.props->>'cooked_sid'))
      FROM _cooked_ev e
      LEFT JOIN identity_stitch sts ON sts.kind = 'sid' AND sts.key = e.props->>'cooked_sid'
      LEFT JOIN identity_stitch sta ON sta.kind = 'aid' AND sta.key = e.props->>'cooked_aid'
      WHERE e.name = 'form_submit' AND form_submit_counts_as_macro(e.props)
        AND COALESCE(e.props->>'cooked_sid', e.props->>'cooked_aid') IS NOT NULL;
    ANALYZE _ct;

    -- Entrée de visite de chaque contact : visite de la dernière pageview
    -- qui précède le contact (≤ 6 h), première pageview de cette visite.
    DROP TABLE IF EXISTS _ce;
    CREATE TEMP TABLE _ce ON COMMIT DROP AS
      SELECT c.d, v.entry_path
      FROM _ct c
      JOIN LATERAL (
        SELECT s.vk, s.visit_n
        FROM _pvseg s
        WHERE s.vk = c.vk AND s.t <= c.t AND c.t - s.t <= interval '6 hours'
        ORDER BY s.t DESC LIMIT 1
      ) lp ON true
      JOIN _ventry v ON v.vk = lp.vk AND v.visit_n = lp.visit_n;

    INSERT INTO public.dashboard_resources_assisted_snapshot
      (window_kind, path, assisted_contacts, assisted_prev, refreshed_at)
    SELECT w, pt.path, COALESCE(cur.n, 0), COALESCE(prv.n, 0), now()
    FROM page_taxonomy pt
    LEFT JOIN (
      SELECT entry_path, count(*) AS n FROM _ce
      WHERE d BETWEEN lns AND lne GROUP BY entry_path
    ) cur ON cur.entry_path = pt.path
    LEFT JOIN (
      SELECT entry_path, count(*) AS n FROM _ce
      WHERE d BETWEEN lps AND lpe GROUP BY entry_path
    ) prv ON prv.entry_path = pt.path
    WHERE pt.category = 'ressource';
  END LOOP;
END $function$;
