-- Clean : la vue events_human_clean (créée dans dashboard_v1_rpcs) n'est référencée par AUCUN
-- objet — les RPC/refresh excluent Baidu au niveau ligne (referrer_hostname), pas via cette vue.
-- On la retire pour éviter un objet mort à la sémantique divergente.
DROP VIEW IF EXISTS public.events_human_clean;
