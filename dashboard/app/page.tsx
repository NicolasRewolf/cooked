import Link from "next/link";
import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { KpiCard } from "@/components/kpi-card";
import { CategoryBadge } from "@/components/category-badge";
import { StatusPill } from "@/components/status-pill";
import {
  gscPagesOverview,
  pipelineHealth,
  siteKpisCompare,
} from "@/lib/cooked";
import { categorize } from "@/lib/page-category";
import { formatInt, formatPct } from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function Home() {
  const [kpis, health, pages] = await Promise.all([
    siteKpisCompare(28),
    pipelineHealth(),
    gscPagesOverview(50),
  ]);

  // Top pages contributrices aux contacts (>= 1 conversion).
  const contributors = pages
    .filter((p) => p.cooked_conversions_28d > 0)
    .slice(0, 5);

  // Alertes : pages d'expertise OU cabinet (pages business)
  // avec trafic significatif (>= 50 clics) et 0 conversion.
  // Les articles sont exclus (leur rôle est éducatif, conversion attendue
  // via maillage interne — cf. débat Plouton vs Adrien).
  const alerts = pages
    .filter((p) => {
      const cat = categorize(p.path);
      return (
        (cat === "expertise" || cat === "cabinet" || cat === "home") &&
        p.cooked_conversions_28d === 0 &&
        p.gsc_clicks_28d >= 50
      );
    })
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

        {/* KPI primaire en pleine largeur */}
        <KpiCard
          label="Contacts générés"
          hint="Total des appels (cta_phone_click) + formulaires soumis (form_submit). C'est la métrique business principale."
          value={kpis.macro_conversions_n}
          deltaPct={kpis.macro_conversions_delta_pct}
          prevValue={kpis.macro_conversions_prev}
          tone="positive"
          emphasis
        />

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

        {/* Top contributors */}
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
            <ContribList rows={contributors} kind="contributor" />
          )}
        </section>

        {/* Alerts */}
        {alerts.length > 0 && (
          <section className="mt-8">
            <h2 className="mb-3 font-heading text-base font-medium tracking-tight">
              À regarder
            </h2>
            <p className="mb-3 text-sm text-muted-foreground">
              Pages business (Cabinet ou Expertise) qui attirent du trafic
              Google mais ne génèrent aucun contact sur la fenêtre. Les
              articles sont volontairement exclus (leur rôle est éducatif).
            </p>
            <ContribList rows={alerts} kind="alert" />
          </section>
        )}
      </main>
    </>
  );
}

function ContribList({
  rows,
  kind,
}: {
  rows: Awaited<ReturnType<typeof gscPagesOverview>>;
  kind: "contributor" | "alert";
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
                {kind === "contributor" ? (
                  <span className="font-medium text-success">
                    {formatInt(p.cooked_conversions_28d)} contact
                    {p.cooked_conversions_28d > 1 ? "s" : ""}
                  </span>
                ) : (
                  <span className="font-medium text-danger">
                    0 contact ·{" "}
                    {p.cooked_pogo_rate_28d != null
                      ? `rebond ${formatPct(p.cooked_pogo_rate_28d, 0)}`
                      : ""}
                  </span>
                )}
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
