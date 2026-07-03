import { Suspense } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { parsePeriod } from "@/lib/periods";
import { getArticleDetail } from "@/data/dashboard";
import { requireUser } from "@/lib/auth";
import { KpiHeader, type KpiItem } from "@/components/KpiHeader";
import { PeriodSelector } from "@/components/PeriodSelector";
import { TrendChart } from "@/components/TrendChart";
import { CpiHealthPanel } from "@/components/CpiHealthPanel";
import { AskClaude } from "@/components/AskClaude";
import { SortableTable, type Column } from "@/components/SortableTable";
import { SectionTitle } from "@/components/ui";
import { num, dec, pct, delta, dateFr, prettyPath } from "@/lib/format";
import type { ArticleDetail, Period } from "@/lib/types";

export const dynamic = "force-dynamic";

// Fiche article (drill-down Vague A) : chaque ligne du tableau devient une porte.
export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ period?: string }>;
}) {
  await requireUser();
  const { slug } = await params;
  if (!slug) notFound();
  const path = `/post/${decodeURIComponent(slug)}`;
  const period = parsePeriod((await searchParams).period);

  return (
    <main className="mx-auto max-w-[1240px] px-8 py-[30px] pb-16">
      <Suspense key={`${slug}:${period}`} fallback={<Loading />}>
        <Content path={path} period={period} />
      </Suspense>
    </main>
  );
}

async function Content({ path, period }: { path: string; period: Period }) {
  const detail = await getArticleDetail(path, period);
  if (!detail || !detail.meta) notFound();

  const visitors = detail.visitors_daily.map((p) => p.v);
  const clicks = detail.gsc_daily.map((p) => p.clicks);
  const visitorsTotal = visitors.reduce((a, b) => a + b, 0);
  const g = detail.gsc;

  const items: KpiItem[] = [
    {
      label: "Entrées (visiteurs/j cumulés)",
      value: num(visitorsTotal),
      series: visitors,
      tooltip: "Somme des visiteurs uniques quotidiens sur la fenêtre (tous canaux).",
    },
    {
      label: "Clics Google",
      value: num(g?.clicks ?? 0),
      delta: g ? delta(g.clicks, g.clicks_prev) : undefined,
      series: clicks,
    },
    {
      label: "Position moyenne",
      value: g?.position != null ? dec(g.position) : "—",
      tooltip: "Pondérée par impressions, toutes requêtes confondues — à lire avec les requêtes ci-dessous.",
    },
    {
      label: "CTR réel / attendu",
      value: g?.ctr_pct != null ? `${pct(g.ctr_pct)} / ${pct(g.ctr_expected, 0)}` : "—",
      tooltip: "CTR attendu = courbe de clics du site à cette position. En-dessous : titre/méta à retravailler.",
    },
    {
      label: "Contacts assistés",
      value: num(detail.assisted?.n ?? 0),
      delta: detail.assisted ? delta(detail.assisted.n, detail.assisted.prev) : undefined,
      tooltip:
        "Contacts (appel ou formulaire) de visiteurs ENTRÉS par cet article — même visite. Attribution page d'entrée.",
    },
  ];

  return (
    <div className="space-y-[18px]">
      <div className="flex items-end justify-between gap-5">
        <div className="min-w-0">
          <div className="font-mono text-[11px] uppercase tracking-[0.08em] text-faint">
            <Link href="/" className="transition-colors hover:text-accent">
              ← articles ressources
            </Link>
          </div>
          <h1 className="mt-2 truncate text-[22px] font-semibold tracking-[-0.02em]">
            {prettyPath(detail.path)}
          </h1>
          <div className="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1 font-mono text-[10.5px] text-dim">
            {detail.meta.theme && <span>{detail.meta.theme}</span>}
            <span title="Première impression Google = âge SEO réel (la date Wix peut être antidatée)">
              né le {dateFr(detail.meta.naissance_google)} · {detail.meta.age_jours ?? "—"} j d&apos;âge SEO
            </span>
            <a
              href={`https://www.jplouton-avocat.fr${detail.path}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-info transition-colors hover:text-accent"
            >
              voir la page ↗
            </a>
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-3">
          <AskClaude path={detail.path} period={period} />
          <PeriodSelector value={period} />
        </div>
      </div>

      <KpiHeader items={items} />

      <div className="grid gap-[18px] lg:grid-cols-2">
        <TrendChart series={visitors} label="Visiteurs uniques / jour" lastDay={detail.bounds.cooked_end} />
        <TrendChart series={clicks} label="Clics Google / jour" lastDay={detail.bounds.gsc_end} />
      </div>

      <CpiHealthPanel detail={detail} />

      <section>
        <SectionTitle>
          requêtes google [{detail.top_queries.length}] · hors marque · {dateFr(detail.bounds.gsc_start)} →{" "}
          {dateFr(detail.bounds.gsc_end)}
        </SectionTitle>
        <SortableTable
          columns={queryColumns}
          rows={detail.top_queries}
          initialSortKey="impressions"
          initialDir="desc"
          minWidth={720}
          emptyLabel="Aucune requête révélée par Google sur la fenêtre (anonymisation)."
        />
        <p className="mt-[11px] font-mono text-[10.5px] leading-relaxed text-dim">
          Google ne révèle qu&apos;une partie des requêtes (le reste est anonymisé) — les totaux de la
          fiche viennent du niveau page, ce tableau sert au diagnostic requête par requête.
        </p>
      </section>
    </div>
  );
}

type QueryRow = ArticleDetail["top_queries"][number];

const queryColumns: Column<QueryRow>[] = [
  {
    key: "query",
    header: "requête",
    align: "left",
    sortValue: (r) => r.query,
    render: (r) => <span className="text-[12px] text-ink">{r.query}</span>,
  },
  {
    key: "impressions",
    header: "affichages",
    align: "right",
    sortValue: (r) => r.impressions,
    render: (r) => <span className="font-mono text-[11.5px] text-[#45423c]">{num(r.impressions)}</span>,
  },
  {
    key: "clicks",
    header: "clics",
    align: "right",
    sortValue: (r) => r.clicks,
    render: (r) => (
      <span className="font-mono text-[12px] font-medium text-ink">{num(r.clicks)}</span>
    ),
  },
  {
    key: "position",
    header: "pos.",
    align: "right",
    sortValue: (r) => r.position,
    render: (r) => <span className="font-mono text-[11.5px] text-[#45423c]">{dec(r.position)}</span>,
  },
  {
    key: "volume",
    header: "vol. / mois",
    align: "right",
    sortValue: (r) => r.volume_fr,
    render: (r) => (
      <span className="font-mono text-[11px] text-faint" title="Volume de recherche France (DataForSEO)">
        {r.volume_fr != null ? num(r.volume_fr) : "n.d."}
      </span>
    ),
  },
];

function Loading() {
  return (
    <div className="space-y-[18px]">
      <div className="h-16 w-96 animate-pulse bg-line" />
      <div className="grid grid-cols-2 gap-px border border-line bg-line sm:grid-cols-3 lg:grid-cols-5">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="h-28 animate-pulse bg-panel" />
        ))}
      </div>
      <div className="grid gap-[18px] lg:grid-cols-2">
        <div className="h-44 animate-pulse border border-line bg-panel" />
        <div className="h-44 animate-pulse border border-line bg-panel" />
      </div>
      <div className="h-56 animate-pulse border border-line bg-panel" />
    </div>
  );
}
