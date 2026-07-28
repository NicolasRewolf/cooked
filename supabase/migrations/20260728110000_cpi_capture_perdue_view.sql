-- C3 — rendre `clics_perdus` lisible en l'accompagnant de sa fiabilite.
--
-- La colonne couv_gsc_pct existe depuis le Sprint 38 mais n'est jamais lue.
-- Or clics_perdus = (clics attendus - clics reels), et les clics attendus sont
-- extrapoles depuis la seule fraction de requetes que Google revele
-- (gsc_query_page_daily). Quand cette couverture est faible, l'extrapolation
-- domine le chiffre.
--
-- Mesure du 27/07/2026 : corr(couv_qpd, capture) = -0,29 sur 120 pages,
-- -0,19 sur les seuls grades S/A/B. Modere — ~8 % de variance — donc un
-- caveat, pas une refutation. Mais il suffit a rendre un classement trompeur.
--
-- Distribution de couv_gsc_pct au 27/07 (mediane par grade) :
--   S  44 %  (0 page sous 20 %)      A  38 %  (3 sous 20 %)
--   B  29 %  (8 sous 20 %)           C  17 %  (71 sur 130 sous 20 %)
-- Les seuils suivent cette distribution.
--
-- Effet immediat sur les donnees du 27/07 : 13 pages en deficit, dont
-- 5 interpretables. accident-du-travail, 2e plus gros deficit apparent avec
-- 56 clics perdus, en sort — sa couverture est de 19 %. C'est exactement le
-- faux gisement que cette vue doit ecarter.

CREATE OR REPLACE VIEW public.cpi_capture_perdue AS
SELECT
  path,
  ptype,
  grade,
  clics_perdus,
  couv_gsc_pct,
  CASE
    WHEN couv_gsc_pct >= 40 THEN 'directe'
    WHEN couv_gsc_pct >= 20 THEN 'partielle'
    ELSE 'extrapolee'
  END AS fiabilite_capture,
  (grade IN ('S','A','B') AND couv_gsc_pct >= 20) AS interpretable,
  zc,
  n_org,
  day
FROM public.cpi_daily
WHERE day = (SELECT max(day) FROM public.cpi_daily)
  AND clics_perdus > 0;

COMMENT ON VIEW public.cpi_capture_perdue IS
  'Pilotage capture : les pages en deficit de clics face a la courbe CTR du '
  'site, accompagnees de la fiabilite du chiffre. fiabilite_capture = directe '
  '(couv_gsc_pct >= 40 %, le head visible domine) / partielle (20-39 %) / '
  'extrapolee (< 20 %, le chiffre est domine par la traine anonymisee de '
  'Google — ne pas le lire comme un gisement). interpretable = grade S/A/B ET '
  'couverture >= 20 %. Ne recalcule rien : relit le dernier cpi_daily. '
  'Rappel (piege 14 du playbook) : un deficit de capture sur une page '
  'informationnelle ne signifie pas un probleme de snippet — verifier le SERP '
  'reel, le clic peut etre capte en amont par un AI Overview.';
