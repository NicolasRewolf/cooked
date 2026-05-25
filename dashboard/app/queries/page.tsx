import { ZoneDashboardChrome } from "@/components/zone-dashboard-chrome";
import { QueriesTable } from "@/components/queries-table";
import { SeoOpportunities } from "@/components/seo-opportunities";
import {
  gscTopQueriesGlobal,
  gscXDfsOpportunities,
} from "@/lib/cooked";
import { loadGscContext } from "@/lib/period-context";
import { parsePeriod, periodLabel } from "@/lib/period";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Props = { searchParams: Promise<{ period?: string }> };

export default async function QueriesList({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  const label = periodLabel(period, "gsc");
  const { health, banner } = await loadGscContext(period);

  const [queries, opportunities] = await Promise.all([
    gscTopQueriesGlobal(period, 500),
    gscXDfsOpportunities(period, 100, 5, 15, 10),
  ]);

  return (
    <ZoneDashboardChrome
      {...banner}
      zoneTitle="Google Search Console"
      zoneSubtitle={`Requêtes — ${label}. Top ${queries.length} requêtes avec page cible et volumes DataForSEO.`}
    >
      <main className="mx-auto w-full max-w-6xl space-y-8 px-6 py-8">
        <SeoOpportunities rows={opportunities} periodLabel={label} />

        <QueriesTable rows={queries} period={period} />
      </main>
    </ZoneDashboardChrome>
  );
}
