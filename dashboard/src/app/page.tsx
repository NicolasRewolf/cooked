import { Suspense } from "react";
import { parsePeriod } from "@/lib/periods";
import {
  getResourcesAssisted,
  getResourcesKpis,
  getResourcesOverview,
  getAnnotations,
  getResourcesCohorts,
  getAssistedQuarter,
} from "@/data/dashboard";
import { getResourcesTrend } from "@/data/trend";
import { buildResourcesView } from "@/data/view-models";
import { CohortChart } from "@/components/CohortChart";
import { ObjectiveLine } from "@/components/ObjectiveLine";
import { requireUser } from "@/lib/auth";
import { KpiHeader } from "@/components/KpiHeader";
import { FreshnessBanner } from "@/components/FreshnessBanner";
import { PeriodSelector } from "@/components/PeriodSelector";
import { ResourcesTable } from "@/components/ResourcesTable";
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
            Ressources &amp; notions juridiques
          </div>
          <h1 className="mt-2 text-[25px] font-semibold tracking-[-0.02em]">Articles Ressources</h1>
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
  const [kpis, rawRows, trendResult, assisted, annotations, cohorts, quarter] = await Promise.all([
    getResourcesKpis(period),
    getResourcesOverview(period),
    getResourcesTrend(period),
    getResourcesAssisted(period),
    getAnnotations(period),
    getResourcesCohorts(),
    // Résilience (incident 03/07 22:57 : 2 timeouts RPC → la home plantait) :
    // la ligne reste visible (« objectif indisponible ») au lieu de tout cacher.
    getAssistedQuarter().catch((e) => {
      console.error("dashboard_assisted_quarter KO — objectif indisponible:", e);
      return null;
    }),
  ]);
  const trend = trendResult.data;
  const { rows, items, markers } = buildResourcesView({
    kpis,
    rows: rawRows,
    trend,
    assisted,
    annotations,
  });

  return (
    <div className="space-y-[18px]">
      <ObjectiveLine q={quarter} />
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
          markers={markers}
        />
      ) : null}
      <section>
        <ResourcesTable rows={rows} />
      </section>
      <CohortChart cohorts={cohorts.cohorts} />
    </div>
  );
}

function Loading() {
  return (
    <div className="space-y-[18px]">
      <div className="h-9 w-72 skeleton" />
      <div className="grid grid-cols-2 gap-px border border-line bg-line sm:grid-cols-3 lg:grid-cols-5">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="h-28 skeleton" />
        ))}
      </div>
      <div className="h-44 skeleton border border-line" />
      <div className="h-80 skeleton border border-line" />
    </div>
  );
}
