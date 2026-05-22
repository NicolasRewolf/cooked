import Link from "next/link";
import { Nav } from "@/components/nav";
import { StatusPill } from "@/components/status-pill";
import { gscPagesOverview, pipelineHealth } from "@/lib/cooked";
import {
  formatInt,
  formatPct,
  formatNumber,
  formatDateTimeFR,
} from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function Home() {
  // Server-side fetch — toutes les données passent par lib/cooked (read-only).
  const [pages, health] = await Promise.all([
    gscPagesOverview(30),
    pipelineHealth(),
  ]);

  return (
    <>
      <Nav />
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-heading text-2xl font-medium tracking-tight">
              Top pages — 28 derniers jours
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Croisement Google Search Console × comportement Cooked. Trié
              par clics organiques.
            </p>
          </div>
          <div className="flex items-center gap-3">
            <StatusPill status={health.status} />
            <span className="font-mono text-xs text-muted-foreground">
              màj {formatDateTimeFR(health.snapshot_refreshed_at)}
            </span>
          </div>
        </header>

        <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
          <table className="w-full text-sm">
            <thead className="border-b border-border bg-surface-subtle/50">
              <tr className="text-left font-mono text-xs uppercase tracking-wide text-muted-foreground">
                <th className="px-4 py-3 font-medium">Page</th>
                <th className="px-3 py-3 text-right font-medium">Clics</th>
                <th className="px-3 py-3 text-right font-medium">Imp.</th>
                <th className="px-3 py-3 text-right font-medium">Pos.</th>
                <th className="px-3 py-3 text-right font-medium">CTR</th>
                <th className="px-3 py-3 text-right font-medium">Sess.</th>
                <th className="px-3 py-3 text-right font-medium">Dwell</th>
                <th className="px-3 py-3 text-right font-medium">Conv.</th>
                <th className="px-4 py-3 text-right font-medium">Pogo</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {pages.map((p) => (
                <tr
                  key={p.path}
                  className="group transition-colors hover:bg-surface-subtle/40"
                >
                  <td className="max-w-md truncate px-4 py-3">
                    <Link
                      href={`/p${p.path}`}
                      className="block truncate text-foreground hover:underline"
                      title={p.path}
                    >
                      {p.path}
                    </Link>
                  </td>
                  <td className="px-3 py-3 text-right font-mono tabular-nums">
                    {formatInt(p.gsc_clicks_28d)}
                  </td>
                  <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                    {formatInt(p.gsc_impressions_28d)}
                  </td>
                  <td className="px-3 py-3 text-right font-mono tabular-nums">
                    {formatNumber(p.gsc_position_avg_28d, 1)}
                  </td>
                  <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                    {formatPct(p.gsc_ctr_pct_28d, 2)}
                  </td>
                  <td className="px-3 py-3 text-right font-mono tabular-nums">
                    {formatInt(p.cooked_sessions_28d)}
                  </td>
                  <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                    {p.cooked_dwell_avg_s_28d != null
                      ? `${formatNumber(p.cooked_dwell_avg_s_28d, 0)}s`
                      : "—"}
                  </td>
                  <td className="px-3 py-3 text-right font-mono tabular-nums">
                    {p.cooked_conversions_28d > 0 ? (
                      <span className="text-foreground">
                        {formatInt(p.cooked_conversions_28d)}
                      </span>
                    ) : (
                      <span className="text-muted-foreground">0</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right font-mono tabular-nums text-muted-foreground">
                    {formatPct(p.cooked_pogo_rate_28d, 1)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <p className="mt-4 font-mono text-xs text-muted-foreground">
          {pages.length} pages · données 28j · GSC J-
          {health.gsc_data_age_days ?? "?"} (max: {health.gsc_last_day ?? "?"})
        </p>
      </main>
    </>
  );
}
