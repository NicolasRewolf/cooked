import { ZoneDashboardChrome } from "@/components/zone-dashboard-chrome";
import type { PipelineHealth, SiteKpisCompare } from "@/lib/cooked";

type Props = {
  kpis: SiteKpisCompare;
  health: PipelineHealth;
  children: React.ReactNode;
};

/** @deprecated Utiliser ZoneDashboardChrome */
export function PeriodDashboardChrome({ kpis, health, children }: Props) {
  return (
    <ZoneDashboardChrome
      lens="live"
      periodStart={kpis.period_n_start}
      periodEnd={kpis.period_n_end}
      periodLabel={kpis.period_label_fr}
      health={health}
      isPartialPeriod={kpis.is_partial_period}
      trackerFirstSeen={kpis.tracker_first_seen}
    >
      {children}
    </ZoneDashboardChrome>
  );
}
