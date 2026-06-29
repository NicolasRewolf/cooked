-- Resync page_taxonomy.category='ressource' sur l'API Wix Blog.
-- Catégorie "Ressources et notions juridiques" (id 9477320f-5902-40e9-ace3-b0e3b6b8b51f), 57 posts au 29/06/2026.
-- Vérifié via le MCP Wix (ListCategories + ListPosts filtrés sur la catégorie, site 0870235c-b92d-4a69-a2f4-25a976ae5f0c).
-- 2 écarts corrigés vs Wix :
--   + Passager (article du 23/06, jamais tagué ; aucune ligne en taxo)
--   - /post/accident-médical-oniam : slug court fantôme (0 impression GSC, absent de Wix ;
--     le vrai article ONIAM est /post/accident-médical-oniam-dans-quels-cas-pouvez-vous-être-indemnisé)

INSERT INTO page_taxonomy (path, theme, source, category)
SELECT '/post/indemnisation-passager-accident-route', 'indemnisation victimes', 'slug_heuristic', 'ressource'
WHERE NOT EXISTS (SELECT 1 FROM page_taxonomy WHERE path = '/post/indemnisation-passager-accident-route');

UPDATE page_taxonomy SET category = 'ressource'
WHERE path = '/post/indemnisation-passager-accident-route' AND category IS DISTINCT FROM 'ressource';

UPDATE page_taxonomy SET category = NULL
WHERE path = '/post/accident-médical-oniam';
