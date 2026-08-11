import { cn } from "@/lib/cn";
import { num, type Delta } from "@/lib/format";
import { Sparkline } from "./Sparkline";
import { Info } from "./Info";
import { dirClass, dirGlyph } from "./ui";

// M4 — bornes discrètes de la sparkline en title natif (DONNÉE, pas définition →
// la règle « pas d'ⓘ pour de la donnée » de M1 ne s'applique pas). Posé ICI, sur
// le conteneur rendu par KpiHeader — surtout PAS dans Sparkline, pour laisser
// intactes les sparklines de tableau (CpiHealthPanel).
function sparkTitle(series?: number[]): string | undefined {
  if (!series || series.length < 2) return undefined;
  return `min ${num(Math.min(...series))} · max ${num(Math.max(...series))} · ${series.length} j`;
}

export interface KpiItem {
  label: string;
  value: string;
  delta?: Delta;
  hint?: string;
  /** Infobulle explicative au survol de la carte (ex. définition des « contacts »). */
  tooltip?: string;
  /** Série journalière optionnelle (sparkline). Absente ⇒ pas de sparkline.
   *  Voir HANDOFF.md : nécessite un RPC renvoyant la série par métrique. */
  series?: number[];
}

function DeltaTag({ delta }: { delta: Delta }) {
  if (delta.dir === "na") return <span className="font-mono text-[11.5px] text-faint">—</span>;
  return (
    <span className={cn("font-mono text-[11.5px] font-medium", dirClass(delta.dir))}>
      {dirGlyph(delta.dir)} {delta.label} <span className="text-dim">N-1</span>
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
          className="min-w-[150px] flex-1 border-l border-line-soft px-[17px] pb-[13px] pt-[15px] first:border-l-0"
        >
          <div className="flex min-h-6 items-center gap-1 text-[10px] font-medium uppercase tracking-[0.07em] text-faint">
            <span>{it.label}</span>
            {it.tooltip ? <Info>{it.tooltip}</Info> : null}
          </div>
          <div className="mt-2.5 font-mono text-[25px] font-semibold tracking-[-0.02em] text-ink">
            {it.value}
          </div>
          {it.delta && <div className="mt-[7px]">{<DeltaTag delta={it.delta} />}</div>}
          {it.hint && <div className="mt-2 font-mono text-[10px] text-dim">{it.hint}</div>}
          {it.series && it.series.length >= 2 ? (
            <div title={sparkTitle(it.series)}>
              <Sparkline series={it.series} />
            </div>
          ) : (
            <Sparkline series={it.series} />
          )}
        </div>
      ))}
    </div>
  );
}
