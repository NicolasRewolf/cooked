-- T-20 (mission 02/09/2026, #121) — restatements passés : annotations manquantes, version de définition
-- du CPI, check de calibration mensuel. Constats f-05, o-11, f-08. Invariant I10.
--
-- Mesure avant (04/09/2026 00:50 Paris) :
--   · annotations : 13 lignes — aucune pour le restatement CPI du 02/07 (grain lectures + classify_channel
--     v2 IA), la redéfinition du 25/07 (momentum sur gsc_query_page_daily + `convertit`), ni le 31/08
--     (page_taxonomy +12 articles) ; la doc CPI affirmait une annotation du 02/07 qui n'existait pas.
--   · cpi_daily (76 jours, 13 040 lignes, 10/06 → 03/09) : aucune colonne de version — 6 définitions
--     successives indiscernables dans la donnée.
--   · check §3 (calibration de la courbe CTR) : rejoué une fois à la main le 11/07 (R² 0,930, médiane
--     |écart| 20,1 %) puis le 02/09 par l'audit (R² 0,909, médiane 28,8 %) — aucune table, aucun cron,
--     aucun registre.
--
-- Changement :
--   1. cpi_daily.cpi_version + rétro-remplissage par date de rupture ; cooked_config.cpi_definition_version
--      lu par cooked_cpi_snapshot() (toute migration « restatement CPI » bumpe la clé ET pose l'annotation).
--   2. 3 annotations (phrases à amender par Nicolas s'il le souhaite).
--   3. cpi_calibration_checks (table) + cpi_calibration_check() (le §3 du harnais, fenêtre 90 j close à
--      gsc_last_data_day(), branded exclu via gsc_is_branded) + cron mensuel + ligne au registre + alerte
--      si R² < 0,85 (critère liant) — la médiane |écart| reste un indicateur de suivi.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Version de définition du CPI
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.cpi_daily ADD COLUMN IF NOT EXISTS cpi_version text;

INSERT INTO public.cooked_config (key, value, updated_at)
VALUES ('cpi_definition_version', '2.2.5', now())
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;

-- Définitions successives (le MODÈLE reste v2.2 — décision 18/06 et 11/07 : pas de v2.3) :
--   2.2.0  16/06 → 01/07  v2.2 (momentum continu, EB dynamique)
--   2.2.1  02/07 → 11/07  grain lectures session×path (restatement 02/07) + classify_channel v2 (IA)
--   2.2.2  12/07 → 24/07  conversion recousue (identity_stitch, conversion_journeys v2)
--   2.2.3  25/07 → 26/07  momentum lu sur gsc_query_page_daily non brandé + `convertit` (revue n°2)
--   2.2.4  27/07 → 02/09  classify_channel v3 : GMB hors organic_google
--   2.2.5  03/09 →        fenêtres closes à gsc_last_data_day() (T-05), momentum sur gsc_path_daily (T-06),
--                          zv sur la fenêtre du score (T-09)
UPDATE public.cpi_daily SET cpi_version = CASE
  WHEN day <  date '2026-07-02' THEN '2.2.0'
  WHEN day <  date '2026-07-12' THEN '2.2.1'
  WHEN day <  date '2026-07-25' THEN '2.2.2'
  WHEN day <  date '2026-07-27' THEN '2.2.3'
  WHEN day <  date '2026-09-03' THEN '2.2.4'
  ELSE '2.2.5' END
WHERE cpi_version IS NULL;

COMMENT ON COLUMN public.cpi_daily.cpi_version IS
  'Version de DÉFINITION du calcul (pas du modèle, qui reste v2.2) — lue dans cooked_config.cpi_definition_version au snapshot. Deux lignes de versions différentes ne se comparent pas sans lire annotations (T-20, 04/09/2026).';

CREATE OR REPLACE FUNCTION public.cooked_cpi_snapshot()
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '600s'
AS $function$
  INSERT INTO public.cpi_daily
    (day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit, cpi_version)
  SELECT public.paris_today(),
    path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct, convertit,
    (SELECT value FROM public.cooked_config WHERE key = 'cpi_definition_version')
  FROM public.cooked_page_index(28)
  ON CONFLICT (day, path) DO UPDATE SET
    ptype=EXCLUDED.ptype, grade=EXCLUDED.grade, cpi=EXCLUDED.cpi, cpi_raw=EXCLUDED.cpi_raw,
    momentum=EXCLUDED.momentum, gate=EXCLUDED.gate,
    zc=EXCLUDED.zc, zr=EXCLUDED.zr, zl=EXCLUDED.zl, zv=EXCLUDED.zv,
    clics_perdus=EXCLUDED.clics_perdus, n_org=EXCLUDED.n_org, couv_gsc_pct=EXCLUDED.couv_gsc_pct,
    convertit=EXCLUDED.convertit, cpi_version=EXCLUDED.cpi_version;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Annotations manquantes (I10)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.annotations (day, kind, label, paths) VALUES
  (date '2026-07-02', 'autre',
   'Restatement CPI du 02/07/2026 (audit T-01→T-19) : lectures calculées au grain session×path (±7 pts max, 4 pages A/B, 8 pages C sorties du scoring) ; classify_channel v2 (IA détectée aussi par utm_source, ~35 % du canal organic_ai récupéré). Un « avant/après 02/07 » dans cpi_daily ou par canal est une correction de mesure, pas un changement de trafic.',
   NULL),
  (date '2026-07-25', 'autre',
   'Redéfinition CPI du 25/07/2026 (revue d''architecture n°2) : momentum lu sur les requêtes révélées (gsc_query_page_daily non brandé) et badge convertit ajouté — définition 2.2.3, corrigée le 03/09/2026 (T-06 : momentum sur gsc_path_daily). Entre le 25/07 et le 03/09, le momentum ne voyait que 16-28 % des clics : ne pas lire un decay sur cette période.',
   NULL),
  (date '2026-08-31', 'autre',
   'Périmètre taxonomie du 31/08/2026 : 12 articles publiés jamais ingérés dans page_taxonomy (dont 5 ressources publiées en juin) entrent dans les lectures par catégorie (dashboard Articles Ressources, content_performance, contrat éditorial). Une hausse « ressources » au 31/08 est un changement de périmètre, pas de trafic.',
   NULL);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Check de calibration mensuel (§3 du harnais) — table, fonction, cron, registre, alerte
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cpi_calibration_checks (
  day               date PRIMARY KEY,
  gsc_end           date NOT NULL,
  r2                numeric NOT NULL,
  pente             numeric NOT NULL,
  n_buckets         integer NOT NULL,
  mediane_ecart_pct numeric,
  max_ecart_pct     numeric,
  ctr_pos1_pct      numeric,
  cpi_version       text,
  created_at        timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cpi_calibration_checks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cpi_calibration_checks FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.cpi_calibration_checks TO service_role;
COMMENT ON TABLE public.cpi_calibration_checks IS
  'T-20 : §3 du harnais cpi_validation_j28.sql, rejoué le 1er de chaque mois (cron cpi-calibration-monthly). Critère liant R² ≥ 0,85 ; la médiane |écart| est un indicateur de suivi (20,1 % le 11/07, 28,8 % le 02/09).';

CREATE OR REPLACE FUNCTION public.cpi_calibration_check()
 RETURNS TABLE(day date, r2 numeric, pente numeric, n_buckets integer, mediane_ecart_pct numeric, max_ecart_pct numeric, ctr_pos1_pct numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  WITH b AS (SELECT public.gsc_last_data_day() AS gsc_end),
  base AS (
    SELECT round(g.position)::int AS pos,
           (sum(g.clicks) + 1.0) / (sum(g.impressions) + 20.0) AS ctr,
           sum(g.impressions) AS imps
    FROM public.gsc_query_page_daily g, b
    WHERE g.day > b.gsc_end - 90 AND g.day <= b.gsc_end
      AND NOT public.gsc_is_branded(g.query)
    GROUP BY 1
    HAVING round(g.position)::int BETWEEN 1 AND 20 AND sum(g.impressions) >= 200
  ),
  fit AS (
    SELECT regr_slope(ln(ctr), ln(pos)) AS pente, regr_intercept(ln(ctr), ln(pos)) AS icept,
           regr_r2(ln(ctr), ln(pos)) AS r2, count(*) AS n_buckets
    FROM base
  ),
  ecarts AS (
    SELECT abs(100 * (bs.ctr - exp(f.icept + f.pente * ln(bs.pos))) / exp(f.icept + f.pente * ln(bs.pos))) AS e
    FROM base bs, fit f
  ),
  agg AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY e) AS med, max(e) AS mx FROM ecarts
  ),
  ins AS (
    INSERT INTO public.cpi_calibration_checks (day, gsc_end, r2, pente, n_buckets, mediane_ecart_pct, max_ecart_pct, ctr_pos1_pct, cpi_version)
    SELECT public.paris_today(), b.gsc_end, round(f.r2::numeric, 3), round(f.pente::numeric, 3), f.n_buckets::int,
           round(agg.med::numeric, 1), round(agg.mx::numeric, 1), round((100 * exp(f.icept))::numeric, 2),
           (SELECT value FROM public.cooked_config WHERE key = 'cpi_definition_version')
    FROM b, fit f, agg
    ON CONFLICT (day) DO UPDATE SET gsc_end = EXCLUDED.gsc_end, r2 = EXCLUDED.r2, pente = EXCLUDED.pente,
      n_buckets = EXCLUDED.n_buckets, mediane_ecart_pct = EXCLUDED.mediane_ecart_pct,
      max_ecart_pct = EXCLUDED.max_ecart_pct, ctr_pos1_pct = EXCLUDED.ctr_pos1_pct, cpi_version = EXCLUDED.cpi_version
    RETURNING day, r2, pente, n_buckets, mediane_ecart_pct, max_ecart_pct, ctr_pos1_pct
  )
  SELECT * FROM ins;
$function$;

REVOKE ALL ON FUNCTION public.cpi_calibration_check() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cpi_calibration_check() TO service_role;

SELECT cron.schedule('cpi-calibration-monthly', '0 5 1 * *', $cmd$SET statement_timeout='300s'; SELECT public.cpi_calibration_check();$cmd$);

INSERT INTO public.freshness_contract
  (source, label, last_point_sql, cadence, normal_lag_days, warn_after_days, critical_after_days,
   gap_relation, gap_day_column, gap_window_days, repair_hint, enabled)
VALUES
  ('cpi_calibration_checks', 'Calibration de la courbe CTR du CPI (§3, mensuel)',
   'SELECT max(day) FROM public.cpi_calibration_checks',
   'monthly', 31, 35, 62, NULL, NULL, NULL,
   'Le cron cpi-calibration-monthly (1er du mois 05:00 UTC) n''a pas écrit : relancer SELECT public.cpi_calibration_check(); et lire r2 (liant ≥ 0,85) et mediane_ecart_pct (suivi).',
   true)
ON CONFLICT (source) DO NOTHING;

CREATE OR REPLACE FUNCTION public.alert_rule_cpi_calibration()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.cpi_calibration_checks ORDER BY day DESC LIMIT 1;
  IF r.day IS NULL THEN RETURN; END IF;
  IF r.r2 < 0.85 THEN
    kind := 'cpi_calibration'; severity := 'critical';
    detail := format('Courbe CTR du CPI : R² = %s < 0,85 (critère liant, check du %s, %s buckets, médiane |écart| %s %%). Le terme capture zc et clics_perdus reposent sur cette loi de puissance : ne pas livrer de « clics perdus » avant instruction (docs/cpi-cooked-page-index.md §validation).',
                     r.r2, to_char(r.day, 'DD/MM/YYYY'), r.n_buckets, r.mediane_ecart_pct);
    RETURN NEXT;
  ELSIF r.mediane_ecart_pct > 30 THEN
    kind := 'cpi_calibration'; severity := 'warn';
    detail := format('Courbe CTR du CPI : R² %s (ok) mais médiane |écart| %s %% > 30 %% (20,1 %% le 11/07/2026, 28,8 %% le 02/09) — courbure non captée par la loi de puissance à 1 segment ; clics_perdus à lire avec prudence.',
                     r.r2, r.mediane_ecart_pct);
    RETURN NEXT;
  END IF;
END $function$;

REVOKE ALL ON FUNCTION public.alert_rule_cpi_calibration() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alert_rule_cpi_calibration() TO service_role;

-- Premier point : maintenant (référence du 04/09/2026).
SELECT * FROM public.cpi_calibration_check();
