import { isResourcePath } from "./resource-slugs";

/**
 * Catégorisation des pages jplouton-avocat.fr.
 *
 * Source : règles CLAUDE.md du repo cooked (taxonomie 4 types).
 * On distingue maintenant 5 catégories pour le filtrage UI :
 *   - home       : la racine /
 *   - cabinet    : pages institutionnelles (notre-cabinet, mentions, hubs)
 *   - expertise  : sous-pages des hubs expertise
 *   - resource   : /post/* présents dans la page hub /comprendre-le-droit
 *                  (sous-ensemble maintenu dans lib/resource-slugs.ts)
 *   - article    : tout autre /post/* (posts classiques, affaires, etc.)
 */

export type PageCategory =
  | "home"
  | "cabinet"
  | "expertise"
  | "resource"
  | "article";

const CABINET_EXACT = new Set<string>([
  "/notre-cabinet",
  "/honoraires-rendez-vous",
  "/mentions-legales",
  // Hubs passerelle vers les expertises (peu d'intérêt analytics propre,
  // gardées sous "cabinet" pour ne pas polluer le filtre Expertise).
  "/defense-penale",
  "/indemnisation-des-victimes",
  "/droit-des-contrats-et-des-personnes",
  // Hubs articles maintenus par Nicolas.
  "/comprendre-le-droit", // ressources
  "/nos-affaires",        // articles classiques
  // Wix blog legacy (peu utilisé depuis /nos-affaires).
  "/blog",
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
  if (path.startsWith("/post/")) {
    return isResourcePath(path) ? "resource" : "article";
  }
  // Fallback : on traite comme cabinet par défaut (page institutionnelle inconnue)
  return "cabinet";
}

export const CATEGORY_LABEL: Record<PageCategory, string> = {
  home: "Accueil",
  cabinet: "Cabinet",
  expertise: "Expertise",
  resource: "Ressource",
  article: "Article",
};

/**
 * Buckets pour les filtres du tableau (4 + tout).
 * "home" est rangé sous "cabinet" pour le filtrage (pas la peine d'avoir
 * un onglet juste pour la racine).
 */
export type FilterBucket = "all" | "cabinet" | "expertise" | "article" | "resource";

export function matchesBucket(path: string, bucket: FilterBucket): boolean {
  if (bucket === "all") return true;
  const cat = categorize(path);
  if (bucket === "cabinet") return cat === "cabinet" || cat === "home";
  return cat === bucket;
}

export const BUCKET_LABEL: Record<FilterBucket, string> = {
  all: "Tout",
  cabinet: "Cabinet",
  expertise: "Expertise",
  article: "Articles",
  resource: "Ressources",
};
