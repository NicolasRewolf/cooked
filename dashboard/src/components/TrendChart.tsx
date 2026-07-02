import { num } from "@/lib/format";

// Graphe principal « oscilloscope » : grille fine + tracé accent + point final.
// `series` = une valeur / jour sur la période. Vide ⇒ le composant ne rend rien
// (la page masque alors le bloc). Voir HANDOFF.md pour le RPC à ajouter.
//
// La série est ancrée sur J-1 (dernier jour réellement couvert) : le point final
// n'est PAS « aujourd'hui » mais le dernier jour clos. `lastDay` (ISO du dernier
// jour couvert) permet d'afficher « au JJ/MM » sous le point final au lieu d'un
// « auj. » trompeur.
export function TrendChart({
  series,
  label,
  lastDay,
}: {
  series?: number[] | null;
  label: string;
  lastDay?: string | null;
}) {
  if (!series || series.length < 2) return null;
  const w = 820;
  const h = 170;
  const pl = 4;
  const pr = 4;
  const pt = 10;
  const pb = 14;
  const n = series.length;
  const min = Math.min(...series);
  const max = Math.max(...series);
  const span = max - min || 1;
  const X = (i: number) => pl + (i * (w - pl - pr)) / (n - 1);
  const Y = (v: number) => h - pb - ((v - min) / span) * (h - pt - pb);
  const pts = series.map((v, i) => `${X(i).toFixed(1)} ${Y(v).toFixed(1)}`);
  const line = "M" + pts.join(" L");
  const area = `${line} L${X(n - 1).toFixed(1)} ${h - pb} L${X(0).toFixed(1)} ${h - pb} Z`;
  const lastX = X(n - 1);
  const lastY = Y(series[n - 1]);

  // Libellés d'axe X dérivés de la longueur réelle de la série (positions
  // proportionnelles), jamais codés en dur : 3 jalons « −Nj » régulièrement
  // espacés du plus ancien au 1er tiers/2e tiers, puis le dernier jour couvert.
  // Ex. n=90 ⇒ −90j / −60j / −30j ; n=28 ⇒ −28j / −19j / −9j.
  const xLabels = [
    `−${n}j`,
    `−${Math.round((n * 2) / 3)}j`,
    `−${Math.round(n / 3)}j`,
    lastDayLabel(lastDay),
  ];

  return (
    <div className="mt-[18px] border border-line bg-panel">
      <div className="flex items-center justify-between gap-4 border-b border-[#efefed] px-4 py-3">
        <h2 className="text-[12px] font-semibold text-ink">{label}</h2>
        <span className="font-mono text-[10.5px] text-faint">
          max {num(max)} · min {num(min)} · n={n} j
        </span>
      </div>
      <div className="flex">
        <div className="flex flex-col justify-between py-3 pl-3.5 pr-2.5 text-right font-mono text-[9.5px] text-dim">
          <span>{num(max)}</span>
          <span>·</span>
          <span>{num(min)}</span>
        </div>
        <div className="flex-1 py-1.5 pr-4">
          <svg
            viewBox={`0 0 ${w} ${h}`}
            preserveAspectRatio="none"
            style={{ width: "100%", height: 168, display: "block", overflow: "visible" }}
          >
            <line x1="0" x2={w} y1="12" y2="12" stroke="#efefed" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            <line x1="0" x2={w} y1="84" y2="84" stroke="#efefed" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            <line x1="0" x2={w} y1="156" y2="156" stroke="#e2e2e0" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            {[205, 410, 615].map((x) => (
              <line key={x} x1={x} x2={x} y1="4" y2="156" stroke="#f1f1ef" strokeWidth="1" strokeDasharray="2 4" vectorEffect="non-scaling-stroke" />
            ))}
            <path d={area} fill="var(--color-accent)" fillOpacity="0.06" />
            <path d={line} fill="none" stroke="var(--color-accent)" strokeWidth="1.4" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
            <circle cx={lastX} cy={lastY} r="2.6" fill="var(--color-accent)" />
          </svg>
        </div>
      </div>
      <div className="flex justify-between px-4 pb-2.5 pl-[50px] font-mono text-[9.5px] text-dim">
        {xLabels.map((t, i) => (
          <span key={i}>{t}</span>
        ))}
      </div>
    </div>
  );
}

// Dernier point = dernier jour réellement couvert (J-1), pas « aujourd'hui ».
// « au JJ/MM » quand la date est connue, sinon repli neutre.
function lastDayLabel(lastDay?: string | null): string {
  if (!lastDay) return "dern.";
  const [, m, d] = lastDay.slice(0, 10).split("-");
  if (!m || !d) return "dern.";
  return `au ${d}/${m}`;
}
