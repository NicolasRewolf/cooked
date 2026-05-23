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
import { cn } from "@/lib/utils";

/**
 * Carte Pulse site-wide pour la home.
 * Affiche le quadrant global + 2 axes chiffrés (GSC 28v28 et Cooked 7v7).
 */

const QUADRANT_HEADLINE: Record<PulseQuadrant, string> = {
  up_up: "La machine tourne",
  up_down: "Trafic ↗ mais engagement ↘",
  down_up: "Audience plus qualifiée",
  down_down: "Perte de vitesse",
  neutral: "Période stable",
  no_signal: "Pas assez de signal",
};

const QUADRANT_STYLE: Record<PulseQuadrant, string> = {
  up_up: "border-success/30 bg-success/5",
  up_down: "border-warning/30 bg-warning/5",
  down_up: "border-info/30 bg-info/5",
  down_down: "border-danger/30 bg-danger/5",
  neutral: "border-border bg-surface",
  no_signal: "border-border bg-surface",
};

const QUADRANT_TEXT: Record<PulseQuadrant, string> = {
  up_up: "text-success",
  up_down: "text-warning",
  down_up: "text-info",
  down_down: "text-danger",
  neutral: "text-muted-foreground",
  no_signal: "text-muted-foreground",
};

export function SitePulseCard({ pulse }: { pulse: SitePulse }) {
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
              label="Pulse de la semaine"
              hint="Cross-source : direction globale du trafic Google (28 j vs 28 j précédents) croisée avec le comportement Cooked (visites 7 j vs 7 j précédents). Seuil ±5 % par axe."
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
          subtitle={`28 j · ${formatDateFR(pulse.gsc_period_start)} → ${formatDateFR(pulse.gsc_period_end)}`}
        />
        <AxisLine
          label="Visites Cooked"
          n={pulse.cooked_sessions_n}
          prev={pulse.cooked_sessions_prev}
          deltaPct={pulse.cooked_sessions_delta_pct}
          subtitle={`7 j · ${formatDateFR(pulse.cooked_period_start)} → ${formatDateFR(pulse.cooked_period_end)}`}
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
        vs {prev == null ? "—" : formatInt(prev)} {subtitle}
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
