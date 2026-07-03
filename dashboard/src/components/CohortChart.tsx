import type { Cohort } from "@/lib/types";

// B3 — cohortes du contrat : clics GSC cumulés moyens PAR ARTICLE, alignés sur l'âge.
// Données PLATES (tableau de cohortes). Cohorte en cours = trait plein accent ;
// précédentes en nuances grises (plus ancien = plus clair).

const MOIS = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];
function moisFr(ym: string): string {
  const m = parseInt(ym.slice(5, 7), 10);
  return MOIS[m - 1] ?? ym;
}
function greyFor(i: number, n: number): string {
  // i in [0, n-2] (les cohortes non-courantes) : plus ancien (i petit) = plus clair.
  const t = n > 2 ? i / (n - 2) : 0;
  const l = Math.round(205 - t * 65);
  return `rgb(${l},${l},${l})`;
}

export function CohortChart({ cohorts }: { cohorts: Cohort[] }) {
  const shown = cohorts.filter((c) => c.series && c.series.length >= 1);
  if (shown.length === 0) return null;

  const w = 820, h = 190, pl = 4, pr = 4, pt = 12, pb = 16;
  const maxAge = 60;
  const maxY = Math.max(1, ...shown.map((c) => (c.series.length ? Math.max(...c.series) : 0)));
  const X = (age: number) => pl + (age / maxAge) * (w - pl - pr);
  const Y = (v: number) => h - pb - (v / maxY) * (h - pt - pb);
  const n = shown.length;
  const midY = (pt + (h - pb)) / 2;

  return (
    <div className="mt-[18px] border border-line bg-panel">
      <div className="flex items-center justify-between gap-4 border-b border-[#efefed] px-4 py-3">
        <h2 className="text-[12px] font-semibold text-ink">Cohortes du contrat</h2>
        <span className="font-mono text-[10.5px] text-faint">
          clics Google cumulés moyens / article · aligné sur l&apos;âge (J0 = 1re impression)
        </span>
      </div>
      <div className="flex">
        <div className="flex flex-col justify-between py-3 pl-3.5 pr-2.5 text-right font-mono text-[9.5px] text-dim">
          <span>{Math.round(maxY)}</span>
          <span>·</span>
          <span>0</span>
        </div>
        <div className="flex-1 py-1.5 pr-4">
          <svg
            viewBox={`0 0 ${w} ${h}`}
            preserveAspectRatio="none"
            style={{ width: "100%", height: 180, display: "block", overflow: "visible" }}
          >
            <line x1="0" x2={w} y1={pt} y2={pt} stroke="#efefed" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            <line x1="0" x2={w} y1={midY} y2={midY} stroke="#efefed" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            <line x1="0" x2={w} y1={h - pb} y2={h - pb} stroke="#e2e2e0" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            {[15, 30, 45].map((a) => (
              <line key={a} x1={X(a)} x2={X(a)} y1={pt} y2={h - pb} stroke="#f1f1ef" strokeWidth="1" strokeDasharray="2 4" vectorEffect="non-scaling-stroke" />
            ))}
            {shown.map((c, i) => {
              const isCur = i === n - 1;
              const color = isCur ? "var(--color-accent)" : greyFor(i, n);
              if (c.series.length < 2) {
                return <circle key={c.month} cx={X(0)} cy={Y(c.series[0] ?? 0)} r="2.2" fill={color} />;
              }
              const d = "M" + c.series.map((v, age) => `${X(age).toFixed(1)} ${Y(v).toFixed(1)}`).join(" L");
              return (
                <path
                  key={c.month}
                  d={d}
                  fill="none"
                  stroke={color}
                  strokeWidth={isCur ? 1.8 : 1.1}
                  strokeLinejoin="round"
                  strokeLinecap="round"
                  vectorEffect="non-scaling-stroke"
                />
              );
            })}
          </svg>
        </div>
      </div>
      <div className="flex justify-between px-4 pb-2 pl-[50px] font-mono text-[9.5px] text-dim">
        <span>J0</span>
        <span>J+15</span>
        <span>J+30</span>
        <span>J+45</span>
        <span>J+60</span>
      </div>
      <div className="flex flex-wrap gap-x-3 gap-y-1 border-t border-[#efefed] px-4 py-2.5 font-mono text-[10.5px]">
        {shown.map((c, i) => {
          const isCur = i === n - 1;
          const color = isCur ? "var(--color-accent)" : greyFor(i, n);
          return (
            <span key={c.month} className="inline-flex items-center gap-1.5">
              <span
                aria-hidden
                style={{ display: "inline-block", width: 14, borderTop: `${isCur ? 2 : 1.5}px solid ${color}` }}
              />
              <span className={isCur ? "font-semibold text-ink" : "text-muted"}>
                {moisFr(c.month)} ({c.n_articles})
              </span>
            </span>
          );
        })}
      </div>
    </div>
  );
}
