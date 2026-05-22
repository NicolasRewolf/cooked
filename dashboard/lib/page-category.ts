/**
 * Catégorisation des pages jplouton-avocat.fr.
 *
 * Source : règles CLAUDE.md du repo cooked (taxonomie 4 types).
 * Note : Cooked ne stocke pas la catégorie en base. Pour distinguer
 * "ressource" vs "post classique" à l'intérieur des /post/*, il
 * faudrait scraper /comprendre-le-droit ou enrichir avec un mapping.
 * Pour MVP on agrège tous les /post/* sous "article".
 */

export type PageCategory = "home" | "cabinet" | "expertise" | "article";

const CABINET_EXACT = new Set<string>([
  "/notre-cabinet",
  "/honoraires-rendez-vous",
  "/mentions-legales",
  "/defense-penale",
  "/indemnisation-des-victimes",
  "/droit-des-contrats-et-des-personnes",
  "/comprendre-le-droit",
]);

const EXPERTISE_PREFIXES = [
  "/defense-penale/",
  "/indemnisation-des-victimes/",
  "/droit-des-contrats-et-des-personnes/",
];

export function categorize(path: string): PageCategory {
  if (!path || path === "/") return "home";
  if (CABINET_EXACT.has(path)) return "cabinet";
  if (EXPERTISE_PREFIXES.some((p) => path.startsWith(p))) return "expertise";
  if (path.startsWith("/post/")) return "article";
  // Fallback : on traite comme cabinet par défaut (page institutionnelle inconnue)
  return "cabinet";
}

export const CATEGORY_LABEL: Record<PageCategory, string> = {
  home: "Accueil",
  cabinet: "Cabinet",
  expertise: "Expertise",
  article: "Article",
};
