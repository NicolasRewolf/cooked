import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { QueriesTable } from "@/components/queries-table";
import {
  gscTopQueriesGlobal,
  pipelineHealth,
  siteKpisCompare,
} from "@/lib/cooked";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function QueriesList() {
  const [queries, health, kpis] = await Promise.all([
    gscTopQueriesGlobal(28, 500),
    pipelineHealth(),
    siteKpisCompare(28),
  ]);

  return (
    <>
      <Nav />
      <DateBanner
        periodStart={kpis.period_n_start}
        periodEnd={kpis.period_n_end}
        gscLastDay={health.gsc_last_day}
        gscDataAgeDays={health.gsc_data_age_days}
      />
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8">
          <h1 className="font-heading text-2xl font-medium tracking-tight">
            Requêtes Google — 28 derniers jours
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Top {queries.length} requêtes du site avec la page cible et le
            nombre de pages qui rankent dessus. Source : Google Search Console.
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Note : GSC anonymise ~54 % du volume impressions sur les
            requêtes rares ; les clics restent quasi-tous attribuables.
          </p>
        </header>

        <QueriesTable rows={queries} />
      </main>
    </>
  );
}
