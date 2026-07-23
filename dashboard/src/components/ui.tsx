import { cn } from "@/lib/cn";
import type { Delta } from "@/lib/format";

// ── Vocabulaire delta unifié (▲ / ▼ / ▬) ──────────────────────────────────────
// Un seul foyer pour le glyphe et la couleur d'une direction — consommé par
// Trend (lignes de tableau), DeltaTag (KPI), PosTrend (position SEO) et les
// points momentum des cellules santé.
export type TrendDir = "up" | "down" | "flat";

export function dirGlyph(dir: TrendDir): string {
  return dir === "up" ? "▲" : dir === "down" ? "▼" : "▬";
}

export function dirClass(dir: TrendDir): string {
  return dir === "up" ? "text-up" : dir === "down" ? "text-down" : "text-faint";
}

// Point momentum (cellule santé) : la baisse est un avertissement (orange),
// pas une alerte rouge — palette bg-* distincte du texte des deltas.
export function dirDotClass(dir: TrendDir): string {
  return dir === "up" ? "bg-up" : dir === "down" ? "bg-warn" : "bg-faint";
}

// Flèche de tendance par ligne (visiteurs / clics vs période précédente).
// Vert = hausse · rouge = baisse · gris = stable / pas de base. Chiffres en mono.
export function Trend({ d }: { d: Delta }) {
  if (d.dir === "na") return <span className="font-mono text-[10px] text-dim">—</span>;
  return (
    <span className={cn("font-mono text-[10px] font-medium", dirClass(d.dir))} title="vs période précédente">
      {dirGlyph(d.dir)} {d.label}
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

export function ConfidenceBadge({ grade }: { grade: "S" | "A" | "B" | "C" }) {
  const tone =
    grade === "S" || grade === "A" ? "good" : grade === "B" ? "info" : "neutral";
  const title =
    grade === "S"
      ? "Fiabilité S — très fiable"
      : grade === "A"
        ? "Fiabilité A — fiable"
        : grade === "B"
          ? "Fiabilité B — indicatif"
          : "Fiabilité C — volume insuffisant, pas de verdict";
  return (
    <span title={title}>
      <Badge tone={tone}>{grade}</Badge>
    </span>
  );
}
