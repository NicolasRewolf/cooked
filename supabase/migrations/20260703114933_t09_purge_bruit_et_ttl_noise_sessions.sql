-- T-09 (03/07/2026) — purge du bruit ancien + TTL noise_sessions + cron hebdo
-- ============================================================================
-- GO explicite de Nicolas le 02/07/2026 (backup externe décliné le même jour —
-- la purge de bruit n'a jamais eu besoin d'archive : ces lignes sont exclues
-- de TOUTE analyse).
--
-- SÉMANTIQUE (à ne jamais oublier) : supprimer du bruit ne change AUCUN
-- résultat à AUCUNE fenêtre, y compris 365 j — events_human = events − bots −
-- noise, ces lignes n'y ont jamais figuré. Seuls le coût de stockage et la
-- durée des scans changent (à la baisse).
--
-- Rétention : 28 j de bruit BRUT conservés (audits du filtrage, dédup
-- double-embed, diagnostics récents) ; au-delà → suppression. Le swarm de
-- bots démarré ~20/06 (≈450 k lignes au 03/07) sera avalé progressivement
-- par le cron hebdo au fil de son vieillissement — comportement voulu.
-- noise_sessions : TTL 90 j sur detected_at (la table grossit de ~12 k/j
-- avec le swarm ; les rows dont les events sont purgés ne servent plus).
--
-- Trigger de ré-instruction du guard d'ingestion (décision du 02/07) :
-- si events bruts > 120 k/j soutenu 7 j, OU purge insuffisante pour tenir
-- events < ~2 Go, OU pollution d'events_human → voir docs/OPERATIONS.md
-- (section swarm, requête « ce qui serait rejeté »).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.purge_cooked_noise(retain_days int DEFAULT 28)
 RETURNS TABLE(events_purged bigint, noise_sessions_purged bigint)
 LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public' SET statement_timeout TO '540s'
AS $function$
DECLARE v_ev bigint; v_ns bigint;
BEGIN
  DELETE FROM public.events e
  WHERE e.occurred_at < now() - make_interval(days => retain_days)
    AND (EXISTS (SELECT 1 FROM public.noise_sessions ns WHERE ns.session_id = e.session_id)
      OR EXISTS (SELECT 1 FROM public.bot_fingerprints bf WHERE bf.anonymous_id = e.anonymous_id));
  GET DIAGNOSTICS v_ev = ROW_COUNT;

  DELETE FROM public.noise_sessions WHERE detected_at < now() - interval '90 days';
  GET DIAGNOSTICS v_ns = ROW_COUNT;

  RETURN QUERY SELECT v_ev, v_ns;
END $function$;
REVOKE ALL ON FUNCTION public.purge_cooked_noise(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_cooked_noise(int) TO service_role;

-- Cron hebdomadaire (dimanche 04:30 UTC — hors fenêtres des snapshots) ;
-- SET dans la commande : seul filet effectif en contexte pg_cron.
SELECT cron.schedule('cooked-purge-noise-weekly', '30 4 * * 0',
  $$SET statement_timeout='540s'; SELECT * FROM public.purge_cooked_noise(28);$$);
