-- T-04 (audit 02/07/2026) — fermer cpi_gisement au rôle anon.
-- cpi_gisement était une vue SANS security_invoker (donc exécutée avec les
-- droits du propriétaire, RLS des tables sous-jacentes contournée) ET grantée
-- à anon/authenticated → lisible via PostgREST avec la seule clé publishable
-- embarquée dans le front data.rewolf.studio. Advisor security = ERROR
-- (security_definer_view). On l'aligne sur cpi_movers (security_invoker=true,
-- service_role only). Le dashboard lit tout en clé service (server-side,
-- src/lib/supabase-admin.ts) → rien ne casse.
ALTER VIEW public.cpi_gisement SET (security_invoker = true);
REVOKE ALL ON public.cpi_gisement FROM anon, authenticated;

-- Grants résiduels de même nature sur un snapshot lu server-side uniquement.
REVOKE ALL ON public.dashboard_trend_snapshot FROM anon, authenticated;
GRANT SELECT ON public.dashboard_trend_snapshot TO service_role;
