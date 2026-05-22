import { Nav } from "@/components/nav";
import { StatusPill } from "@/components/status-pill";
import { pipelineHealth } from "@/lib/cooked";
import {
  formatAge,
  formatDateTimeFR,
  formatInt,
  formatNumber,
} from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function HealthPage() {
  const h = await pipelineHealth();

  const axes: Axis[] = [
    {
      title: "Snapshot",
      status: snapshotStatus(h.snapshot_age_hours),
      lines: [
        ["Dernier refresh", formatDateTimeFR(h.snapshot_refreshed_at)],
        ["Âge", formatAge(h.snapshot_age_hours)],
      ],
      note: "rebuild seo_url_snapshot — cron quotidien 03:00 UTC",
    },
    {
      title: "Cron snapshot",
      status: cronStatus(h.cron_last_status, h.cron_age_hours),
      lines: [
        ["Dernier run", formatDateTimeFR(h.cron_last_run)],
        ["Statut", h.cron_last_status ?? "—"],
        ["Âge", formatAge(h.cron_age_hours)],
      ],
      note: "refresh_seo_url_snapshot (pg_cron)",
    },
    {
      title: "Ingestion events",
      status: ingestStatus(h.last_event_age_minutes),
      lines: [
        ["Dernier event", formatDateTimeFR(h.last_event_at)],
        [
          "Retard",
          h.last_event_age_minutes != null
            ? `${formatNumber(h.last_event_age_minutes, 0)} min`
            : "—",
        ],
        ["Events / 60min", formatInt(h.events_last_60min)],
      ],
      note: "tracker → /track Edge Function",
    },
    {
      title: "Google Search Console",
      status: gscStatus(h.gsc_data_age_days, h.gsc_ingest_age_hours),
      lines: [
        ["Dernier jour GSC", h.gsc_last_day ?? "—"],
        [
          "Âge donnée",
          h.gsc_data_age_days != null
            ? `J-${formatNumber(h.gsc_data_age_days, 0)}`
            : "—",
        ],
        ["Dernier ingest", formatDateTimeFR(h.gsc_last_ingest)],
        ["Âge ingest", formatAge(h.gsc_ingest_age_hours)],
      ],
      note: "GitHub Actions — 06:00 UTC quotidien",
    },
  ];

  return (
    <>
      <Nav />
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8 flex items-end justify-between">
          <div>
            <h1 className="font-heading text-2xl font-medium tracking-tight">
              Pipeline
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Self-diagnostic 4 axes — `refresh_pipeline_health()`.
            </p>
          </div>
          <StatusPill status={h.status} />
        </header>

        <div className="grid gap-4 md:grid-cols-2">
          {axes.map((a) => (
            <AxisCard key={a.title} axis={a} />
          ))}
        </div>

        {h.issues.length > 0 && (
          <section className="mt-8 rounded-lg border border-border bg-surface p-5 shadow-xs">
            <h2 className="mb-3 font-heading text-sm font-medium tracking-tight">
              Issues détectés
            </h2>
            <ul className="space-y-1.5 font-mono text-xs">
              {h.issues.map((i) => (
                <li
                  key={i}
                  className="rounded bg-surface-subtle px-2.5 py-1.5 text-foreground"
                >
                  {i}
                </li>
              ))}
            </ul>
          </section>
        )}
      </main>
    </>
  );
}

type Axis = {
  title: string;
  status: "healthy" | "degraded" | "critical";
  lines: [string, string][];
  note?: string;
};

function AxisCard({ axis }: { axis: Axis }) {
  return (
    <div className="rounded-lg border border-border bg-surface p-5 shadow-xs">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="font-heading text-sm font-medium tracking-tight">
          {axis.title}
        </h3>
        <StatusPill status={axis.status} />
      </div>
      <dl className="space-y-2 text-sm">
        {axis.lines.map(([k, v]) => (
          <div key={k} className="flex items-baseline justify-between gap-4">
            <dt className="text-muted-foreground">{k}</dt>
            <dd className="font-mono text-xs tabular-nums text-foreground">
              {v}
            </dd>
          </div>
        ))}
      </dl>
      {axis.note && (
        <p className="mt-4 border-t border-[var(--border-subtle)] pt-3 font-mono text-xs text-muted-foreground">
          {axis.note}
        </p>
      )}
    </div>
  );
}

function snapshotStatus(h: number | null): Axis["status"] {
  if (h == null) return "critical";
  if (h > 36) return "critical";
  if (h > 25) return "degraded";
  return "healthy";
}
function cronStatus(s: string | null, h: number | null): Axis["status"] {
  if (s !== "succeeded") return "critical";
  if (h != null && h > 25) return "critical";
  return "healthy";
}
function ingestStatus(m: number | null): Axis["status"] {
  if (m == null) return "critical";
  if (m > 360) return "critical";
  if (m > 60) return "degraded";
  return "healthy";
}
function gscStatus(
  dataAge: number | null,
  ingestAge: number | null
): Axis["status"] {
  if (dataAge == null) return "critical";
  if (dataAge > 7 || (ingestAge != null && ingestAge > 72)) return "critical";
  if (dataAge > 4 || (ingestAge != null && ingestAge > 30)) return "degraded";
  return "healthy";
}
