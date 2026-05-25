import { Suspense } from "react";
import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { PartialDataBanner } from "@/components/partial-data-banner";
import { PeriodSelector } from "@/components/period-selector";
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
  /** Titre de la zone (niveau 1 : Activité / Google / Croisement). */
  zoneTitle: string;
  /** Sous-titre optionnel (ex. page Requêtes sous Google). */
  zoneSubtitle?: string;
  children: React.ReactNode;
};

/**
 * Enveloppe zone : Nav (source) → en-tête zone + période → bandeau dates → données.
 */
export function ZoneDashboardChrome({
  zoneTitle,
  zoneSubtitle,
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
      <header className="border-b border-border bg-surface-subtle/50">
        <div className="mx-auto max-w-6xl space-y-4 px-6 py-5">
          <div>
            <h1 className="font-heading text-xl font-medium tracking-tight text-foreground">
              {zoneTitle}
            </h1>
            {zoneSubtitle ? (
              <p className="mt-1 text-sm text-muted-foreground">
                {zoneSubtitle}
              </p>
            ) : null}
          </div>
          <Suspense fallback={null}>
            <PeriodSelector />
          </Suspense>
          <DateBanner
            periodStart={periodStart}
            periodEnd={periodEnd}
            periodLabel={periodLabel}
            lens={lens}
            gscLastDay={health.gsc_last_day}
            gscDataAgeDays={health.gsc_data_age_days}
            compact
          />
        </div>
      </header>
      {children}
    </>
  );
}
