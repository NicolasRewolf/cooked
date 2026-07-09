"use client";

import { useState } from "react";
import { num } from "@/lib/format";
import { jjmmForIndex, lastDayLabel } from "@/lib/dates";
import { linearTrend } from "@/lib/trend-math";
import type { TrendMarker } from "@/lib/types";

// Graphe principal « oscilloscope » : grille fine + tracé accent + point final.
// `series` = une valeur / jour sur la période. Vide ⇒ le composant ne rend rien
// (la page masque alors le bloc).
//
// La série est ancrée sur J-1 (dernier jour réellement couvert) : le point final
// n'est PAS « aujourd'hui » mais le dernier jour clos. `lastDay` (ISO du dernier
// jour couvert) sert à dater l'axe (« du JJ/MM » … « au JJ/MM ») et le readout.
//
// M4 — survol = lecture. Composant CLIENT (props 100 % plates, conforme RSC) :
// au pointermove sur le SVG, ligne verticale + point sur la courbe + readout
// {JJ/MM · valeur} dans la barre de titre (pas de tooltip flottant → esthétique
// instrument). preserveAspectRatio="none" déforme les coordonnées → on mappe le
// pointeur via le bounding rect, jamais via les coordonnées SVG natives.
export function TrendChart({
  series,
  label,
  lastDay,
  markers,
  trend = false,
}: {
  series?: number[] | null;
  label: string;
  lastDay?: string | null;
  // B1 — marqueurs d'interventions : données PLATES uniquement (jamais de fonction).
  markers?: TrendMarker[];
  // Droite de tendance (régression linéaire). Opt-in : activée sur les fiches
  // article uniquement. Fit calculé À PARTIR du 1er jour non nul pour ignorer les
  // zéros STRUCTURELS de début de fenêtre (tracker/Google pas encore couvrants) —
  // sinon la pente est faussée à la hausse (piège d'amorçage, cf. CLAUDE.md).
  trend?: boolean;
}) {
  const [hover, setHover] = useState<{ x: number; y: number; jjmm: string | null; value: number } | null>(
    null,
  );

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

  // Tendance linéaire sur la région mesurée (dès le 1er jour non nul). `dir` sert
  // au libellé « en hausse / stable / en baisse » ; la droite est bornée à la zone
  // de tracé pour ne jamais déborder du cadre.
  const tr = trend ? linearTrend(series) : null;
  const clampY = (v: number) => Math.max(pt, Math.min(h - pb, Y(v)));
  const trPath = tr
    ? `M${X(tr.i0).toFixed(1)} ${clampY(tr.yStart).toFixed(1)} L${lastX.toFixed(1)} ${clampY(tr.yEnd).toFixed(1)}`
    : null;

  // Mapping pointeur → index. Piège (a) : preserveAspectRatio="none" étire la
  // viewBox sur le rect rendu → on projette via rect.width, puis on inverse X(i).
  function onMove(e: React.PointerEvent<SVGSVGElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    if (rect.width === 0) return;
    const xSvg = ((e.clientX - rect.left) / rect.width) * w;
    let i = Math.round(((xSvg - pl) * (n - 1)) / (w - pl - pr));
    i = Math.max(0, Math.min(n - 1, i));
    setHover({ x: X(i), y: Y(series![i]), jjmm: jjmmForIndex(lastDay, i, n), value: series![i] });
  }

  // Libellés d'axe X : le 1er jalon devient une VRAIE date (« du JJ/MM » = lastDay
  // − (n−1) j) au lieu de « −Nj » ; les deux jalons intermédiaires restent relatifs ;
  // « au JJ/MM » final inchangé.
  const startLabel = jjmmForIndex(lastDay, 0, n);
  const xLabels = [
    startLabel ? `du ${startLabel}` : `−${n}j`,
    `−${Math.round((n * 2) / 3)}j`,
    `−${Math.round(n / 3)}j`,
    lastDayLabel(lastDay),
  ];

  return (
    <div className="mt-[18px] border border-line bg-panel">
      <div className="flex items-center justify-between gap-4 border-b border-[#efefed] px-4 py-3">
        <h2 className="text-[12px] font-semibold text-ink">{label}</h2>
        <span className="font-mono text-[10.5px] tabular-nums">
          {hover ? (
            <span className="text-ink">
              {hover.jjmm ? `${hover.jjmm} · ` : ""}
              {num(hover.value)}
            </span>
          ) : (
            <span className="text-faint">
              max {num(max)} · min {num(min)} · n={n} j
            </span>
          )}
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
            style={{ width: "100%", height: 168, display: "block", overflow: "visible", cursor: "crosshair", touchAction: "pan-y" }}
            onPointerDown={(e) => {
              // Tactile : capturer le pointeur permet de scruber au doigt ; touchAction
              // pan-y laisse le scroll vertical de la page passer. Lecture dès le toucher.
              e.currentTarget.setPointerCapture(e.pointerId);
              onMove(e);
            }}
            onPointerMove={onMove}
            onPointerUp={(e) => {
              if (e.pointerType !== "mouse") setHover(null);
            }}
            onPointerLeave={() => setHover(null)}
          >
            <line x1="0" x2={w} y1="12" y2="12" stroke="#efefed" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            <line x1="0" x2={w} y1="84" y2="84" stroke="#efefed" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            <line x1="0" x2={w} y1="156" y2="156" stroke="#e2e2e0" strokeWidth="1" vectorEffect="non-scaling-stroke" />
            {[205, 410, 615].map((x) => (
              <line key={x} x1={x} x2={x} y1="4" y2="156" stroke="#f1f1ef" strokeWidth="1" strokeDasharray="2 4" vectorEffect="non-scaling-stroke" />
            ))}
            <path d={area} fill="var(--color-accent)" fillOpacity="0.06" />
            {/* Droite de tendance sous le tracé accent : pointillé gris discret pour
                donner la direction sans voler la vedette à la série brute. */}
            {trPath && (
              <path d={trPath} fill="none" stroke="#b4b3ae" strokeWidth="1.2" strokeDasharray="5 4" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
            )}
            <path d={line} fill="none" stroke="var(--color-accent)" strokeWidth="1.4" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
            {/* Point = path à cap rond de largeur en pixels-écran (vectorEffect) →
                disque parfait malgré preserveAspectRatio="none" ; un <circle> serait
                étiré en œuf par la déformation de la viewBox. */}
            <path d={`M${lastX.toFixed(1)} ${lastY.toFixed(1)} l0 0`} stroke="var(--color-accent)" strokeWidth="5.2" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
            {markers?.map((m, i) => {
              const mx = X(Math.max(0, Math.min(m.index, n - 1)));
              const fill = m.kind === "site_change" ? "var(--color-accent)" : "var(--color-info)";
              return (
                <polygon
                  key={i}
                  points={`${mx.toFixed(1)},158 ${(mx - 4).toFixed(1)},165 ${(mx + 4).toFixed(1)},165`}
                  fill={fill}
                >
                  <title>{m.label}</title>
                </polygon>
              );
            })}
            {hover && (
              <>
                <line
                  x1={hover.x}
                  x2={hover.x}
                  y1="4"
                  y2="156"
                  stroke="#e2e2e0"
                  strokeWidth="1"
                  vectorEffect="non-scaling-stroke"
                />
                <path d={`M${hover.x.toFixed(1)} ${hover.y.toFixed(1)} l0 0`} stroke="#fff" strokeWidth="8" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
                <path d={`M${hover.x.toFixed(1)} ${hover.y.toFixed(1)} l0 0`} stroke="var(--color-accent)" strokeWidth="6" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
              </>
            )}
          </svg>
        </div>
      </div>
      <div className="flex justify-between px-4 pb-2.5 pl-[50px] font-mono text-[9.5px] text-dim">
        {xLabels.map((t, i) => (
          <span key={i}>{t}</span>
        ))}
      </div>
      {tr && (
        <div className="border-t border-[#f2f2f0] px-4 py-1.5 pl-[50px] font-mono text-[9.5px] leading-snug text-dim">
          <span className="text-[#b4b3ae]">‑ ‑</span> tendance {tr.dir === "up" ? "↗ en hausse" : tr.dir === "down" ? "↘ en baisse" : "→ stable"} sur la région mesurée
          {max < 5 ? " · petit volume, à lire avec prudence" : ""}
        </div>
      )}
    </div>
  );
}
