import { cn } from "@/lib/cn";
import type { Delta } from "@/lib/format";

export interface KpiItem {
  label: string;
  value: string;
  delta?: Delta;
  hint?: string;
}

function DeltaTag({ delta }: { delta: Delta }) {
  if (delta.dir === "na") return <span className="text-xs text-neutral-400">—</span>;
  const cls =
    delta.dir === "up"
      ? "text-emerald-600 dark:text-emerald-400"
      : delta.dir === "down"
        ? "text-red-600 dark:text-red-400"
        : "text-neutral-500";
  const glyph = delta.dir === "up" ? "▲" : delta.dir === "down" ? "▼" : "▬";
  return (
    <span className={cn("text-xs font-medium", cls)}>
      {glyph} {delta.label}
    </span>
  );
}

export function KpiHeader({ items }: { items: KpiItem[] }) {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      {items.map((it) => (
        <div
          key={it.label}
          className="rounded-xl border border-neutral-200 bg-white p-4 dark:border-neutral-800 dark:bg-neutral-950"
        >
          <div className="text-2xl font-semibold tracking-tight tabular-nums text-neutral-900 dark:text-neutral-100">
            {it.value}
          </div>
          <div className="mt-1 flex items-center justify-between gap-2">
            <span className="text-[11px] uppercase tracking-wide text-neutral-500">{it.label}</span>
            {it.delta && <DeltaTag delta={it.delta} />}
          </div>
          {it.hint && <div className="mt-1 text-[10px] text-neutral-400">{it.hint}</div>}
        </div>
      ))}
    </div>
  );
}
