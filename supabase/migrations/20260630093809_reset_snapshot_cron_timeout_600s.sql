-- Après le refacto temp-eh (20260630092247) : le rebuild passe de ~671 s à ~210 s. Le reliquat est
-- dominé par le PRÉAMBULE refresh_noise_sessions/bot_fingerprints (scan de tout events_no_bots, sans
-- borne temporelle), PAS par le snapshot lui-même.
-- Le doc tablait sur « quelques secondes » → 300 s ; la réalité mesurée est 210 s, donc on retient
-- un plafond SAIN de 600 s (≈3× la durée observée, marge pour la croissance) plutôt que 300 s
-- (trop juste, ~30 % de marge) — on a déjà payé un incident de timeout silencieux ici.
-- Remplace le stopgap 1500 s. Optimiser refresh_noise_sessions (le nouveau goulot) = suivi séparé.
ALTER FUNCTION public.refresh_seo_url_snapshot() SET statement_timeout = '600s';

SELECT cron.unschedule('refresh_seo_url_snapshot');
SELECT cron.schedule('refresh_seo_url_snapshot', '0 3 * * *',
  $$SET statement_timeout='600s'; SELECT public.refresh_seo_url_snapshot();$$);
