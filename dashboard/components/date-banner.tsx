import { formatDateFR } from "@/lib/format";

export function DateBanner({
  periodStart,
  periodEnd,
  periodLabel,
  gscLastDay,
  gscDataAgeDays,
}: {
  periodStart: string | null;
  periodEnd: string | null;
  periodLabel?: string;
  gscLastDay: string | null;
  gscDataAgeDays: number | null;
}) {
  const gscLabel =
    gscLastDay && gscDataAgeDays != null
      ? `GSC à J-${Math.round(gscDataAgeDays)} (${formatDateFR(gscLastDay)})`
      : "GSC indisponible";

  return (
    <div className="border-b border-border bg-surface-subtle/40 font-mono text-xs text-muted-foreground">
      <div className="mx-auto flex h-9 max-w-6xl items-center justify-between px-6">
        <span>
          {periodStart && periodEnd ? (
            <>
              Données{" "}
              <span className="text-foreground">
                {formatDateFR(periodStart)} → {formatDateFR(periodEnd)}
              </span>
              {periodLabel ? (
                <>
                  {" "}
                  · <span className="text-foreground">{periodLabel}</span>
                </>
              ) : null}{" "}
              · heure Paris
            </>
          ) : (
            "Période indisponible"
          )}
        </span>
        <span>{gscLabel}</span>
      </div>
    </div>
  );
}
