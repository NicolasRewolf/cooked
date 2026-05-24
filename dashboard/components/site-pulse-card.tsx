import {
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  Minus,
  TrendingDown,
  TrendingUp,
} from "lucide-react";
import { InfoLabel } from "@/components/info-label";
import { formatDateFR, formatInt, formatNumber } from "@/lib/format";
import type { PulseQuadrant, SitePulse } from "@/lib/cooked";
import {
  QUADRANT_HEADLINE,
  QUADRANT_STYLE,
  QUADRANT_TEXT,
} from "@/lib/pulse-quadrant";
import { cn } from "@/lib/utils";

export function SitePulseCard({ pulse }: { pulse: SitePulse }) {
  const periodLabel = pulse.period_label_fr ?? "période sélectionnée";

  return (
    <div
      className={cn(
        "rounded-lg border p-5 shadow-xs",
        QUADRANT_STYLE[pulse.quadrant]
      )}
    >
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
            <InfoLabel
              label={`Pulse — ${periodLabel}`}
              hint={`Cross-source : trafic Google (${periodLabel}) vs période précédente équivalente, croisé avec le comportement Cooked sur la même fenêtre. Seuil ±5 % par axe.`}
            />
          </div>
          <h2
            className={cn(
              "mt-2 font-heading text-2xl font-medium tracking-tight",
              QUADRANT_TEXT[pulse.quadrant]
            )}
          >
            {QUADRANT_HEADLINE[pulse.quadrant]}
          </h2>
        </div>
        <QuadrantIconLarge quadrant={pulse.quadrant} />
      </div>

      <div className="mt-5 grid gap-3 md:grid-cols-2">
        <AxisLine
          label="Clics Google"
          n={pulse.gsc_clicks_n}
          prev={pulse.gsc_clicks_prev}
          deltaPct={pulse.gsc_delta_pct}
          subtitle={`${formatDateFR(pulse.gsc_period_start)} → ${formatDateFR(pulse.gsc_period_end)}`}
        />
        <AxisLine
          label="Visites Cooked"
          n={pulse.cooked_sessions_n}
          prev={pulse.cooked_sessions_prev}
          deltaPct={pulse.cooked_sessions_delta_pct}
          subtitle={`${formatDateFR(pulse.cooked_period_start)} → ${formatDateFR(pulse.cooked_period_end)}`}
        />
      </div>
    </div>
  );
}

function AxisLine({
  label,
  n,
  prev,
  deltaPct,
  subtitle,
}: {
  label: string;
  n: number;
  prev: number | null;
  deltaPct: number | null;
  subtitle: string;
}) {
  return (
    <div className="rounded-md border border-border bg-surface/60 p-3">
      <div className="font-mono text-[10px] uppercase tracking-wide text-muted-foreground">
        {label}
      </div>
      <div className="mt-1 flex items-baseline gap-2">
        <span className="font-mono text-xl tabular-nums tracking-tight text-foreground">
          {formatInt(n)}
        </span>
        <DeltaInline deltaPct={deltaPct} />
      </div>
      <div className="mt-1 font-mono text-[10px] text-muted-foreground">
        vs {prev == null ? "—" : formatInt(prev)} · {subtitle}
      </div>
    </div>
  );
}

function DeltaInline({ deltaPct }: { deltaPct: number | null }) {
  if (deltaPct == null) {
    return <span className="font-mono text-xs text-muted-foreground">—</span>;
  }
  const Icon =
    deltaPct >= 5
      ? ArrowUpRight
      : deltaPct <= -5
        ? ArrowDownRight
        : ArrowRight;
  const tone =
    deltaPct >= 5
      ? "text-success"
      : deltaPct <= -5
        ? "text-danger"
        : "text-muted-foreground";

  return (
    <span
      className={cn(
        "inline-flex items-center gap-0.5 font-mono text-xs tabular-nums",
        tone
      )}
    >
      <Icon className="h-3 w-3" aria-hidden="true" />
      {deltaPct > 0 ? "+" : ""}
      {formatNumber(deltaPct, 1)} %
    </span>
  );
}

function QuadrantIconLarge({ quadrant }: { quadrant: PulseQuadrant }) {
  const cls = cn("h-8 w-8", QUADRANT_TEXT[quadrant]);
  switch (quadrant) {
    case "up_up":
      return <TrendingUp className={cls} aria-hidden="true" />;
    case "down_down":
      return <TrendingDown className={cls} aria-hidden="true" />;
    case "up_down":
      return <ArrowUpRight className={cls} aria-hidden="true" />;
    case "down_up":
      return <ArrowDownRight className={cls} aria-hidden="true" />;
    case "neutral":
    case "no_signal":
      return <Minus className={cls} aria-hidden="true" />;
  }
}
