-- Pont SECIB — colonnes UTM sur crm_prospects (10/08/2026).
-- L'export Wix historique (795 soumissions, 03/2025 → 08/2026) porte les UTM
-- de soumission : conservées pour la lecture « conversion par canal » des
-- prospects sans cooked_aid/sid (antérieurs aux champs cachés de juin 2026).
alter table crm_prospects
  add column utm_source text,
  add column utm_medium text,
  add column utm_term text;

comment on column crm_prospects.utm_source is
  'UTM au moment de la soumission (import Wix historique ou capture future) — lecture canal quand cooked_aid/sid absents.';
