import { Suspense } from "react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { parsePeriod } from "@/lib/periods";
import { getArticleDetail, getAnnotations, getInterventionEffect } from "@/data/dashboard";
import { requireUser } from "@/lib/auth";
import { KpiHeader, type KpiItem } from "@/components/KpiHeader";
import { PeriodSelector } from "@/components/PeriodSelector";
import { TrendChart } from "@/components/TrendChart";
import { CpiHealthPanel } from "@/components/CpiHealthPanel";
import { AskClaude } from "@/components/AskClaude";
import { ArticleQueriesTable } from "@/components/ArticleQueriesTable";
import { SectionTitle } from "@/components/ui";
import { InterventionsTimeline } from "@/components/InterventionsTimeline";
import { InterventionEffects } from "@/components/InterventionEffects";
import { buildMarkers, annotationsForPath, uncoveredByGsc, dayShort } from "@/lib/annotations";
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
  const [detail, annotations] = await Promise.all([
    getArticleDetail(path, period),
    getAnnotations(period),
  ]);
  if (!detail || !detail.meta) notFound();

  const visitors = detail.visitors_daily.map((p) => p.v);
  const clicks = detail.gsc_daily.map((p) => p.clicks);
  // B1 — interventions ciblant cet article OU globales (paths NULL/vide), sur les
  // deux graphes (index par fenêtre propre) + la mini-timeline.
  const interventions = annotationsForPath(annotations, detail.path);
  const visMarkers = buildMarkers(interventions, detail.bounds.cooked_start, visitors.length);
  const gscMarkers = buildMarkers(interventions, detail.bounds.gsc_start, clicks.length);
  // M4 — interventions visibles côté visiteurs mais pas encore couvertes par Google
  // (day > gsc_end) : on l'annonce sous le graphe clics pour lever l'asymétrie.
  const uncovered = uncoveredByGsc(
    interventions,
    detail.bounds.gsc_end,
    detail.bounds.cooked_start,
    detail.bounds.cooked_end,
  );
  // B2 — effet mesuré des interventions site_change (RPC live, 1 appel par intervention).
  const siteChanges = interventions.filter((a) => a.kind === "site_change");
  const effects = await Promise.all(
    siteChanges.map(async (a) => ({
      label: a.label,
      day: a.day,
      effect: await getInterventionEffect(detail.path, a.day),
    })),
  );
  const visitorsTotal = visitors.reduce((a, b) => a + b, 0);
  const g = detail.gsc;

  const items: KpiItem[] = [
    {
      label: "Visiteurs (cumul quotidien)",
      value: num(visitorsTotal),
      series: visitors,
      tooltip: "Somme des visiteurs uniques quotidiens sur la fenêtre (tous canaux).",
    },
    {
      label: "Clics Google",
      value: num(g?.clicks ?? 0),
      delta: g ? delta(g.clicks, g.clicks_prev) : undefined,
      series: clicks,
      tooltip: "Clics organiques venus de la recherche Google vers cet article sur la fenêtre.",
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
            {/* M2 — le breadcrumb conserve la période ; les FILTRES, eux, sont
                restaurés par le bouton Retour du navigateur (l'entrée d'historique
                de la liste porte ces params) — comportement attendu. */}
            <Link
              href={period === "rolling_28" ? "/?period=rolling_28" : "/"}
              className="transition-colors hover:text-accent"
            >
              ← articles ressources
            </Link>
          </div>
          {/* Pas de truncate : un titre coupé n'est pas un titre lisible. Le vrai
              titre éditorial (accents/casse) demanderait la synchro des titres Wix
              — ici c'est un dé-sluggage au mieux (prettyPath). */}
          <h1 className="mt-2 text-[22px] font-semibold leading-tight tracking-[-0.02em]">
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

      {/* items-start : sans ça, le graphe visiteurs (enfant direct, stretch) s'étire
          à la hauteur de la rangée dès que la note ⚑ grandit la colonne de droite. */}
      <div className="grid items-start gap-[18px] lg:grid-cols-2">
        <TrendChart series={visitors} label="Visiteurs uniques / jour" lastDay={detail.bounds.cooked_end} markers={visMarkers} />
        <div>
          <TrendChart series={clicks} label="Clics Google / jour" lastDay={detail.bounds.gsc_end} markers={gscMarkers} />
          {uncovered.length > 0 && (
            <div className="mt-1.5 space-y-0.5 font-mono text-[10.5px] leading-snug text-dim">
              {uncovered.map((u, i) => (
                <p key={i}>
                  ⚑ {u.label} ({dayShort(u.day)}) — pas encore couvert par les données Google (jusqu&apos;au{" "}
                  {dayShort(detail.bounds.gsc_end)}).
                </p>
              ))}
            </div>
          )}
        </div>
      </div>

      <InterventionsTimeline items={interventions} />

      <InterventionEffects items={effects} />

      <CpiHealthPanel detail={detail} />

      <section>
        <SectionTitle>
          requêtes google [{detail.top_queries.length}] · hors marque · {dateFr(detail.bounds.gsc_start)} →{" "}
          {dateFr(detail.bounds.gsc_end)}
        </SectionTitle>
        <ArticleQueriesTable rows={detail.top_queries} />
        <p className="mt-[11px] font-mono text-[10.5px] leading-relaxed text-dim">
          Google ne révèle qu&apos;une partie des requêtes (le reste est anonymisé) — les totaux de la
          fiche viennent du niveau page, ce tableau sert au diagnostic requête par requête.
        </p>
      </section>
    </div>
  );
}

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
