import { formatDateFR } from "@/lib/format";
import type { DataLens } from "@/lib/data-lens";

export function DateBanner({
  periodStart,
  periodEnd,
  periodLabel,
  lens,
  gscLastDay,
  gscDataAgeDays,
}: {
  periodStart: string | null;
  periodEnd: string | null;
  periodLabel?: string;
  lens: DataLens;
  gscLastDay: string | null;
  gscDataAgeDays: number | null;
}) {
  const lag =
    gscLastDay && gscDataAgeDays != null
      ? `J-${Math.round(gscDataAgeDays)}`
      : null;

  const rightLabel =
    lens === "live"
      ? gscLastDay && lag
        ? `Google consolidé au ${formatDateFR(gscLastDay)} (${lag}) — hors zone`
        : "Zone Cooked · à jour"
      : lens === "gsc"
        ? gscLastDay && lag
          ? `Consolidé au ${formatDateFR(gscLastDay)} · retard ${lag}`
          : "GSC indisponible"
        : gscLastDay && lag
          ? `Fenêtre alignée Google · retard ${lag}`
          : "Croisement";

  const leftPrefix =
    lens === "live"
      ? "Activité site"
      : lens === "gsc"
        ? "Google Search Console"
        : "Croisement Cooked × Google";

  return (
    <div className="border-b border-border bg-surface-subtle/40 font-mono text-xs text-muted-foreground">
      <div className="mx-auto flex h-9 max-w-6xl items-center justify-between gap-4 px-6">
        <span>
          {periodStart && periodEnd ? (
            <>
              {leftPrefix}{" "}
              <span className="text-foreground">
                {formatDateFR(periodStart)} → {formatDateFR(periodEnd)}
              </span>
              {periodLabel ? (
                <>
                  {" "}
                  · <span className="text-foreground">{periodLabel}</span>
                </>
              ) : null}{" "}
              · Paris
            </>
          ) : (
            "Période indisponible"
          )}
        </span>
        <span className="shrink-0 text-right">{rightLabel}</span>
      </div>
    </div>
  );
}
