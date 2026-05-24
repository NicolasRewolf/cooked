import { PeriodDashboardChrome } from "@/components/period-dashboard-chrome";
import { PagesTable } from "@/components/pages-table";
import { pagesOverviewUnified, pagesPulse } from "@/lib/cooked";
import { loadPeriodContext } from "@/lib/period-context";
import { parsePeriod, periodLabel, periodSubtitle } from "@/lib/period";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Props = { searchParams: Promise<{ period?: string }> };

export default async function PagesList({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  const label = periodLabel(period);
  const { kpis, health } = await loadPeriodContext(period);

  const [pages, pulseRows] = await Promise.all([
    pagesOverviewUnified(period, 250),
    pagesPulse(period, 5.0),
  ]);

  const pulseByPath = Object.fromEntries(
    pulseRows.map((r) => [r.path, r])
  );

  return (
    <PeriodDashboardChrome kpis={kpis} health={health}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8">
          <h1 className="font-heading text-2xl font-medium tracking-tight">
            Pages — {label}
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {periodSubtitle(period)} Croisement Google Search Console ×
            comportement Cooked.
          </p>
        </header>

        <PagesTable
          rows={pages}
          pulseByPath={pulseByPath}
          period={period}
          periodLabel={label}
        />
      </main>
    </PeriodDashboardChrome>
  );
}
