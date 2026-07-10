-- Arch #3 — validation gsc_is_branded (vecteur contracts/branded_query_vectors.json)
-- Attendu : 0 lignes (tous les cas passent).

SELECT id, input, expected, public.gsc_is_branded(input) AS actual
FROM (
  VALUES
    ('navigational', 'plouton avocat bordeaux'::text, true),
    ('accent', 'Maître Plouton', true),
    ('slug_fragment', 'cabinet plouton avocat', true),
    ('generic_penal', 'avocat accident route bordeaux', false),
    ('generic_gav', 'durée garde à vue', false),
    ('empty', '', false),
    ('null', NULL::text, false)
) AS v(id, input, expected)
WHERE public.gsc_is_branded(input) IS DISTINCT FROM expected;
