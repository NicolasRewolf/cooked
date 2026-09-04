-- Décision Nicolas 04/09/2026 : 1 ligne par (email, minute).
-- Gardés : 17/04 14:31:20 (crm id 232) et 25/08 16:31:05 (crm id 839, avec aid + path).
-- Retirés : le 2e envoi 21 s / 52 s plus tard (sans aid, sans page).

DO $$
DECLARE
  n_crm int;
  n_ev int;
BEGIN
  SELECT count(*) INTO n_crm FROM crm_prospects
   WHERE wix_submission_id IN (
     'wiximport-09eda23c05177ec053db',
     '787bf192-79fd-4157-9d06-75847488b401'
   );
  IF n_crm <> 2 THEN
    RAISE EXCEPTION 'crm_prospects: attendu 2 lignes à supprimer, trouvé %', n_crm;
  END IF;

  SELECT count(*) INTO n_ev FROM events
   WHERE name = 'form_submit'
     AND props->>'submission_id' = '787bf192-79fd-4157-9d06-75847488b401';
  IF n_ev <> 1 THEN
    RAISE EXCEPTION 'events form_submit: attendu 1 ligne à supprimer, trouvé %', n_ev;
  END IF;
END $$;

DELETE FROM crm_prospects
WHERE wix_submission_id IN (
  'wiximport-09eda23c05177ec053db',
  '787bf192-79fd-4157-9d06-75847488b401'
);

DELETE FROM events
WHERE name = 'form_submit'
  AND props->>'submission_id' = '787bf192-79fd-4157-9d06-75847488b401';

INSERT INTO annotations (day, kind, label, paths)
VALUES (
  DATE '2026-08-25',
  'autre',
  'Dédup formulaire (décision Nicolas 04/09/2026) : 2e envoi 52 s après, sans page — retiré. Le contact du 25/08 16:31 avec page /honoraires-rendez-vous est conservé. Un « avant/après 04/09 » de −1 contact 28 j n''est pas une baisse de demande.',
  ARRAY['/honoraires-rendez-vous']
);
