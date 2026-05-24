-- Backfill ponctuel — objet_de_ma_demande pour les form_submit du 24/05/2026
-- Source : export Wix « Prise de contact site-web.csv »
-- À lancer UNE FOIS après APPLIQUER_exclure_candidatures.sql

UPDATE public.events e
SET props = coalesce(e.props, '{}'::jsonb) || jsonb_build_object(
  'objet_de_ma_demande', v.objet,
  'counts_as_macro', v.counts_as_macro
)
FROM (VALUES
  ('2026-05-24 16:04:19.772+00'::timestamptz, 'Nous rejoindre (candidature)', false),
  ('2026-05-24 12:19:50.031+00', 'Droit de la famille', true),
  ('2026-05-24 11:10:51.539+00', 'Violences conjugales et féminicides', true),
  ('2026-05-24 07:40:05.234+00', 'Droit de la famille', true),
  ('2026-05-24 06:47:24.497+00', 'Droit des assurances particuliers et professionnels', true)
) AS v(ts, objet, counts_as_macro)
WHERE e.name = 'form_submit'
  AND e.occurred_at = v.ts;

-- Contrôle
SELECT
  props->>'objet_de_ma_demande' AS objet,
  props->>'counts_as_macro' AS compte_en_contact,
  to_char(occurred_at AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI') AS quand
FROM public.events_human
WHERE name = 'form_submit'
  AND (occurred_at AT TIME ZONE 'Europe/Paris')::date = '2026-05-24'
ORDER BY occurred_at;
