-- Sprint 36+ (04/06/2026) — Couture (seam) Paris-date : paris_date() / paris_today()
--
-- CONTEXTE
-- --------
-- La règle absolue CLAUDE.md "fenêtre Paris partout" est aujourd'hui tenue
-- par RECOPIE MANUELLE de l'expression
--     (occurred_at AT TIME ZONE 'Europe/Paris')::date
-- à ~207 endroits dans 25 fichiers SQL (vérifié au grep le 04/06/2026).
-- C'est la règle la plus répétée du repo, et elle ne tient que par la
-- discipline : l'oublier une seule fois = bug silencieux "perte de 2h chaque
-- matin" (déjà arrivé le 18/05/2026 — les events 00:00–01:59 Paris rattachés
-- à la veille, une conversion disparue du compte du jour).
--
-- OBJECTIF
-- --------
-- Donner à cette règle UN SEUL foyer : deux fonctions que tous les call sites
-- finiront par traverser. La règle vit une fois, s'apprend une fois, et le
-- bug devient irreproductible.
--
--   paris_date(ts)  -> date calendaire Paris d'un instant      (IMMUTABLE)
--   paris_today()   -> date calendaire Paris de maintenant     (STABLE)
--
-- Cette migration est PUREMENT ADDITIVE : elle crée les fonctions, ne touche
-- aucune RPC ni aucune donnée, ne casse rien. La conversion des call sites se
-- fera ensuite RPC par RPC, validée à chaque étape (méthodo itérative #4).
--
-- ⚠️ CONTRAT D'INLINING — NE PAS CASSER (sinon l'index meurt)
-- ----------------------------------------------------------
-- Il existe un index fonctionnel idx_events_paris_date sur l'expression
--     ((occurred_at AT TIME ZONE 'Europe/Paris')::date) DESC
-- (cf. 20260525170000_events_paris_date_index.sql).
-- Pour que `WHERE paris_date(occurred_at) = ...` continue d'utiliser cet
-- index, le planner Postgres doit INLINER paris_date() — remplacer l'appel
-- par son corps avant de planifier. L'inlining d'une fonction SQL n'a lieu
-- QUE si elle est :
--     • LANGUAGE sql, corps mono-SELECT scalaire    -> ✓
--     • IMMUTABLE (ou STABLE)                        -> ✓
--     • PAS marquée STRICT      (STRICT bloque l'inlining)
--     • SANS clause SET, ex. SET search_path = ''    (SET bloque l'inlining)
-- => paris_date NE DOIT JAMAIS recevoir STRICT ni SET search_path, même si un
--    linter Supabase (0011_function_search_path_mutable) le suggère. Le corps
--    n'utilise que des built-ins (AT TIME ZONE, cast ::date), non détournables
--    par search_path : l'avertissement est ici inoffensif. La preuve EXPLAIN
--    (index range scan via paris_date) est faite juste après l'application.

CREATE OR REPLACE FUNCTION public.paris_date(ts timestamptz)
RETURNS date
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT (ts AT TIME ZONE 'Europe/Paris')::date;
$$;

COMMENT ON FUNCTION public.paris_date(timestamptz) IS
  'Date calendaire Europe/Paris d''un instant. Foyer unique de la règle "fenêtre Paris" (CLAUDE.md). IMMUTABLE, non-STRICT, sans SET search_path -> s''inline pour réutiliser idx_events_paris_date. Ne JAMAIS ajouter STRICT ni SET search_path (casserait l''usage de l''index).';

CREATE OR REPLACE FUNCTION public.paris_today()
RETURNS date
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT (now() AT TIME ZONE 'Europe/Paris')::date;
$$;

COMMENT ON FUNCTION public.paris_today() IS
  'Date calendaire Europe/Paris de maintenant (STABLE, dépend de now()). Remplace (now() AT TIME ZONE ''Europe/Paris'')::date dans les RPCs.';
