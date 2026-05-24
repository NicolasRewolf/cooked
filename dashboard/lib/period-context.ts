import "server-only";

import {
  pipelineHealth,
  siteKpisCompare,
  type PipelineHealth,
  type SiteKpisCompare,
} from "@/lib/cooked";
import type { PeriodKind } from "@/lib/period";

export type PeriodContext = {
  period: PeriodKind;
  kpis: SiteKpisCompare;
  health: PipelineHealth;
};

/** KPIs + santé pipeline pour Nav/bandeaux — une seule requête parallèle. */
export async function loadPeriodContext(
  period: PeriodKind
): Promise<PeriodContext> {
  const [kpis, health] = await Promise.all([
    siteKpisCompare(period),
    pipelineHealth(),
  ]);
  return { period, kpis, health };
}
