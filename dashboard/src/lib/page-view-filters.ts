import type { PageViews } from "./page-views";

export const periods = [30, 60, 90] as const;
export type Period = (typeof periods)[number];
export const pageTypes = [
  { value: "all", label: "Toutes les pages" },
  { value: "expertises", label: "Expertises" },
  { value: "articles", label: "Articles" },
  { value: "resources", label: "Ressources et notions juridiques" },
] as const;
export type PageTypeFilter = (typeof pageTypes)[number]["value"];

type SearchParams = Record<string, string | string[] | undefined>;

export function parseFilters(params: SearchParams): { days: Period; type: PageTypeFilter } {
  const days = params.days === "30" ? 30 : params.days === "60" ? 60 : 90;
  const type = pageTypes.find((item) => item.value === params.type)?.value ?? "all";
  return { days, type };
}

export function filterPages(pages: PageViews["pages"], type: PageTypeFilter) {
  return pages.filter((page) => {
    if (type === "expertises") return page.page_type === "expertise" || page.page_type === "hub";
    if (type === "articles") return page.page_type === "post" && page.category !== "ressource";
    if (type === "resources") return page.page_type === "post" && page.category === "ressource";
    return true;
  }).sort((a, b) => b.views - a.views || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

export function pageUrl(path: string): string {
  const url = new URL("https://www.jplouton-avocat.fr");
  url.pathname = path;
  return url.href;
}

