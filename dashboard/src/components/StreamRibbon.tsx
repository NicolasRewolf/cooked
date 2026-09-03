"use client";

import { useState } from "react";
import { num } from "@/lib/format";
import { jjmm } from "@/lib/dates";
import { indexFromPointerX, xScaleIndex, type ChartBox } from "@/lib/chart-geometry";
import { bandPath, monthTicks, stackSilhouette, widestIndex } from "@/lib/stream-geometry";
import type { LabGscView } from "@/data/lab-view-models";

// Stream Ribbon (d'après Lieflat F16 « Stream Ribbon ») : constitution de plusieurs
// séries au fil d'un temps continu, en gardant le total sous les yeux. Rivière
// symétrique autour de l'axe central (silhouette) ; largeur d'une bande = clics de la
// semaine ; coutures couleur panneau ; la bande la plus large aujourd'hui est la plus
// noire, son nom est posé à sa semaine la plus large.
//
// Composant CLIENT, props 100 % plates (frontière RSC). Survol = lecture dans la barre
// de titre, pas de tooltip flottant (esthétique instrument, comme TrendChart). Le SVG
// garde son ratio (pas de preserveAspectRatio="none") : les textes ne se déforment pas
// et rect.width ↔ viewBox.w reste une homothétie → indexFromPointerX est exact.

const BOX: ChartBox = { w: 820, h: 300, pl: 4, pr: 4, pt: 18, pb: 36 };

function inkVar(tone: string): string {
  return `var(--color-${tone})`;
}

export function StreamRibbon({ view }: { view: LabGscView }) {
  const [hover, setHover] = useState<number | null>(null);
  const n = view.weeks.length;
  if (n < 2) return null;

  const { w, h, pt, pb } = BOX;
  const X = xScaleIndex(BOX, n);
  const bands = stackSilhouette(
    view.bands.map((b) => b.clicks),
    BOX,
  );
  const floorY = h - pb + 8;
  const ticks = monthTicks(view.weeks);
  const monthIdx = new Set(ticks.map((t) => t.index));

  function onMove(e: React.PointerEvent<SVGSVGElement>) {
    const rect = e.currentTarget.getBoundingClientRect();
    const i = indexFromPointerX(e.clientX - rect.left, rect.width, BOX, n);
    if (i !== null) setHover(i);
  }

  const hoverMarkers = hover === null ? [] : view.markers.filter((m) => m.index === hover);

  return (
    <div className="border border-line bg-panel">
      <div className="flex items-center justify-between gap-4 border-b border-line-soft px-4 py-3">
        <h2 className="text-[12px] font-semibold text-ink">Clics Google par semaine, par type de page</h2>
        <span className="font-mono text-[10.5px] tabular-nums">
          {hover !== null ? (
            <span className="text-ink">
              sem. du {jjmm(view.weeks[hover])} · {num(view.totals[hover])} clics
              {view.bands.map((b) => (
                <span key={b.key} className="ml-3 text-muted">
                  <span
                    className="mr-1 inline-block h-[7px] w-[7px] align-middle"
                    style={{ background: inkVar(b.tone) }}
                    aria-hidden
                  />
                  {num(b.clicks[hover])}
                </span>
              ))}
            </span>
          ) : (
            <span className="text-faint">
              pic {num(view.peakTotal)} (sem. du {jjmm(view.peakTotalWeek)}) · dern. sem. {num(view.lastTotal)} · n={n} sem.
            </span>
          )}
        </span>
      </div>

      <div className="px-4 pt-2">
        <svg
          viewBox={`0 0 ${w} ${h}`}
          style={{ width: "100%", height: "auto", display: "block", overflow: "visible", cursor: "crosshair", touchAction: "pan-y" }}
          onPointerDown={(e) => {
            e.currentTarget.setPointerCapture(e.pointerId);
            onMove(e);
          }}
          onPointerMove={onMove}
          onPointerUp={(e) => {
            if (e.pointerType !== "mouse") setHover(null);
          }}
          onPointerLeave={() => setHover(null)}
        >
          {/* Axe central : la ligne de base silhouette. */}
          <line x1={X(0)} x2={X(n - 1)} y1={pt + (h - pt - pb) / 2} y2={pt + (h - pt - pb) / 2} stroke="var(--color-line-soft)" strokeWidth="1" strokeDasharray="2 4" />

          {bands.map((band, bi) => {
            const b = view.bands[bi];
            return (
              <path key={b.key} d={bandPath(band, X)} fill={inkVar(b.tone)} stroke="var(--color-panel)" strokeWidth="1.5" strokeLinejoin="round">
                <title>{b.label}</title>
              </path>
            );
          })}

          {/* Noms de bande APRÈS toutes les bandes : aucune couture ne les traverse. Halo
              (paint-order) de la couleur de la bande pour rester lisible sur une couture. */}
          {bands.map((band, bi) => {
            const b = view.bands[bi];
            const wi = widestIndex(b.clicks);
            const thickness = band.bottom[wi] - band.top[wi];
            if (thickness < 13) return null;
            const dark = b.tone === "ink" || b.tone === "muted";
            return (
              <text
                key={b.key}
                x={X(wi)}
                y={(band.top[wi] + band.bottom[wi]) / 2 + 3}
                textAnchor="middle"
                fontSize="9"
                fontWeight="600"
                letterSpacing="0.08em"
                fill={dark ? "var(--color-panel)" : "var(--color-ink)"}
                stroke={inkVar(b.tone)}
                strokeWidth="3"
                strokeLinejoin="round"
                style={{ fontFamily: "var(--font-mono)", textTransform: "uppercase", pointerEvents: "none", paintOrder: "stroke" }}
              >
                {b.label}
              </text>
            );
          })}

          {/* Plancher « code-barres » : un trait par semaine, plus haut aux débuts de mois. */}
          <line x1={X(0) - 4} x2={X(n - 1) + 4} y1={floorY} y2={floorY} stroke="var(--color-line-strong)" strokeWidth="1" />
          {view.weeks.map((wk, i) => (
            <line key={wk} x1={X(i)} x2={X(i)} y1={floorY} y2={floorY - (monthIdx.has(i) ? 7 : 3.5)} stroke="var(--color-dim)" strokeWidth="0.7" />
          ))}
          {ticks.map((t) => (
            <text key={t.index} x={X(t.index)} y={floorY + 13} textAnchor="middle" fontSize="8" fontWeight="600" letterSpacing="0.08em" fill="var(--color-faint)" style={{ fontFamily: "var(--font-mono)" }}>
              {t.label}
            </text>
          ))}

          {/* Annotations : triangle sous le plancher, à la semaine de l'événement. */}
          {view.markers.map((m, i) => {
            const mx = X(m.index);
            const fill = m.kind === "site_change" ? "var(--color-accent)" : "var(--color-info)";
            return (
              <polygon key={i} points={`${mx.toFixed(1)},${floorY + 17} ${(mx - 4).toFixed(1)},${floorY + 24} ${(mx + 4).toFixed(1)},${floorY + 24}`} fill={fill}>
                <title>{`${jjmm(m.day)} — ${m.label}`}</title>
              </polygon>
            );
          })}

          {hover !== null && (
            <line x1={X(hover)} x2={X(hover)} y1={pt - 6} y2={floorY} stroke="var(--color-ink)" strokeWidth="1" strokeDasharray="3 3" />
          )}
        </svg>
      </div>

      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-t border-line-soft px-4 py-2 font-mono text-[9.5px] leading-snug text-dim">
        <span>largeur = clics / semaine · la rivière = le total · le plus noir = le plus large aujourd&apos;hui</span>
        <span>
          semaines closes du {jjmm(view.windowStart)} au {jjmm(view.windowEnd)} · Google jusqu&apos;au {jjmm(view.gscEnd)}
        </span>
      </div>
      {hoverMarkers.length > 0 && (
        <div className="border-t border-line-soft px-4 py-2 font-mono text-[10px] leading-relaxed text-muted">
          {hoverMarkers.map((m, i) => (
            <div key={i}>
              <span className={m.kind === "site_change" ? "text-accent" : "text-info"}>▲</span> {jjmm(m.day)} — {m.label}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
