import Link from "next/link";
import { ZoneDashboardChrome } from "@/components/zone-dashboard-chrome";
import { KpiCard } from "@/components/kpi-card";
import { StatusPill } from "@/components/status-pill";
import { gscTopQueriesGlobal } from "@/lib/cooked";
import { loadGscContext } from "@/lib/period-context";
import {
  hrefWithPeriod,
  parsePeriod,
  periodLabel,
  prevPeriodCompareLabel,
} from "@/lib/period";
import { formatInt, formatNumber } from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Props = { searchParams: Promise<{ period?: string }> };

export default async function GooglePage({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  const label = periodLabel(period, "gsc");
  const prevLabel = prevPeriodCompareLabel(period, "gsc");
  const { kpis, health, banner } = await loadGscContext(period);
  const topQueries = await gscTopQueriesGlobal(period, 10);

  return (
    <ZoneDashboardChrome
      {...banner}
      zoneTitle="Google Search Console"
      zoneSubtitle="Données Google consolidées (retard habituel ~3–4 jours)."
    >
      <main className="mx-auto w-full max-w-6xl px-6 py-8">
        <div className="mb-6 flex justify-end">
          <StatusPill status={health.status} />
        </div>

        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          <KpiCard
            label="Clics Google"
            hint="Clics organiques agrégés sur toutes les pages."
            value={kpis.clicks_n}
            deltaPct={kpis.clicks_delta_pct}
            prevValue={kpis.clicks_prev}
            prevPeriodLabel={prevLabel}
            emphasis
          />
          <KpiCard
            label="Impressions"
            hint="Impressions Google sur la fenêtre consolidée."
            value={kpis.impressions_n}
            deltaPct={kpis.impressions_delta_pct}
            prevValue={kpis.impressions_prev}
            prevPeriodLabel={prevLabel}
          />
          <div className="rounded-lg border border-border bg-surface p-5 shadow-xs">
            <div className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
              CTR moyen
            </div>
            <p className="mt-3 font-mono text-3xl tabular-nums">
              {kpis.ctr_pct_n != null ? `${formatNumber(kpis.ctr_pct_n, 2)} %` : "—"}
            </p>
          </div>
          <div className="rounded-lg border border-border bg-surface p-5 shadow-xs">
            <div className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
              Position moy.
            </div>
            <p className="mt-3 font-mono text-3xl tabular-nums">
              {kpis.position_avg_n != null
                ? formatNumber(kpis.position_avg_n, 1)
                : "—"}
            </p>
          </div>
        </div>

        <section className="mt-10">
          <div className="mb-3 flex items-baseline justify-between">
            <h2 className="font-heading text-base font-medium tracking-tight">
              Top requêtes — {label}
            </h2>
            <Link
              href={hrefWithPeriod("/queries", period)}
              className="font-mono text-xs text-muted-foreground hover:text-foreground"
            >
              Toutes les requêtes →
            </Link>
          </div>
          <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
            <table className="w-full text-sm">
              <thead className="border-b border-border bg-surface-subtle/60 font-mono text-xs text-muted-foreground">
                <tr>
                  <th className="px-5 py-2 text-left font-normal">Requête</th>
                  <th className="px-5 py-2 text-right font-normal">Clics</th>
                  <th className="px-5 py-2 text-right font-normal">Impr.</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-subtle)]">
                {topQueries.map((q) => (
                  <tr key={q.query}>
                    <td className="max-w-md truncate px-5 py-3 text-sm">
                      {q.query}
                    </td>
                    <td className="px-5 py-3 text-right font-mono text-xs">
                      {formatInt(q.clicks)}
                    </td>
                    <td className="px-5 py-3 text-right font-mono text-xs text-muted-foreground">
                      {formatInt(q.impressions)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      </main>
    </ZoneDashboardChrome>
  );
}
