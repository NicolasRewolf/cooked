BEGIN;
SELECT public.refresh_dashboard_expertises_snapshots('rolling_28');
SELECT count(*) AS exp_rows, sum(unique_visitors) AS sum_uv
FROM public.dashboard_expertises_snapshot
WHERE window_kind = 'rolling_28';
ROLLBACK;
