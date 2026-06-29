import { Suspense } from "react";
import { parsePeriod } from "@/lib/periods";
import { getResourcesKpis, getSeoByQuery } from "@/data/dashboard";
import { KpiHeader, type KpiItem } from "@/components/KpiHeader";
import { FreshnessBanner } from "@/components/FreshnessBanner";
import { PeriodSelector } from "@/components/PeriodSelector";
import { SeoTable } from "@/components/SeoTable";
import { SectionTitle } from "@/components/ui";
import { num, delta } from "@/lib/format";
import type { Period } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function SeoPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  const period = parsePeriod((await searchParams).period);
  return (
    <main className="mx-auto max-w-6xl space-y-6 px-4 py-6">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">SEO — requêtes des articles ressources</h1>
        <PeriodSelector value={period} />
      </div>
      <Suspense key={period} fallback={<Loading />}>
        <Content period={period} />
      </Suspense>
    </main>
  );
}

async function Content({ period }: { period: Period }) {
  const [kpis, rows] = await Promise.all([getResourcesKpis(period), getSeoByQuery(period)]);
  const quickWins = rows.filter((r) => r.is_quick_win).length;

  const items: KpiItem[] = [
    {
      label: "Clics Google",
      value: num(kpis?.gsc_clicks_n ?? 0),
      delta: kpis ? delta(kpis.gsc_clicks_n, kpis.gsc_clicks_prev) : undefined,
    },
    {
      label: "Affichages Google",
      value: num(kpis?.gsc_impressions_n ?? 0),
      delta: kpis ? delta(kpis.gsc_impressions_n, kpis.gsc_impressions_prev) : undefined,
    },
    { label: "Requêtes", value: num(rows.length) },
    { label: "Quick wins", value: num(quickWins), hint: "position 5–15 · volume ≥ 100" },
  ];

  return (
    <div className="space-y-6">
      {kpis && (
        <FreshnessBanner
          cookedEnd={kpis.cooked_end}
          gscLastDay={kpis.gsc_last_day}
          lagDays={kpis.lag_days}
          isPartial={kpis.is_partial}
        />
      )}
      <KpiHeader items={items} />
      <section>
        <SectionTitle>Requêtes ({rows.length})</SectionTitle>
        <div className="rounded-xl border border-neutral-200 bg-white p-3 dark:border-neutral-800 dark:bg-neutral-950">
          <SeoTable rows={rows} />
        </div>
        <p className="mt-2 text-[11px] text-neutral-400">
          Requêtes de marque (« plouton ») exclues · volume DataForSEO (France) comme référence ·
          captation = clics / demande mensuelle estimée. Google n'expose qu'une partie des requêtes
          (le reste est anonymisé).
        </p>
      </section>
    </div>
  );
}

function Loading() {
  return (
    <div className="space-y-6">
      <div className="h-9 animate-pulse rounded-lg bg-neutral-200 dark:bg-neutral-800" />
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-20 animate-pulse rounded-xl bg-neutral-200 dark:bg-neutral-800" />
        ))}
      </div>
      <div className="h-96 animate-pulse rounded-xl bg-neutral-200 dark:bg-neutral-800" />
    </div>
  );
}
