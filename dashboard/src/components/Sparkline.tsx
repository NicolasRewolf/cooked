import {
  buildLinePath,
  lastPoint,
  seriesExtent,
  xScaleIndex,
  yScale,
  type ChartBox,
} from "@/lib/chart-geometry";

// Sparkline « instrument » : tracé fin accent + point final, sur une ligne de base.
// Rendu vide si la série n'a pas (encore) de données — voir HANDOFF.md (RPC séries).
export function Sparkline({
  series,
  height = 26,
}: {
  series?: number[] | null;
  height?: number;
}) {
  if (!series || series.length < 2) return null;
  const box: ChartBox = { w: 120, h: 28, pl: 3, pr: 3, pt: 3, pb: 3 };
  const { w, h } = box;
  const { min, span } = seriesExtent(series);
  const X = xScaleIndex(box, series.length);
  const Y = yScale(box, min, span);
  const line = buildLinePath(series, X, Y);
  const { x: lastX, y: lastY } = lastPoint(series, X, Y);

  return (
    <div className="relative mt-3">
      <div className="absolute inset-x-0 bottom-0 h-px bg-line" />
      <svg
        viewBox={`0 0 ${w} ${h}`}
        preserveAspectRatio="none"
        style={{ width: "100%", height, display: "block", overflow: "visible" }}
      >
        <path
          d={line}
          fill="none"
          stroke="var(--color-accent)"
          strokeWidth={1.25}
          strokeLinejoin="round"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
        />
        <circle cx={lastX} cy={lastY} r={1.9} fill="var(--color-accent)" />
      </svg>
    </div>
  );
}
