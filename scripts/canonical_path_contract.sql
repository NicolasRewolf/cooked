-- Contrat C3 — canonical_path SQL vs vecteur partagé (exécuter après migration C3)
BEGIN;

DO $$
DECLARE
  row record;
  got text;
BEGIN
  FOR row IN
    SELECT * FROM (VALUES
      ('root',                '/',                         '/'),
      ('empty',               '',                          '/'),
      ('trailing_slash',      '/post/foo/',                '/post/foo'),
      ('no_slash',            '/post/foo',                 '/post/foo'),
      ('percent_utf8_eacute', '/post/caf%C3%A9',           '/post/café'),
      ('percent_space',       '/post/hello%20world',       '/post/hello world'),
      ('already_decoded',     '/indemnisation-des-victimes', '/indemnisation-des-victimes'),
      ('invalid_percent',     '/post/foo%ZZbar',           '/post/foo%ZZbar'),
      ('nfc_compose',         '/post/cafe' || chr(769),    '/post/café'),
      ('home_trailing',       '/honoraires-rendez-vous/',  '/honoraires-rendez-vous')
    ) AS t(id, input, expected)
  LOOP
    got := public.canonical_path(row.input);
    IF got IS DISTINCT FROM row.expected THEN
      RAISE EXCEPTION 'canonical_path SQL fail [%]: input=% got=% want=%',
        row.id, row.input, got, row.expected;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS canonical_path SQL contract (% cases)', 10;
END $$;

ROLLBACK;
