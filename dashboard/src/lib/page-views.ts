import "server-only";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { requireUser } from "@/lib/auth";

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

const count = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
export const pageViewsSchema = z.object({
  period_start: z.iso.date(),
  period_end: z.iso.date(),
  expected_days: z.union([z.literal(30), z.literal(60), z.literal(90)]),
  observed_days: count,
  inventory_checked_at: z.iso.datetime({ offset: true }).nullable(),
  pages: z.array(z.object({
    path: z.string().startsWith("/"),
    page_type: z.string(),
    category: z.string().nullable(),
    views: count,
  })),
}).refine((data) => data.observed_days <= data.expected_days, "Couverture invalide")
  .refine((data) => Date.parse(data.period_end) - Date.parse(data.period_start)
    === (data.expected_days - 1) * 86_400_000, "Période invalide");

export type PageViews = z.infer<typeof pageViewsSchema>;

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

export async function getPageViews(days: Period) {
  // L’accès métier suit toujours la validation serveur de la session et de l’allowlist.
  await requireUser();
  const secret = process.env.SUPABASE_SECRET_KEY;
  if (!secret) throw new Error("Lecture des vues non configurée");
  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let response;
  try {
    response = await supabase.rpc("page_view_counts", { p_days: days });
  } catch {
    throw new Error("Lecture des vues indisponible");
  }
  const { data, error } = response;
  if (error) throw new Error("Lecture des vues indisponible");
  const result = pageViewsSchema.safeParse(data);
  if (!result.success || result.data.expected_days !== days) {
    throw new Error("Réponse des vues invalide");
  }
  let inventoryStale = true;
  if (result.data.inventory_checked_at) {
    const parts = new Intl.DateTimeFormat("fr-FR", {
      timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(new Date(result.data.inventory_checked_at));
    const checkedDay = ["year", "month", "day"]
      .map((part) => parts.find((item) => item.type === part)!.value).join("-");
    // La borne SQL est hier à Paris : mêmes jours calendaires que le contrat de fraîcheur.
    const today = Date.parse(result.data.period_end) + 86_400_000;
    inventoryStale = (today - Date.parse(checkedDay)) / 86_400_000 > 2;
  }
  return { ...result.data, inventoryStale };
}
