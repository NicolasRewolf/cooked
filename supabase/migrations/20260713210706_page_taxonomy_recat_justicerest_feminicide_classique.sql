-- Nicolas a retiré ces 2 posts de la catégorie Wix « Ressources et notions
-- juridiques » le 13/07/2026 (comptes-rendus datés — journée d'étude, actu
-- d'une affaire — pas des notions evergreen). Cooked ne se re-synchronise pas
-- seul → reclassement en 'classique' pour refléter l'action Wix (source de
-- vérité). N'affecte PAS le CPI (category-blind) ; ne change que l'univers
-- 'ressource' consommé par le dashboard.
UPDATE public.page_taxonomy
SET category = 'classique'
WHERE path IN (
  '/post/au-cœur-de-la-justice-restaurative-retour-sur-une-journée-d-étude-à-bordeaux',
  '/post/feminicide-saint-raphael-edith-verite'
)
AND category = 'ressource';
