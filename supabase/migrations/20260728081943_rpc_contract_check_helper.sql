-- Candidat 3 de la revue d'architecture — deplier run_rpc_contract_tests.
--
-- Les 8 tests etaient 8 blocs identiques de ~20 lignes : clock_timestamp,
-- begin, un count avec predicat, un insert si vert, un insert si rouge,
-- exception, end. Seuls le nom, la requete et le predicat changeaient.
--
-- L'incident du 04/07 -> 27/07 en est la consequence directe : le handler
-- `exception when others` — qui ne rattrape pas query_canceled — etait copie
-- HUIT fois. Le corriger a demande une transformation textuelle de la
-- definition vive, avec un garde-fou IF v_n <> 8 THEN RAISE pour se premunir
-- d'une copie oubliee. Un bug dans le motif etait un bug x8.
--
-- Le helper porte desormais la mesure de duree, la gestion d'erreur et
-- l'ecriture dans rpc_health. Le harnais devient une LISTE de donnees.
-- Ajouter un RPC au contrat coute une ligne — c'est ce qui devrait faire
-- remonter la couverture, aujourd'hui de 9 fonctions sur 115.
--
-- Changement assume : les messages d'echec sont desormais generes de facon
-- uniforme ('expected exactly 1 row, got 3') au lieu des libelles ad hoc de
-- chaque bloc. Le contrat de sortie de rpc_health est inchange.
--
-- Verifie en prod le 28/07/2026 a 10:23, run lance A LA MAIN donc sans le
-- SET du cron, c'est-a-dire sous le plafond par defaut de 120 s :
--   * 7 RPC a l'identique du run vert de 05:30 (memes statuts, memes
--     rows_returned) ;
--   * page_reads ajoute, ok, 3 119 lectures en 24,2 s ;
--   * behavior_pages_for_period tombe en 'failed / canceling statement due to
--     statement timeout' au cumul exact de 120,0 s — et les CINQ tests
--     suivants s'executent quand meme, total 167,3 s.
-- C'est la propriete de resilience demontree en conditions reelles : sous
-- l'ancien code, les 9 lignes auraient disparu sans trace.

CREATE OR REPLACE FUNCTION public.rpc_contract_check(p_name text, p_sql text, p_min_rows integer DEFAULT NULL::integer, p_exact_rows integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_start timestamptz := clock_timestamp();
  v_rows  bigint;
  v_ms    numeric;
BEGIN
  EXECUTE p_sql INTO v_rows;
  v_ms := extract(epoch from (clock_timestamp() - v_start)) * 1000;

  IF p_exact_rows IS NOT NULL AND v_rows <> p_exact_rows THEN
    INSERT INTO rpc_health (rpc_name, status, detail, rows_returned, duration_ms)
    VALUES (p_name, 'failed',
            format('expected exactly %s row(s), got %s', p_exact_rows, v_rows),
            v_rows, v_ms);
  ELSIF p_min_rows IS NOT NULL AND v_rows < p_min_rows THEN
    INSERT INTO rpc_health (rpc_name, status, detail, rows_returned, duration_ms)
    VALUES (p_name, 'failed',
            format('expected at least %s row(s), got %s', p_min_rows, v_rows),
            v_rows, v_ms);
  ELSE
    INSERT INTO rpc_health (rpc_name, status, rows_returned, duration_ms)
    VALUES (p_name, 'ok', v_rows, v_ms);
  END IF;

EXCEPTION WHEN OTHERS OR query_canceled THEN
  INSERT INTO rpc_health (rpc_name, status, detail, duration_ms)
  VALUES (p_name, 'failed', SQLERRM,
          extract(epoch from (clock_timestamp() - v_start)) * 1000);
END;
$function$;


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
      ('page_reads',
       $q$select count(*) from public.page_reads(7) where source = 'page_exit'$q$,
       1, NULL)
    ) AS v(nom, requete, min_rows, exact_rows)
  LOOP
    PERFORM public.rpc_contract_check(t.nom, t.requete, t.min_rows, t.exact_rows);
  END LOOP;

  -- Retention 90j
  DELETE FROM rpc_health WHERE checked_at < now() - interval '90 days';
END;
$function$;
