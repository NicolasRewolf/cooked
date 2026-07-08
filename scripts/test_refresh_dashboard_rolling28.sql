BEGIN;
SELECT public.refresh_dashboard_snapshots('rolling_28');
SELECT count(*) AS res_rows, sum(unique_visitors) AS sum_uv
FROM public.dashboard_resources_snapshot
WHERE window_kind = 'rolling_28';
ROLLBACK;
