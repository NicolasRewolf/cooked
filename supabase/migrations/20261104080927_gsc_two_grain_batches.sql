-- Future GSC batches contain page totals and queries per page only.
-- Existing completed manifests remain historical evidence; no rows are rewritten.
-- CREATE OR REPLACE retains the existing service-only execution grants.
CREATE OR REPLACE FUNCTION public.gsc_ingest_complete(p_run_id uuid, p_row_counts jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE v_latest public.gsc_ingest_batches%ROWTYPE; v_key text; v_total numeric := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(782026) THEN
    RAISE EXCEPTION 'GSC refresh is running; retry batch completion later' USING ERRCODE = '55P03';
  END IF;
  IF p_row_counts IS NULL OR jsonb_typeof(p_row_counts) <> 'object'
     OR (SELECT count(*) FROM jsonb_object_keys(p_row_counts)) <> 2 THEN
    RAISE EXCEPTION 'row counts must contain exactly the two GSC tables' USING ERRCODE = '22023';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['gsc_path_daily','gsc_query_page_daily'] LOOP
    IF NOT (p_row_counts ? v_key) OR jsonb_typeof(p_row_counts->v_key) <> 'number'
       OR (p_row_counts->>v_key) !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'invalid row count for %', v_key USING ERRCODE = '22023';
    END IF;
    v_total := v_total + (p_row_counts->>v_key)::numeric;
  END LOOP;
  IF v_total=0 THEN
    RAISE EXCEPTION 'cannot mark an entirely empty GSC batch complete' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_latest FROM public.gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
  IF NOT FOUND OR v_latest.run_id IS DISTINCT FROM p_run_id OR v_latest.status NOT IN ('running','completed') THEN
    RAISE EXCEPTION 'only the latest running GSC batch may complete' USING ERRCODE = '22023';
  END IF;
  IF v_latest.status='completed' THEN
    IF v_latest.row_counts=p_row_counts THEN RETURN; END IF;
    RAISE EXCEPTION 'completed GSC batch has different row counts' USING ERRCODE = '22023';
  END IF;
  UPDATE public.gsc_ingest_batches SET status='completed', completed_at=clock_timestamp(), row_counts=p_row_counts
    WHERE run_id=p_run_id;
END;
$function$;
