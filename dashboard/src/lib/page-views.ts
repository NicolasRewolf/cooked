import "server-only";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { requireUser } from "@/lib/auth";
import type { Period } from "./page-view-filters";

const count = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const period = z.union([z.literal(30), z.literal(60), z.literal(90)]);
const dayMs = 86_400_000;
const metrics = {
  views: count, entries: count, phone_visits: count, form_visits: count, contact_visits: count,
  contact_rate_pct: z.number().min(0).max(100).nullable(),
};
const metricSchema = z.object(metrics);
function coherentMetrics(data: z.infer<typeof metricSchema>) {
  return data.entries <= data.views && data.contact_visits <= data.entries
    && data.phone_visits <= data.contact_visits && data.form_visits <= data.contact_visits
    && data.contact_visits <= data.phone_visits + data.form_visits
    && (data.entries === 0 ? data.contact_rate_pct === null
      : data.contact_rate_pct !== null
        && Math.abs(data.contact_rate_pct - Math.round(10_000 * data.contact_visits / data.entries) / 100) < 1e-8);
}
const previousMetrics = metricSchema.refine(coherentMetrics, "Contacts incohérents");
const windowDays = (start: string, end: string) => (Date.parse(end) - Date.parse(start)) / dayMs + 1;

export const pageViewsSchema = z.object({
  period_start: z.iso.date(), period_end: z.iso.date(), expected_days: period, observed_days: count,
  inventory_checked_at: z.iso.datetime({ offset: true }).nullable(),
  unattributed_phone_events: count, unattributed_form_events: count,
  previous: z.object({
    period_start: z.iso.date(), period_end: z.iso.date(), observed_days: count,
    unattributed_phone_events: count, unattributed_form_events: count,
  }),
  pages: z.array(z.object({
    path: z.string().startsWith("/"), page_type: z.string(), category: z.string().nullable(),
    ...metrics, previous: previousMetrics,
  }).refine(coherentMetrics, "Contacts incohérents")),
}).refine((data) => new Set(data.pages.map((page) => page.path)).size === data.pages.length, "Pages dupliquées")
  .refine((data) => data.observed_days <= data.expected_days && data.previous.observed_days <= data.expected_days, "Couverture invalide")
  .refine((data) => windowDays(data.period_start, data.period_end) === data.expected_days
    && windowDays(data.previous.period_start, data.previous.period_end) === data.expected_days
    && Date.parse(data.period_start) - Date.parse(data.previous.period_end) === dayMs, "Périodes invalides");

export const pageQueryParamsSchema = z.object({
  path: z.string().min(1).max(2048).startsWith("/")
    .refine((path) => !path.startsWith("//") && !/[\\?#\u0000-\u001f\u007f]/u.test(path), "Chemin invalide"),
  days: z.enum(["30", "60", "90"]).transform((value) => Number(value) as Period),
}).strict();

export const pageQueriesSchema = z.object({
  path: z.string().startsWith("/"), period_start: z.iso.date().nullable(), period_end: z.iso.date().nullable(),
  expected_days: period, observed_days: count,
  previous: z.object({ period_start: z.iso.date().nullable(), period_end: z.iso.date().nullable(), observed_days: count }),
  queries: z.array(z.object({
    query: z.string(), clicks: count, previous_clicks: count,
    position_avg: z.number().nonnegative().nullable(), previous_position_avg: z.number().nonnegative().nullable(),
  })),
}).refine((data) => data.observed_days <= data.expected_days && data.previous.observed_days <= data.expected_days, "Couverture invalide")
  .refine((data) => {
    const dates = [data.period_start, data.period_end, data.previous.period_start, data.previous.period_end];
    if (dates.every((date) => date === null)) return data.observed_days === 0 && data.previous.observed_days === 0 && data.queries.length === 0;
    return dates.every((date) => date !== null)
      && windowDays(data.period_start!, data.period_end!) === data.expected_days
      && windowDays(data.previous.period_start!, data.previous.period_end!) === data.expected_days
      && Date.parse(data.period_start!) - Date.parse(data.previous.period_end!) === dayMs;
  }, "Périodes invalides");

export type PageViews = z.infer<typeof pageViewsSchema>;
export type PageQueries = z.infer<typeof pageQueriesSchema>;

function reportRpcFailure(rpc: "page_view_counts" | "page_query_counts", code?: unknown, status?: unknown) {
  console.error("cooked_rpc_failed", {
    rpc,
    sqlstate: typeof code === "string" && /^[0-9A-Z]{5}$/.test(code) ? code : null,
    status: typeof status === "number" && Number.isInteger(status)
      && (status === 0 || (status >= 100 && status <= 599)) ? status : null,
  });
}

async function readRpc(name: "page_view_counts" | "page_query_counts", params: { p_days: Period; p_path?: string }) {
  await requireUser();
  const secret = process.env.SUPABASE_SECRET_KEY;
  if (!secret) throw new Error("Lecture des données non configurée");
  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let response;
  try {
    response = await supabase.rpc(name, params);
  } catch {
    reportRpcFailure(name);
    throw new Error("Lecture des données indisponible");
  }
  if (response.error) {
    reportRpcFailure(name, response.error.code, response.status);
    throw new Error("Lecture des données indisponible");
  }
  return response.data;
}

export async function getPageViews(days: Period) {
  const result = pageViewsSchema.safeParse(await readRpc("page_view_counts", { p_days: days }));
  if (!result.success || result.data.expected_days !== days) throw new Error("Réponse des vues invalide");
  let inventoryStale = true;
  if (result.data.inventory_checked_at) {
    const parts = new Intl.DateTimeFormat("fr-FR", {
      timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(new Date(result.data.inventory_checked_at));
    const checkedDay = ["year", "month", "day"]
      .map((part) => parts.find((item) => item.type === part)!.value).join("-");
    const today = Date.parse(result.data.period_end) + dayMs;
    inventoryStale = (today - Date.parse(checkedDay)) / dayMs > 2;
  }
  return { ...result.data, inventoryStale };
}

export async function getPageQueries(path: string, days: Period) {
  const result = pageQueriesSchema.safeParse(await readRpc("page_query_counts", { p_path: path, p_days: days }));
  if (!result.success || result.data.expected_days !== days) throw new Error("Réponse Google invalide");
  return result.data;
}
