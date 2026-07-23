-- 23/07/2026 — Norme produit CPI :
--   • colonne `grade` = **Fiabilité** S / A / B / C (plus « Grade »)
--   • vue `cpi_gisement` → `cpi_opportunite_contact` (« Opportunité de contact »)
--   • `cpi_gisement` reste un ALIAS déprécié (compat refreshers / scripts)
--
-- Seuils Fiabilité (cooked_page_index) :
--   S = n_org ≥ 200 ET E ≥ 40   (très fiable)
--   A = n_org ≥ 100 ET E ≥ 20   (fiable — ancien A)
--   B = n_org ≥  30 ET E ≥  5   (indicatif — ancien B)
--   C = sinon                   (insuffisant)
-- « Fiable » pour movers / opportunités / alertes = grade IN ('S','A','B').

-- ── 1. cooked_page_index : Fiabilité S/A/B/C ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.cooked_page_index(p_days integer DEFAULT 28)
 RETURNS TABLE(path text, ptype text, grade text, cpi integer, cpi_raw integer, momentum numeric, momentum_badge text, gate numeric, zc numeric, zr numeric, zl numeric, zv numeric, clics_perdus integer, n_org bigint, couv_gsc_pct integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
WITH fit AS (
  SELECT regr_slope(ln(ctr), ln(pos)) AS pente, regr_intercept(ln(ctr), ln(pos)) AS icept
  FROM (SELECT round(position)::int pos, (sum(clicks)+1.0)/(sum(impressions)+20.0) ctr
        FROM public.gsc_query_page_daily WHERE day > current_date - 90 AND NOT public.gsc_is_branded(query)
        GROUP BY 1 HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions) >= 200) b
),
capq AS (SELECT g.path, sum(g.impressions) i_qpd,
    sum(g.impressions * least(greatest(exp(f.icept + f.pente*ln(greatest(g.position,1.0))),0.0005),0.5)) e_qpd
  FROM public.gsc_query_page_daily g, fit f WHERE g.day > current_date - p_days AND NOT public.gsc_is_branded(g.query) GROUP BY g.path),
capb AS (SELECT path, sum(clicks) o_b, sum(impressions) i_b FROM public.gsc_query_page_daily
  WHERE day > current_date - p_days AND public.gsc_is_branded(query) GROUP BY path),
capp AS (SELECT path, sum(clicks) o_full, sum(impressions) i_full FROM public.gsc_path_daily WHERE day > current_date - p_days GROUP BY path),
cap AS (SELECT p.path, greatest(p.o_full - coalesce(b.o_b,0),0)::numeric AS o,
    CASE WHEN coalesce(q.i_qpd,0)>0 THEN q.e_qpd*(greatest(p.i_full-coalesce(b.i_b,0),0)::numeric/q.i_qpd) ELSE NULL END AS e,
    q.i_qpd, greatest(p.i_full-coalesce(b.i_b,0),0) AS i_nb
  FROM capp p LEFT JOIN capq q ON q.path=p.path LEFT JOIN capb b ON b.path=p.path),
firstpv AS (SELECT DISTINCT ON (session_id) session_id, eh.path,
    public.classify_channel(referrer_hostname, utm_source, utm_medium,'www.jplouton-avocat.fr') chan
  FROM public.events_human eh WHERE name='pageview' AND occurred_at > now() - make_interval(days => p_days) ORDER BY session_id, occurred_at),
orge AS (SELECT session_id, firstpv.path FROM firstpv WHERE chan LIKE 'organic%'),
norg AS (SELECT orge.path, count(*) n_org FROM orge GROUP BY orge.path),
spv AS (SELECT session_id, count(*) pv FROM public.events_human WHERE name='pageview' AND occurred_at > now() - make_interval(days => p_days) GROUP BY session_id),
pex AS (SELECT e.session_id, e.path,
    max((e.props->>'duration_seconds')::numeric) d,
    max(coalesce((e.props->>'max_scroll')::numeric,0)) s
  FROM public.events_human e
  WHERE e.name='page_exit' AND e.occurred_at > now() - make_interval(days => p_days)
  GROUP BY e.session_id, e.path),
ex2 AS (SELECT o.path, public.cooked_page_type(o.path) ptype, px.d,
    coalesce(px.s,0) s,
    (px.d >= 15 OR coalesce(s2.pv,1) >= 2) retained
  FROM orge o JOIN pex px ON px.session_id=o.session_id AND px.path=o.path
  LEFT JOIN spv s2 ON s2.session_id=o.session_id),
thr AS (SELECT ptype, percentile_cont(0.5) WITHIN GROUP (ORDER BY d) tau, percentile_cont(0.5) WITHIN GROUP (ORDER BY s) sig FROM ex2 WHERE retained GROUP BY ptype),
reads AS (SELECT e.path, max(e.ptype) ptype, count(*) n, count(*) FILTER (WHERE retained) r,
    count(*) FILTER (WHERE retained AND d >= t.tau AND s >= t.sig) k FROM ex2 e JOIN thr t ON t.ptype=e.ptype GROUP BY e.path),
tmeans AS (SELECT ptype, coalesce(sum(r)::numeric/nullif(sum(n),0),0.5) rho, coalesce(sum(k)::numeric/nullif(sum(r),0),0.25) q FROM reads GROUP BY ptype),
ebk AS (
  SELECT t.ptype, t.rho, t.q,
    CASE WHEN er.np>=5 AND er.v>0 AND er.v < t.rho*(1-t.rho) THEN least(greatest(t.rho*(1-t.rho)/er.v - 1, 5), 200) ELSE 20 END kappa_ret,
    CASE WHEN el.np>=5 AND el.v>0 AND el.v < t.q*(1-t.q) THEN least(greatest(t.q*(1-t.q)/el.v - 1, 5), 200) ELSE 20 END kappa_lec
  FROM tmeans t
  LEFT JOIN (SELECT ptype, var_samp(r::numeric/n) v, count(*) np FROM reads WHERE n>=10 GROUP BY ptype) er ON er.ptype=t.ptype
  LEFT JOIN (SELECT ptype, var_samp(k::numeric/nullif(r,0)) v, count(*) np FROM reads WHERE r>=10 GROUP BY ptype) el ON el.ptype=t.ptype
),
jx AS (SELECT * FROM public.conversion_journeys(p_days) WHERE entry_channel LIKE 'organic%'),
direct AS (SELECT entry_path path, count(*)::numeric v FROM jx WHERE entry_path IS NOT NULL GROUP BY 1),
assist AS (SELECT jp.path, sum(1.0/greatest(j.pages_count,1)) v FROM jx j CROSS JOIN LATERAL unnest(j.journey) jp(path) WHERE jp.path <> j.entry_path GROUP BY jp.path),
book AS (SELECT o.path, 0.25*count(*)::numeric v FROM orge o JOIN public.events_human b ON b.session_id=o.session_id AND b.path=o.path AND b.name='cta_booking_click' GROUP BY o.path),
convv AS (SELECT n.path, n.n_org, coalesce(d.v,0)+coalesce(a.v,0)+coalesce(b.v,0) val
  FROM norg n LEFT JOIN direct d ON d.path=n.path LEFT JOIN assist a ON a.path=n.path LEFT JOIN book b ON b.path=n.path),
tconv AS (SELECT public.cooked_page_type(convv.path) ptype, coalesce(sum(val)/nullif(sum(convv.n_org),0),0) nu FROM convv GROUP BY 1),
xs AS (
  SELECT r.path, r.ptype, c.n_org, c.val, coalesce(cap.o,0) o, cap.e, coalesce(cap.i_qpd,0) i_qpd, coalesce(cap.i_nb,0) i_nb,
    coalesce(ln((coalesce(cap.o,0)+3)/(cap.e+3)),0) x_cap,
    ln( least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999) / (1-least(greatest((r.r + tm.kappa_ret*tm.rho)/(r.n + tm.kappa_ret),0.001),0.999)) ) x_ret,
    ln( least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999) / (1-least(greatest((r.k + tm.kappa_lec*tm.q)/(r.r + tm.kappa_lec),0.001),0.999)) ) x_lec,
    ln( (c.val + 30*tc.nu + 0.05)/(c.n_org+30) ) x_conv
  FROM reads r JOIN convv c ON c.path=r.path LEFT JOIN cap ON cap.path=r.path
  JOIN ebk tm ON tm.ptype=r.ptype JOIN tconv tc ON tc.ptype=r.ptype
  WHERE c.n_org >= 5 AND r.n >= 3
),
medt AS (SELECT ptype, count(*) cnt, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs GROUP BY ptype),
madt AS (SELECT x.ptype,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-m.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-m.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-m.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-m.mv)),0.15) sv FROM xs x JOIN medt m ON m.ptype=x.ptype GROUP BY x.ptype),
medg AS (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml, percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv FROM xs),
madg AS (SELECT greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-g.mc)),0.15) sc,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-g.mr)),0.15) sr,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-g.ml)),0.15) sl,
  greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-g.mv)),0.15) sv FROM xs x, medg g),
mom AS (SELECT gpd.path,
    coalesce(sum(clicks) FILTER (WHERE day > current_date - p_days),0) c1,
    coalesce(sum(clicks) FILTER (WHERE day BETWEEN current_date - 2*p_days AND current_date - p_days - 1),0) c0,
    avg(position) FILTER (WHERE day > current_date - p_days) p1,
    avg(position) FILTER (WHERE day BETWEEN current_date - 2*p_days AND current_date - p_days - 1) p0
  FROM public.gsc_path_daily gpd WHERE day > current_date - 2*p_days GROUP BY gpd.path),
site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom),
lcp AS (SELECT eh.path, percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric) lcp75
  FROM public.events_human eh WHERE name='web_vitals' AND props->>'metric'='LCP' AND device_type='mobile'
    AND occurred_at > now() - make_interval(days => p_days) GROUP BY eh.path),
scored AS (
  SELECT x.path, x.ptype, x.n_org, round(greatest(coalesce(x.e,0)-x.o,0))::int clics_perdus,
    CASE WHEN coalesce(x.i_nb,0)>0 THEN round(100.0*x.i_qpd/x.i_nb)::int ELSE 0 END couv,
    round(least(greatest((x.x_cap - CASE WHEN mt.cnt>=15 THEN mt.mc ELSE mg.mc END)/(CASE WHEN mt.cnt>=15 THEN dt.sc ELSE dg.sc END),-3),3)::numeric,1) zc,
    round(least(greatest((x.x_ret - CASE WHEN mt.cnt>=15 THEN mt.mr ELSE mg.mr END)/(CASE WHEN mt.cnt>=15 THEN dt.sr ELSE dg.sr END),-3),3)::numeric,1) zr,
    round(least(greatest((x.x_lec - CASE WHEN mt.cnt>=15 THEN mt.ml ELSE mg.ml END)/(CASE WHEN mt.cnt>=15 THEN dt.sl ELSE dg.sl END),-3),3)::numeric,1) zl,
    round(least(greatest((x.x_conv - CASE WHEN mt.cnt>=15 THEN mt.mv ELSE mg.mv END)/(CASE WHEN mt.cnt>=15 THEN dt.sv ELSE dg.sv END),-3),3)::numeric,1) zv,
    round(exp(least(greatest(
      (1 - 1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (-0.08*coalesce(m.p1-m.p0,0))
      + (1.0/(1+exp(-((coalesce(m.c1,0)+coalesce(m.c0,0))-20)/5.0))) * (ln((coalesce(m.c1,0)+5.0)/(coalesce(m.c0,0)+5.0)) - ln((s.s1+50.0)/(s.s0+50.0)))
    ,-0.336),0.336))::numeric,2) mm,
    round((1 - 0.15*least(greatest((coalesce(l.lcp75,2500)-2500)/2500.0,0),1))::numeric,2) gg,
    CASE
      WHEN x.n_org >= 200 AND coalesce(x.e,0) >= 40 THEN 'S'
      WHEN x.n_org >= 100 AND coalesce(x.e,0) >= 20 THEN 'A'
      WHEN x.n_org >= 30 AND coalesce(x.e,0) >= 5 THEN 'B'
      ELSE 'C'
    END grade
  FROM xs x LEFT JOIN medt mt ON mt.ptype=x.ptype LEFT JOIN madt dt ON dt.ptype=x.ptype
  CROSS JOIN medg mg CROSS JOIN madg dg LEFT JOIN mom m ON m.path=x.path CROSS JOIN site s LEFT JOIN lcp l ON l.path=x.path
)
SELECT scored.path, scored.ptype, scored.grade,
  least(100, round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int) cpi,
  round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int cpi_raw,
  mm momentum, (CASE WHEN mm>=1.15 THEN '↗' WHEN mm<=0.87 THEN '↘' ELSE '→' END) momentum_badge,
  gg gate, zc, zr, zl, zv, clics_perdus, n_org, couv couv_gsc_pct
FROM scored
$function$;

COMMENT ON FUNCTION public.cooked_page_index(integer) IS
  'CPI par page. Colonne grade = Fiabilité S/A/B/C '
  '(S: n_org≥200∧E≥40 ; A: ≥100∧≥20 ; B: ≥30∧≥5 ; C: sinon).';

COMMENT ON COLUMN public.cpi_daily.grade IS
  'Fiabilité S/A/B/C (norme 23/07/2026). Ancien libellé « grade ».';

COMMENT ON FUNCTION public.cpi_compose(numeric, numeric, numeric, numeric, numeric, numeric, boolean) IS
  'CPI sigmoid (C8). exclude_conversion=true = potentiel opportunité de contact '
  '(zv neutralisé, coeffs historiques).';

-- ── 2. Vue Opportunité de contact (+ alias déprécié cpi_gisement) ───────────
CREATE OR REPLACE VIEW public.cpi_opportunite_contact
  WITH (security_invoker = true)
AS
 SELECT path,
    ptype,
    grade,
    n_org,
    cpi,
    round(public.cpi_compose(zc, zr, zl, 0::numeric, momentum, gate, true))::integer AS potentiel,
    zv > 0::numeric AS convertit,
    zc,
    zr,
    zl,
    zv,
    day
   FROM cpi_daily
  WHERE day = (( SELECT max(cpi_daily_1.day) AS max
           FROM cpi_daily cpi_daily_1));

COMMENT ON VIEW public.cpi_opportunite_contact IS
  'Opportunité de contact (ex-gisement) : relit le dernier cpi_daily, sépare '
  'le potentiel (capture+rétention+lecture) du badge convertit. '
  'Filtrer grade IN (''S'',''A'',''B'') AND NOT convertit ORDER BY potentiel DESC. '
  'Ne recalcule rien.';

REVOKE ALL ON public.cpi_opportunite_contact FROM anon, authenticated;
GRANT SELECT ON public.cpi_opportunite_contact TO service_role;

-- Alias rétrocompat : mêmes lignes, nom historique.
CREATE OR REPLACE VIEW public.cpi_gisement
  WITH (security_invoker = true)
AS
  SELECT * FROM public.cpi_opportunite_contact;

COMMENT ON VIEW public.cpi_gisement IS
  'DEPRECATED alias de cpi_opportunite_contact (norme 23/07/2026). '
  'Préférer cpi_opportunite_contact.';

REVOKE ALL ON public.cpi_gisement FROM anon, authenticated;
GRANT SELECT ON public.cpi_gisement TO service_role;

-- ── 3. cpi_movers : fiable = Fiabilité S/A/B ────────────────────────────────
CREATE OR REPLACE VIEW public.cpi_movers AS
 WITH bounds AS (
         SELECT l.d1,
            r.d0
           FROM ( SELECT max(cpi_daily.day) AS d1
                   FROM cpi_daily) l
             CROSS JOIN LATERAL ( SELECT max(cpi_daily.day) AS d0
                   FROM cpi_daily
                  WHERE cpi_daily.day >= (l.d1 - 14) AND cpi_daily.day <= (l.d1 - 7)) r
          WHERE r.d0 IS NOT NULL
        ), now_rows AS (
         SELECT c.day, c.path, c.ptype, c.grade, c.cpi, c.cpi_raw, c.momentum,
            c.gate, c.zc, c.zr, c.zl, c.zv, c.clics_perdus, c.n_org,
            c.couv_gsc_pct, c.created_at
           FROM cpi_daily c
             JOIN bounds b_1 ON c.day = b_1.d1
        ), ref_rows AS (
         SELECT c.day, c.path, c.ptype, c.grade, c.cpi, c.cpi_raw, c.momentum,
            c.gate, c.zc, c.zr, c.zl, c.zv, c.clics_perdus, c.n_org,
            c.couv_gsc_pct, c.created_at
           FROM cpi_daily c
             JOIN bounds b_1 ON c.day = b_1.d0
        )
 SELECT b.d1 AS day_now,
    b.d0 AS day_ref,
    b.d1 - b.d0 AS ecart_jours,
    COALESCE(n.path, p.path) AS path,
    COALESCE(n.ptype, p.ptype) AS ptype,
        CASE
            WHEN p.path IS NULL THEN 'nouveau'::text
            WHEN n.path IS NULL THEN 'disparu'::text
            ELSE 'present'::text
        END AS statut,
    n.cpi AS cpi_now,
    p.cpi AS cpi_ref,
    n.cpi - p.cpi AS delta_cpi,
    n.grade AS grade_now,
    p.grade AS grade_ref,
    COALESCE(
      (n.grade = ANY (ARRAY['S'::text, 'A'::text, 'B'::text]))
      AND (p.grade = ANY (ARRAY['S'::text, 'A'::text, 'B'::text])),
      false
    ) AS fiable,
    round(n.zc - p.zc, 1) AS delta_zc,
    round(n.zr - p.zr, 1) AS delta_zr,
    round(n.zl - p.zl, 1) AS delta_zl,
    round(n.zv - p.zv, 1) AS delta_zv,
    round(n.momentum - p.momentum, 2) AS delta_momentum,
    n.momentum AS momentum_now,
    n.n_org AS n_org_now,
    n.clics_perdus AS clics_perdus_now
   FROM now_rows n
     FULL JOIN ref_rows p ON p.path = n.path
     CROSS JOIN bounds b
  ORDER BY (n.cpi - p.cpi);

COMMENT ON VIEW public.cpi_movers IS
  'Δ CPI ~7j. fiable = Fiabilité S/A/B aux deux dates (norme 23/07/2026).';

-- ── 4. Backfill historique approximatif (sans E) + snapshot du jour ─────────
-- Historique : ancien A avec n_org≥200 → S (proxy ; E non stocké dans cpi_daily).
UPDATE public.cpi_daily
SET grade = 'S'
WHERE grade = 'A'
  AND n_org >= 200;

-- Recalcule le snapshot du jour avec les vrais seuils (E inclus).
-- Via cron one-shot si le client SQL timeoute (Cloudflare 524) :
--   SELECT cron.schedule(... cooked_cpi_snapshot ...);
-- Sinon en direct :
-- SELECT public.cooked_cpi_snapshot();
