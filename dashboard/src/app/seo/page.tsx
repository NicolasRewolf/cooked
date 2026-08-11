import { Suspense } from "react";
import { parsePeriod } from "@/lib/periods";
import { getSeoKpis, getSeoByQuery } from "@/data/dashboard";
import { buildSeoView } from "@/data/view-models";
import { requireUser } from "@/lib/auth";
import { KpiHeader } from "@/components/KpiHeader";
import { FreshnessBanner } from "@/components/FreshnessBanner";
import { PeriodSelector } from "@/components/PeriodSelector";
import { SeoTable } from "@/components/SeoTable";
import { GisementsPanel } from "@/components/GisementsPanel";
import type { Period } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function SeoPage({
  searchParams,
}: {
  searchParams: Promise<{ period?: string }>;
}) {
  await requireUser();
  const period = parsePeriod((await searchParams).period);
  return (
    <main className="mx-auto max-w-[1240px] px-8 py-[30px] pb-16">
      <div className="mb-[18px] flex items-end justify-between gap-5">
        <div>
          <div className="font-mono text-[11px] uppercase tracking-[0.08em] text-faint">
            Requêtes Google · top 200 par clics
          </div>
          <h1 className="mt-2 text-[25px] font-semibold tracking-[-0.02em]">SEO · requêtes</h1>
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
  const [seo, rows] = await Promise.all([getSeoKpis(period), getSeoByQuery(period, { maxRows: 200 })]);
  const view = buildSeoView(seo);

  return (
    <div className="space-y-[18px]">
      {seo && <FreshnessBanner gscLastDay={seo.gsc_end} lagDays={view.lagDays} live />}
      <KpiHeader items={view.items} />
      <GisementsPanel rows={rows} />
      <section>
        <SeoTable rows={rows} />
        <p className="mt-[11px] max-w-[920px] font-mono text-[10.5px] leading-relaxed text-dim">
          ⚠ Deux univers de clics : le KPI « Clics Google » ({view.clicksPathTotalLabel}) est au
          niveau page, marque incluse ; le tableau somme {view.clicksNamedNonbrandedLabel} clics
          sur les requêtes <em>connues hors marque</em>. Volume DataForSEO (France) = référence.
        </p>
      </section>
    </div>
  );
}

function Loading() {
  return (
    <div className="space-y-[18px]">
      <div className="h-9 w-72 skeleton" />
      <div className="grid grid-cols-2 gap-px border border-line bg-line sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-24 skeleton" />
        ))}
      </div>
      <div className="h-48 skeleton border border-line" />
      <div className="h-96 skeleton border border-line" />
    </div>
  );
}
