-- Post-index cleanup : stats planner (idempotent, safe si 301200 déjà passée sans ANALYZE)

ANALYZE public.gsc_path_daily;
ANALYZE public.gsc_query_daily;
ANALYZE public.gsc_query_page_daily;
