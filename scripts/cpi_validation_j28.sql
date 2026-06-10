-- ============================================================================
-- CPI v2.1 — Harnais de validation prédictive J+28 (Sprint 38, backlog P1)
-- ============================================================================
--
-- À LANCER À PARTIR DU 08/07/2026 (t0 = snapshot cpi_daily du 10/06/2026 + 28 j
-- de contacts observés). Chaque section (§) est une requête AUTONOME : copier-
-- coller une section dans le MCP Supabase (les sessions execute_sql sont
-- indépendantes, pas de temp table possible). Le paramètre t0 vit dans la CTE
-- `params` en tête de chaque requête — ne changer QUE là.
--
-- Exécutables DÈS AUJOURD'HUI (ne dépendent pas du futur) :
--   §0 intégrité de recomposition, §3 calibration CTR (= aussi le check
--   mensuel du backlog #3 : les SERP features dérivent), §5 stabilité poids.
-- Exécutables à J+28 SEULEMENT : §1-2 Spearman prédictif, §4 ablation.
--
-- CRITÈRES (spec docs/cpi-cooked-page-index.md §Validation) :
--   §0 : |recomposé − cpi_raw| ≤ 2 pts sur ≥ 95 % des pages (écarts = arrondis
--        des z/momentum/gate stockés à 1-2 décimales).
--   §2 : Spearman(CPI_t0, Δcontacts) > 0,3 sur le périmètre grade A/B.
--   §3 : R² log-log ≥ 0,85 (référence au fit du 10/06/2026 : 0,917) et écart
--        médian |obs−préd|/préd par bucket < 20 %.
--   §4 : aucune ablation ne doit AMÉLIORER le ρ de > 0,05 (sinon la composante
--        retirée ajoute du bruit → recalibrer son poids à la baisse).
--   §5 : Kendall τ-b > 0,9 pour les 8 perturbations ±0,05.
--
-- SI LE TEST §2 ÉCHOUE — grille de décision (recalibrer, pas masquer) :
--   1. Lire d'abord n et pct_ties : si > 70 % des pages ont Δ = 0, le test
--      primaire manque de puissance → juger sur les cibles secondaires
--      (Δvaleur composite §2, Δclics GSC §2bis) avant de toucher aux poids.
--   2. Lire §4 : si une ablation monte le ρ, baisser le poids de la composante
--      retirée (pas de grid search sauvage : ±0,05 par ±0,05, re-§2 à chaque
--      pas, et re-§5 pour vérifier que le classement reste stable).
--   3. Si TOUTES les cibles sont plates : le CPI décrit mais ne prédit pas à
--      28 j — l'écrire tel quel dans la doc, allonger l'horizon (56 j) et
--      re-tester. Ne JAMAIS supprimer le critère de la spec.
--
-- CAVEATS DE MESURE (à rappeler dans le rapport) :
--   - Attribution asymétrique : les champs cachés cooked_aid sont déployés
--     depuis la nuit du 10/06/2026 → le stitching résout mieux le futur
--     (~95 % attendu) que le passé (~75 %). Corrigé par la normalisation
--     par taux de résolution (CTE `resol` du §1-2). Sans elle, le Δ serait
--     gonflé uniformément.
--   - GSC a un lag J-2/J-3 : §2bis tronque symétriquement les deux fenêtres
--     (len = min(28, jours GSC disponibles après t0)) et expose
--     `fenetre_suffisante` (len ≥ 21) — ne PAS conclure si false.
--   - Spearman/Kendall calculés sur le SCORE CONTINU recomposé (pas l'int
--     borné à 100) pour ne pas fabriquer des ties artificiels.
--
-- DRY-RUN DU 10/06/2026 (baselines pour le lecteur du 08/07) :
--   §0 : 194/194 pages recomposées exactement (écart max 0) ✓
--   §3 : R² = 0,915, pente −1,352, 20 buckets ✓ — MAIS courbure non captée :
--        obs +44/+67 % vs prédit en pos 3-4, −28/−42 % en pos 9-13 (médiane
--        |écart| ≈ 24 %). Candidat v2.2 : fit log-log à 2 segments.
--   §5 : τ-b ∈ [0,952 ; 0,966] sur les 8 perturbations ✓ (pire : conv−0,05)
--   Périmètres figés par le snapshot t0 : n = 194 (tous), n = 51 (grade A/B).
--   §1-2/§4 lancés en smoke : ρ négatifs = artefact d'amorçage (1 jour de
--   futur vs 28 de passé) — IGNORER toute exécution avant le 08/07/2026.
--
-- ============================================================================


-- ============================================================================
-- §0 — PRÉ-VOL : intégrité de la recomposition du score depuis cpi_daily
-- (si ceci échoue, §4 et §5 sont invalides : ils reposent sur la recomposition)
-- ============================================================================
WITH params AS (SELECT date '2026-06-10' AS t0),
snap AS (SELECT c.* FROM public.cpi_daily c JOIN params p ON c.day = p.t0),
recomp AS (
  SELECT path, cpi_raw,
    round(100 * (1/(1+exp(-(0.30*zc + 0.15*zr + 0.20*zl + 0.35*zv)/0.8)))
          * momentum * gate)::int AS recompose
  FROM snap
)
SELECT count(*)                                                    AS pages,
       count(*) FILTER (WHERE abs(recompose - cpi_raw) <= 2)       AS ok_2pts,
       round(100.0 * count(*) FILTER (WHERE abs(recompose - cpi_raw) <= 2)
             / count(*), 1)                                        AS pct_ok,
       max(abs(recompose - cpi_raw))                               AS ecart_max
FROM recomp;
-- Attendu : pct_ok ≥ 95, ecart_max ≤ 3.


-- ============================================================================
-- §1-2 — SPEARMAN PRÉDICTIF (cible primaire + composite) — à J+28
-- Cible primaire  : Δcontacts macro attribués à l'entrée organique
--                   (conversion_journeys, même attribution que le zv du CPI,
--                   normalisée par le taux de résolution de chaque fenêtre).
-- Cible composite : Δ(contacts + 0,25×bookings de session organique) — plus
--                   dense, aligne la définition de valeur du CPI.
-- Sortie : un rapport cible × périmètre (tous / grade A-B) avec ρ, n, ties.
-- ============================================================================
WITH params AS (SELECT date '2026-06-10' AS t0, 28 AS h),
snap AS (
  SELECT c.path, c.grade,
    100 * (1/(1+exp(-(0.30*c.zc + 0.15*c.zr + 0.20*c.zl + 0.35*c.zv)/0.8)))
        * c.momentum * c.gate AS score
  FROM public.cpi_daily c JOIN params p ON c.day = p.t0
),
-- contacts attribués (toutes entrées, pour le taux de résolution par fenêtre)
cj_all AS (
  SELECT j.*, CASE WHEN public.paris_date(j.occurred_at) >= p.t0 THEN 'fut'
                   WHEN public.paris_date(j.occurred_at) >= p.t0 - p.h THEN 'pas'
              END AS fen
  FROM params p
  CROSS JOIN LATERAL public.conversion_journeys((current_date - (p.t0 - p.h))::int + 1) j
  WHERE public.paris_date(j.occurred_at) >= p.t0 - p.h
    AND public.paris_date(j.occurred_at) <  p.t0 + p.h
),
resol AS (  -- taux de résolution de l'attribution, par fenêtre
  SELECT fen,
    greatest(count(*) FILTER (WHERE entry_path IS NOT NULL)::numeric
             / nullif(count(*), 0), 0.01) AS taux
  FROM cj_all GROUP BY fen
),
contacts AS (
  SELECT c.entry_path AS path,
    sum((c.fen = 'fut')::int) / max(rf.taux) AS c_fut,
    sum((c.fen = 'pas')::int) / max(rp.taux) AS c_pas
  FROM cj_all c
  JOIN resol rf ON rf.fen = 'fut'
  JOIN resol rp ON rp.fen = 'pas'
  WHERE c.entry_path IS NOT NULL AND c.entry_channel LIKE 'organic%'
  GROUP BY c.entry_path
),
-- bookings par session d'entrée organique, bornes absolues (pour la composite)
firstpv AS (
  SELECT DISTINCT ON (e.session_id) e.session_id, e.path,
    public.classify_channel(e.referrer_hostname, e.utm_source, e.utm_medium,
                            'www.jplouton-avocat.fr') AS chan,
    public.paris_date(e.occurred_at) AS d
  FROM public.events_human e, params p
  WHERE e.name = 'pageview'
    AND public.paris_date(e.occurred_at) >= p.t0 - p.h
    AND public.paris_date(e.occurred_at) <  p.t0 + p.h
  ORDER BY e.session_id, e.occurred_at
),
books AS (
  SELECT f.path,
    0.25 * count(*) FILTER (WHERE f.d >= p.t0) AS b_fut,
    0.25 * count(*) FILTER (WHERE f.d <  p.t0) AS b_pas
  FROM firstpv f
  JOIN public.events_human b
    ON b.session_id = f.session_id AND b.name = 'cta_booking_click'
  CROSS JOIN params p
  WHERE f.chan LIKE 'organic%'
  GROUP BY f.path
),
cibles AS (
  SELECT s.path, s.grade, s.score,
    coalesce(c.c_fut, 0) - coalesce(c.c_pas, 0)                        AS d_contacts,
    (coalesce(c.c_fut, 0) + coalesce(b.b_fut, 0))
      - (coalesce(c.c_pas, 0) + coalesce(b.b_pas, 0))                  AS d_valeur
  FROM snap s
  LEFT JOIN contacts c ON c.path = s.path
  LEFT JOIN books    b ON b.path = s.path
),
-- Spearman = corr(mid-rank x, mid-rank y) ; déplié par cible × périmètre
deplie AS (
  SELECT v.cible, v.perim, v.path, v.x, v.y
  FROM cibles t
  CROSS JOIN LATERAL (VALUES
    ('d_contacts', 'tous',  t.path, t.score, t.d_contacts),
    ('d_valeur',   'tous',  t.path, t.score, t.d_valeur),
    ('d_contacts', 'gradeAB', t.path, t.score, t.d_contacts),
    ('d_valeur',   'gradeAB', t.path, t.score, t.d_valeur)
  ) v(cible, perim, path, x, y)
  WHERE v.perim = 'tous' OR t.grade IN ('A','B')
),
ranks AS (
  SELECT cible, perim, x, y,
    avg(rnx) OVER (PARTITION BY cible, perim, x) AS rx,   -- mid-rank (ties)
    avg(rny) OVER (PARTITION BY cible, perim, y) AS ry
  FROM (
    SELECT cible, perim, x, y,
      row_number() OVER (PARTITION BY cible, perim ORDER BY x) AS rnx,
      row_number() OVER (PARTITION BY cible, perim ORDER BY y) AS rny
    FROM deplie
  ) r
)
SELECT cible, perim,
  count(*)                                          AS n,
  round(corr(rx, ry)::numeric, 3)                   AS spearman_rho,
  round(100.0 * (count(*) - count(DISTINCT y)) / count(*), 0) AS pct_ties_cible
FROM ranks
GROUP BY cible, perim
ORDER BY cible, perim;
-- Critère officiel : spearman_rho > 0,3 sur (d_contacts, gradeAB).
-- Si pct_ties_cible > 70 : test sous-puissant, lire d_valeur et §2bis.


-- ============================================================================
-- §2bis — SPEARMAN SECONDAIRE : Δclics GSC (cible dense, ~milliers de clics)
-- Fenêtres tronquées symétriquement au lag GSC. À J+28.
-- ============================================================================
WITH params AS (
  SELECT date '2026-06-10' AS t0,
         greatest(least(public.gsc_last_data_day() - date '2026-06-10' + 1, 28), 0) AS len
),
snap AS (
  SELECT c.path, c.grade,
    100 * (1/(1+exp(-(0.30*c.zc + 0.15*c.zr + 0.20*c.zl + 0.35*c.zv)/0.8)))
        * c.momentum * c.gate AS score
  FROM public.cpi_daily c JOIN params p ON c.day = p.t0
),
gsc AS (
  SELECT g.path,
    sum(g.clicks) FILTER (WHERE g.day >= p.t0)                       AS clics_fut,
    sum(g.clicks) FILTER (WHERE g.day <  p.t0)                       AS clics_pas
  FROM public.gsc_path_daily g, params p
  WHERE g.day >= p.t0 - p.len AND g.day < p.t0 + p.len
  GROUP BY g.path
),
cibles AS (
  SELECT s.path, s.grade, s.score,
    coalesce(g.clics_fut, 0) - coalesce(g.clics_pas, 0) AS d_clics
  FROM snap s LEFT JOIN gsc g ON g.path = s.path
),
ranks AS (
  SELECT perim, x, y,
    avg(rnx) OVER (PARTITION BY perim, x) AS rx,
    avg(rny) OVER (PARTITION BY perim, y) AS ry
  FROM (
    SELECT v.perim, v.x, v.y,
      row_number() OVER (PARTITION BY v.perim ORDER BY v.x) AS rnx,
      row_number() OVER (PARTITION BY v.perim ORDER BY v.y) AS rny
    FROM cibles t
    CROSS JOIN LATERAL (VALUES ('tous', t.score, t.d_clics),
                               ('gradeAB', t.score, t.d_clics)) v(perim, x, y)
    WHERE v.perim = 'tous' OR t.grade IN ('A','B')
  ) r
)
SELECT perim, count(*) AS n,
  round(corr(rx, ry)::numeric, 3) AS spearman_rho,
  (SELECT len FROM params)        AS fenetre_jours,
  (SELECT len >= 21 FROM params)  AS fenetre_suffisante
FROM ranks GROUP BY perim ORDER BY perim;
-- Lecture : cible dense → si ρ y est net mais plat sur les contacts, le CPI
-- prédit le trafic mais pas (encore) la conversion à cet horizon.
-- fenetre_suffisante = false ⇒ trop tôt (lag GSC) : NE PAS conclure.


-- ============================================================================
-- §3 — CALIBRATION DE LA COURBE CTR (exécutable à tout moment ; check mensuel)
-- Refit identique à la CTE `fit` de cooked_page_index (90 j, branded exclu,
-- buckets pos 1-20 avec ≥ 200 imps) + R² + écart observé/prédit par bucket.
-- ============================================================================
WITH base AS (
  SELECT round(position)::int AS pos,
    (sum(clicks) + 1.0) / (sum(impressions) + 20.0) AS ctr,
    sum(impressions) AS imps
  FROM public.gsc_query_page_daily
  WHERE day > current_date - 90 AND query !~* 'plouton'
  GROUP BY 1
  HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions) >= 200
),
fit AS (
  SELECT regr_slope(ln(ctr), ln(pos))     AS pente,
         regr_intercept(ln(ctr), ln(pos)) AS icept,
         regr_r2(ln(ctr), ln(pos))        AS r2,
         count(*)                         AS n_buckets
  FROM base
)
SELECT b.pos, b.imps,
  round(b.ctr::numeric, 4)                                   AS ctr_obs,
  round(exp(f.icept + f.pente * ln(b.pos))::numeric, 4)      AS ctr_pred,
  round((100 * (b.ctr - exp(f.icept + f.pente * ln(b.pos)))
         / exp(f.icept + f.pente * ln(b.pos)))::numeric, 0)  AS ecart_pct,
  round(f.r2::numeric, 3)                                    AS r2_global,
  round(f.pente::numeric, 3)                                 AS pente,
  f.n_buckets
FROM base b, fit f
ORDER BY b.pos;
-- Critères : r2_global ≥ 0,85 (réf. 10/06/2026 : 0,917) ; médiane |ecart_pct|
-- < 20. Si r2 < 0,85 : la SERP a dérivé (features, ads) → noter la date, et
-- si persistant 2 mois, envisager un fit par famille d'intent (v2.2).


-- ============================================================================
-- §4 — ABLATION PAR COMPOSANTE (à J+28 — requiert la cible du §1-2)
-- Le score est recomposé 5× depuis cpi_daily (complet + 4 ablations w_k = 0).
-- Échelle non renormalisée : Spearman ne dépend que des rangs.
-- ============================================================================
WITH params AS (SELECT date '2026-06-10' AS t0, 28 AS h),
snap AS (
  SELECT c.* FROM public.cpi_daily c JOIN params p ON c.day = p.t0
),
cj_all AS (
  SELECT j.*, CASE WHEN public.paris_date(j.occurred_at) >= p.t0 THEN 'fut'
                   WHEN public.paris_date(j.occurred_at) >= p.t0 - p.h THEN 'pas'
              END AS fen
  FROM params p
  CROSS JOIN LATERAL public.conversion_journeys((current_date - (p.t0 - p.h))::int + 1) j
  WHERE public.paris_date(j.occurred_at) >= p.t0 - p.h
    AND public.paris_date(j.occurred_at) <  p.t0 + p.h
),
resol AS (
  SELECT fen, greatest(count(*) FILTER (WHERE entry_path IS NOT NULL)::numeric
               / nullif(count(*), 0), 0.01) AS taux
  FROM cj_all GROUP BY fen
),
contacts AS (
  SELECT c.entry_path AS path,
    sum((c.fen = 'fut')::int) / max(rf.taux)
      - sum((c.fen = 'pas')::int) / max(rp.taux) AS d_contacts
  FROM cj_all c
  JOIN resol rf ON rf.fen = 'fut' JOIN resol rp ON rp.fen = 'pas'
  WHERE c.entry_path IS NOT NULL AND c.entry_channel LIKE 'organic%'
  GROUP BY c.entry_path
),
variantes AS (
  SELECT s.path, s.grade, coalesce(c.d_contacts, 0) AS y, v.nom,
    100 * (1/(1+exp(-(v.wc*s.zc + v.wr*s.zr + v.wl*s.zl + v.wv*s.zv)/0.8)))
        * s.momentum * s.gate AS x
  FROM snap s LEFT JOIN contacts c ON c.path = s.path
  CROSS JOIN LATERAL (VALUES
    ('complet',        0.30, 0.15, 0.20, 0.35),
    ('sans_capture',   0.00, 0.15, 0.20, 0.35),
    ('sans_retention', 0.30, 0.00, 0.20, 0.35),
    ('sans_lecture',   0.30, 0.15, 0.00, 0.35),
    ('sans_conversion',0.30, 0.15, 0.20, 0.00)
  ) v(nom, wc, wr, wl, wv)
  WHERE s.grade IN ('A','B')   -- périmètre du critère officiel
),
ranks AS (
  SELECT nom, x, y,
    avg(rnx) OVER (PARTITION BY nom, x) AS rx,
    avg(rny) OVER (PARTITION BY nom, y) AS ry
  FROM (
    SELECT nom, x, y,
      row_number() OVER (PARTITION BY nom ORDER BY x) AS rnx,
      row_number() OVER (PARTITION BY nom ORDER BY y) AS rny
    FROM variantes
  ) r
)
SELECT nom, count(*) AS n, round(corr(rx, ry)::numeric, 3) AS spearman_rho
FROM ranks GROUP BY nom
ORDER BY (nom <> 'complet'), nom;
-- Lecture : ρ(ablation) > ρ(complet) + 0,05 ⇒ la composante retirée NUIT au
-- pouvoir prédictif → baisser son poids (pas la supprimer d'office : elle
-- peut porter du diagnostic même sans prédire).


-- ============================================================================
-- §5 — STABILITÉ DES POIDS ±0,05 : Kendall τ-b vs classement de référence
-- (exécutable dès aujourd'hui — ne dépend pas de la cible future)
-- ============================================================================
WITH params AS (SELECT date '2026-06-10' AS t0),
snap AS (
  SELECT c.* FROM public.cpi_daily c JOIN params p ON c.day = p.t0
),
variantes AS (
  SELECT s.path, v.nom,
    100 * (1/(1+exp(-(v.wc*s.zc + v.wr*s.zr + v.wl*s.zl + v.wv*s.zv)/0.8)))
        * s.momentum * s.gate AS x
  FROM snap s
  CROSS JOIN LATERAL (VALUES
    ('ref',      0.30, 0.15, 0.20, 0.35),
    ('cap+.05',  0.35, 0.15, 0.20, 0.35), ('cap-.05',  0.25, 0.15, 0.20, 0.35),
    ('ret+.05',  0.30, 0.20, 0.20, 0.35), ('ret-.05',  0.30, 0.10, 0.20, 0.35),
    ('lec+.05',  0.30, 0.15, 0.25, 0.35), ('lec-.05',  0.30, 0.15, 0.15, 0.35),
    ('conv+.05', 0.30, 0.15, 0.20, 0.40), ('conv-.05', 0.30, 0.15, 0.20, 0.30)
  ) v(nom, wc, wr, wl, wv)
),
ref AS (SELECT path, x FROM variantes WHERE nom = 'ref'),
paires AS (
  SELECT va.nom,
    sign(va.x - vb.x) AS sx,
    sign(ra.x - rb.x) AS sy
  FROM variantes va
  JOIN variantes vb ON vb.nom = va.nom AND vb.path > va.path
  JOIN ref ra ON ra.path = va.path
  JOIN ref rb ON rb.path = vb.path
  WHERE va.nom <> 'ref'
),
compte AS (
  SELECT nom,
    count(*) FILTER (WHERE sx * sy > 0)::numeric            AS c_conc,
    count(*) FILTER (WHERE sx * sy < 0)::numeric            AS d_disc,
    count(*) FILTER (WHERE sx = 0 AND sy <> 0)::numeric     AS t_x,
    count(*) FILTER (WHERE sy = 0 AND sx <> 0)::numeric     AS t_y
  FROM paires GROUP BY nom
)
SELECT nom,
  round((c_conc - d_disc)
        / sqrt((c_conc + d_disc + t_x) * (c_conc + d_disc + t_y)), 3) AS kendall_tau_b
FROM compte
ORDER BY kendall_tau_b ASC;
-- Critère : τ-b > 0,9 partout. Le pire τ identifie le poids le plus sensible
-- (attendu : conv, le plus lourd). Si τ < 0,9 : le classement est un artefact
-- du choix des poids → les recalibrer contre la cible §2 avant tout usage.
