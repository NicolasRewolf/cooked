import { Suspense } from "react";
import { parsePeriod } from "@/lib/periods";
import { getResourcesKpis, getResourcesOverview } from "@/data/dashboard";
import { requireUser } from "@/lib/auth";
import { KpiHeader, type KpiItem } from "@/components/KpiHeader";
import { FreshnessBanner } from "@/components/FreshnessBanner";
import { PeriodSelector } from "@/components/PeriodSelector";
import { ResourcesTable } from "@/components/ResourcesTable";
import { SectionTitle } from "@/components/ui";
import { num, delta } from "@/lib/format";
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
    <main className="mx-auto max-w-6xl space-y-6 px-4 py-6">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Synthèse — articles ressources</h1>
        <PeriodSelector value={period} />
      </div>
      <Suspense key={period} fallback={<Loading />}>
        <Content period={period} />
      </Suspense>
    </main>
  );
}

async function Content({ period }: { period: Period }) {
  const [kpis, rows] = await Promise.all([getResourcesKpis(period), getResourcesOverview(period)]);

  const items: KpiItem[] = kpis
    ? [
        { label: "Visiteurs uniques", value: num(kpis.visitors_n), delta: delta(kpis.visitors_n, kpis.visitors_prev) },
        { label: "Pages vues", value: num(kpis.pageviews_n), delta: delta(kpis.pageviews_n, kpis.pageviews_prev) },
        { label: "Contacts", value: num(kpis.contacts_n), delta: delta(kpis.contacts_n, kpis.contacts_prev) },
        { label: "Clics Google", value: num(kpis.gsc_clicks_n), delta: delta(kpis.gsc_clicks_n, kpis.gsc_clicks_prev) },
        { label: "Affichages Google", value: num(kpis.gsc_impressions_n), delta: delta(kpis.gsc_impressions_n, kpis.gsc_impressions_prev) },
      ]
    : [];

  return (
    <div className="space-y-6">
      {kpis && (
        <FreshnessBanner
          cookedEnd={kpis.cooked_end}
          gscLastDay={kpis.gsc_last_day}
          lagDays={kpis.lag_days}
          refreshedAt={kpis.refreshed_at}
          currentDayPartial={kpis.current_day_partial}
          noPrevBaseline={kpis.no_prev_baseline}
        />
      )}
      <KpiHeader items={items} />
      <section>
        <SectionTitle>Articles ({rows.length})</SectionTitle>
        <div className="rounded-xl border border-neutral-200 bg-white p-1 dark:border-neutral-800 dark:bg-neutral-950">
          <ResourcesTable rows={rows} />
        </div>
        <p className="mt-2 text-[11px] text-neutral-400">
          Visiteurs uniques (hors robots/Baidu) · lecture médiane des vrais lecteurs (hors
          ré-ouvertures réseaux sociaux) · totaux Google depuis Search Console · volume DataForSEO
          (France) · fiabilité notée par visiteurs/jour.
        </p>
      </section>
    </div>
  );
}

function Loading() {
  return (
    <div className="space-y-6">
      <div className="h-9 animate-pulse rounded-lg bg-neutral-200 dark:bg-neutral-800" />
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="h-20 animate-pulse rounded-xl bg-neutral-200 dark:bg-neutral-800" />
        ))}
      </div>
      <div className="h-64 animate-pulse rounded-xl bg-neutral-200 dark:bg-neutral-800" />
    </div>
  );
}
