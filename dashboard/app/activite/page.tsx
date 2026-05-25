import Link from "next/link";
import { ZoneDashboardChrome } from "@/components/zone-dashboard-chrome";
import { KpiCard } from "@/components/kpi-card";
import { StatusPill } from "@/components/status-pill";
import { cookedPagesSnapshot } from "@/lib/cooked";
import { loadCookedContext } from "@/lib/period-context";
import {
  hrefWithPeriod,
  parsePeriod,
  periodSubtitle,
  prevPeriodCompareLabel,
} from "@/lib/period";
import { formatInt } from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Props = { searchParams: Promise<{ period?: string }> };

export default async function ActivitePage({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  const prevLabel = prevPeriodCompareLabel(period);
  const { kpis, health, banner } = await loadCookedContext(period);
  const pages = await cookedPagesSnapshot(period, 15);

  return (
    <ZoneDashboardChrome {...banner}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-heading text-2xl font-medium tracking-tight">
              Activité site
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {periodSubtitle(period, "live")}
            </p>
          </div>
          <StatusPill status={health.status} />
        </header>

        <div className="mb-6">
          <KpiCard
            label="Contacts générés"
            hint="Appels + formulaires (hors candidatures). Métrique business — à jour."
            value={kpis.macro_conversions_n}
            deltaPct={kpis.macro_conversions_delta_pct}
            prevValue={kpis.macro_conversions_prev}
            prevPeriodLabel={prevLabel}
            tone="positive"
            emphasis
          />
        </div>

        <div className="grid gap-4 md:grid-cols-3">
          <KpiCard
            label="Appels"
            hint="Clics téléphone sur la période."
            value={kpis.phone_clicks_n}
            deltaPct={kpis.phone_clicks_delta_pct}
            prevValue={kpis.phone_clicks_prev}
            prevPeriodLabel={prevLabel}
          />
          <KpiCard
            label="Formulaires"
            hint="Formulaires contact (server-side)."
            value={kpis.form_submits_n}
            deltaPct={kpis.form_submits_delta_pct}
            prevValue={kpis.form_submits_prev}
            prevPeriodLabel={prevLabel}
          />
          <KpiCard
            label="Visites"
            hint="Sessions humaines (events_human)."
            value={kpis.sessions_n}
            deltaPct={kpis.sessions_delta_pct}
            prevValue={kpis.sessions_prev}
            prevPeriodLabel={prevLabel}
          />
        </div>

        <section className="mt-10">
          <h2 className="font-heading mb-3 text-base font-medium tracking-tight">
            Pages les plus actives (Cooked)
          </h2>
          {pages.length === 0 ? (
            <p className="rounded-lg border border-dashed border-border px-5 py-6 text-center text-sm text-muted-foreground">
              Aucune activité sur la fenêtre.
            </p>
          ) : (
            <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
              <table className="w-full text-sm">
                <thead className="border-b border-border bg-surface-subtle/60 font-mono text-xs text-muted-foreground">
                  <tr>
                    <th className="px-5 py-2 text-left font-normal">Page</th>
                    <th className="px-5 py-2 text-right font-normal">
                      Visites
                    </th>
                    <th className="px-5 py-2 text-right font-normal">
                      Contacts
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-subtle)]">
                  {pages.map((p) => (
                    <tr key={p.path} className="hover:bg-surface-subtle/40">
                      <td className="px-5 py-3 font-mono text-xs">{p.path}</td>
                      <td className="px-5 py-3 text-right font-mono text-xs">
                        {formatInt(p.cooked_sessions)}
                      </td>
                      <td className="px-5 py-3 text-right font-mono text-xs text-success">
                        {formatInt(p.cooked_contacts)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <p className="mt-4 text-sm text-muted-foreground">
            Pour le croisement avec Google, voir{" "}
            <Link
              href={hrefWithPeriod("/croisement", period)}
              className="text-foreground underline-offset-2 hover:underline"
            >
              Croisement
            </Link>
            .
          </p>
        </section>
      </main>
    </ZoneDashboardChrome>
  );
}
