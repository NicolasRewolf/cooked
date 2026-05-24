import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { PartialDataBanner } from "@/components/partial-data-banner";
import type { PipelineHealth, SiteKpisCompare } from "@/lib/cooked";

type Props = {
  kpis: SiteKpisCompare;
  health: PipelineHealth;
  children: React.ReactNode;
};

/** Nav + bandeaux période partagés par les pages dashboard principales. */
export function PeriodDashboardChrome({ kpis, health, children }: Props) {
  return (
    <>
      <Nav />
      {kpis.is_partial_period && (
        <PartialDataBanner trackerFirstSeen={kpis.tracker_first_seen} />
      )}
      <DateBanner
        periodStart={kpis.period_n_start}
        periodEnd={kpis.period_n_end}
        periodLabel={kpis.period_label_fr}
        gscLastDay={health.gsc_last_day}
        gscDataAgeDays={health.gsc_data_age_days}
      />
      {children}
    </>
  );
}
