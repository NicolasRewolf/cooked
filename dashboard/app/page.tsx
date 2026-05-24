import Link from "next/link";
import { PeriodDashboardChrome } from "@/components/period-dashboard-chrome";
import { KpiCard } from "@/components/kpi-card";
import { CategoryBadge } from "@/components/category-badge";
import { SitePulseCard } from "@/components/site-pulse-card";
import { SeoFunnel } from "@/components/seo-funnel";
import { QuadrantBadge } from "@/components/quadrant-badge";
import { StatusPill } from "@/components/status-pill";
import {
  pagesPulse,
  topContactPages,
  sitePulse,
  siteSeoFunnel,
  type PagePulseRow,
} from "@/lib/cooked";
import { loadPeriodContext } from "@/lib/period-context";
import {
  hrefWithPeriod,
  parsePeriod,
  periodSubtitle,
  prevPeriodCompareLabel,
  type PeriodKind,
} from "@/lib/period";
import { formatInt } from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const PULSE_ALERT_MIN_CLICKS = 20;

type Props = { searchParams: Promise<{ period?: string }> };

export default async function Home({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  const prevLabel = prevPeriodCompareLabel(period);
  const { kpis, health } = await loadPeriodContext(period);

  const [contributors, pulse, pulseRows, funnel] = await Promise.all([
    topContactPages(period, 10),
    sitePulse(period, 5.0),
    pagesPulse(period, 5.0),
    siteSeoFunnel(period),
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
    <PeriodDashboardChrome kpis={kpis} health={health}>
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-heading text-2xl font-medium tracking-tight">
              Vue d&apos;ensemble
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              {periodSubtitle(period)}
            </p>
          </div>
          <StatusPill status={health.status} />
        </header>

        <SitePulseCard pulse={pulse} />

        <div className="mt-6">
          <SeoFunnel funnel={funnel} />
        </div>

        <div className="mt-6">
          <KpiCard
            label="Contacts générés"
            hint="Total des appels (cta_phone_click) + formulaires soumis (form_submit). C'est la métrique business principale."
            value={kpis.macro_conversions_n}
            deltaPct={kpis.macro_conversions_delta_pct}
            prevValue={kpis.macro_conversions_prev}
            prevPeriodLabel={prevLabel}
            tone="positive"
            emphasis
          />
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-3">
          <KpiCard
            label="Appels téléphone"
            hint="Clics sur un numéro tel: depuis le site. Sur mobile, ouvre directement le composeur."
            value={kpis.phone_clicks_n}
            deltaPct={kpis.phone_clicks_delta_pct}
            prevValue={kpis.phone_clicks_prev}
            prevPeriodLabel={prevLabel}
          />
          <KpiCard
            label="Formulaires"
            hint="Formulaires de contact soumis et reçus côté serveur Cooked (event form_submit)."
            value={kpis.form_submits_n}
            deltaPct={kpis.form_submits_delta_pct}
            prevValue={kpis.form_submits_prev}
            prevPeriodLabel={prevLabel}
          />
          <KpiCard
            label="Visites"
            hint="Sessions humaines uniques (bots et bruit filtrés)."
            value={kpis.sessions_n}
            deltaPct={kpis.sessions_delta_pct}
            prevValue={kpis.sessions_prev}
            prevPeriodLabel={prevLabel}
          />
        </div>

        {alerts.length > 0 && (
          <section className="mt-10">
            <div className="mb-3 flex items-baseline justify-between">
              <h2 className="font-heading text-base font-medium tracking-tight">
                À regarder — alertes Pulse
              </h2>
              <Link
                href={hrefWithPeriod("/pages", period)}
                className="font-mono text-xs text-muted-foreground hover:text-foreground"
              >
                Voir toutes les pages →
              </Link>
            </div>
            <p className="mb-3 text-sm text-muted-foreground">
              Pages où Google envoie plus de trafic mais le comportement
              Cooked baisse (quadrant SEO ↗ engagement ↘). Filtre :
              ≥ {PULSE_ALERT_MIN_CLICKS} clics Google sur la fenêtre.
            </p>
            <PulseAlertList rows={alerts} period={period} />
          </section>
        )}

        <section className="mt-10">
          <div className="mb-3 flex items-baseline justify-between">
            <h2 className="font-heading text-base font-medium tracking-tight">
              Pages qui ont généré des contacts
            </h2>
            <Link
              href={hrefWithPeriod("/pages", period)}
              className="font-mono text-xs text-muted-foreground hover:text-foreground"
            >
              Voir toutes les pages →
            </Link>
          </div>
          {contributors.length === 0 ? (
            <EmptyHint text="Aucune page n'a généré de contact sur la fenêtre." />
          ) : (
            <ContribList
              rows={contributors}
              pulseByPath={pulseByPath}
              period={period}
            />
          )}
        </section>
      </main>
    </PeriodDashboardChrome>
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
                <span className="truncate text-sm text-foreground">
                  {p.path}
                </span>
              </div>
              <div className="flex shrink-0 items-baseline gap-5 font-mono text-xs">
                <span className="text-muted-foreground">
                  {formatInt(p.gsc_clicks)} clics
                </span>
                <span className="text-muted-foreground">
                  {formatInt(p.cooked_sessions)} visites
                </span>
                <span className="font-medium text-success">
                  {formatInt(p.cooked_contacts)} contact
                  {p.cooked_contacts > 1 ? "s" : ""}
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
              className="flex items-center justify-between gap-4 px-5 py-4 transition-colors hover:bg-warning/10"
            >
              <div className="flex min-w-0 items-center gap-3">
                <CategoryBadge path={p.path} />
                <span className="truncate text-sm text-foreground">
                  {p.path}
                </span>
              </div>
              <div className="flex shrink-0 items-baseline gap-5 font-mono text-xs">
                <span className="text-muted-foreground">
                  {formatInt(p.gsc_clicks_n)} clics Google
                </span>
                <span className="text-muted-foreground">
                  {formatInt(p.cooked_sessions_n)} visites
                </span>
                <QuadrantBadge row={p} />
              </div>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}

function EmptyHint({ text }: { text: string }) {
  return (
    <p className="rounded-lg border border-dashed border-border bg-surface px-5 py-6 text-center text-sm text-muted-foreground">
      {text}
    </p>
  );
}
