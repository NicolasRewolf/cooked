-- 28/07/2026 — Google Business Profile : métriques quotidiennes de la fiche.
--
-- Pourquoi cette table existe
--   Le tracker ne verra JAMAIS un appel passé depuis la fiche Google : le
--   composeur s'ouvre sur le téléphone, pas sur le site. C'est l'angle mort
--   GMB (B3), assumé le 28/07/2026 après le refus du numéro traçable.
--   L'API Business Profile Performance donne CALL_CLICKS sans toucher à la
--   fiche et sans numéro de tracking. Approbation Google reçue le 28/07/2026.
--
-- Format long (une ligne par métrique) et non large : Google ajoute des
-- métriques au fil du temps (BUSINESS_BOOKINGS, BUSINESS_CONVERSATIONS…),
-- et une nouvelle métrique ne doit pas coûter une migration.
--
-- Pièges mesurés au premier probe (28/07/2026, fiche du cabinet) :
--   * Lag ~J-4. L'API REMBOURRE la fin de fenêtre avec des jours à zéro
--     tant que Google n'a pas consolidé — un zéro récent n'est PAS un vrai
--     zéro. Toute lecture doit s'arrêter au dernier jour non nul.
--   * WEBSITE_CLICKS sous-compte les arrivées réelles : 121 côté Google vs
--     194 sessions utm_source=gmb côté Cooked sur 28/06→25/07/2026, soit
--     ×1,60. Décomposition faite : 167/195 sessions viennent de google.*,
--     100 % atterrissent sur /, donc ce n'est pas Cooked qui sur-compte —
--     Google dédoublonne par utilisateur et par jour. Pour le trafic WEB,
--     events_human reste la source ; cette table sert l'APPEL, que Cooked
--     ne voit pas.
--   * CALL_CLICKS = taps sur le bouton, pas appels aboutis ni personnes
--     distinctes. Même nature que cta_phone_click. Ne pas le sommer avec
--     les contacts macro du site sans le dire.
--   * Ne PAS extrapoler CALL_CLICKS par le ratio ×1,60 mesuré sur les
--     clics site : rien ne prouve que le dédoublonnage s'y applique pareil.
--     162 clics d'appel / 28 j est un plancher, pas un point.

CREATE TABLE IF NOT EXISTS public.gbp_daily (
  day          date        NOT NULL,
  location     text        NOT NULL,
  metric       text        NOT NULL,
  value        integer     NOT NULL CHECK (value >= 0),
  ingested_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (day, location, metric)
);

CREATE INDEX IF NOT EXISTS gbp_daily_day_idx
  ON public.gbp_daily(day DESC);
CREATE INDEX IF NOT EXISTS gbp_daily_metric_day_idx
  ON public.gbp_daily(metric, day DESC);

ALTER TABLE public.gbp_daily ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.gbp_daily IS
  'Google Business Profile — métriques quotidiennes par fiche (format long). Ferme l''angle mort des appels passés depuis la fiche. Lag ~J-4 ; l''API rembourre la fin de fenêtre à zéro, ne jamais lire le dernier jour brut.';
COMMENT ON COLUMN public.gbp_daily.location IS
  'Identifiant API de la fiche, ex. locations/3503242316391395629 (Cabinet Plouton). Plusieurs fiches sont accessibles au compte : filtrer.';
COMMENT ON COLUMN public.gbp_daily.metric IS
  'DailyMetric de l''API : CALL_CLICKS, WEBSITE_CLICKS, BUSINESS_DIRECTION_REQUESTS, BUSINESS_IMPRESSIONS_{DESKTOP,MOBILE}_{MAPS,SEARCH}, BUSINESS_CONVERSATIONS, BUSINESS_BOOKINGS.';
COMMENT ON COLUMN public.gbp_daily.value IS
  'Compteur du jour. Les impressions sont dédoublonnées par utilisateur/jour côté Google ; CALL_CLICKS ne l''est pas explicitement.';
