import { cn } from "@/lib/cn";
import type { Delta } from "@/lib/format";

// Flèche de tendance par ligne (visiteurs / clics vs période précédente).
// Vert = hausse · rouge = baisse · gris = stable / pas de base. Chiffres en mono.
export function Trend({ d }: { d: Delta }) {
  if (d.dir === "na") return <span className="font-mono text-[10px] text-dim">—</span>;
  const cls =
    d.dir === "up" ? "text-up" : d.dir === "down" ? "text-down" : "text-faint";
  const glyph = d.dir === "up" ? "▲" : d.dir === "down" ? "▼" : "▬";
  return (
    <span className={cn("font-mono text-[10px] font-medium", cls)} title="vs période précédente">
      {glyph} {d.label}
    </span>
  );
}

export function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="mb-2.5 font-mono text-[11px] font-semibold uppercase tracking-[0.05em] text-muted">
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
    neutral: "bg-[#f0f0ee] text-muted",
    good: "bg-[#e6f0e9] text-up",
    warn: "bg-[#fbf0e0] text-warn",
    info: "bg-[#e7eef7] text-info",
  };
  return (
    <span
      className={cn(
        "inline-flex items-center px-[7px] py-[2px] font-mono text-[10px] font-medium",
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
