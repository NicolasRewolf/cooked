import { Suspense } from "react";
import { parsePeriod } from "@/lib/periods";
import { getSeoKpis, getSeoByQuery } from "@/data/dashboard";
import { requireUser } from "@/lib/auth";
import { KpiHeader, type KpiItem } from "@/components/KpiHeader";
import { FreshnessBanner } from "@/components/FreshnessBanner";
import { PeriodSelector } from "@/components/PeriodSelector";
import { SeoTable } from "@/components/SeoTable";
import { GisementsPanel } from "@/components/GisementsPanel";
import { num } from "@/lib/format";
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
  const lag = seo
    // eslint-disable-next-line react-hooks/purity -- Server Component rendu à la requête : heure courante lue une fois
    ? Math.max(0, Math.floor((Date.now() - new Date(seo.gsc_end).getTime()) / 86_400_000))
    : null;

  // B2/B3 : total quick wins calculé SQL (indépendant du cap du tableau) ; 2 niveaux de clics distincts.
  const items: KpiItem[] = [
    { label: "Clics Google", value: num(seo?.clicks_path_total ?? 0), hint: "toutes requêtes · marque incluse" },
    { label: "Affichages Google", value: num(seo?.impressions_path_total ?? 0), hint: "niveau page" },
    { label: "Requêtes connues", value: num(seo?.total_queries ?? 0), hint: "hors marque (fraction nommée par Google)" },
    { label: "Quick wins", value: num(seo?.total_quick_wins ?? 0), hint: "position 5–15 · volume ≥ 100" },
  ];

  return (
    <div className="space-y-[18px]">
      {seo && <FreshnessBanner gscLastDay={seo.gsc_end} lagDays={lag} live />}
      <KpiHeader items={items} />
      <GisementsPanel rows={rows} />
      <section>
        <SeoTable rows={rows} />
        <p className="mt-[11px] max-w-[920px] font-mono text-[10.5px] leading-relaxed text-dim">
          ⚠ Deux univers de clics : le KPI « Clics Google » ({num(seo?.clicks_path_total ?? 0)}) est au
          niveau page, marque incluse ; le tableau somme {num(seo?.clicks_named_nonbranded ?? 0)} clics
          sur les requêtes <em>connues hors marque</em>. Volume DataForSEO (France) = référence.
        </p>
      </section>
    </div>
  );
}

function Loading() {
  return (
    <div className="space-y-[18px]">
      <div className="h-9 w-72 animate-pulse bg-line" />
      <div className="grid grid-cols-2 gap-px border border-line bg-line sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-24 animate-pulse bg-panel" />
        ))}
      </div>
      <div className="h-48 animate-pulse border border-line bg-panel" />
      <div className="h-96 animate-pulse border border-line bg-panel" />
    </div>
  );
}
