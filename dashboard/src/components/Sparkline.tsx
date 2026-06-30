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
  const w = 120;
  const h = 28;
  const pad = 3;
  const min = Math.min(...series);
  const max = Math.max(...series);
  const span = max - min || 1;
  const X = (i: number) => pad + (i * (w - 2 * pad)) / (series.length - 1);
  const Y = (v: number) => h - pad - ((v - min) / span) * (h - 2 * pad);
  const line =
    "M" + series.map((v, i) => `${X(i).toFixed(1)} ${Y(v).toFixed(1)}`).join(" L");
  const lastX = X(series.length - 1);
  const lastY = Y(series[series.length - 1]);

  return (
    <div className="relative mt-3">
      <div className="absolute inset-x-0 bottom-0 h-px bg-[#ececea]" />
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
