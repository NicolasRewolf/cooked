"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type { DataLens } from "@/lib/data-lens";
import {
  PERIOD_KINDS,
  type PeriodKind,
  periodLabel,
  periodSelectorHint,
} from "@/lib/period";
import { usePeriodFromUrl } from "@/lib/use-period-from-url";
import { cn } from "@/lib/utils";

type Props = { lens: DataLens };

/** Sélecteur de période — libellés selon la zone (live vs GSC vs croisement). */
export function PeriodSelector({ lens }: Props) {
  const pathname = usePathname();
  const router = useRouter();
  const searchParams = useSearchParams();
  const current = usePeriodFromUrl();
  const hint = periodSelectorHint(lens);

  function setPeriod(kind: PeriodKind) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("period", kind);
    router.push(`${pathname}?${params.toString()}`);
  }

  const tablistLabel =
    lens === "live"
      ? "Période d'analyse — activité site"
      : lens === "gsc"
        ? "Période d'analyse — Google Search Console"
        : "Période d'analyse — croisement Cooked × Google";

  return (
    <div className="space-y-2">
      <p className="font-mono text-[10px] uppercase tracking-wider text-muted-foreground">
        Période
      </p>
      <div
        className="flex flex-wrap items-center gap-1 rounded-md border border-border bg-canvas/80 p-0.5"
        role="tablist"
        aria-label={tablistLabel}
      >
        {PERIOD_KINDS.map((kind) => (
          <button
            key={kind}
            type="button"
            role="tab"
            aria-selected={current === kind}
            title={periodLabel(kind, lens)}
            onClick={() => setPeriod(kind)}
            className={cn(
              "rounded px-2.5 py-1 font-mono text-xs transition-colors",
              current === kind
                ? "bg-surface text-foreground shadow-xs"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            {periodLabel(kind, lens)}
          </button>
        ))}
      </div>
      {hint ? (
        <p className="text-xs text-muted-foreground">{hint}</p>
      ) : null}
    </div>
  );
}
