import { Suspense } from "react";
import { parsePeriod } from "@/lib/periods";
import { getExpertisesKpis, getExpertisesOverview, getHonorairesFunnel } from "@/data/dashboard";
import { getExpertisesTrend } from "@/data/trend";
import { buildExpertisesView } from "@/data/view-models";
import { requireUser } from "@/lib/auth";
import { KpiHeader } from "@/components/KpiHeader";
import { FreshnessBanner } from "@/components/FreshnessBanner";
import { PeriodSelector } from "@/components/PeriodSelector";
import { ExpertisesTable } from "@/components/ExpertisesTable";
import { HonorairesFunnelPanel } from "@/components/HonorairesFunnelPanel";
import { TrendChart } from "@/components/TrendChart";
import type { Period } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  await requireUser(); // défense en profondeur (au-delà du proxy)
  const period = parsePeriod((await searchParams).period);
  return (
    <main className="mx-auto max-w-[1240px] px-8 py-[30px] pb-16">
      <div className="mb-[18px] flex items-end justify-between gap-5">
        <div>
          <div className="font-mono text-[11px] uppercase tracking-[0.08em] text-faint">
            Pages expertise · fort trafic Adwords
          </div>
          <h1 className="mt-2 text-[25px] font-semibold tracking-[-0.02em]">Expertises</h1>
        </div>
        <PeriodSelector value={period} />
      </div>
      <Suspense key={period} fallback={<Loading />}>
        <Content period={period} />
      </Suspense>
    </main>
  );
}

async function Content({ period }: { period: Period }) {
  const [kpis, rows, trendResult, funnel] = await Promise.all([
    getExpertisesKpis(period),
    getExpertisesOverview(period),
    getExpertisesTrend(period),
    getHonorairesFunnel(period),
  ]);
  const trend = trendResult.data;
  const { items } = buildExpertisesView({ kpis, trend });

  return (
    <div className="space-y-[18px]">
      {kpis && (
        <FreshnessBanner
          cookedEnd={kpis.cooked_end}
          gscLastDay={kpis.gsc_last_day}
          lagDays={kpis.lag_days}
          refreshedAt={kpis.refreshed_at}
          noPrevBaseline={kpis.no_prev_baseline}
        />
      )}
      <KpiHeader items={items} />
      {funnel ? <HonorairesFunnelPanel funnel={funnel} /> : null}
      {trendResult.error ? (
        <div className="border border-warn/40 bg-warn/5 px-3 py-2 font-mono text-[11px] leading-snug text-muted">
          ⚠ Séries journalières indisponibles — le RPC des tendances a échoué (sparklines et graphe masqués).
        </div>
      ) : null}
      {trend?.visitors_daily?.length ? (
        <TrendChart
          series={trend.visitors_daily}
          label="Visiteurs uniques / jour"
          lastDay={kpis?.cooked_end}
        />
      ) : null}
      <section>
        <ExpertisesTable rows={rows} />
      </section>
    </div>
  );
}

function Loading() {
  return (
    <div className="space-y-[18px]">
      <div className="h-9 w-72 animate-pulse bg-line" />
      <div className="grid grid-cols-2 gap-px border border-line bg-line sm:grid-cols-3 lg:grid-cols-5">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="h-28 animate-pulse bg-panel" />
        ))}
      </div>
      <div className="h-44 animate-pulse border border-line bg-panel" />
      <div className="h-80 animate-pulse border border-line bg-panel" />
    </div>
  );
}
