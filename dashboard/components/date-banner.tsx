import { formatDateFR } from "@/lib/format";
import type { DataLens } from "@/lib/data-lens";

export function DateBanner({
  periodStart,
  periodEnd,
  periodLabel,
  lens,
  gscLastDay,
  gscDataAgeDays,
  compact = false,
}: {
  periodStart: string | null;
  periodEnd: string | null;
  periodLabel?: string;
  lens: DataLens;
  gscLastDay: string | null;
  gscDataAgeDays: number | null;
  /** Intégré sous la zone + période (pas une barre pleine largeur). */
  compact?: boolean;
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

  const range =
    periodStart && periodEnd ? (
      <>
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
    );

  if (compact) {
    return (
      <p className="font-mono text-xs text-muted-foreground">
        <span className="text-[10px] uppercase tracking-wider">Données </span>
        {range}
        <span className="text-muted-foreground/80"> — {rightLabel}</span>
      </p>
    );
  }

  return (
    <div className="border-b border-border bg-surface-subtle/40 font-mono text-xs text-muted-foreground">
      <div className="mx-auto flex h-9 max-w-6xl items-center justify-between gap-4 px-6">
        <span>{range}</span>
        <span className="shrink-0 text-right">{rightLabel}</span>
      </div>
    </div>
  );
}
