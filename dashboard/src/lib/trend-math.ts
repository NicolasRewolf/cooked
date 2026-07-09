// Régression linéaire sur séries journalières (pur, testable hors composant client).

export type TrendDir = "up" | "down" | "flat";

export interface LinearTrendResult {
  i0: number;
  yStart: number;
  yEnd: number;
  dir: TrendDir;
}

/** Moindres carrés à partir du 1er jour non nul (zéros de début = artefact de couverture). */
export function linearTrend(series: number[]): LinearTrendResult | null {
  const n = series.length;
  let i0 = 0;
  while (i0 < n && series[i0] === 0) i0++;
  const m = n - i0;
  if (m < 5) return null;

  let sx = 0;
  let sy = 0;
  let sxx = 0;
  let sxy = 0;
  for (let i = i0; i < n; i++) {
    sx += i;
    sy += series[i];
    sxx += i * i;
    sxy += i * series[i];
  }
  const denom = m * sxx - sx * sx;
  if (denom === 0) return null;

  const slope = (m * sxy - sx * sy) / denom;
  const intercept = (sy - slope * sx) / m;
  const yStart = intercept + slope * i0;
  const yEnd = intercept + slope * (n - 1);
  const deadband = 0.1 * ((Math.max(...series) - Math.min(...series)) || 1);
  const dir: TrendDir =
    yEnd - yStart > deadband ? "up" : yEnd - yStart < -deadband ? "down" : "flat";
  return { i0, yStart, yEnd, dir };
}
