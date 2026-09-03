-- T-06 (mission 02/09/2026, #107) — étape 2/3 : momentum du CPI sur une source complète (option (b)), potentiel sans
-- momentum ni gate, cpi_drop refuse une page dont les clics réels montent.
--
-- Constats : f-01 (P1) — depuis le correctif « momentum non brandé » du 25/07/2026, le momentum lit gsc_query_page_daily
-- non brandé, soit 16 % (grade B) à 28 % (grade S) des clics réels d'une page ; contrefactuel du 03/09 : 15 des 47 pages
-- fiables ont un momentum de direction inverse à leurs clics réels (1 A, 12 B, 2 S) ; l'alerte cpi_drop du 01/09 a sonné
-- sur une page en croissance. f-07 — le `potentiel` de cpi_opportunite_contact était multiplié par momentum × gate :
-- 7 des 16 opportunités déplacées de ≥ 3 rangs par un terme qui n'a rien à voir avec le potentiel de contact.
-- Décision Nicolas (03/09/2026 ~12:02) : option (b) — gsc_path_daily total moins les clics brandés révélés par qpd.
--
-- Changement :
--   1. cooked_page_index : CTE `mom` = momf (gsc_path_daily, c1/c0 sur p_days et les p_days précédents) − momb (clics
--      brandés révélés) ; terme position p1/p0 inchangé (requêtes révélées non brandées). Le `site` (s1/s0) suit :
--      le momentum reste relatif au site. Aucune autre composante ne change.
--   2. cpi_opportunite_contact : potentiel = cpi_compose(zc, zr, zl, 0, 1, 1, true) — identité hors conversion, hors
--      momentum, hors gate (alias cpi_gisement inchangé).
--   3. alert_rule_cpi_drop : exclut toute page dont les clics gsc_path_daily des 7 derniers jours livrés dépassent les
--      7 précédents.
--   4. Invariants I4/I10 : contract-tests `cpi_momentum_source_complete` et `potentiel_sans_momentum_gate`.
-- Restatement : photo « avant » = cpi_daily du 03/09 (après T-09) copié en phase t06_avant (étape 1/3) ; « après »
-- recalculé le même jour par cooked_cpi_snapshot() (étape 2bis/3) ; annotation (étape 3/3).
-- Corps générés depuis la prod (rpcs.sql, sha vérifié) par substitutions ciblées.

-- 1. cooked_page_index : momentum sur la source complète.
CREATE OR REPLACE FUNCTION public.cooked_page_index(p_days integer DEFAULT 28)
 RETURNS TABLE(path text, ptype text, grade text, cpi integer, cpi_raw integer, momentum numeric, momentum_badge text, gate numeric, zc numeric, zr numeric, zl numeric, zv numeric, clics_perdus integer, n_org bigint, couv_gsc_pct integer, convertit boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- T-05 (mission 02/09/2026, #106 — d-03/d-07/f-04) : UNE fenêtre pour tout le score. Côté GSC : p_days jours clos à
-- gsc_last_data_day() (avant : borne sur la date serveur, soit 24 jours de données réelles sur 28 nominaux, lag Google J-4).
-- Côté Cooked : les MÊMES jours Paris, bornés par cooked_paris_ts_start/_end_exclusive (avant : 28 × 24 h glissantes, borne
-- qui glissait avec l'heure du run — deux snapshots consécutifs étaient séparés de 18 à 34 h). Le score d'un jour donné
-- est désormais reproductible. T-09 (#110) : le terme zv (conversion_journeys) est lui aussi clos à gsc_last_data_day() —
-- plus aucune borne d'horloge dans le score ; url passée à classify_channel (gclid ⇒ paid, o-14).
WITH w AS (
  SELECT g.g_end,
         public.cooked_paris_ts_start(g.g_end - (p_days - 1)) AS t0,
         public.cooked_paris_ts_end_exclusive(g.g_end)        AS t1
  FROM (SELECT public.gsc_last_data_day() AS g_end) g
),
fit AS (
  SELECT regr_slope(ln(ctr), ln(pos)) AS pente, regr_intercept(ln(ctr), ln(pos)) AS icept
  FROM (SELECT round(position)::int pos, (sum(clicks)+1.0)/(sum(impressions)+20.0) ctr
        FROM public.gsc_query_page_daily WHERE day > (SELECT g_end FROM w) - 90 AND NOT public.gsc_is_branded(query)
        GROUP BY 1 HAVING round(position)::int BETWEEN 1 AND 20 AND sum(impressions) >= 200) b
),
capq AS (SELECT g.path, sum(g.impressions) i_qpd,
    sum(g.impressions * least(greatest(exp(f.icept + f.pente*ln(greatest(g.position,1.0))),0.0005),0.5)) e_qpd
  FROM public.gsc_query_page_daily g, fit f WHERE g.day > (SELECT g_end FROM w) - p_days AND NOT public.gsc_is_branded(g.query) GROUP BY g.path),
capb AS (SELECT path, sum(clicks) o_b, sum(impressions) i_b FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - p_days AND public.gsc_is_branded(query) GROUP BY path),
capp AS (SELECT path, sum(clicks) o_full, sum(impressions) i_full FROM public.gsc_path_daily WHERE day > (SELECT g_end FROM w) - p_days GROUP BY path),
cap AS (SELECT p.path, greatest(p.o_full - coalesce(b.o_b,0),0)::numeric AS o,
    CASE WHEN coalesce(q.i_qpd,0)>0 THEN q.e_qpd*(greatest(p.i_full-coalesce(b.i_b,0),0)::numeric/q.i_qpd) ELSE NULL END AS e,
    q.i_qpd, greatest(p.i_full-coalesce(b.i_b,0),0) AS i_nb
  FROM capp p LEFT JOIN capq q ON q.path=p.path LEFT JOIN capb b ON b.path=p.path),
firstpv AS (SELECT DISTINCT ON (session_id) session_id, eh.path,
    public.classify_channel(referrer_hostname, utm_source, utm_medium,'www.jplouton-avocat.fr', url) chan
  FROM public.events_human eh WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) ORDER BY session_id, occurred_at),
orge AS (SELECT session_id, firstpv.path FROM firstpv WHERE chan LIKE 'organic%'),
norg AS (SELECT orge.path, count(*) n_org FROM orge GROUP BY orge.path),
spv AS (SELECT session_id, count(*) pv FROM public.events_human WHERE name='pageview' AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) GROUP BY session_id),
pex AS (SELECT e.session_id, e.path,
    max((e.props->>'duration_seconds')::numeric) d,
    max(coalesce((e.props->>'max_scroll')::numeric,0)) s
  FROM public.events_human e
  WHERE e.name='page_exit' AND e.occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w)
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
jx AS (SELECT * FROM public.conversion_journeys(p_days, (SELECT g_end FROM w)) WHERE entry_channel LIKE 'organic%'),
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
-- T-06 (mission 02/09/2026, f-01, option (b) — décision Nicolas 03/09/2026) : les clics du momentum viennent de la source
-- COMPLÈTE gsc_path_daily, moins les clics brandés que Google révèle dans gsc_query_page_daily (≈ total non brandé).
-- Avant (25/07/2026) : gsc_query_page_daily non brandé seul = 16 à 28 % des clics réels d'une page ; 15 des 47 pages
-- fiables avaient un momentum de direction inverse à leurs clics. Le terme position (p1/p0) reste sur les requêtes
-- révélées non brandées : la position n'a de sens que requête par requête.
momf AS (SELECT path,
    coalesce(sum(clicks) FILTER (WHERE day > (SELECT g_end FROM w) - p_days),0) c1,
    coalesce(sum(clicks) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days),0) c0
  FROM public.gsc_path_daily
  WHERE day > (SELECT g_end FROM w) - 2*p_days
  GROUP BY path),
momb AS (SELECT path,
    coalesce(sum(clicks) FILTER (WHERE day > (SELECT g_end FROM w) - p_days),0) b1,
    coalesce(sum(clicks) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days),0) b0
  FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - 2*p_days AND public.gsc_is_branded(query)
  GROUP BY path),
momp AS (SELECT path,
    avg(position) FILTER (WHERE day > (SELECT g_end FROM w) - p_days) p1,
    avg(position) FILTER (WHERE day <= (SELECT g_end FROM w) - p_days) p0
  FROM public.gsc_query_page_daily
  WHERE day > (SELECT g_end FROM w) - 2*p_days AND NOT public.gsc_is_branded(query)
  GROUP BY path),
mom AS (SELECT f.path,
    greatest(f.c1 - coalesce(b.b1,0), 0) c1,
    greatest(f.c0 - coalesce(b.b0,0), 0) c0,
    p.p1, p.p0
  FROM momf f LEFT JOIN momb b ON b.path = f.path LEFT JOIN momp p ON p.path = f.path),
site AS (SELECT sum(c1) s1, sum(c0) s0 FROM mom),
lcp AS (SELECT eh.path, percentile_cont(0.75) WITHIN GROUP (ORDER BY (props->>'value')::numeric) lcp75
  FROM public.events_human eh WHERE name='web_vitals' AND props->>'metric'='LCP' AND device_type='mobile'
    AND occurred_at >= (SELECT t0 FROM w) AND occurred_at < (SELECT t1 FROM w) GROUP BY eh.path),
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
    END grade,
    coalesce(cv.val, 0) > 0 AS convertit
  FROM xs x LEFT JOIN medt mt ON mt.ptype=x.ptype LEFT JOIN madt dt ON dt.ptype=x.ptype
  CROSS JOIN medg mg CROSS JOIN madg dg LEFT JOIN mom m ON m.path=x.path CROSS JOIN site s LEFT JOIN lcp l ON l.path=x.path
  LEFT JOIN convv cv ON cv.path=x.path
)
SELECT scored.path, scored.ptype, scored.grade,
  least(100, round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int) cpi,
  round(public.cpi_compose(zc, zr, zl, zv, mm, gg))::int cpi_raw,
  mm momentum, (CASE WHEN mm>=1.15 THEN '↗' WHEN mm<=0.87 THEN '↘' ELSE '→' END) momentum_badge,
  gg gate, zc, zr, zl, zv, clics_perdus, n_org, couv couv_gsc_pct, convertit
FROM scored
$function$;

-- 2. cpi_opportunite_contact : potentiel hors momentum et hors gate (f-07). Colonnes et types inchangés.
CREATE OR REPLACE VIEW public.cpi_opportunite_contact AS
 SELECT path,
    ptype,
    grade,
    n_org,
    cpi,
    round(public.cpi_compose(zc, zr, zl, 0::numeric, 1::numeric, 1::numeric, true))::integer AS potentiel,
    coalesce(convertit, false) AS convertit,
    zc,
    zr,
    zl,
    zv,
    day
   FROM cpi_daily
  WHERE day = (( SELECT max(cpi_daily_1.day) AS max
           FROM cpi_daily cpi_daily_1));

COMMENT ON VIEW public.cpi_opportunite_contact IS
  'Opportunité de contact : dernier cpi_daily, potentiel = cpi_compose(zc, zr, zl, 0, 1, 1, true) — hors conversion, hors momentum, hors gate (T-06, 03/09/2026). Filtrer grade IN (S,A,B) AND NOT convertit, trier potentiel DESC.';

-- 3. alert_rule_cpi_drop : refuse une page dont les clics réels montent.
CREATE OR REPLACE FUNCTION public.alert_rule_cpi_drop()
 RETURNS TABLE(kind text, severity text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_n bigint; v_detail text;
BEGIN
  BEGIN
    SELECT count(*),
           string_agg(
             path || ' (' || cpi_ref || '→' || cpi_now
               || ', zvΔ' || round(coalesce(delta_zv, 0)::numeric, 1)
               || ' momΔ' || round(coalesce(delta_momentum, 0)::numeric, 2) || ')',
             ', ' ORDER BY rn
           ) FILTER (WHERE rn <= 3)
      INTO v_n, v_detail
    FROM (
      SELECT path, cpi_ref, cpi_now, delta_zv, delta_momentum,
             row_number() OVER (ORDER BY delta_cpi ASC) AS rn
      FROM public.cpi_movers
      WHERE statut = 'present'
        AND fiable
        AND delta_cpi <= -15
        AND coalesce(ecart_jours, 99) <= 8
        AND (coalesce(delta_momentum, 0) <= -0.10 OR coalesce(delta_zc, 0) <= -0.5)
        -- T-06 (mission 02/09/2026, f-01) : pas de « decay » sur une page dont les clics réels (gsc_path_daily)
        -- montent — 7 derniers jours livrés par Google contre les 7 précédents. Le 01/09 l'alerte avait sonné sur une
        -- page en croissance, le momentum ne voyant que la traîne révélée.
        AND NOT EXISTS (
          SELECT 1
          FROM (SELECT public.gsc_last_data_day() AS g_end) g,
               LATERAL (SELECT coalesce(sum(p.clicks) FILTER (WHERE p.day > g.g_end - 7), 0)  AS r1,
                               coalesce(sum(p.clicks) FILTER (WHERE p.day <= g.g_end - 7), 0) AS r0
                        FROM public.gsc_path_daily p
                        WHERE p.path = cpi_movers.path AND p.day > g.g_end - 14) c
          WHERE c.r1 > c.r0
        )
    ) m;
    IF v_n >= 1 THEN
      RETURN QUERY SELECT
        'cpi_drop'::text,
        'warn'::text,
        format(
          '%s page(s) fiable(s) en vrai decay sur ~7j (fenêtre ≤8j, volatilité conversion exclue) : %s%s — diagnostiquer via cpi_movers (delta_zc/zr/zl/zv)',
          v_n,
          v_detail,
          CASE WHEN v_n > 3 THEN format(' … et %s autre(s)', v_n - 3) ELSE '' END
        );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT
      'cpi_movers_failed'::text,
      'critical'::text,
      SQLERRM;
  END;
END;
$function$;

-- 4. Contract-tests I4/I10.
CREATE OR REPLACE FUNCTION public.run_rpc_contract_tests()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '900s'
AS $function$
DECLARE
  t record;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
      ('snapshot_pages_export',
       $q$select count(*) from public.snapshot_pages_export() where refreshed_at is not null$q$,
       1, NULL),

      ('site_context_export',
       $q$select count(*) from public.site_context_export() where global_sessions_28d > 0$q$,
       NULL, 1),

      ('cta_breakdown_for_path',
       $q$select count(*) from public.cta_breakdown_for_path('/', 28)
          where cta_type in ('phone', 'email', 'booking')
            and placement in ('header', 'footer', 'body', 'sticky')$q$,
       NULL, NULL),

      ('outbound_destinations_for_path',
       $q$select count(*) from public.outbound_destinations_for_path('/', 28)$q$,
       NULL, NULL),

      ('behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())$q$,
       NULL, NULL),

      ('engagement_density_for_path',
       $q$select count(*) from public.engagement_density_for_path('/', 28)$q$,
       NULL, NULL),

      ('tracker_first_seen_global',
       $q$select count(*) from (select public.tracker_first_seen_global() v) s where s.v is not null$q$,
       NULL, 1),

      ('refresh_pipeline_health',
       $q$select count(*) from public.refresh_pipeline_health()$q$,
       NULL, 1),

      -- Ajoute le 28/07/2026 : le module Lecture (CONTEXT.md § Lecture).
      -- Cout d'ajout d'un test au contrat : une ligne. C'etait tout l'objet
      -- de ce depliage. `source` doit rester 'page_exit' tant que la
      -- reconstruction engagement_tick n'est pas decidee et annotee.
      ('page_reads',
       $q$select count(*) from public.page_reads(7) where source = 'page_exit'$q$,
       1, NULL),

      -- T-03 (mission 02/09/2026, invariant I5) : contrat d'unités — *_rate ∈ [0,1], *_pct ∈ [0,100],
      -- et un même nom de colonne = une même unité. exact_rows = 0 : aucune ligne ne doit violer.
      ('units_behavior_pages_for_period',
       $q$select count(*) from public.behavior_pages_for_period(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),

      ('units_seo_pages_overview',
       $q$select count(*) from public.seo_pages_overview(now() - interval '7 days', now())
          where bounce_rate > 1 or bounce_rate_pct > 100 or abs(bounce_rate * 100 - bounce_rate_pct) > 0.02$q$,
       NULL, 0),

      ('units_cooked_bounce_rate_range',
       $q$select count(*) from (
            select cooked_bounce_rate from public.gsc_page_performance('/', 'rolling_28')
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u where cooked_bounce_rate > 100 or cooked_bounce_rate < 0$q$,
       NULL, 0),

      -- Un lot de ≥ 20 pages dont le max ≤ 1 = une fraction 0-1 publiée sous un nom en pourcentage.
      ('units_cooked_bounce_rate_unit',
       $q$select case when count(*) >= 20 and max(cooked_bounce_rate) <= 1 then 1 else 0 end from (
            select cooked_bounce_rate from public.pages_overview_unified('rolling_28', 50)
            union all
            select cooked_bounce_rate from public.pages_overview_unified('rolling_7', 50)
          ) u$q$,
       NULL, 0),

      -- T-04 (mission 02/09/2026, invariant I3) : part de pageviews de robot / referrer spam dans events_human
      -- < 1 % sur 7 j (1 si violation, 0 sinon ; garde ≥ 100 pageviews). Avant T-04 : 13,6 % (03/09/2026).
      ('spam_share_events_human',
       $q$select case when count(*) filter (where name = 'pageview') >= 100
                    and 100.0 * count(*) filter (where name = 'pageview'
                          and (lower(user_agent) = 'pc' or user_agent ilike '%sebot%'
                               or public.cooked_is_spam_referrer(referrer_hostname)))
                        / count(*) filter (where name = 'pageview') >= 1
                  then 1 else 0 end
          from public.events_human where occurred_at > now() - interval '7 days'$q$,
       NULL, 0),

      -- T-04 (invariant I3) : classify_channel renvoie 'spam' pour tout referrer spam (0 écart attendu).
      ('classify_channel_spam',
       $q$select count(*) from (values ('m.baidu.com'), ('baidu.com')) v(h)
          where public.classify_channel(v.h, null, null, 'www.jplouton-avocat.fr') <> 'spam'$q$,
       NULL, 0),

      -- T-05 (mission 02/09/2026, invariant I4) : « 28 j » GSC = 28 jours clos à gsc_last_data_day(). Écart attendu 0.
      ('gsc_pages_overview_28d_alignes',
       $q$select abs(coalesce((select sum(gsc_clicks_28d) from public.gsc_pages_overview(100000)), 0)
                 - coalesce((select sum(g.clicks) from public.gsc_path_daily g,
                               public.cooked_period_bounds('rolling_28', 'gsc') b
                             where g.day between b.n_start and b.n_end), 0))$q$,
       NULL, 0),

      -- T-05 (invariants I4/I10) : aucune borne d'horloge dans le CPI — ses fenêtres sont closes à gsc_last_data_day()
      -- et le score d'un jour est reproductible. 0 occurrence attendue de now()/current_date/… dans le corps.
      ('cpi_sans_horloge',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'now\(\)|current_date|current_timestamp|localtimestamp', 'gi')$q$,
       NULL, 0),

      -- T-09 (mission 02/09/2026, invariant I4) : « contacts macro 28 j » = UN chiffre. site_macro_counts sur les bornes
      -- live_j1 = Σ macro_contacts_by_path(28) = conversion_journeys(28) (téléphone + formulaires macro). Écart attendu 0.
      ('contacts_28j_une_fenetre',
       $q$with b as (select n_start, n_end from public.cooked_period_bounds('rolling_28', 'live_j1')),
               s as (select sm.macro_conversions as n from b, public.site_macro_counts(b.n_start, b.n_end) sm),
               m as (select coalesce(sum(contacts), 0) as n from public.macro_contacts_by_path(28)),
               j as (select count(*) as n from public.conversion_journeys(28))
          select abs((select n from s) - (select n from m)) + abs((select n from s) - (select n from j))$q$,
       NULL, 0),

      -- T-09 (I4) : le funnel SEO et conversion_journeys comptent les mêmes contacts organiques sur la même fenêtre (cross).
      ('funnel_meme_total_que_journeys',
       $q$with b as (select n_end from public.cooked_period_bounds('rolling_28', 'cross'))
          select abs(coalesce((select sum(contacts) from public.seo_to_contact_funnel(28)), 0)
                   - (select count(*) from b, public.conversion_journeys(28, b.n_end) j
                      where j.entry_channel like 'organic%' and j.entry_path is not null))$q$,
       NULL, 0),

      -- T-09 (o-14) : un identifiant de clic Ads dans l'URL d'atterrissage prime sur utm_source=gmb et sur le referrer.
      ('classify_channel_gclid_paid',
       $q$select count(*) from (values
            ('www.google.com', 'gmb', null, 'https://www.jplouton-avocat.fr/?utm_source=gmb&gclid=abc'),
            ('www.google.com', null, null, 'https://www.jplouton-avocat.fr/defense-penale?gbraid=xyz'),
            (null, null, null, 'https://www.jplouton-avocat.fr/?wbraid=k')) v(r, s, m, u)
          where public.classify_channel(v.r, v.s, v.m, 'www.jplouton-avocat.fr', v.u) is distinct from 'paid'$q$,
       NULL, 0),

      -- T-06 (mission 02/09/2026, invariants I4/I10) : le momentum du CPI lit la source COMPLÈTE des clics
      -- (gsc_path_daily) — la CTE `mom` doit s'appuyer sur momf ← gsc_path_daily. 1 occurrence attendue au minimum.
      ('cpi_momentum_source_complete',
       $q$select count(*) from regexp_matches(
            pg_get_functiondef('public.cooked_page_index(integer)'::regprocedure),
            'momf AS \(SELECT path,.*?FROM public\.gsc_path_daily', 'g')$q$,
       1, NULL),

      -- T-06 (f-07) : le `potentiel` de cpi_opportunite_contact est hors conversion ET hors momentum/gate
      -- (cpi_compose(zc, zr, zl, 0, 1, 1, true)). 0 ligne du dernier cpi_daily en désaccord attendue.
      ('potentiel_sans_momentum_gate',
       $q$select count(*) from public.cpi_opportunite_contact o
          where o.potentiel is distinct from round(public.cpi_compose(o.zc, o.zr, o.zl, 0, 1, 1, true))::int$q$,
       NULL, 0)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;

  -- Retention 90j
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;
