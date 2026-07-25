-- Revue d'architecture 25/07/2026, tâche n°5 (cause racine R2, volet
-- ingestion) : compteur d'auditabilité des drops à l'ingestion.
--
-- L'Edge `track` v26 cesse d'écrire les events dont l'UA matche la taxonomie
-- ua_bot de refresh_noise_sessions (mesuré le 25/07/2026 : 90,2 % des
-- écritures sur 48 h, et 0 event bot-UA de plus de 90 minutes encore visible
-- dans events_human — le drop est donc iso-comportement pour toutes les
-- lectures). Ce compteur trace ce qui n'est plus écrit : sans lui, « moins
-- d'events » serait indistinguable d'une panne d'ingestion.

CREATE TABLE public.ingest_drops (
  day    date   NOT NULL,
  reason text   NOT NULL,
  n      bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (day, reason)
);
ALTER TABLE public.ingest_drops ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.ingest_drops IS
  'Compteur journalier (jour Paris) des events refusés par l''Edge track avant INSERT : bot_ua (taxonomie ua_bot de refresh_noise_sessions), missing_fields, disallowed_name.';

-- Incrément appelé par l'Edge (service_role). SECURITY DEFINER + ACL fermées :
-- personne d'autre n'a de raison d'écrire ce compteur.
CREATE OR REPLACE FUNCTION public.record_ingest_drop(p_reason text, p_n integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
  INSERT INTO public.ingest_drops (day, reason, n)
  VALUES (public.paris_today(), p_reason, greatest(p_n, 0))
  ON CONFLICT (day, reason) DO UPDATE SET n = ingest_drops.n + excluded.n;
$function$;

REVOKE ALL ON FUNCTION public.record_ingest_drop(text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_ingest_drop(text, integer) TO service_role;
