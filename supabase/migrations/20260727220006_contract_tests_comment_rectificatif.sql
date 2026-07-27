-- Rectificatif au commentaire pose par 20260727214327.
--
-- Ce commentaire affirmait que le "SET statement_timeout de la commande
-- pg_cron ne s'applique pas". C'est FAUX : au moment des echecs (05/07 ->
-- 27/07), le job jobid 2 n'avait tout simplement AUCUN SET. Celui qu'on lit
-- aujourd'hui dans cron.job a ete ajoute le 27/07/2026 a 22:34 Paris par la
-- migration 20260727203415 (commit 8401ef1), quelques minutes avant cette
-- session.
--
-- Ce qui reste vrai et verifie :
--   * le harnais dure 146,5 s, au-dessus des 120 s par defaut ;
--   * un SET porte par la DEFINITION de la fonction ne suffit pas, car
--     PostgreSQL arme le minuteur au debut du statement de plus haut niveau ;
--   * WHEN OTHERS ne rattrape pas query_canceled (57014).
--
-- Les deux correctifs sont complementaires : le SET du cron releve le plafond,
-- le WHEN OTHERS OR query_canceled garantit qu'un depassement futur soit
-- enregistre au lieu d'effacer le run.

COMMENT ON FUNCTION public.run_rpc_contract_tests() IS
  'Contract tests des 8 RPC socle. Duree mesuree 146,5 s le 27/07/2026 '
  '(site_context_export 60,5 s + behavior_pages_for_period 57,9 s + '
  'tracker_first_seen_global 18,7 s + 5 autres), contre 113 s au dernier run '
  'vert du 04/07 : ces RPC ralentissent avec le volume de events. Deux '
  'protections : SET statement_timeout=600s dans la commande cron (jobid 2), '
  'et WHEN OTHERS OR query_canceled sur les 8 handlers — sans quoi un seul '
  'RPC lent annule la transaction et n''ecrit rien dans rpc_health. Le SET '
  'porte par la fonction elle-meme ne protege PAS : le minuteur est arme au '
  'debut du statement de plus haut niveau. Si la duree approche 600 s, '
  'decouper en un job cron par RPC plutot que remonter encore le plafond.';
