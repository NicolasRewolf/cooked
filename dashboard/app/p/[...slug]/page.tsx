import Link from "next/link";
import { notFound } from "next/navigation";
import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { CategoryBadge } from "@/components/category-badge";
import {
  gscPagePerformance,
  gscTopQueriesForPath,
  pipelineHealth,
  siteKpisCompare,
} from "@/lib/cooked";
import { formatInt, formatPct, formatNumber } from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Props = { params: Promise<{ slug: string[] }> };

export default async function PageDetail({ params }: Props) {
  const { slug } = await params;
  const path = "/" + slug.map((s) => decodeURIComponent(s)).join("/");

  const [perf, queries, health, kpis] = await Promise.all([
    gscPagePerformance(path),
    gscTopQueriesForPath(path, 28, 20),
    pipelineHealth(),
    siteKpisCompare(28),
  ]);

  if (!perf) notFound();

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
        <Link
          href="/pages"
          className="mb-6 inline-block font-mono text-xs text-muted-foreground hover:text-foreground"
        >
          ← Pages
        </Link>

        <div className="flex flex-wrap items-center gap-3">
          <CategoryBadge path={perf.path} />
          <h1 className="break-words font-mono text-xl tracking-tight text-foreground">
            {perf.path}
          </h1>
        </div>
        <p className="mt-1 text-sm text-muted-foreground">
          Fiche cross-source sur les 28 derniers jours.
        </p>

        {/* Métriques principales */}
        <div className="mt-8 grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-border bg-border shadow-xs md:grid-cols-4">
          <Stat
            label="Clics Google"
            value={formatInt(perf.gsc_clicks_28d)}
            sub={`${formatInt(perf.gsc_impressions_28d)} impressions`}
          />
          <Stat
            label="Position moyenne"
            value={formatNumber(perf.gsc_position_avg_28d, 1)}
            sub={`CTR ${formatPct(perf.gsc_ctr_pct_28d, 2)}`}
          />
          <Stat
            label="Sessions Cooked"
            value={formatInt(perf.cooked_sessions_28d)}
            sub={`${formatInt(perf.cooked_google_sessions_28d)} via Google`}
          />
          <Stat
            label="Conversions"
            value={formatInt(
              perf.cooked_phone_clicks_28d + perf.cooked_booking_clicks_28d
            )}
            sub={`${perf.cooked_phone_clicks_28d} phone · ${perf.cooked_booking_clicks_28d} booking`}
            highlight={
              perf.cooked_phone_clicks_28d + perf.cooked_booking_clicks_28d > 0
            }
          />
        </div>

        {/* Comportement + CWV */}
        <div className="mt-6 grid gap-6 md:grid-cols-2">
          <Panel title="Comportement">
            <Row
              label="Dwell moyen"
              value={
                perf.cooked_dwell_avg_s_28d != null
                  ? `${formatNumber(perf.cooked_dwell_avg_s_28d, 0)} s`
                  : "—"
              }
            />
            <Row
              label="Scroll médian"
              value={
                perf.cooked_scroll_median_28d != null
                  ? `${formatNumber(perf.cooked_scroll_median_28d, 0)} %`
                  : "—"
              }
            />
            <Row
              label="Bounce rate"
              value={formatPct(perf.cooked_bounce_rate_28d, 1)}
            />
            <Row
              label="Pogo-stick rate"
              value={formatPct(perf.cooked_pogo_rate_28d, 1)}
            />
            <Row
              label="Top referrer"
              value={perf.top_referrer_28d ?? "—"}
              mono
            />
          </Panel>

          <Panel title="Core Web Vitals (p75)">
            <Row
              label="LCP"
              value={
                perf.lcp_p75_ms != null
                  ? `${formatNumber(perf.lcp_p75_ms, 0)} ms`
                  : "—"
              }
              hint={lcpVerdict(perf.lcp_p75_ms)}
            />
            <Row
              label="INP"
              value={
                perf.inp_p75_ms != null
                  ? `${formatNumber(perf.inp_p75_ms, 0)} ms`
                  : "—"
              }
              hint={inpVerdict(perf.inp_p75_ms)}
            />
            <Row
              label="CLS"
              value={formatNumber(perf.cls_p75, 2)}
              hint={clsVerdict(perf.cls_p75)}
            />
            <Row
              label="Device split"
              value={
                perf.device_split_28d
                  ? Object.entries(perf.device_split_28d)
                      .map(([k, v]) => `${k} ${v}%`)
                      .join(" · ")
                  : "—"
              }
              mono
            />
          </Panel>
        </div>

        {/* Top requêtes Google */}
        <section className="mt-8">
          <h2 className="mb-3 font-heading text-base font-medium tracking-tight">
            Top requêtes Google
          </h2>
          {queries.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Aucune requête attribuable sur cette période (peut être anonymisé
              par GSC).
            </p>
          ) : (
            <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
              <table className="w-full text-sm">
                <thead className="border-b border-border bg-surface-subtle/50">
                  <tr className="text-left font-mono text-xs uppercase tracking-wide text-muted-foreground">
                    <th className="px-4 py-3 font-medium">Requête</th>
                    <th className="px-3 py-3 text-right font-medium">Clics</th>
                    <th className="px-3 py-3 text-right font-medium">Imp.</th>
                    <th className="px-3 py-3 text-right font-medium">Pos.</th>
                    <th className="px-4 py-3 text-right font-medium">CTR</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--border-subtle)]">
                  {queries.map((q) => (
                    <tr key={q.query} className="hover:bg-surface-subtle/40">
                      <td className="px-4 py-3 text-foreground">{q.query}</td>
                      <td className="px-3 py-3 text-right font-mono tabular-nums">
                        {formatInt(q.clicks)}
                      </td>
                      <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                        {formatInt(q.impressions)}
                      </td>
                      <td className="px-3 py-3 text-right font-mono tabular-nums">
                        {formatNumber(q.position_avg, 1)}
                      </td>
                      <td className="px-4 py-3 text-right font-mono tabular-nums text-muted-foreground">
                        {formatPct(q.ctr_pct, 1)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </main>
    </>
  );
}

function Stat({
  label,
  value,
  sub,
  highlight,
}: {
  label: string;
  value: string;
  sub?: string;
  highlight?: boolean;
}) {
  return (
    <div className="bg-surface p-5">
      <div className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
        {label}
      </div>
      <div
        className={`mt-2 font-mono text-2xl tabular-nums tracking-tight ${
          highlight ? "text-success" : "text-foreground"
        }`}
      >
        {value}
      </div>
      {sub && (
        <div className="mt-1 font-mono text-xs text-muted-foreground">
          {sub}
        </div>
      )}
    </div>
  );
}

function Panel({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface p-5 shadow-xs">
      <h3 className="mb-3 font-heading text-sm font-medium tracking-tight">
        {title}
      </h3>
      <dl className="space-y-2.5">{children}</dl>
    </div>
  );
}

function Row({
  label,
  value,
  hint,
  mono,
}: {
  label: string;
  value: string;
  hint?: string;
  mono?: boolean;
}) {
  return (
    <div className="flex items-baseline justify-between gap-4 text-sm">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="flex items-baseline gap-2 text-right">
        {hint && (
          <span className="font-mono text-xs text-muted-foreground">
            {hint}
          </span>
        )}
        <span
          className={`${mono ? "font-mono text-xs" : ""} tabular-nums text-foreground`}
        >
          {value}
        </span>
      </dd>
    </div>
  );
}

function lcpVerdict(ms: number | null): string {
  if (ms == null) return "";
  if (ms <= 2500) return "good";
  if (ms <= 4000) return "needs-improvement";
  return "poor";
}
function inpVerdict(ms: number | null): string {
  if (ms == null) return "";
  if (ms <= 200) return "good";
  if (ms <= 500) return "needs-improvement";
  return "poor";
}
function clsVerdict(v: number | null): string {
  if (v == null) return "";
  if (v <= 0.1) return "good";
  if (v <= 0.25) return "needs-improvement";
  return "poor";
}
