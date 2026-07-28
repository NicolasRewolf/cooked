-- Miroir exact de la migration appliquee en prod (MCP) le 28/07/2026.
-- Snapshots des briques d'analyse mathematique.
-- Raison d'etre : math_visit_sequences(28) coute ~65 s (events_human ~12 s
-- par scan) alors que PostgREST plafonne a 8 s (statement_timeout du role
-- authenticator). Une RPC lourde n'est donc pas appelable depuis un script.
-- Meme pattern que cpi_daily : on materialise, le client lit la table.
CREATE TABLE IF NOT EXISTS public.math_visit_sequences_snapshot (
  computed_at   timestamptz NOT NULL DEFAULT now(),
  window_days   integer     NOT NULL,
  journey       text[]      NOT NULL,
  converted     boolean     NOT NULL,
  entry_channel text,
  n             bigint      NOT NULL
);

CREATE INDEX IF NOT EXISTS math_visit_sequences_snapshot_win_idx
  ON public.math_visit_sequences_snapshot (window_days, computed_at DESC);

CREATE TABLE IF NOT EXISTS public.math_internal_edges_snapshot (
  computed_at  timestamptz NOT NULL DEFAULT now(),
  window_days  integer     NOT NULL,
  src          text        NOT NULL,
  dst          text        NOT NULL,
  kind         text        NOT NULL,
  placement    text,
  weight       bigint      NOT NULL,
  dst_resolved boolean     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS math_internal_edges_snapshot_win_idx
  ON public.math_internal_edges_snapshot (window_days, computed_at DESC);

ALTER TABLE public.math_visit_sequences_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.math_internal_edges_snapshot  ENABLE ROW LEVEL SECURITY;

-- Rafraichissement d'une fenetre : remplace la photo precedente.
CREATE OR REPLACE FUNCTION public.math_refresh_snapshots(p_window_days integer DEFAULT 28)
RETURNS TABLE(sequences bigint, edges bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_seq bigint;
  v_edg bigint;
BEGIN
  DELETE FROM public.math_visit_sequences_snapshot WHERE window_days = p_window_days;
  INSERT INTO public.math_visit_sequences_snapshot
    (window_days, journey, converted, entry_channel, n)
  SELECT p_window_days, s.journey, s.converted, s.entry_channel, s.n
  FROM public.math_visit_sequences(p_window_days) s;
  GET DIAGNOSTICS v_seq = ROW_COUNT;

  DELETE FROM public.math_internal_edges_snapshot WHERE window_days = p_window_days;
  INSERT INTO public.math_internal_edges_snapshot
    (window_days, src, dst, kind, placement, weight, dst_resolved)
  SELECT p_window_days, e.src, e.dst, e.kind, e.placement, e.weight, e.dst_resolved
  FROM public.math_internal_edges(p_window_days) e;
  GET DIAGNOSTICS v_edg = ROW_COUNT;

  RETURN QUERY SELECT v_seq, v_edg;
END;
$function$;

GRANT SELECT ON public.math_visit_sequences_snapshot TO service_role;
GRANT SELECT ON public.math_internal_edges_snapshot  TO service_role;
GRANT EXECUTE ON FUNCTION public.math_refresh_snapshots(integer) TO service_role;
