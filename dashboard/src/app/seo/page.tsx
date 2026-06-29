import { Suspense } from "react";
import { parsePeriod } from "@/lib/periods";
import { getSeoKpis, getSeoByQuery } from "@/data/dashboard";
import { requireUser } from "@/lib/auth";
import { KpiHeader, type KpiItem } from "@/components/KpiHeader";
import { FreshnessBanner } from "@/components/FreshnessBanner";
import { PeriodSelector } from "@/components/PeriodSelector";
import { SeoTable } from "@/components/SeoTable";
import { SectionTitle } from "@/components/ui";
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
  const [seo, rows] = await Promise.all([getSeoKpis(period), getSeoByQuery(period, { maxRows: 200 })]);
  const lag = seo ? Math.max(0, Math.floor((Date.now() - new Date(seo.gsc_end).getTime()) / 86_400_000)) : null;

  // B2/B3 : total quick wins calculé SQL (indépendant du cap du tableau) ; 2 niveaux de clics distincts.
  const items: KpiItem[] = [
    {
      label: "Clics Google",
      value: num(seo?.clicks_path_total ?? 0),
      hint: "toutes requêtes, marque incluse",
    },
    {
      label: "Affichages Google",
      value: num(seo?.impressions_path_total ?? 0),
    },
    {
      label: "Requêtes connues",
      value: num(seo?.total_queries ?? 0),
      hint: "hors marque (fraction nommée par Google)",
    },
    {
      label: "Quick wins",
      value: num(seo?.total_quick_wins ?? 0),
      hint: "position 5–15 · volume ≥ 100",
    },
  ];

  return (
    <div className="space-y-6">
      {seo && <FreshnessBanner gscLastDay={seo.gsc_end} lagDays={lag} live />}
      <KpiHeader items={items} />
      <section>
        <SectionTitle>Requêtes — top 200 par clics ({rows.length})</SectionTitle>
        <div className="rounded-xl border border-neutral-200 bg-white p-3 dark:border-neutral-800 dark:bg-neutral-950">
          <SeoTable rows={rows} />
        </div>
        <p className="mt-2 text-[11px] text-neutral-400">
          ⚠ Deux univers de clics : le KPI « Clics Google » ({num(seo?.clicks_path_total ?? 0)}) est au
          niveau page, marque incluse ; le tableau ci-dessus somme {num(seo?.clicks_named_nonbranded ?? 0)}{" "}
          clics sur les requêtes <em>connues hors marque</em> — Google n'expose qu'une fraction des
          requêtes (le reste est anonymisé). Volume DataForSEO (France) = référence. Captation = clics /
          demande mensuelle estimée.
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
