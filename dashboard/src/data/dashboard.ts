import "server-only";
import { admin } from "@/lib/supabase-admin";
import type { Period, ResourceRow, ResourceKpis, SeoQueryRow } from "@/lib/types";

class RpcError extends Error {
  constructor(rpc: string, cause: unknown) {
    super(`RPC ${rpc} a échoué: ${(cause as { message?: string })?.message ?? String(cause)}`);
    this.name = "RpcError";
  }
}

export async function getResourcesOverview(period: Period): Promise<ResourceRow[]> {
  const { data, error } = await admin.rpc("dashboard_resources_overview", {
    period_kind: period,
    max_rows: 100,
  });
  if (error) throw new RpcError("dashboard_resources_overview", error);
  return (data ?? []) as ResourceRow[];
}

export async function getResourcesKpis(period: Period): Promise<ResourceKpis | null> {
  const { data, error } = await admin.rpc("dashboard_resources_kpis", { period_kind: period });
  if (error) throw new RpcError("dashboard_resources_kpis", error);
  return ((data ?? [])[0] as ResourceKpis) ?? null;
}

export async function getSeoByQuery(
  period: Period,
  opts: { minVolume?: number; maxRows?: number } = {},
): Promise<SeoQueryRow[]> {
  const { data, error } = await admin.rpc("dashboard_seo_by_query", {
    period_kind: period,
    scope: "ressource",
    min_volume: opts.minVolume ?? 0,
    max_rows: opts.maxRows ?? 200,
  });
  if (error) throw new RpcError("dashboard_seo_by_query", error);
  return (data ?? []) as SeoQueryRow[];
}
