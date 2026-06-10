-- Sprint 38 : CPI v2.1 (Cooked Page Index)
-- Score composite 0-100 par page : capture GSC (standardisation indirecte sur la
-- courbe CTR propre du site), rétention/lecture organiques (cascade orthogonale,
-- empirical Bayes), conversion (direct + assists dilués 1/L + 0.25*bookings),
-- momentum log-symétrique relatif au site, gate LCP.
-- v2.1 = 3 fixes calibration issus du run de validation du 10/06 :
--   1) Couverture GSC : O depuis gsc_path_daily (complet, branded soustrait),
--      E scalé par imps_path/imps_qpd (Google anonymise jusqu'à ~94% des requêtes)
--   2) Momentum fallback position : lambda 0.15 -> 0.08 (saturation petites pages)
--   3) Affichage : cpi borné à 100 + cpi_raw + badge momentum
-- Grades de confiance : A (n_org>=100 et E>=20) / B (>=30, >=5) / C (hypothèse).
-- Lecture : >75 champion, 50-75 sain, 35-50 à surveiller, <35 malade.

CREATE OR REPLACE FUNCTION public.cooked_page_index(p_days int DEFAULT 28)
RETURNS TABLE (
  path text, ptype text, grade text,
  cpi int, cpi_raw int, momentum numeric, momentum_badge text, gate numeric,
  zc numeric, zr numeric, zl numeric, zv numeric,
  clics_perdus int, n_org bigint, couv_gsc_pct int
)
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$
WITH fit AS (
  SELECT regr_slope(ln(ctr), ln(pos)) AS pente, regr_intercept(ln(ctr), ln(pos)) AS icept
  FROM (SELECT round(position)::int pos, (sum(clicks)+1.0)/(sum(impressions)+20.0) ctr
        FROM public.gsc_query_page_daily
        WHERE day > current_date - 90 AND query !~* 'plouton'
        GROUP BY 1 HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions) >= 200) b
),
capq AS (
  SELECT g.path, sum(g.impressions) i_qpd,
    sum(g.impressions * least(greatest(exp(f.icept + f.pente*ln(greatest(g.position,1.0))),0.0005),0.5)) e_qpd
  FROM public.gsc_query_page_daily g, fit f
  WHERE g.day > current_date - p_days AND g.query !~* 'plouton'
  GROUP BY g.path
),
capb AS (
  SELECT path, sum(clicks) o_b, sum(impressions) i_b
  FROM public.gsc_query_page_daily
  WHERE day > current_date - p_days AND query ~* 'plouton'
  GROUP BY path
),
capp AS (
  SELECT path, sum(clicks) o_full, sum(impressions) i_full
  FROM public.gsc_path_daily WHERE day > current_date - p_days GROUP BY path
),
cap AS (
  SELECT p.path,
    greatest(p.o_full - coalesce(b.o_b,0), 0)::numeric AS o,
    CASE WHEN coalesce(q.i_qpd,0) > 0
      THEN q.e_qpd * (greatest(p.i_full - coalesce(b.i_b,0),0)::numeric / q.i_qpd)
      ELSE NULL END AS e,
    q.i_qpd, greatest(p.i_full - coalesce(b.i_b,0),0) AS i_nb
  FROM capp p
  LEFT JOIN capq q ON q.path = p.path
  LEFT JOIN capb b ON b.path = p.path
),
firstpv AS (
  SELECT DISTINCT ON (session_id) session_id, eh.path,
    public.classify_channel(referrer_hostname, utm_source, utm_medium,'www.jplouton-avocat.fr') chan
  FROM public.events_human eh
  WHERE name='pageview' AND occurred_at > now() - make_interval(days => p_days)
  ORDER BY session_id, occurred_at
),
orge AS (SELECT session_id, firstpv.path FROM firstpv WHERE chan LIKE 'organic%'),
norg AS (SELECT orge.path, count(*) n_org FROM orge GROUP BY orge.path),
spv AS (SELECT session_id, count(*) pv FROM public.events_human
  WHERE name='pageview' AND occurred_at > now() - make_interval(days => p_days) GROUP BY session_id),
ex2 AS (
  SELECT o.path, public.cooked_page_type(o.path) ptype,
    (e.props->>'duration_seconds')::numeric d,
    coalesce((e.props->>'max_scroll')::numeric,0) s,
    ((e.props->>'duration_seconds')::numeric >= 15 OR coalesce(s2.pv,1) >= 2) retained
  FROM orge o
  JOIN public.events_human e ON e.session_id=o.session_id AND e.path=o.path AND e.name='page_exit'
  LEFT JOIN spv s2 ON s2.session_id=o.session_id
),
thr AS (
  SELECT ptype, percentile_cont(0.5) WITHIN GROUP (ORDER BY d) tau,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY s) sig
  FROM ex2 WHERE retained GROUP BY ptype
),
reads AS (
  SELECT e.path, max(e.ptype) ptype, count(*) n,
    count(*) FILTER (WHERE retained) r,
    count(*) FILTER (WHERE retained AND d >= t.tau AND s >= t.sig) k
  FROM ex2 e JOIN thr t ON t.ptype=e.ptype GROUP BY e.path
),
tmeans AS (SELECT ptype, coalesce(sum(r)::numeric/nullif(sum(n),0),0.5) rho,
  coalesce(sum(k)::numeric/nullif(sum(r),0),0.25) q FROM reads GROUP BY ptype),
jx AS (SELECT * FROM public.conversion_journeys(p_days) WHERE entry_channel LIKE 'organic%'),
direct AS (SELECT entry_path path, count(*)::numeric v FROM jx WHERE entry_path IS NOT NULL GROUP BY 1),
assist AS (SELECT jp.path, sum(1.0/greatest(j.pages_count,1)) v
  FROM jx j CROSS JOIN LATERAL unnest(j.journey) jp(path)
  WHERE jp.path <> j.entry_path GROUP BY jp.path),
book AS (SELECT o.path, 0.25*count(*)::numeric v
  FROM orge o JOIN public.events_human b ON b.session_id=o.session_id AND b.path=o.path AND b.name='cta_booking_click'
  GROUP BY o.path),
convv AS (
  SELECT n.path, n.n_org, coalesce(d.v,0)+coalesce(a.v,0)+coalesce(b.v,0) val
  FROM norg n LEFT JOIN direct d ON d.path=n.path
  LEFT JOIN assist a ON a.path=n.path LEFT JOIN book b ON b.path=n.path
),
tconv AS (SELECT public.cooked_page_type(convv.path) ptype,
  coalesce(sum(val)/nullif(sum(convv.n_org),0),0) nu FROM convv GROUP BY 1),
xs AS (
  SELECT r.path, r.ptype, c.n_org, c.val,
    coalesce(cap.o,0) o, cap.e, coalesce(cap.i_qpd,0) i_qpd, coalesce(cap.i_nb,0) i_nb,
    coalesce(ln((coalesce(cap.o,0)+3)/(cap.e+3)), 0) x_cap,
    ln( least(greatest((r.r+20*tm.rho)/(r.n+20),0.001),0.999)
      / (1-least(greatest((r.r+20*tm.rho)/(r.n+20),0.001),0.999)) ) x_ret,
    ln( least(greatest((r.k+20*tm.q)/(r.r+20),0.001),0.999)
      / (1-least(greatest((r.k+20*tm.q)/(r.r+20),0.001),0.999)) ) x_lec,
    ln( (c.val + 30*tc.nu + 0.05)/(c.n_org+30) ) x_conv
  FROM reads r
  JOIN convv c ON c.path=r.path
  LEFT JOIN cap ON cap.path=r.path
  JOIN tmeans tm ON tm.ptype=r.ptype
  JOIN tconv tc ON tc.ptype=r.ptype
  WHERE c.n_org >= 5 AND r.n >= 3
),
medt AS (
  SELECT ptype, count(*) cnt,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv
  FROM xs GROUP BY ptype
),
madt AS (
  SELECT x.ptype,
    greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-m.mc)),0.15) sc,
    greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-m.mr)),0.15) sr,
    greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-m.ml)),0.15) sl,
    greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-m.mv)),0.15) sv
  FROM xs x JOIN medt m ON m.ptype=x.ptype GROUP BY x.ptype
),
medg AS (
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x_cap) mc,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY x_ret) mr,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY x_lec) ml,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY x_conv) mv
  FROM xs
),
madg AS (
  SELECT greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_cap-g.mc)),0.15) sc,
    greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_ret-g.mr)),0.15) sr,
    greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_lec-g.ml)),0.15) sl,
    greatest(1.4826*percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(x.x_conv-g.mv)),0.15) sv
  FROM xs x, medg g
),
mom AS (
  SELECT gpd.path,
    coalesce(sum(clicks) FILTER (WHERE day > current_date - p_days),0) c1,
    coalesce(sum(clicks) FILTER (WHERE day BETWEEN current_date - 2*p_days AND current_date - p_days - 1),0) c0,
    avg(position) FILTER (WHERE day > current_date - p_days) p1,
    avg(position) FILTER (WHERE day BETWEEN current_date - 2*p_days AND current_date - p_days - 1) p0
  FROM public.gsc_path_daily gpd WHERE day > current_date - 2*p_days GROUP BY gpd.path
),
site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom),
lcp AS (
  SELECT eh.path, percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric) lcp75
  FROM public.events_human eh
  WHERE name='web_vitals' AND props->>'metric'='LCP' AND device_type='mobile'
    AND occurred_at > now() - make_interval(days => p_days)
  GROUP BY eh.path
),
scored AS (
  SELECT x.path, x.ptype, x.n_org,
    round(greatest(coalesce(x.e,0)-x.o,0))::int clics_perdus,
    CASE WHEN coalesce(x.i_nb,0) > 0 THEN round(100.0*x.i_qpd/x.i_nb)::int ELSE 0 END couv,
    round(least(greatest((x.x_cap - CASE WHEN mt.cnt>=15 THEN mt.mc ELSE mg.mc END)/(CASE WHEN mt.cnt>=15 THEN dt.sc ELSE dg.sc END),-3),3)::numeric,1) zc,
    round(least(greatest((x.x_ret - CASE WHEN mt.cnt>=15 THEN mt.mr ELSE mg.mr END)/(CASE WHEN mt.cnt>=15 THEN dt.sr ELSE dg.sr END),-3),3)::numeric,1) zr,
    round(least(greatest((x.x_lec - CASE WHEN mt.cnt>=15 THEN mt.ml ELSE mg.ml END)/(CASE WHEN mt.cnt>=15 THEN dt.sl ELSE dg.sl END),-3),3)::numeric,1) zl,
    round(least(greatest((x.x_conv - CASE WHEN mt.cnt>=15 THEN mt.mv ELSE mg.mv END)/(CASE WHEN mt.cnt>=15 THEN dt.sv ELSE dg.sv END),-3),3)::numeric,1) zv,
    round(exp(least(greatest(
      CASE WHEN m.c1+m.c0 < 20 THEN -0.08*coalesce(m.p1-m.p0,0)
        ELSE ln((m.c1+5.0)/(m.c0+5.0)) - ln((s.s1+50.0)/(s.s0+50.0)) END
      ,-0.336),0.336))::numeric,2) mm,
    round((1 - 0.15*least(greatest((coalesce(l.lcp75,2500)-2500)/2500.0,0),1))::numeric,2) gg,
    CASE WHEN x.n_org>=100 AND coalesce(x.e,0)>=20 THEN 'A'
         WHEN x.n_org>=30 AND coalesce(x.e,0)>=5 THEN 'B' ELSE 'C' END grade
  FROM xs x
  LEFT JOIN medt mt ON mt.ptype=x.ptype
  LEFT JOIN madt dt ON dt.ptype=x.ptype
  CROSS JOIN medg mg CROSS JOIN madg dg
  LEFT JOIN mom m ON m.path=x.path CROSS JOIN site s
  LEFT JOIN lcp l ON l.path=x.path
)
SELECT scored.path, scored.ptype, scored.grade,
  least(100, round(100 * (1/(1+exp(-(0.30*zc+0.15*zr+0.20*zl+0.35*zv)/0.8))) * mm * gg))::int cpi,
  round(100 * (1/(1+exp(-(0.30*zc+0.15*zr+0.20*zl+0.35*zv)/0.8))) * mm * gg)::int cpi_raw,
  mm momentum,
  CASE WHEN mm >= 1.15 THEN '↗' WHEN mm <= 0.87 THEN '↘' ELSE '→' END momentum_badge,
  gg gate, zc, zr, zl, zv, clics_perdus, n_org, couv couv_gsc_pct
FROM scored
$$;

REVOKE ALL ON FUNCTION public.cooked_page_index(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cooked_page_index(int) TO service_role;

-- Snapshot quotidien : la trajectoire du score lui-même
CREATE TABLE IF NOT EXISTS public.cpi_daily (
  day date NOT NULL,
  path text NOT NULL,
  ptype text, grade text,
  cpi int, cpi_raw int, momentum numeric, gate numeric,
  zc numeric, zr numeric, zl numeric, zv numeric,
  clics_perdus int, n_org bigint, couv_gsc_pct int,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (day, path)
);
ALTER TABLE public.cpi_daily ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.cooked_cpi_snapshot()
RETURNS void
LANGUAGE sql
SET search_path = public, pg_temp
AS $$
  INSERT INTO public.cpi_daily
    (day, path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct)
  SELECT (now() AT TIME ZONE 'Europe/Paris')::date,
    path, ptype, grade, cpi, cpi_raw, momentum, gate, zc, zr, zl, zv, clics_perdus, n_org, couv_gsc_pct
  FROM public.cooked_page_index(28)
  ON CONFLICT (day, path) DO UPDATE SET
    ptype=EXCLUDED.ptype, grade=EXCLUDED.grade, cpi=EXCLUDED.cpi, cpi_raw=EXCLUDED.cpi_raw,
    momentum=EXCLUDED.momentum, gate=EXCLUDED.gate,
    zc=EXCLUDED.zc, zr=EXCLUDED.zr, zl=EXCLUDED.zl, zv=EXCLUDED.zv,
    clics_perdus=EXCLUDED.clics_perdus, n_org=EXCLUDED.n_org, couv_gsc_pct=EXCLUDED.couv_gsc_pct;
$$;

REVOKE ALL ON FUNCTION public.cooked_cpi_snapshot() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cooked_cpi_snapshot() TO service_role;

-- Cron : tous les jours à 07:30 UTC (90 min après l'ingest GSC de 06:00 UTC)
SELECT cron.schedule('cooked-cpi-daily-snapshot', '30 7 * * *',
  $$SELECT public.cooked_cpi_snapshot()$$);
