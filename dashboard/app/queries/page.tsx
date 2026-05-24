import { PeriodDashboardChrome } from "@/components/period-dashboard-chrome";
import { QueriesTable } from "@/components/queries-table";
import { SeoOpportunities } from "@/components/seo-opportunities";
import {
  gscTopQueriesGlobal,
  gscXDfsOpportunities,
} from "@/lib/cooked";
import { loadPeriodContext } from "@/lib/period-context";
import { parsePeriod, periodLabel, periodSubtitle } from "@/lib/period";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Props = { searchParams: Promise<{ period?: string }> };

export default async function QueriesList({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  const label = periodLabel(period);
  const { kpis, health } = await loadPeriodContext(period);

  const [queries, opportunities] = await Promise.all([
    gscTopQueriesGlobal(period, 500),
    gscXDfsOpportunities(period, 100, 5, 15, 10),
  ]);

  return (
    <PeriodDashboardChrome kpis={kpis} health={health}>
      <main className="mx-auto w-full max-w-6xl space-y-8 px-6 py-10">
        <header>
          <h1 className="font-heading text-2xl font-medium tracking-tight">
            Requêtes Google — {label}
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {periodSubtitle(period)} Top {queries.length} requêtes avec page
            cible et enrichissement DataForSEO (volumes France).
          </p>
        </header>

        <SeoOpportunities rows={opportunities} periodLabel={label} />

        <QueriesTable rows={queries} />
      </main>
    </PeriodDashboardChrome>
  );
}
