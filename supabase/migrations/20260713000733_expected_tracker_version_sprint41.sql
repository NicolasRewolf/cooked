-- Tracker sprint41 déployé en prod le 12/07/2026 ~22:20 (Wix Custom Code).
-- Sans ce bump, l'alerte tracker_drift comparerait la prod à sprint40.
UPDATE public.cooked_config
SET value = 'sprint41'
WHERE key = 'expected_tracker_version';
