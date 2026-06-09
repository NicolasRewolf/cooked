-- Sprint 37 (09/06/2026) — nettoyage des vestiges hors-repo
-- Audit du 09/06/2026 : 3 objets en prod absents du repo, 0 dépendant utile.
--   • events_stitched (vue)        — tentative de stitching abandonnée
--   • session_canonical_id (vue)   — idem (seule events_stitched en dépendait)
--   • sessions_corrected_daily (fn)— orpheline
-- + fix linter : paris_date / paris_today sans search_path pinné (Sprint 36)

drop view if exists public.events_stitched;
drop view if exists public.session_canonical_id;
drop function if exists public.sessions_corrected_daily(date, date);

alter function public.paris_date(timestamptz) set search_path = public, pg_catalog;
alter function public.paris_today() set search_path = public, pg_catalog;
