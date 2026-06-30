import { cn } from "@/lib/cn";

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
