-- Sprint 35 (03/06/2026) — cta_anchor_click : exclure le chrome UI du base
-- canonique (events_human).
--
-- CONTEXTE
-- --------
-- Le tracker (wix/tracker.html §4c "sticky-fallback") classait TOUT clic
-- dans un conteneur sticky/fixed comme un cta_anchor_click (micro-conversion).
-- Un audit prod du 03/06/2026 (sur events_human, site-wide, 7 318 events)
-- montre que ~90 % des cta_anchor_click sont en réalité du chrome UI, en
-- quatre familles :
--   1. Bandeau de consentement Cookiebot (#CybotCookiebotDialog) — boutons
--      "Tout autoriser" (2 321) / "Refuser" (2 149) / "Personnaliser" /
--      "Autoriser la sélection", ET clics sur le corps du dialog
--      ("ConsentementDétails…" 608, "Sélection du consentement…" 294, …).
--   2. Burger / menu mobile ("Menu mobile - burger" 289, "Menu").
--   3. Liens de nav globale (Équipe, Mentions Légales, Affaires…).
--   4. Dumps de texte : quand le clic remonte à un conteneur sans bouton
--      interne, le libellé = tout son textContent — un <script> inline
--      ("if (!window.Intl…" 424), un méga-menu ("DÉFENSE PÉNALE1Droit Pénal…"
--      144), une liste d'indicatifs téléphoniques, etc.
-- → les micro-conversions cta_anchor_click étaient gonflées d'un facteur ~10.
--
-- Le fix tracker (Sprint 35) arrête d'émettre ces events (sélecteur consent
-- Cookiebot + cap de longueur ≥ 80 + règle structurelle nav + denylist de
-- libellés). Cette migration traite le RÉTROACTIF (events déjà en base).
--
-- POURQUOI events_human (et pas seulement la couche de comptage) ?
-- ---------------------------------------------------------------
-- Contraste volontaire avec form_submit_counts_as_macro (20260527120000),
-- qui filtre les candidatures UNIQUEMENT au comptage en les laissant dans
-- events_human :
--   • un form_submit « Nous rejoindre » est un event CORRECTEMENT typé, réel,
--     exclu d'UNE métrique mais comptable ailleurs → filtre au comptage.
--   • un clic « Refuser » / un <script> enregistré EN cta_anchor_click est de
--     la donnée MAL TYPÉE produite par un bug tracker : jamais un anchor,
--     aucune métrique ne le veut → c'est du bruit, comme un hit de bot. Sa
--     place est HORS du base canonique.
-- events_human étant « la base canonique de toutes les analyses business »
-- (CLAUDE.md) et le mode d'usage dominant étant les requêtes ad-hoc dessus,
-- l'exclure ici rend automatiquement propres TOUS les consommateurs (RPCs,
-- snapshot nocturne, requêtes ad-hoc) sans devoir se souvenir d'un filtre.
--
-- COUVERTURE & RÉSIDU
-- -------------------
-- Le helper récupère 90,6 % des cta_anchor_click (6 629 / 7 318), SANS jeter
-- un seul vrai anchor (vérifié : les 689 survivants sont tous des sections de
-- pages expertise/article ou des anchors de prise de RDV). Il reste ~343
-- libellés de nav courts (Équipe, Affaires, Domaines d'expertises, Ressources…)
-- NON filtrés rétroactivement : par le seul libellé on ne distingue pas un lien
-- de nav d'une section in-page de même nom (la homepage a des sections
-- "Domaines d'expertises", "Nos affaires"…), et les events pré-fix ne stockent
-- pas le href. Les filtrer risquerait de jeter de vrais anchors. Ce résidu
-- n'est traité que côté tracker (règle structurelle : un vrai anchor porte un
-- #hash ou un data-anchor, un lien de nav non), donc forward-only.

-- ---------------------------------------------------------------------
-- 1. Helper : true si ce cta_anchor_click est du chrome UI
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cooked_is_chrome_anchor(props jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'public', 'pg_catalog'
AS $$
  SELECT
    -- (a) dump de texte (>= 80 car.) : <script> inline, méga-menu, corps du
    --     dialog consent, liste d'indicatifs. Vrais libellés courts (max
    --     prod : 78). Miroir du cap de longueur §4c du tracker.
    char_length(coalesce(props->>'anchor', '')) >= 80
    -- (b) boutons consent + burger + libellés chrome courts (miroir CHROME_LABELS)
    OR lower(trim(coalesce(props->>'anchor', ''))) = ANY (ARRAY[
      'tout autoriser', 'tout refuser', 'refuser',
      'autoriser la sélection', 'autoriser la selection',
      'personnaliser', 'tout accepter', 'accepter', 'continuer sans accepter',
      'enregistrer', 'afficher les détails', 'menu', 'menu mobile',
      'menu mobile - burger', 'fermer', 'close', 'recherche sur le site'
    ])
    OR lower(coalesce(props->>'anchor', '')) LIKE '%burger%'
    -- (c) corps du dialog Cookiebot < 80 car. Phrases SPÉCIFIQUES cookies
    --     uniquement — surtout PAS le bare 'consentement' (site de droit pénal
    --     où le consentement est un vrai sujet d'article).
    OR lower(coalesce(props->>'anchor', '')) LIKE '%sélection du consentement%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%modifiez consentement%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%utilise des cookies%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%vendre ou partager mes information%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%iabv2settings%'
    OR lower(coalesce(props->>'anchor', '')) LIKE '%paramètres des cookies%'
    -- (d) miroir slugifié (target_section)
    OR lower(trim(coalesce(props->>'target_section', ''))) = ANY (ARRAY[
      'tout-autoriser', 'tout-refuser', 'refuser',
      'autoriser-la-selection', 'personnaliser', 'tout-accepter',
      'accepter', 'continuer-sans-accepter', 'menu', 'menu-mobile-burger'
    ]);
$$;

COMMENT ON FUNCTION public.cooked_is_chrome_anchor(jsonb) IS
  'true si un cta_anchor_click est du chrome UI (consent Cookiebot, burger, nav, dump de texte de conteneur) et non un vrai anchor in-page. Miroir de la logique tracker §4c (Sprint 35) : cap de longueur >= 80 + denylist. Utilisé dans events_human.';

-- Fonction pure, sans accès aux données : exécutable par tous. Contrairement
-- à form_submit_counts_as_macro (verrouillée car appelée uniquement dans des
-- RPC SECURITY DEFINER), celle-ci est embarquée dans events_human qui est en
-- security_invoker=true : elle doit être exécutable par tout rôle qui lit la
-- vue, sinon la vue casse pour les rôles non privilégiés.
GRANT EXECUTE ON FUNCTION public.cooked_is_chrome_anchor(jsonb) TO public;

-- ---------------------------------------------------------------------
-- 2. events_human : on retire les cta_anchor_click chrome
--    (restate complet de la vue — create or replace exige le SELECT entier).
--    Reste strictement : events_no_bots − noise_sessions − chrome anchors.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW public.events_human
WITH (security_invoker = true) AS
SELECT e.*
FROM public.events_no_bots e
WHERE NOT EXISTS (
  SELECT 1 FROM public.noise_sessions n
  WHERE n.session_id = e.session_id
)
-- Sprint 35 — chrome UI mal typé en cta_anchor_click. Le garde
-- `name = 'cta_anchor_click'` court-circuite l'appel de fonction pour les
-- ~98 % d'events qui ne sont pas des anchor clicks.
AND NOT (
  e.name = 'cta_anchor_click'
  AND public.cooked_is_chrome_anchor(e.props)
);
