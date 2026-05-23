/**
 * Liste des paths d'articles appartenant à la catégorie
 * "Ressources et notions juridiques" — sous-ensemble de /post/*.
 *
 * Source de vérité : la page hub /comprendre-le-droit (maintenue
 * manuellement par Nicolas). Cooked ne stocke pas cette info en base,
 * cf. CLAUDE.md du repo cooked.
 *
 * ⚠️ La catégorie Wix Blog /blog/categories/ressources-et-notions-juridiques
 * ne contient qu'un sous-ensemble (~20 articles). NE PAS l'utiliser.
 *
 * Maintenance :
 *   1. Aller sur https://www.jplouton-avocat.fr/comprendre-le-droit
 *   2. Récupérer la liste des paths (51 attendus au 22/05/2026).
 *   3. Mettre à jour ce Set ci-dessous.
 *   4. Commit + push.
 *
 * Format : chaque entrée doit commencer par "/post/" et matcher exactement
 * le path stocké dans events.path (donc post-canonical_path : decode +
 * NFC + sans slash final).
 */

export const RESOURCE_PATHS: ReadonlySet<string> = new Set([
  // TODO Nicolas : coller ici les 51 paths /post/* de /comprendre-le-droit.
  // Exemple :
  //   "/post/durée-de-la-garde-à-vue-24h-48h-96h-combien-de-temps-maximum",
  //   "/post/itt-pénale-définition-en-2025",
]);

export function isResourcePath(path: string): boolean {
  return RESOURCE_PATHS.has(path);
}
