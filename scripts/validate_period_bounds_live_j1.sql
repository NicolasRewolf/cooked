-- Arch #1 — validation : live_j1 ≡ cooked_period_bounds(live) + v_shift T-16
-- Attendu : 0 lignes dans mismatch (toutes colonnes égales).

WITH kinds AS (
  SELECT unnest(ARRAY['rolling_28', 'rolling_90']) AS period_kind
),
legacy AS (
  SELECT
    k.period_kind,
    b.n_start - GREATEST(b.n_end - (b.paris_today - 1), 0) AS n_start,
    b.n_end   - GREATEST(b.n_end - (b.paris_today - 1), 0) AS n_end,
    b.prev_start - GREATEST(b.n_end - (b.paris_today - 1), 0) AS prev_start,
    b.prev_end   - GREATEST(b.n_end - (b.paris_today - 1), 0) AS prev_end
  FROM kinds k
  CROSS JOIN LATERAL public.cooked_period_bounds(k.period_kind, 'live') b
),
modern AS (
  SELECT
    k.period_kind,
    b.n_start,
    b.n_end,
    b.prev_start,
    b.prev_end
  FROM kinds k
  CROSS JOIN LATERAL public.cooked_period_bounds(k.period_kind, 'live_j1') b
)
SELECT
  COALESCE(l.period_kind, m.period_kind) AS period_kind,
  l.n_start AS legacy_n_start,
  m.n_start AS live_j1_n_start,
  l.n_end AS legacy_n_end,
  m.n_end AS live_j1_n_end,
  l.prev_start AS legacy_prev_start,
  m.prev_start AS live_j1_prev_start,
  l.prev_end AS legacy_prev_end,
  m.prev_end AS live_j1_prev_end
FROM legacy l
FULL OUTER JOIN modern m USING (period_kind)
WHERE l.n_start IS DISTINCT FROM m.n_start
   OR l.n_end   IS DISTINCT FROM m.n_end
   OR l.prev_start IS DISTINCT FROM m.prev_start
   OR l.prev_end   IS DISTINCT FROM m.prev_end;
