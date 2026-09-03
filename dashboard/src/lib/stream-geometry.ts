// Géométrie du « Stream Ribbon » (Lieflat F16, adapté au système Cooked) — module PUR,
// aucun import React. Empilement à ligne de base « silhouette » (le haut de la pile
// démarre à −total/2 autour de l'axe central) → la rivière est le total, chaque bande
// = sa série. Chemins arrondis au dixième (toFixed(1)) comme chart-geometry.

import type { ChartBox } from "@/lib/chart-geometry";

export interface Band {
  /** y du bord haut, par index de semaine (unités viewBox). */
  top: number[];
  /** y du bord bas, par index de semaine. */
  bottom: number[];
}

/** Total par index (Σ des séries). Séries de longueurs inégales → longueur min. */
export function totals(series: number[][]): number[] {
  if (series.length === 0) return [];
  const n = Math.min(...series.map((s) => s.length));
  const out: number[] = [];
  for (let i = 0; i < n; i++) {
    let t = 0;
    for (const s of series) t += s[i];
    out.push(t);
  }
  return out;
}

/** Échelle verticale : le total max occupe la hauteur de tracé (pt → h − pb). */
export function streamScale(box: ChartBox, maxTotal: number): number {
  const inner = box.h - box.pt - box.pb;
  return maxTotal > 0 ? inner / maxTotal : 0;
}

/**
 * Empile les séries (dans l'ordre donné, la première en haut) autour de l'axe
 * central cy. Retourne une bande par série.
 */
export function stackSilhouette(series: number[][], box: ChartBox): Band[] {
  const tot = totals(series);
  const n = tot.length;
  const sc = streamScale(box, n ? Math.max(...tot) : 0);
  const cy = box.pt + (box.h - box.pt - box.pb) / 2;
  let run = tot.map((t) => cy - (t * sc) / 2);
  const bands: Band[] = [];
  for (const s of series) {
    const top = run.slice();
    const bottom = top.map((y, i) => y + s[i] * sc);
    bands.push({ top, bottom });
    run = bottom;
  }
  return bands;
}

/** Courbe lissée (quadratiques par points milieux, comme le modèle F16). */
export function smoothPath(pts: [number, number][]): string {
  if (pts.length === 0) return "";
  const f = (v: number) => v.toFixed(1);
  let d = `M${f(pts[0][0])} ${f(pts[0][1])}`;
  if (pts.length === 1) return d;
  for (let k = 1; k < pts.length - 1; k++) {
    const p = pts[k];
    const q = pts[k + 1];
    d += ` Q${f(p[0])} ${f(p[1])} ${f((p[0] + q[0]) / 2)} ${f((p[1] + q[1]) / 2)}`;
  }
  const last = pts[pts.length - 1];
  return `${d} L${f(last[0])} ${f(last[1])}`;
}

/** Contour fermé d'une bande : haut lissé, puis bas en sens inverse (lissé aussi). */
export function bandPath(band: Band, X: (i: number) => number): string {
  const n = band.top.length;
  if (n === 0) return "";
  const topPts: [number, number][] = band.top.map((y, i): [number, number] => [X(i), y]);
  const botPts: [number, number][] = band.bottom.map((y, i): [number, number] => [X(i), y]).reverse();
  const bot = smoothPath(botPts);
  // smoothPath commence par "M…" : on la raccorde par un "L" vers son premier point.
  return `${smoothPath(topPts)} L${bot.slice(1)} Z`;
}

/**
 * Index où la série est la plus large, hors des `margin` premiers/derniers points
 * (le libellé posé là ne déborde pas de la bande). Séries courtes → milieu.
 */
export function widestIndex(values: number[], margin = 4): number {
  const n = values.length;
  if (n === 0) return 0;
  if (n <= 2 * margin + 1) return Math.floor(n / 2);
  let best = margin;
  for (let i = margin; i < n - margin; i++) if (values[i] > values[best]) best = i;
  return best;
}

const MOIS_COURT = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];

export interface MonthTick {
  index: number;
  label: string;
}

/**
 * Un repère à chaque semaine qui ouvre un nouveau mois (semaine ISO « YYYY-MM-DD »).
 * Janvier (ou le premier repère) porte l'année.
 */
export function monthTicks(weekStarts: string[]): MonthTick[] {
  const out: MonthTick[] = [];
  let prev = "";
  for (let i = 0; i < weekStarts.length; i++) {
    const ym = weekStarts[i].slice(0, 7);
    if (ym === prev) continue;
    prev = ym;
    if (i === 0) continue; // le bord gauche n'est pas un début de mois lisible
    const m = parseInt(ym.slice(5, 7), 10);
    const label = MOIS_COURT[m - 1] ?? ym;
    out.push({ index: i, label: m === 1 || out.length === 0 ? `${label} ${ym.slice(0, 4)}` : label });
  }
  return out;
}

/** Index de la semaine ISO (lundi) contenant `dayISO`, ou null hors fenêtre. */
export function weekIndexOf(weekStarts: string[], dayISO: string): number | null {
  if (weekStarts.length === 0) return null;
  const d = dayISO.slice(0, 10);
  if (d < weekStarts[0]) return null;
  let idx: number | null = null;
  for (let i = 0; i < weekStarts.length; i++) {
    if (weekStarts[i] <= d) idx = i;
    else break;
  }
  if (idx === null) return null;
  // Au-delà du dimanche de la dernière semaine → hors fenêtre.
  const last = weekStarts[weekStarts.length - 1];
  if (idx === weekStarts.length - 1 && dayDiffISO(last, d) > 6) return null;
  return idx;
}

function dayDiffISO(a: string, b: string): number {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000);
}
