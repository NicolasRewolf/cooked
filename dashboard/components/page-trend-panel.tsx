"use client";

import {
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip as RechartsTooltip,
} from "recharts";
import {
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  Minus,
  TrendingDown,
  TrendingUp,
} from "lucide-react";
import { formatDateFR, formatInt, formatNumber } from "@/lib/format";
import type {
  CookedDailyPoint,
  GscDailyPoint,
  PagePulseRow,
  PulseQuadrant,
} from "@/lib/cooked";
import { cn } from "@/lib/utils";

const QUADRANT_HEADLINE: Record<PulseQuadrant, string> = {
  up_up: "La page performe",
  up_down: "Trafic ↗ mais engagement ↘",
  down_up: "Audience plus qualifiée",
  down_down: "Page en perte de vitesse",
  neutral: "Stable",
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

const QUADRANT_LINE: Record<PulseQuadrant, string> = {
  up_up: "var(--success)",
  up_down: "var(--warning)",
  down_up: "var(--info)",
  down_down: "var(--danger)",
  neutral: "var(--muted-foreground)",
  no_signal: "var(--muted-foreground)",
};

export function PageTrendPanel({
  pulse,
  gscSeries,
  cookedSeries,
}: {
  pulse: PagePulseRow | null;
  gscSeries: GscDailyPoint[];
  cookedSeries: CookedDailyPoint[];
}) {
  // Sans pulse on n'affiche pas le panneau (page hors fenêtre Pulse)
  if (!pulse) return null;

  const lineColor = QUADRANT_LINE[pulse.quadrant];

  return (
    <section
      className={cn(
        "mt-8 rounded-lg border p-5 shadow-xs",
        QUADRANT_STYLE[pulse.quadrant]
      )}
    >
      <div className="grid gap-5 md:grid-cols-[auto_1fr_1fr] md:items-stretch">
        {/* Badge Pulse grand */}
        <div className="flex items-start gap-3 md:items-center">
          <QuadrantIconLarge quadrant={pulse.quadrant} />
          <div>
            <div className="font-mono text-[10px] uppercase tracking-wide text-muted-foreground">
              Tendance
            </div>
            <p
              className={cn(
                "font-heading text-base font-medium tracking-tight",
                QUADRANT_TEXT[pulse.quadrant]
              )}
            >
              {QUADRANT_HEADLINE[pulse.quadrant]}
            </p>
          </div>
        </div>

        {/* Sparkline GSC 56j */}
        <Sparkline
          label="Clics Google · 56 j"
          dataKey="clicks"
          data={gscSeries}
          n={pulse.gsc_clicks_n}
          prev={pulse.gsc_clicks_prev}
          deltaPct={pulse.gsc_delta_pct}
          windowLabel="28 j vs 28 j-1"
          color={lineColor}
        />

        {/* Sparkline Cooked 14j */}
        <Sparkline
          label="Visites Cooked · 14 j"
          dataKey="sessions"
          data={cookedSeries}
          n={pulse.cooked_sessions_n}
          prev={pulse.cooked_sessions_prev}
          deltaPct={pulse.cooked_sessions_delta_pct}
          windowLabel="7 j vs 7 j-1"
          color={lineColor}
        />
      </div>
    </section>
  );
}

function Sparkline({
  label,
  data,
  dataKey,
  n,
  prev,
  deltaPct,
  windowLabel,
  color,
}: {
  label: string;
  data: Array<{ day: string } & Record<string, unknown>>;
  dataKey: string;
  n: number;
  prev: number | null;
  deltaPct: number | null;
  windowLabel: string;
  color: string;
}) {
  return (
    <div className="rounded-md border border-border bg-surface/60 p-3">
      <div className="flex items-baseline justify-between gap-2">
        <span className="font-mono text-[10px] uppercase tracking-wide text-muted-foreground">
          {label}
        </span>
        <DeltaInline deltaPct={deltaPct} />
      </div>

      <div className="mt-1 font-mono text-xl tabular-nums tracking-tight text-foreground">
        {formatInt(n)}
        <span className="ml-2 font-mono text-[10px] font-normal text-muted-foreground">
          vs {prev == null ? "—" : formatInt(prev)} · {windowLabel}
        </span>
      </div>

      <div className="mt-2 h-12">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 4, right: 4, bottom: 4, left: 4 }}>
            <RechartsTooltip
              content={<SparklineTooltip dataKey={dataKey} />}
              cursor={{ stroke: "var(--muted-foreground)", strokeOpacity: 0.2 }}
            />
            <Line
              type="monotone"
              dataKey={dataKey}
              stroke={color}
              strokeWidth={1.5}
              dot={false}
              isAnimationActive={false}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

function SparklineTooltip({
  active,
  payload,
  label,
  dataKey,
}: {
  active?: boolean;
  payload?: Array<{ value: number }>;
  label?: string;
  dataKey: string;
}) {
  if (!active || !payload || !payload[0] || !label) return null;
  const v = payload[0].value;
  return (
    <div className="rounded bg-foreground px-2 py-1 font-mono text-[10px] tabular-nums text-background shadow-md">
      <div>{formatDateFR(label)}</div>
      <div className="text-background/70">
        {formatInt(v)} {dataKey === "clicks" ? "clic" : "visite"}
        {v > 1 ? "s" : ""}
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
  const cls = cn("h-10 w-10", QUADRANT_TEXT[quadrant]);
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
