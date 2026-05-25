import Link from "next/link";
import { ZoneDashboardChrome } from "@/components/zone-dashboard-chrome";
import { PagesTable } from "@/components/pages-table";
import { CategoryBadge } from "@/components/category-badge";
import { SitePulseCard } from "@/components/site-pulse-card";
import { SeoFunnel } from "@/components/seo-funnel";
import { QuadrantBadge } from "@/components/quadrant-badge";
import { StatusPill } from "@/components/status-pill";
import {
  pagesOverviewUnified,
  pagesPulse,
  siteSeoFunnel,
  topContactPages,
  type PagePulseRow,
} from "@/lib/cooked";
import { loadCrossContext } from "@/lib/period-context";
import {
  hrefWithPeriod,
  parsePeriod,
  periodLabel,
  periodSubtitle,
  type PeriodKind,
} from "@/lib/period";
import { formatInt } from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const PULSE_ALERT_MIN_CLICKS = 20;

type Props = { searchParams: Promise<{ period?: string }> };

export default async function CroisementPage({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  const label = periodLabel(period);
  const { pulse, health, banner } = await loadCrossContext(period);

  const [pages, pulseRows, funnel, contributors] = await Promise.all([
    pagesOverviewUnified(period, 250),
    pagesPulse(period, 5.0),
    siteSeoFunnel(period),
    topContactPages(period, 10),
  ]);

  const pulseByPath = Object.fromEntries(pulseRows.map((r) => [r.path, r]));

  const alerts = [...pulseRows]
    .filter(
      (p) =>
        p.quadrant === "up_down" && p.gsc_clicks_n >= PULSE_ALERT_MIN_CLICKS
    )
    .sort((a, b) => b.gsc_clicks_n - a.gsc_clicks_n)
    .slice(0, 5);

  return (
    <ZoneDashboardChrome {...banner}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-heading text-2xl font-medium tracking-tight">
              Croisement — {label}
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {periodSubtitle(period, "cross")}
            </p>
          </div>
          <StatusPill status={health.status} />
        </header>

        <SitePulseCard pulse={pulse} />

        <div className="mt-6">
          <SeoFunnel funnel={funnel} />
        </div>

        {alerts.length > 0 && (
          <section className="mt-10">
            <h2 className="font-heading mb-3 text-base font-medium tracking-tight">
              Alertes Pulse
            </h2>
            <PulseAlertList rows={alerts} period={period} />
          </section>
        )}

        {contributors.length > 0 && (
          <section className="mt-10">
            <h2 className="font-heading mb-3 text-base font-medium tracking-tight">
              Pages avec contacts (fenêtre alignée)
            </h2>
            <ContribList
              rows={contributors}
              pulseByPath={pulseByPath}
              period={period}
            />
          </section>
        )}

        <section className="mt-10">
          <h2 className="font-heading mb-3 text-base font-medium tracking-tight">
            Toutes les pages
          </h2>
          <PagesTable
            rows={pages}
            pulseByPath={pulseByPath}
            period={period}
            periodLabel={label}
          />
        </section>
      </main>
    </ZoneDashboardChrome>
  );
}

function ContribList({
  rows,
  pulseByPath,
  period,
}: {
  rows: Awaited<ReturnType<typeof topContactPages>>;
  pulseByPath: Record<string, PagePulseRow>;
  period: PeriodKind;
}) {
  return (
    <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
      <ul className="divide-y divide-[var(--border-subtle)]">
        {rows.map((p) => (
          <li key={p.path}>
            <Link
              href={hrefWithPeriod(`/p${p.path}`, period)}
              className="flex items-center justify-between gap-4 px-5 py-4 transition-colors hover:bg-surface-subtle/40"
            >
              <div className="flex min-w-0 items-center gap-3">
                <CategoryBadge path={p.path} />
                <span className="truncate text-sm">{p.path}</span>
              </div>
              <div className="flex shrink-0 items-baseline gap-5 font-mono text-xs">
                <span className="text-muted-foreground">
                  {formatInt(p.gsc_clicks)} clics
                </span>
                <span className="text-muted-foreground">
                  {formatInt(p.cooked_sessions)} visites
                </span>
                <span className="font-medium text-success">
                  {formatInt(p.cooked_contacts)} contacts
                </span>
                <QuadrantBadge row={pulseByPath[p.path]} />
              </div>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}

function PulseAlertList({
  rows,
  period,
}: {
  rows: PagePulseRow[];
  period: PeriodKind;
}) {
  return (
    <div className="overflow-hidden rounded-lg border border-warning/30 bg-warning/5 shadow-xs">
      <ul className="divide-y divide-[var(--border-subtle)]">
        {rows.map((p) => (
          <li key={p.path}>
            <Link
              href={hrefWithPeriod(`/p${p.path}`, period)}
              className="flex items-center justify-between gap-4 px-5 py-4 hover:bg-warning/10"
            >
              <span className="truncate font-mono text-sm">{p.path}</span>
              <QuadrantBadge row={p} />
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
