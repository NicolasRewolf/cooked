import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { PagesTable } from "@/components/pages-table";
import {
  pagesOverviewUnified,
  pagesPulse,
  pipelineHealth,
  siteKpisCompare,
} from "@/lib/cooked";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function PagesList() {
  const [pages, health, kpis, pulseRows] = await Promise.all([
    pagesOverviewUnified(1000),
    pipelineHealth(),
    siteKpisCompare(28),
    pagesPulse(28, 7, 5.0),
  ]);

  // Map server-side pour lookup O(1) côté Client Component
  const pulseByPath = Object.fromEntries(
    pulseRows.map((r) => [r.path, r])
  );

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
            Pages — 28 derniers jours
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Croisement Google Search Console × comportement Cooked. Filtre
            par catégorie et tri sur chaque colonne.
          </p>
        </header>

        <PagesTable rows={pages} pulseByPath={pulseByPath} />
      </main>
    </>
  );
}
