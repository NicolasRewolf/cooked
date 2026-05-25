import "server-only";

import {
  pipelineHealth,
  siteGscKpisCompare,
  siteKpisCompare,
  sitePulse,
  type PipelineHealth,
  type SiteGscKpisCompare,
  type SiteKpisCompare,
  type SitePulse,
} from "@/lib/cooked";
import type { DataLens } from "@/lib/data-lens";
import { periodLabel, type PeriodKind } from "@/lib/period";
import type { ZoneBannerProps } from "@/components/zone-dashboard-chrome";

export type CookedPeriodContext = {
  period: PeriodKind;
  kpis: SiteKpisCompare;
  health: PipelineHealth;
  banner: ZoneBannerProps;
};

export type GscPeriodContext = {
  period: PeriodKind;
  kpis: SiteGscKpisCompare;
  health: PipelineHealth;
  banner: ZoneBannerProps;
};

export type CrossPeriodContext = {
  period: PeriodKind;
  pulse: SitePulse;
  health: PipelineHealth;
  banner: ZoneBannerProps;
};

export async function loadCookedContext(
  period: PeriodKind
): Promise<CookedPeriodContext> {
  const [kpis, health] = await Promise.all([
    siteKpisCompare(period),
    pipelineHealth(),
  ]);
  return {
    period,
    kpis,
    health,
    banner: {
      lens: "live",
      periodStart: kpis.period_n_start,
      periodEnd: kpis.period_n_end,
      periodLabel: periodLabel(period, "live"),
      health,
      isPartialPeriod: kpis.is_partial_period,
      trackerFirstSeen: kpis.tracker_first_seen,
    },
  };
}

export async function loadGscContext(
  period: PeriodKind
): Promise<GscPeriodContext> {
  const [kpis, health] = await Promise.all([
    siteGscKpisCompare(period),
    pipelineHealth(),
  ]);
  return {
    period,
    kpis,
    health,
    banner: {
      lens: "gsc",
      periodStart: kpis.period_n_start,
      periodEnd: kpis.period_n_end,
      periodLabel: periodLabel(period, "gsc"),
      health,
    },
  };
}

export async function loadCrossContext(
  period: PeriodKind
): Promise<CrossPeriodContext> {
  const [pulse, health] = await Promise.all([
    sitePulse(period, 5.0),
    pipelineHealth(),
  ]);
  return {
    period,
    pulse,
    health,
    banner: {
      lens: "cross",
      periodStart: pulse.gsc_period_start,
      periodEnd: pulse.gsc_period_end,
      periodLabel: periodLabel(period, "cross"),
      health,
    },
  };
}

/** @deprecated Utiliser loadCookedContext / loadGscContext / loadCrossContext */
export async function loadPeriodContext(period: PeriodKind) {
  const ctx = await loadCookedContext(period);
  return { period: ctx.period, kpis: ctx.kpis, health: ctx.health };
}
