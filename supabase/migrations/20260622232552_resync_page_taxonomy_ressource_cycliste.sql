-- 22/06/2026 — resync de la catégorie 'ressource' (réflexe CLAUDE.md : rejouer la
-- synchro API Wix quand des posts ressources manquent dans page_taxonomy).
-- Diff API Wix (catégorie "Ressources et notions juridiques", id 9477320f-...)
-- vs page_taxonomy : 55/56 déjà taggés 'ressource'. Seul manquant : cycliste-
-- renversé (faible trafic, passé sous le radar de la synchro du 11/06).
-- category d'après l'API Wix ; theme par heuristique slug (le slug contient
-- "indemnisation" → indemnisation victimes, comme piéton/loi-badinter/pretium).
INSERT INTO public.page_taxonomy (path, category, theme, source)
SELECT '/post/cycliste-renverse-preuves-indemnisation', 'ressource', 'indemnisation victimes', 'slug_heuristic'
WHERE NOT EXISTS (
  SELECT 1 FROM public.page_taxonomy WHERE path = '/post/cycliste-renverse-preuves-indemnisation'
);
