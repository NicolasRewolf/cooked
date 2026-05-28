-- Sprint 33+ (25/05/2026) — Index fonctionnel Paris-date sur events
--
-- Contexte : la règle absolue CLAUDE.md impose
--   WHERE (occurred_at AT TIME ZONE 'Europe/Paris')::date >= X
-- pour éviter le bug "fenêtre glissante UTC = perte de 2h chaque matin".
--
-- Problème : le planner Postgres ne peut PAS utiliser idx_events_occurred
-- (btree sur occurred_at) pour ce prédicat — la fonction AT TIME ZONE
-- + cast ::date masque la colonne. Résultat : seq scan ou bitmap
-- imprécis sur events (220k lignes au 25/05/2026, croissance ~10k/sem).
--
-- Solution : index fonctionnel sur l'expression exacte utilisée par
-- les RPCs. Le planner peut alors faire un index range scan direct.
--
-- IMMUTABLE requis : 'Europe/Paris' est un littéral, l'expression est
-- effectivement immuable (la conversion ne dépend que de occurred_at).
-- Postgres accepte AT TIME ZONE comme IMMUTABLE quand le tz est un literal.
--
-- Bénéficiaires (RPCs filtrant sur Paris-date via events_human / events) :
--   - macro_contacts_by_path (3 RPCs en dépendent)
--   - site_seo_funnel
--   - pogo_rates_for_period
--   - engagement_density_for_path
--   - cta_breakdown_for_path
--   - outbound_destinations_for_path
--   - behavior_pages_for_period
--   - refresh_seo_url_snapshot (4 fenêtres glissantes)

CREATE INDEX IF NOT EXISTS idx_events_paris_date
  ON public.events
  ((((occurred_at AT TIME ZONE 'Europe/Paris'))::date) DESC);

COMMENT ON INDEX public.idx_events_paris_date IS
  'Index fonctionnel Paris-date sur events (table brute). Les RPCs lisent events_human ; le planner peut pousser le prédicat sous la vue.';
