import { cn } from "@/lib/cn";
import type { Delta } from "@/lib/format";
import { Sparkline } from "./Sparkline";

export interface KpiItem {
  label: string;
  value: string;
  delta?: Delta;
  hint?: string;
  /** Série journalière optionnelle (sparkline). Absente ⇒ pas de sparkline.
   *  Voir HANDOFF.md : nécessite un RPC renvoyant la série par métrique. */
  series?: number[];
}

function DeltaTag({ delta }: { delta: Delta }) {
  if (delta.dir === "na") return <span className="font-mono text-[11.5px] text-faint">—</span>;
  const cls = delta.dir === "up" ? "text-up" : delta.dir === "down" ? "text-down" : "text-faint";
  const glyph = delta.dir === "up" ? "▲" : delta.dir === "down" ? "▼" : "▬";
  return (
    <span className={cn("font-mono text-[11.5px] font-medium", cls)}>
      {glyph} {delta.label} <span className="text-dim">N-1</span>
    </span>
  );
}

// Grappe d'instruments : une rangée, chiffres mono, séparateurs filaires.
export function KpiHeader({ items }: { items: KpiItem[] }) {
  return (
    <div className="flex flex-wrap border border-line bg-panel">
      {items.map((it) => (
        <div
          key={it.label}
          className="min-w-[150px] flex-1 border-l border-[#efefed] px-[17px] pb-[13px] pt-[15px] first:border-l-0"
        >
          <div className="min-h-6 text-[10px] font-medium uppercase tracking-[0.07em] text-faint">
            {it.label}
          </div>
          <div className="mt-2.5 font-mono text-[25px] font-semibold tracking-[-0.02em] text-ink">
            {it.value}
          </div>
          {it.delta && <div className="mt-[7px]">{<DeltaTag delta={it.delta} />}</div>}
          {it.hint && <div className="mt-2 font-mono text-[10px] text-dim">{it.hint}</div>}
          <Sparkline series={it.series} />
        </div>
      ))}
    </div>
  );
}
