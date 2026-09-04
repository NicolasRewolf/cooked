-- Tracker sprint42 collé dans Wix par Nicolas le 04/09/2026 (premiers events sprint42 à 10:12 Paris,
-- 4 sessions / 28 events / 4 CLS en 1 minute ; sprint41 encore présent sur les pages déjà ouvertes).
-- Bascule de la version attendue par l'alerte tracker_drift (T-17, mission 02/09/2026).
UPDATE public.cooked_config SET value = 'sprint42', updated_at = now()
WHERE key = 'expected_tracker_version';
