import {
  ArrowDownRight,
  ArrowUpRight,
  Minus,
  TrendingDown,
  TrendingUp,
} from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import type { PagePulseRow, PulseQuadrant } from "@/lib/cooked";
import { formatInt, formatNumber } from "@/lib/format";
import { cn } from "@/lib/utils";

/**
 * Badge visuel pour le Pulse cross-source d'une page.
 *
 * 6 états (cf migration 20260524160000_pages_pulse.sql) :
 *   up_up      SEO ↗ comportement ↗ — la machine tourne
 *   up_down    SEO ↗ comportement ↘ — alerte UX (trafic monte, engagement baisse)
 *   down_up    SEO ↘ comportement ↗ — audience qualifiée qui reste
 *   down_down  SEO ↘ comportement ↘ — page en perte de vitesse
 *   neutral    deltas dans le seuil ±5 % sur les deux axes
 *   no_signal  volume nul sur un axe, ou pro-ratage Cooked
 *
 * Le tooltip révèle les deltas chiffrés + les volumes N et N-1 pour
 * permettre la lecture exacte (pas seulement le quadrant).
 */
const STYLES: Record<PulseQuadrant, { ring: string; text: string; label: string; emoji: string }> = {
  up_up: {
    ring: "bg-success/10 text-success ring-success/20",
    text: "text-success",
    label: "SEO ↗ engagement ↗",
    emoji: "↗",
  },
  up_down: {
    ring: "bg-warning/10 text-warning ring-warning/20",
    text: "text-warning",
    label: "SEO ↗ engagement ↘",
    emoji: "⚠",
  },
  down_up: {
    ring: "bg-info/10 text-info ring-info/15",
    text: "text-info",
    label: "SEO ↘ engagement ↗",
    emoji: "↘↗",
  },
  down_down: {
    ring: "bg-danger/10 text-danger ring-danger/20",
    text: "text-danger",
    label: "SEO ↘ engagement ↘",
    emoji: "↘",
  },
  neutral: {
    ring: "bg-surface-subtle text-muted-foreground ring-border",
    text: "text-muted-foreground",
    label: "Stable",
    emoji: "→",
  },
  no_signal: {
    ring: "bg-surface-subtle text-muted-foreground ring-border",
    text: "text-muted-foreground",
    label: "Pas de signal",
    emoji: "—",
  },
};

export function QuadrantBadge({ row }: { row: PagePulseRow | undefined }) {
  // Pas dans la map (paths sans data Pulse) — affiché comme no_signal silencieux
  if (!row) {
    return <NoSignalBadge label="Hors fenêtre Pulse" />;
  }

  const style = STYLES[row.quadrant];

  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <span
            className={cn(
              "inline-flex cursor-help items-center gap-1 rounded-md px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-wide ring-1 ring-inset",
              style.ring
            )}
            aria-label={style.label}
          >
            <QuadrantIcon quadrant={row.quadrant} />
            <span>{quadrantShortLabel(row.quadrant)}</span>
          </span>
        }
      />
      <TooltipContent
        side="top"
        className="max-w-xs text-left text-xs leading-relaxed"
      >
        <PulseTooltipBody row={row} />
      </TooltipContent>
    </Tooltip>
  );
}

function NoSignalBadge({ label }: { label: string }) {
  return (
    <span className="inline-flex items-center gap-1 rounded-md bg-surface-subtle px-1.5 py-0.5 font-mono text-[10px] uppercase tracking-wide text-muted-foreground ring-1 ring-inset ring-border">
      <Minus className="h-2.5 w-2.5" aria-hidden="true" />
      <span>{label}</span>
    </span>
  );
}

function QuadrantIcon({ quadrant }: { quadrant: PulseQuadrant }) {
  switch (quadrant) {
    case "up_up":
      return <TrendingUp className="h-3 w-3" aria-hidden="true" />;
    case "down_down":
      return <TrendingDown className="h-3 w-3" aria-hidden="true" />;
    case "up_down":
      return <ArrowUpRight className="h-3 w-3" aria-hidden="true" />;
    case "down_up":
      return <ArrowDownRight className="h-3 w-3" aria-hidden="true" />;
    case "neutral":
    case "no_signal":
      return <Minus className="h-2.5 w-2.5" aria-hidden="true" />;
  }
}

function quadrantShortLabel(quadrant: PulseQuadrant): string {
  switch (quadrant) {
    case "up_up":
      return "↗↗";
    case "up_down":
      return "↗↘";
    case "down_up":
      return "↘↗";
    case "down_down":
      return "↘↘";
    case "neutral":
      return "→";
    case "no_signal":
      return "—";
  }
}

function PulseTooltipBody({ row }: { row: PagePulseRow }) {
  const baseTitle = STYLES[row.quadrant].label;

  if (row.quadrant === "no_signal") {
    return (
      <div className="space-y-1.5">
        <p className="font-medium text-background">Pas assez de signal</p>
        <p className="text-background/80">
          Aucun clic Google ni session Cooked sur les fenêtres comparées, ou
          historique Cooked trop court pour pro-rater.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-1.5">
      <p className="font-medium text-background">{baseTitle}</p>
      <DeltaLine
        label="Clics Google (28 j vs 28 j-1)"
        n={row.gsc_clicks_n}
        prev={row.gsc_clicks_prev}
        deltaPct={row.gsc_delta_pct}
      />
      <DeltaLine
        label="Visites Cooked (7 j vs 7 j-1)"
        n={row.cooked_sessions_n}
        prev={row.cooked_sessions_prev}
        deltaPct={row.cooked_sessions_delta_pct}
      />
      <p className="text-[10px] uppercase tracking-wide text-background/50">
        Seuil ±5 % par axe · sous le seuil = stable
      </p>
    </div>
  );
}

function DeltaLine({
  label,
  n,
  prev,
  deltaPct,
}: {
  label: string;
  n: number;
  prev: number | null;
  deltaPct: number | null;
}) {
  const dir =
    deltaPct == null ? null : deltaPct >= 5 ? "up" : deltaPct <= -5 ? "down" : "flat";

  const dirText =
    dir === "up" ? "↗" : dir === "down" ? "↘" : dir === "flat" ? "→" : "";

  return (
    <p className="text-background/90">
      <span className="text-background/60">{label} : </span>
      <span className="tabular-nums">
        {formatInt(n)}
      </span>
      <span className="text-background/40">{" "}vs{" "}</span>
      <span className="tabular-nums">
        {prev == null ? "—" : formatInt(prev)}
      </span>
      {deltaPct != null && (
        <>
          <span className="text-background/40">{" — "}</span>
          <span className="tabular-nums">
            {deltaPct > 0 ? "+" : ""}
            {formatNumber(deltaPct, 1)} %{dirText}
          </span>
        </>
      )}
    </p>
  );
}
