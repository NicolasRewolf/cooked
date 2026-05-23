import Link from "next/link";
import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { KpiCard } from "@/components/kpi-card";
import { CategoryBadge } from "@/components/category-badge";
import { SitePulseCard } from "@/components/site-pulse-card";
import { QuadrantBadge } from "@/components/quadrant-badge";
import { StatusPill } from "@/components/status-pill";
import {
  pagesOverviewUnified,
  pagesPulse,
  pipelineHealth,
  siteKpisCompare,
  sitePulse,
  type PagePulseRow,
} from "@/lib/cooked";
import { formatInt } from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

// Seuil minimum de volume GSC pour qu'une alerte up_down soit
// considérée comme actionnable. En dessous, le delta % est dominé
// par le bruit (ex. 2 → 5 clics).
const PULSE_ALERT_MIN_CLICKS = 20;

export default async function Home() {
  const [kpis, health, pages, pulse, pulseRows] = await Promise.all([
    siteKpisCompare(28),
    pipelineHealth(),
    pagesOverviewUnified(200),
    sitePulse(28, 7, 5.0),
    pagesPulse(28, 7, 5.0),
  ]);

  const pulseByPath = Object.fromEntries(pulseRows.map((r) => [r.path, r]));

  // Top pages contributrices aux contacts (>= 1 conversion).
  const contributors = [...pages]
    .filter((p) => p.cooked_contacts_28d > 0)
    .sort((a, b) => b.cooked_contacts_28d - a.cooked_contacts_28d)
    .slice(0, 5);

  // Alertes : pages où Google envoie plus de trafic mais Cooked
  // baisse en engagement (quadrant up_down). Filtre par volume minimal
  // pour exclure le bruit statistique des petites pages.
  const alerts = [...pulseRows]
    .filter(
      (p) =>
        p.quadrant === "up_down" && p.gsc_clicks_n >= PULSE_ALERT_MIN_CLICKS
    )
    .sort((a, b) => b.gsc_clicks_n - a.gsc_clicks_n)
    .slice(0, 5);

  return (
    <>
      <Nav />
      <DateBanner
        periodStart={kpis.period_n_start}
        periodEnd={kpis.period_n_end}
        gscLastDay={health.gsc_last_day}
        gscDataAgeDays={health.gsc_data_age_days}
      />

      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-heading text-2xl font-medium tracking-tight">
              Vue d&apos;ensemble
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Ce que le cabinet a généré sur les 28 derniers jours.
            </p>
          </div>
          <StatusPill status={health.status} />
        </header>

        {/* Pulse site-wide */}
        <SitePulseCard pulse={pulse} />

        {/* KPI primaire en pleine largeur */}
        <div className="mt-6">
          <KpiCard
            label="Contacts générés"
            hint="Total des appels (cta_phone_click) + formulaires soumis (form_submit). C'est la métrique business principale."
            value={kpis.macro_conversions_n}
            deltaPct={kpis.macro_conversions_delta_pct}
            prevValue={kpis.macro_conversions_prev}
            tone="positive"
            emphasis
          />
        </div>

        {/* 3 sous-KPIs */}
        <div className="mt-4 grid gap-4 md:grid-cols-3">
          <KpiCard
            label="Appels téléphone"
            hint="Clics sur un numéro tel: depuis le site. Sur mobile, ouvre directement le composeur."
            value={kpis.phone_clicks_n}
            deltaPct={kpis.phone_clicks_delta_pct}
            prevValue={kpis.phone_clicks_prev}
          />
          <KpiCard
            label="Formulaires"
            hint="Formulaires de contact soumis et reçus côté serveur Cooked (event form_submit)."
            value={kpis.form_submits_n}
            deltaPct={kpis.form_submits_delta_pct}
            prevValue={kpis.form_submits_prev}
          />
          <KpiCard
            label="Visites"
            hint="Sessions humaines uniques (bots et bruit filtrés)."
            value={kpis.sessions_n}
            deltaPct={kpis.sessions_delta_pct}
            prevValue={kpis.sessions_prev}
          />
        </div>

        {/* Alertes Pulse — top up_down (trafic monte, engagement baisse) */}
        {alerts.length > 0 && (
          <section className="mt-10">
            <div className="mb-3 flex items-baseline justify-between">
              <h2 className="font-heading text-base font-medium tracking-tight">
                À regarder — alertes Pulse
              </h2>
              <Link
                href="/pages"
                className="font-mono text-xs text-muted-foreground hover:text-foreground"
              >
                Voir toutes les pages →
              </Link>
            </div>
            <p className="mb-3 text-sm text-muted-foreground">
              Pages où Google envoie plus de trafic mais le comportement
              Cooked baisse (quadrant SEO ↗ engagement ↘). Filtre :
              ≥ {PULSE_ALERT_MIN_CLICKS} clics Google sur la fenêtre
              pour exclure le bruit statistique.
            </p>
            <PulseAlertList rows={alerts} />
          </section>
        )}

        {/* Top contributors aux contacts */}
        <section className="mt-10">
          <div className="mb-3 flex items-baseline justify-between">
            <h2 className="font-heading text-base font-medium tracking-tight">
              Pages qui ont généré des contacts
            </h2>
            <Link
              href="/pages"
              className="font-mono text-xs text-muted-foreground hover:text-foreground"
            >
              Voir toutes les pages →
            </Link>
          </div>
          {contributors.length === 0 ? (
            <EmptyHint text="Aucune page n'a généré de contact sur la fenêtre." />
          ) : (
            <ContribList rows={contributors} pulseByPath={pulseByPath} />
          )}
        </section>
      </main>
    </>
  );
}

function ContribList({
  rows,
  pulseByPath,
}: {
  rows: Awaited<ReturnType<typeof pagesOverviewUnified>>;
  pulseByPath: Record<string, PagePulseRow>;
}) {
  return (
    <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
      <ul className="divide-y divide-[var(--border-subtle)]">
        {rows.map((p) => (
          <li key={p.path}>
            <Link
              href={`/p${p.path}`}
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
                  {formatInt(p.gsc_clicks_28d)} clics
                </span>
                <span className="text-muted-foreground">
                  {formatInt(p.cooked_sessions_28d)} visites
                </span>
                <span className="font-medium text-success">
                  {formatInt(p.cooked_contacts_28d)} contact
                  {p.cooked_contacts_28d > 1 ? "s" : ""}
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

function PulseAlertList({ rows }: { rows: PagePulseRow[] }) {
  return (
    <div className="overflow-hidden rounded-lg border border-warning/30 bg-warning/5 shadow-xs">
      <ul className="divide-y divide-[var(--border-subtle)]">
        {rows.map((p) => (
          <li key={p.path}>
            <Link
              href={`/p${p.path}`}
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
