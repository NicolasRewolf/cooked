-- STOPGAP (pas le fix de fond) : refresh_seo_url_snapshot re-scanne events_human ~15× (vue avec
-- anti-joins sur 82k noise_sessions), sur des fenêtres jusqu'à 365 j → le rebuild dépasse 600s
-- (timeout observé dans pogo_rates_for_period). Durée réelle mesurée : 671s. On relève le plafond à
-- 1500s (2,2× de marge) pour que le cron nocturne repasse au vert en attendant le VRAI fix :
-- matérialiser events_human une fois en table temporaire (pattern dashboard) puis lancer les CTE
-- dessus. Suivi tracé (voir tâche de refacto).
ALTER FUNCTION public.refresh_seo_url_snapshot() SET statement_timeout = '1500s';

SELECT cron.unschedule('refresh_seo_url_snapshot');
SELECT cron.schedule('refresh_seo_url_snapshot', '0 3 * * *',
  $$SET statement_timeout='1500s'; SELECT public.refresh_seo_url_snapshot();$$);
