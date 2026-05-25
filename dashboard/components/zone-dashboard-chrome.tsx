import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { PartialDataBanner } from "@/components/partial-data-banner";
import type { DataLens } from "@/lib/data-lens";
import type { PipelineHealth } from "@/lib/cooked";

export type ZoneBannerProps = {
  periodStart: string | null;
  periodEnd: string | null;
  periodLabel?: string;
  lens: DataLens;
  health: PipelineHealth;
  isPartialPeriod?: boolean;
  trackerFirstSeen?: string | null;
};

type Props = ZoneBannerProps & {
  children: React.ReactNode;
};

export function ZoneDashboardChrome({
  periodStart,
  periodEnd,
  periodLabel,
  lens,
  health,
  isPartialPeriod,
  trackerFirstSeen,
  children,
}: Props) {
  return (
    <>
      <Nav />
      {lens === "live" && isPartialPeriod && trackerFirstSeen && (
        <PartialDataBanner trackerFirstSeen={trackerFirstSeen} />
      )}
      <DateBanner
        periodStart={periodStart}
        periodEnd={periodEnd}
        periodLabel={periodLabel}
        lens={lens}
        gscLastDay={health.gsc_last_day}
        gscDataAgeDays={health.gsc_data_age_days}
      />
      {children}
    </>
  );
}
