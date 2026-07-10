// Géométrie SVG partagée des graphes (TrendChart, Sparkline, CohortChart).
// Module PUR — aucun import React : échelles linéaires sur une boîte de tracé,
// path strings arrondies au dixième (toFixed(1)), inversion pointeur → index.
//
// ⚠️ Rendu pixel-identique GARANTI : l'ordre des opérations flottantes est FIGÉ
// et reproduit verbatim les maths historiques des composants. En particulier
// `pl + (i * inner) / (n − 1)` (échelle par index) et `pl + (x / max) * inner`
// (échelle par domaine) ne commutent PAS toujours en IEEE 754 — ne pas
// « simplifier » l'une vers l'autre.

/** Boîte de tracé : dimensions de la viewBox + paddings internes. */
export interface ChartBox {
  w: number;
  h: number;
  pl: number;
  pr: number;
  pt: number;
  pb: number;
}

export interface SeriesExtent {
  min: number;
  max: number;
  /** max − min, forcé à 1 si nul (série plate) pour éviter la division par 0. */
  span: number;
}

/** Bornes d'une série + span protégé (série plate ⇒ span = 1, tracé posé sur la baseline). */
export function seriesExtent(series: number[]): SeriesExtent {
  const min = Math.min(...series);
  const max = Math.max(...series);
  return { min, max, span: max - min || 1 };
}

/** Échelle X par index : i ∈ [0, n−1] → [pl, w−pr]. Suppose n ≥ 2 (les composants gardent la porte). */
export function xScaleIndex(box: ChartBox, n: number): (i: number) => number {
  const { w, pl, pr } = box;
  return (i) => pl + (i * (w - pl - pr)) / (n - 1);
}

/** Échelle X par domaine : x ∈ [0, domainMax] → [pl, w−pr] (cohortes : âge en jours). */
export function xScaleDomain(box: ChartBox, domainMax: number): (x: number) => number {
  const { w, pl, pr } = box;
  return (x) => pl + (x / domainMax) * (w - pl - pr);
}

/** Échelle Y : v ∈ [min, min+span] → [h−pb, pt] (axe SVG inversé, valeurs hautes en haut). */
export function yScale(box: ChartBox, min: number, span: number): (v: number) => number {
  const { h, pt, pb } = box;
  return (v) => h - pb - ((v - min) / span) * (h - pt - pb);
}

/** Path « ligne » : `M x0 y0 L x1 y1 …`, chaque coordonnée arrondie via toFixed(1). */
export function buildLinePath(
  series: number[],
  x: (i: number) => number,
  y: (v: number) => number,
): string {
  return "M" + series.map((v, i) => `${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(" L");
}

/**
 * Path « aire » sous une ligne, fermée sur `baseline` (ordonnée de la ligne de
 * base). La baseline est interpolée BRUTE (sans toFixed) — idiome historique
 * de TrendChart (`156`, pas `156.0`), à conserver pour le pixel-identique.
 */
export function buildAreaPath(
  line: string,
  x: (i: number) => number,
  n: number,
  baseline: number,
): string {
  return `${line} L${x(n - 1).toFixed(1)} ${baseline} L${x(0).toFixed(1)} ${baseline} Z`;
}

/** Dernier point de la série, coordonnées BRUTES (l'appelant arrondit s'il trace un path). */
export function lastPoint(
  series: number[],
  x: (i: number) => number,
  y: (v: number) => number,
): { x: number; y: number } {
  const n = series.length;
  return { x: x(n - 1), y: y(series[n - 1]) };
}

/**
 * Path « disque » : segment nul à cap rond, largeur en pixels-écran via
 * vectorEffect → reste un disque parfait malgré preserveAspectRatio="none"
 * (un <circle> serait étiré en œuf par la déformation de la viewBox).
 */
export function dotPath(x: number, y: number): string {
  return `M${x.toFixed(1)} ${y.toFixed(1)} l0 0`;
}

/** Clamp d'une ordonnée (px) dans la zone de tracé [pt, h−pb] — droite de tendance. */
export function clampYToPlot(box: ChartBox, yPx: number): number {
  return Math.max(box.pt, Math.min(box.h - box.pb, yPx));
}

/**
 * Inversion pointeur → index de série. `pointerX` = clientX − rect.left,
 * `rectWidth` = largeur RENDUE du SVG : preserveAspectRatio="none" étire la
 * viewBox sur le rect → on projette via le rect, jamais via les coordonnées
 * SVG natives. Index arrondi au point le plus proche puis clampé à [0, n−1].
 * Retourne null si le rect n'a pas de largeur (SVG pas encore layouté).
 */
export function indexFromPointerX(
  pointerX: number,
  rectWidth: number,
  box: ChartBox,
  n: number,
): number | null {
  if (rectWidth === 0) return null;
  const { w, pl, pr } = box;
  const xSvg = (pointerX / rectWidth) * w;
  const i = Math.round(((xSvg - pl) * (n - 1)) / (w - pl - pr));
  return Math.max(0, Math.min(n - 1, i));
}

/** Jalons relatifs de l'axe X (jours) : [n, 2n/3, n/3] arrondis — libellés « −Nj ». */
export function relativeDayTicks(n: number): [number, number, number] {
  return [n, Math.round((n * 2) / 3), Math.round(n / 3)];
}
