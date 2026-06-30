import { cn } from "@/lib/cn";
import type { Delta } from "@/lib/format";

// Flèche de tendance par ligne (visiteurs/clics vs période précédente).
// Vert = hausse (bien), rouge = baisse, gris = stable / pas de base de comparaison.
export function Trend({ d }: { d: Delta }) {
  if (d.dir === "na") return <span className="text-[11px] text-neutral-300 dark:text-neutral-600">—</span>;
  const cls =
    d.dir === "up"
      ? "text-emerald-600 dark:text-emerald-400"
      : d.dir === "down"
        ? "text-red-600 dark:text-red-400"
        : "text-neutral-400";
  const glyph = d.dir === "up" ? "▲" : d.dir === "down" ? "▼" : "▬";
  return (
    <span className={cn("text-[11px] font-medium tabular-nums", cls)} title="vs période précédente">
      {glyph} {d.label}
    </span>
  );
}

export function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="mb-3 text-xs font-semibold uppercase tracking-widest text-neutral-500">
      {children}
    </h2>
  );
}

export function Badge({
  children,
  tone = "neutral",
}: {
  children: React.ReactNode;
  tone?: "neutral" | "good" | "warn" | "info";
}) {
  const tones: Record<string, string> = {
    neutral: "bg-neutral-100 text-neutral-700 dark:bg-neutral-800 dark:text-neutral-300",
    good: "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300",
    warn: "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300",
    info: "bg-sky-100 text-sky-800 dark:bg-sky-950 dark:text-sky-300",
  };
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium",
        tones[tone],
      )}
    >
      {children}
    </span>
  );
}

export function ConfidenceBadge({ grade }: { grade: "A" | "B" | "C" }) {
  const tone = grade === "A" ? "good" : grade === "B" ? "info" : "neutral";
  const title =
    grade === "A" ? "Fiable" : grade === "B" ? "Indicatif" : "Faible volume — pas de verdict";
  return (
    <span title={title}>
      <Badge tone={tone}>{grade}</Badge>
    </span>
  );
}
