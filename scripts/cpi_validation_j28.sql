-- ============================================================================
-- CPI v2.2 — Harnais de validation J+28 (Sprint 38 → amendé T-07, 02/07/2026)
-- ============================================================================
--
-- À LANCER À PARTIR DU 08/07/2026 (t0 = snapshot cpi_daily du 10/06/2026 + 28 j
-- de contacts observés) ; re-test DIAGNOSTIC à 56 j = 05/08/2026 (t0 inchangé,
-- horizon doublé — pas un gate). Chaque section (§) est une requête AUTONOME
-- (execute_sql indépendants, pas de temp table). Le t0 vit dans la CTE `params`
-- en tête de chaque requête — ne changer QUE là.
--
-- Exécutables DÈS AUJOURD'HUI : §0 recomposition, §3 calibration CTR, §5
-- stabilité poids. Exécutables à J+28 : §1 tiers, §1-annexe, §2bis, §4.
--
-- ┌─ AMENDEMENT T-07 (02/07/2026) — POURQUOI ────────────────────────────────
-- │ Cible primaire d'origine = Spearman(CPI, Δcontacts) > 0,3. Or Δ = change-
-- │ score (c_fut − c_pas) et les 4 z du CPI encodent le PASSÉ → le score
-- │ corrèle avec c_pas, donc tout Δ est anti-corrélé par régression vers la
-- │ moyenne. Mesuré au t0 (grade A/B, n=51) : ρ(score,c_pas)=+0,49 ;
-- │ ρ(score,Δcontacts)=−0,43  ← artefact RTM, PAS un échec du CPI. Tel quel le
-- │ test conclurait « échec » et la grille baisserait le poids conversion pour
-- │ une mauvaise raison. On corrige le PROTOCOLE, pas les poids (décision S39).
-- │
-- │ Vérif 02/07 : passer au NIVEAU futur par page supprime l'artefact mais ne
-- │ crée pas de signal — ρ(score,c_fut/n_org)=−0,13 (84% ties, contacts trop
-- │ rares) ; ρ(score,clics_fut)=−0,18/−0,40 (le CPI n'est VOLONTAIREMENT pas un
-- │ proxy de taille). => le Spearman PAR PAGE est sans puissance sur un outcome
-- │ rare. On le remplace comme diagnostic PRIMAIRE par une comparaison AGRÉGÉE
-- │ PAR TIERS (Σc_fut/Σn_org, tiers haut vs bas), qui garde de la puissance
-- │ (smoke 22j : ratio 3,18). La corrélation par page passe en ANNEXE.
-- │ La validation prédictive reste NON-GATING ; le verdict repose sur les
-- │ critères STRUCTURELS (§0/§3/§5).
-- └──────────────────────────────────────────────────────────────────────────
--
-- CRITÈRES LIANTS (pass/fail — validation réelle du CPI) :
--   §0 recomposition : |recomposé − cpi_raw| ≤ 2 pts sur ≥ 95% des pages.
--   §3 calibration   : R² log-log ≥ 0,85 (auj. 0,930 ; réf 10/06 0,917).
--   §5 stabilité     : Kendall τ-b > 0,9 sur les 8 perturbations ±0,05.
--
-- DIAGNOSTICS EXPLORATOIRES (aucun gate ; cibles en NIVEAU futur, jamais en Δ) :
--   §1 PRIMAIRE = ratio de taux de contact futur (Σc_fut/Σn_org) tiers HAUT vs
--        BAS des pages grade A/B triées par CPI. Pré-déclaré :
--          ratio ≥ 1,5  = signal prédictif POSITIF (bonus)
--          ratio ≤ 1    = signal d'ALERTE à investiguer (non liant)
--          1 < ratio < 1,5 = neutre.
--   §1-annexe = Spearman PAR PAGE : rate_fut (niveau, sous-puissant attendu) +
--        Δcontacts, Δvaleur (RTM, ρ≈−0,4). Descriptif, AUCUN verdict.
--   §2bis dense = clics GSC futurs (niveau). ρ ≤ 0 y est ATTENDU (indépendance
--        à la taille) → ne valide NI n'invalide.
--   §4 ablation = même ratio par tiers, recomposé par pondération (grade A/B).
--
-- RÈGLE DE VERDICT GLOBAL (pré-déclarée avant le 08/07) :
--   VALIDÉ            : §0 ∧ §3(R²) ∧ §5 passent (état attendu).
--   +BONUS PRÉDICTIF  : si en plus §1 ratio ≥ 1,5.
--   ALERTE            : §1 ratio ≤ 1 → investiguer (non liant, ne fait pas
--                       échouer la validation structurelle).
--   INCONCLUANT-PRED  : signaux plats → l'écrire tel quel ; ré-tester à 56 j.
--   INTERDIT          : baisser un poids du CPI sur la foi d'un ρ/ratio (Δ=RTM,
--                       niveau par page = sous-puissant). Décision produit S39.
--   LIBELLÉ MAX AUTORISÉ dans le rapport : « CPI validé comme score de
--   PRIORISATION, non comme prédicteur d'outcome à 28 j ». Toujours reporter le
--   chiffre §3 (médiane |écart|) dans le verdict.
--
-- §3 — STATUT HONNÊTE (ne PAS marquer « PASSE » sans nuance) :
--   R² = 0,930 ≥ 0,85 → critère liant PASSE. MAIS la médiane |obs−préd|/préd =
--   20,1% aujourd'hui (24% au 10/06) dépasse le sous-seuil « < 20% » de la spec
--   d'origine. AMENDEMENT ÉCRIT : ce sous-seuil est RÉTROGRADÉ en INDICATEUR DE
--   SUIVI (non liant) — il mesure la courbure non captée par la loi de puissance
--   à 1 segment (obs > préd en pos 3-4, obs < préd en pos 9-13), candidat v2.2
--   « fit 2 segments ». On NE prétend PAS que « < 20% » passe ; on REPORTE le
--   chiffre. Le critère liant reste R² ≥ 0,85.
--
-- CAVEATS DE MESURE (à rappeler dans le rapport) :
--   - Attribution asymétrique : cooked_aid déployé depuis la nuit du 10/06 →
--     le futur résout mieux (~95%) que le passé (~75%). Normalisé par le taux
--     de résolution par fenêtre (CTE `resol`).
--   - GSC lag J-2/J-3 : §2bis tronque symétriquement (len = min(28, jours GSC
--     dispo après t0)) et expose `fenetre_suffisante` (len ≥ 21) — ne PAS
--     conclure si false.
--   - Spearman/Kendall sur le SCORE CONTINU recomposé (pas l'int borné à 100).
--
-- DRY-RUN 02/07/2026 (baselines pour le lecteur du 08/07) :
--   §0 : recomposition exacte (réf 10/06 : 194/194, écart max 0) ✓
--   §3 : R² 0,930 ✓ ; médiane |écart| 20,1% (suivi, non liant) ; max 73%
--   §5 : τ-b ∈ [0,952 ; 0,966] (réf 10/06) ✓
--   §1 tiers (smoke, futur partiel ~22j) : taux_haut 0,62% vs taux_bas 0,20%,
--        ratio 3,18 (n=17/tiers) → prometteur mais petits comptes (13,9 vs 11,1
--        contacts), à refaire à 28j pleins le 08/07.
--   §1-annexe (smoke) : ρ(niveau) ≈ −0,13, ties 84–94% → sous-puissant CONFIRMÉ.
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
-- §1 — DIAGNOSTIC PRIMAIRE (NON-GATING) : ratio de taux de contact futur
-- entre le tiers HAUT et le tiers BAS des pages grade A/B triées par CPI.
-- Pooler (Σc_fut/Σn_org par tiers) garde de la puissance là où le Spearman
-- par page n'en a aucune (contacts rares, 84-94% de ties). À J+28.
-- ============================================================================
WITH params AS (SELECT date '2026-06-10' AS t0, 28 AS h),
snap AS (
  SELECT c.path, c.grade, c.n_org,
    100 * (1/(1+exp(-(0.30*c.zc + 0.15*c.zr + 0.20*c.zl + 0.35*c.zv)/0.8)))
        * c.momentum * c.gate AS score
  FROM public.cpi_daily c JOIN params p ON c.day = p.t0
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
resol AS (  -- taux de résolution de l'attribution, futur uniquement (primaire)
  SELECT fen, greatest(count(*) FILTER (WHERE entry_path IS NOT NULL)::numeric
               / nullif(count(*), 0), 0.01) AS taux
  FROM cj_all GROUP BY fen
),
contacts AS (
  SELECT c.entry_path AS path, sum((c.fen = 'fut')::int) / max(rf.taux) AS c_fut
  FROM cj_all c JOIN resol rf ON rf.fen = 'fut'
  WHERE c.entry_path IS NOT NULL AND c.entry_channel LIKE 'organic%'
  GROUP BY c.entry_path
),
ab AS (  -- pages grade A/B avec score, dénominateur organique, contacts futurs
  SELECT s.path, s.score, s.n_org, coalesce(c.c_fut, 0) AS c_fut
  FROM snap s LEFT JOIN contacts c ON c.path = s.path
  WHERE s.grade IN ('A','B')
),
tiers AS (SELECT *, ntile(3) OVER (ORDER BY score DESC) AS tier FROM ab)
SELECT
  count(*) FILTER (WHERE tier = 1)                                  AS n_haut,
  count(*) FILTER (WHERE tier = 3)                                  AS n_bas,
  round(sum(c_fut) FILTER (WHERE tier = 1)::numeric, 1)             AS cfut_haut,
  round(sum(n_org) FILTER (WHERE tier = 1)::numeric, 0)             AS norg_haut,
  round(sum(c_fut) FILTER (WHERE tier = 3)::numeric, 1)             AS cfut_bas,
  round(sum(n_org) FILTER (WHERE tier = 3)::numeric, 0)             AS norg_bas,
  round((sum(c_fut) FILTER (WHERE tier = 1)
         / nullif(sum(n_org) FILTER (WHERE tier = 1), 0))::numeric, 5) AS taux_haut,
  round((sum(c_fut) FILTER (WHERE tier = 3)
         / nullif(sum(n_org) FILTER (WHERE tier = 3), 0))::numeric, 5) AS taux_bas,
  round(((sum(c_fut) FILTER (WHERE tier = 1) / nullif(sum(n_org) FILTER (WHERE tier = 1), 0))
       / nullif(sum(c_fut) FILTER (WHERE tier = 3)
                / nullif(sum(n_org) FILTER (WHERE tier = 3), 0), 0))::numeric, 2) AS ratio_haut_bas
FROM tiers;
-- Pré-déclaré : ratio ≥ 1,5 = signal prédictif POSITIF (bonus) ; ≤ 1 = ALERTE
-- (non liant, à investiguer) ; entre = neutre. Petits comptes → lire cfut_*.


-- ============================================================================
-- §1-annexe — SPEARMAN PAR PAGE (DESCRIPTIF, AUCUN VERDICT) : niveau + Δ.
-- rate_fut (niveau, sous-puissant attendu) documente l'absence de signal par
-- page ; d_contacts / d_valeur (Δ) documentent l'ampleur du biais RTM (≈ −0,4).
-- À J+28. NE JAMAIS tirer de décision de poids de cette section.
-- ============================================================================
WITH params AS (SELECT date '2026-06-10' AS t0, 28 AS h),
snap AS (
  SELECT c.path, c.grade, c.n_org,
    100 * (1/(1+exp(-(0.30*c.zc + 0.15*c.zr + 0.20*c.zl + 0.35*c.zv)/0.8)))
        * c.momentum * c.gate AS score
  FROM public.cpi_daily c JOIN params p ON c.day = p.t0
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
    sum((c.fen = 'fut')::int) / max(rf.taux) AS c_fut,
    sum((c.fen = 'pas')::int) / max(rp.taux) AS c_pas
  FROM cj_all c
  JOIN resol rf ON rf.fen = 'fut'
  JOIN resol rp ON rp.fen = 'pas'
  WHERE c.entry_path IS NOT NULL AND c.entry_channel LIKE 'organic%'
  GROUP BY c.entry_path
),
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
    coalesce(c.c_fut, 0) / nullif(s.n_org, 0)                          AS rate_fut,
    coalesce(c.c_fut, 0) - coalesce(c.c_pas, 0)                        AS d_contacts,
    (coalesce(c.c_fut, 0) + coalesce(b.b_fut, 0))
      - (coalesce(c.c_pas, 0) + coalesce(b.b_pas, 0))                  AS d_valeur
  FROM snap s
  LEFT JOIN contacts c ON c.path = s.path
  LEFT JOIN books    b ON b.path = s.path
),
deplie AS (
  SELECT v.cible, v.perim, v.x, v.y
  FROM cibles t
  CROSS JOIN LATERAL (VALUES
    ('1_rate_fut(niveau)', 'gradeAB', t.score, t.rate_fut),
    ('2_d_contacts(Δ,RTM)','gradeAB', t.score, t.d_contacts),
    ('3_d_valeur(Δ,RTM)',  'gradeAB', t.score, t.d_valeur),
    ('1_rate_fut(niveau)', 'tous',    t.score, t.rate_fut),
    ('2_d_contacts(Δ,RTM)','tous',    t.score, t.d_contacts),
    ('3_d_valeur(Δ,RTM)',  'tous',    t.score, t.d_valeur)
  ) v(cible, perim, x, y)
  WHERE v.perim = 'tous' OR t.grade IN ('A','B')
),
ranks AS (
  SELECT cible, perim, x, y,
    avg(rnx) OVER (PARTITION BY cible, perim, x) AS rx,
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
  round(100.0 * (count(*) - count(DISTINCT y)) / count(*), 0) AS pct_ties
FROM ranks
GROUP BY cible, perim
ORDER BY cible, perim;
-- Descriptif : rate_fut ≈ 0 avec ties élevés = sous-puissance (contacts rares) ;
-- d_* ≈ −0,4 = régression vers la moyenne. AUCUNE de ces lignes ne décide.


-- ============================================================================
-- §2bis — SECONDAIRE DENSE : clics GSC FUTURS (niveau). À J+28.
-- Cible dense (~milliers, peu de ties). ATTENTION : un ρ ≤ 0 est ATTENDU ici —
-- le CPI est volontairement indépendant de la taille (momentum relatif, capture
-- standardisée). Cette section NE valide NI n'invalide ; elle borne la lecture.
-- Fenêtres tronquées symétriquement au lag GSC.
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
    coalesce(g.clics_fut, 0)                            AS clics_fut,
    coalesce(g.clics_fut, 0) - coalesce(g.clics_pas, 0) AS d_clics
  FROM snap s LEFT JOIN gsc g ON g.path = s.path
),
ranks AS (
  SELECT cible, perim, x, y,
    avg(rnx) OVER (PARTITION BY cible, perim, x) AS rx,
    avg(rny) OVER (PARTITION BY cible, perim, y) AS ry
  FROM (
    SELECT v.cible, v.perim, v.x, v.y,
      row_number() OVER (PARTITION BY v.cible, v.perim ORDER BY v.x) AS rnx,
      row_number() OVER (PARTITION BY v.cible, v.perim ORDER BY v.y) AS rny
    FROM cibles t
    CROSS JOIN LATERAL (VALUES
      ('clics_fut(niveau)', 'tous',    t.score, t.clics_fut),
      ('clics_fut(niveau)', 'gradeAB', t.score, t.clics_fut),
      ('d_clics(Δ)',        'tous',    t.score, t.d_clics)
    ) v(cible, perim, x, y)
    WHERE v.perim = 'tous' OR t.grade IN ('A','B')
  ) r
)
SELECT cible, perim, count(*) AS n,
  round(corr(rx, ry)::numeric, 3) AS spearman_rho,
  (SELECT len FROM params)        AS fenetre_jours,
  (SELECT len >= 21 FROM params)  AS fenetre_suffisante
FROM ranks GROUP BY cible, perim ORDER BY cible, perim;
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
-- CRITÈRE LIANT : r2_global ≥ 0,85 (réf. 10/06/2026 : 0,917 ; auj. 0,930).
-- SUIVI (non liant, T-07) : médiane |ecart_pct| — la reporter dans le verdict
-- (auj. 20,1%, 10/06 : 24%). > 20% = courbure non captée par la loi de puissance
-- 1 segment (candidat v2.2 « fit 2 segments »), PAS un échec de validation.


-- ============================================================================
-- §4 — ABLATION PAR COMPOSANTE (à J+28) : même RATIO PAR TIERS que §1, recomposé
-- 5× (complet + 4 ablations w_k = 0). Cible NIVEAU (c_fut/n_org), grade A/B.
-- ============================================================================
WITH params AS (SELECT date '2026-06-10' AS t0, 28 AS h),
snap AS (SELECT c.* FROM public.cpi_daily c JOIN params p ON c.day = p.t0),
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
  SELECT c.entry_path AS path, sum((c.fen = 'fut')::int) / max(rf.taux) AS c_fut
  FROM cj_all c JOIN resol rf ON rf.fen = 'fut'
  WHERE c.entry_path IS NOT NULL AND c.entry_channel LIKE 'organic%'
  GROUP BY c.entry_path
),
variantes AS (
  SELECT s.path, s.n_org, coalesce(c.c_fut, 0) AS c_fut, v.nom,
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
  WHERE s.grade IN ('A','B')
),
tiers AS (SELECT *, ntile(3) OVER (PARTITION BY nom ORDER BY x DESC) AS tier FROM variantes)
SELECT nom,
  round((sum(c_fut) FILTER (WHERE tier = 1) / nullif(sum(n_org) FILTER (WHERE tier = 1), 0))
      / nullif(sum(c_fut) FILTER (WHERE tier = 3)
               / nullif(sum(n_org) FILTER (WHERE tier = 3), 0), 0)::numeric, 2) AS ratio_haut_bas
FROM tiers GROUP BY nom
ORDER BY (nom <> 'complet'), nom;
-- Lecture : ratio(ablation) nettement > ratio(complet) ⇒ la composante retirée
-- NUIT à la séparation → baisser son poids (jamais supprimer d'office : elle
-- peut porter du diagnostic sans prédire). Pas de grid search sauvage.


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
-- CRITÈRE LIANT : τ-b > 0,9 partout. Le pire τ identifie le poids le plus
-- sensible (attendu : conv, le plus lourd). Si τ < 0,9 : le classement est un
-- artefact du choix des poids → recalibrer contre §1 avant tout usage.
