import "server-only";

import { callRpcTrend, type TrendResult } from "@/data/call-rpc";
import type { Period } from "@/data/rpc-schemas";

export type { ResourcesTrend } from "@/data/rpc-schemas";
export type { TrendResult };

const TREND_RPC = {
  resources: "dashboard_resources_trend",
  expertises: "dashboard_expertises_trend",
} as const;

export async function getDashboardTrend(
  kind: keyof typeof TREND_RPC,
  period: Period,
): Promise<TrendResult> {
  return callRpcTrend(TREND_RPC[kind], period);
}

export function getResourcesTrend(period: Period): Promise<TrendResult> {
  return getDashboardTrend("resources", period);
}

export function getExpertisesTrend(period: Period): Promise<TrendResult> {
  return getDashboardTrend("expertises", period);
}
