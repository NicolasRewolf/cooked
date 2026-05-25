"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { PERIOD_KINDS, type PeriodKind, periodLabel } from "@/lib/period";
import { usePeriodFromUrl } from "@/lib/use-period-from-url";
import { cn } from "@/lib/utils";

/** Sélecteur de période — affiché sous la zone active, pas dans la nav globale. */
export function PeriodSelector() {
  const pathname = usePathname();
  const router = useRouter();
  const searchParams = useSearchParams();
  const current = usePeriodFromUrl();

  function setPeriod(kind: PeriodKind) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("period", kind);
    router.push(`${pathname}?${params.toString()}`);
  }

  return (
    <div className="space-y-2">
      <p className="font-mono text-[10px] uppercase tracking-wider text-muted-foreground">
        Période
      </p>
      <div
        className="flex flex-wrap items-center gap-1 rounded-md border border-border bg-canvas/80 p-0.5"
        role="tablist"
        aria-label="Période d'analyse"
      >
        {PERIOD_KINDS.map((kind) => (
          <button
            key={kind}
            type="button"
            role="tab"
            aria-selected={current === kind}
            onClick={() => setPeriod(kind)}
            className={cn(
              "rounded px-2.5 py-1 font-mono text-xs transition-colors",
              current === kind
                ? "bg-surface text-foreground shadow-xs"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            {periodLabel(kind)}
          </button>
        ))}
      </div>
    </div>
  );
}
