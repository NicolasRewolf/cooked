-- Dédoublonnage crm_prospects : l'import CSV du 23/08/2026 (rattrapage de la
-- panne webhook) a réinséré sous empreinte 'wiximport-…' 7 soumissions du
-- 10-11/08 déjà capturées par le webhook v13 avec leur vrai submissionId Wix.
-- On garde la row webhook (id Wix réel = lien avec events.props->>'submission_id')
-- et on supprime la copie import au même instant (±2 s). Idempotent.
DELETE FROM public.crm_prospects b
USING public.crm_prospects a
WHERE b.wix_submission_id LIKE 'wiximport-%'
  AND a.wix_submission_id NOT LIKE 'wiximport-%'
  AND abs(extract(epoch FROM (a.occurred_at - b.occurred_at))) < 2;
