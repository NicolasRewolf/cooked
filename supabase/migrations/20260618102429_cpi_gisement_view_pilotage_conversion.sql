-- 18/06/2026 — vue de PILOTAGE CONVERSION (décision : garder l'essentiel, ne pas
-- complexifier le modèle). cpi_gisement ne calcule RIEN de nouveau : c'est une
-- lecture du dernier snapshot cpi_daily qui sépare les deux angles que le CPI
-- fusionne — le « potentiel » (capture+rétention+lecture, hors conversion) et la
-- « conversion réalisée » (badge). Le GISEMENT = grade A/B + potentiel élevé +
-- NOT convertit (audience captée/engagée qui ne convertit pas encore → où poser
-- un pont vers le contact). À croiser avec l'intention du sujet (indemnisation >
-- pénal éducatif). Le CPI v2.2 reste la référence pour la surveillance/decay.
-- Poids renormalisés hors conversion : 0.30/0.15/0.20 → /0.65.
CREATE OR REPLACE VIEW public.cpi_gisement AS
SELECT
  path, ptype, grade, n_org, cpi,
  round(100*(1/(1+exp(-(0.46*zc::numeric + 0.23*zr::numeric + 0.20/0.65*zl::numeric)/0.8)))
        * momentum::numeric * gate::numeric)::int AS potentiel,
  (zv::numeric > 0) AS convertit,
  zc::numeric AS zc, zr::numeric AS zr, zl::numeric AS zl, zv::numeric AS zv,
  day
FROM public.cpi_daily
WHERE day = (SELECT max(day) FROM public.cpi_daily);

COMMENT ON VIEW public.cpi_gisement IS
  'Pilotage conversion (18/06/2026) : lecture du dernier cpi_daily séparant potentiel (zc/zr/zl renormalisés, hors conversion) et conversion (badge zv>0). Gisement = grade A/B + potentiel haut + NOT convertit. Ne modifie pas le CPI ; croiser avec l''intention du sujet.';
