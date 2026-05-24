import { ArrowDownRight, ArrowRight, ArrowUpRight } from "lucide-react";
import { InfoLabel } from "@/components/info-label";
import { formatInt, formatNumber } from "@/lib/format";
import { cn } from "@/lib/utils";

type Tone = "neutral" | "positive";

export function KpiCard({
  label,
  hint,
  value,
  deltaPct,
  prevValue,
  prevPeriodLabel = "période précédente",
  unit,
  tone = "neutral",
  emphasis = false,
}: {
  label: string;
  hint: string;
  value: number | null;
  deltaPct: number | null;
  prevValue: number | null;
  /** Libellé court pour la comparaison N-1 (ex. « hier », « 28 j précédents ») */
  prevPeriodLabel?: string;
  unit?: string;
  tone?: Tone;
  emphasis?: boolean;
}) {
  return (
    <div
      className={cn(
        "rounded-lg border border-border bg-surface p-5 shadow-xs",
        emphasis && "md:p-6"
      )}
    >
      <div className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
        <InfoLabel label={label} hint={hint} />
      </div>

      <div
        className={cn(
          "mt-3 flex items-baseline gap-2 font-mono tabular-nums tracking-tight",
          emphasis ? "text-4xl" : "text-3xl",
          tone === "positive" && value != null && value > 0
            ? "text-success"
            : "text-foreground"
        )}
      >
        {value != null ? formatInt(value) : "—"}
        {unit && (
          <span className="text-base font-normal text-muted-foreground">
            {unit}
          </span>
        )}
      </div>

      <DeltaRow
        deltaPct={deltaPct}
        prevValue={prevValue}
        prevPeriodLabel={prevPeriodLabel}
      />
    </div>
  );
}

function DeltaRow({
  deltaPct,
  prevValue,
  prevPeriodLabel,
}: {
  deltaPct: number | null;
  prevValue: number | null;
  prevPeriodLabel: string;
}) {
  // Pas de N-1 disponible (tracker démarré récemment)
  if (deltaPct == null) {
    return (
      <p className="mt-2 font-mono text-xs text-muted-foreground">
        Période précédente :{" "}
        {prevValue == null ? "—" : formatInt(prevValue)} (pas assez d&apos;historique
        pour comparer)
      </p>
    );
  }

  const Icon =
    deltaPct > 0 ? ArrowUpRight : deltaPct < 0 ? ArrowDownRight : ArrowRight;
  const color =
    deltaPct > 0
      ? "text-success"
      : deltaPct < 0
        ? "text-danger"
        : "text-muted-foreground";

  return (
    <p
      className={cn(
        "mt-2 inline-flex items-center gap-1 font-mono text-xs",
        color
      )}
    >
      <Icon className="h-3 w-3" />
      <span>
        {deltaPct > 0 ? "+" : ""}
        {formatNumber(deltaPct, 1)} %
      </span>
      <span className="text-muted-foreground">
        vs {prevValue != null ? formatInt(prevValue) : "—"} ({prevPeriodLabel})
      </span>
    </p>
  );
}
