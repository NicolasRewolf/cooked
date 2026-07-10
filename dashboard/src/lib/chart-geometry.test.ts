import { describe, expect, it } from "vitest";
import {
  buildAreaPath,
  buildLinePath,
  clampYToPlot,
  dotPath,
  indexFromPointerX,
  lastPoint,
  relativeDayTicks,
  seriesExtent,
  xScaleDomain,
  xScaleIndex,
  yScale,
  type ChartBox,
} from "./chart-geometry";

// Boîtes réelles des trois composants consommateurs.
const TREND: ChartBox = { w: 820, h: 170, pl: 4, pr: 4, pt: 10, pb: 14 };
const SPARK: ChartBox = { w: 120, h: 28, pl: 3, pr: 3, pt: 3, pb: 3 };
const COHORT: ChartBox = { w: 820, h: 190, pl: 4, pr: 4, pt: 12, pb: 16 };

describe("seriesExtent", () => {
  it("série croissante", () => {
    expect(seriesExtent([1, 2, 3, 8])).toEqual({ min: 1, max: 8, span: 7 });
  });
  it("série décroissante", () => {
    expect(seriesExtent([9, 4, 2, 0])).toEqual({ min: 0, max: 9, span: 9 });
  });
  it("série plate (valeurs égales) : span 0 forcé à 1", () => {
    expect(seriesExtent([5, 5, 5])).toEqual({ min: 5, max: 5, span: 1 });
  });
  it("1 point : span forcé à 1", () => {
    expect(seriesExtent([42])).toEqual({ min: 42, max: 42, span: 1 });
  });
});

describe("échelles", () => {
  it("xScaleIndex : bornes [pl, w−pr]", () => {
    const X = xScaleIndex(TREND, 28);
    expect(X(0)).toBe(4);
    expect(X(27)).toBe(816);
  });
  it("xScaleDomain : bornes + point unique à X(0)=pl (cohorte d'1 jour)", () => {
    const X = xScaleDomain(COHORT, 60);
    expect(X(0)).toBe(4);
    expect(X(60)).toBe(816);
    expect(X(30)).toBe(410);
  });
  it("yScale : min sur la baseline, max au plafond", () => {
    const Y = yScale(TREND, 2, 8); // domaine [2, 10]
    expect(Y(2)).toBe(170 - 14); // h − pb
    expect(Y(10)).toBe(10); // pt
  });
  it("yScale sur série plate (span forcé 1) : tout sur la baseline", () => {
    const { min, span } = seriesExtent([5, 5, 5, 5]);
    const Y = yScale(SPARK, min, span);
    expect(Y(5)).toBe(28 - 3);
  });
});

describe("paths", () => {
  it("buildLinePath : coordonnées arrondies au dixième", () => {
    const X = xScaleIndex(SPARK, 3);
    const Y = yScale(SPARK, 0, 10);
    expect(buildLinePath([0, 5, 10], X, Y)).toBe("M3.0 25.0 L60.0 14.0 L117.0 3.0");
  });
  it("buildAreaPath : baseline interpolée BRUTE (156, pas 156.0)", () => {
    const X = xScaleIndex(TREND, 3);
    const Y = yScale(TREND, 0, 10);
    const line = buildLinePath([0, 5, 10], X, Y);
    expect(buildAreaPath(line, X, 3, 170 - 14)).toBe(`${line} L816.0 156 L4.0 156 Z`);
  });
  it("lastPoint : coordonnées brutes du dernier point", () => {
    const X = xScaleIndex(SPARK, 2);
    const Y = yScale(SPARK, 0, 10);
    expect(lastPoint([0, 10], X, Y)).toEqual({ x: 117, y: 3 });
  });
  it("dotPath : segment nul à cap rond", () => {
    expect(dotPath(816, 23.456)).toBe("M816.0 23.5 l0 0");
  });
  it("clampYToPlot : borne la droite de tendance à [pt, h−pb]", () => {
    expect(clampYToPlot(TREND, -50)).toBe(10);
    expect(clampYToPlot(TREND, 300)).toBe(156);
    expect(clampYToPlot(TREND, 80)).toBe(80);
  });
});

describe("indexFromPointerX", () => {
  const n = 28;
  it("borne gauche : x=0 → index 0", () => {
    expect(indexFromPointerX(0, 640, TREND, n)).toBe(0);
  });
  it("borne droite : x=rectWidth → index n−1 (clamp du dépassement pr)", () => {
    expect(indexFromPointerX(640, 640, TREND, n)).toBe(n - 1);
  });
  it("hors cadre : clamp aux bornes", () => {
    expect(indexFromPointerX(-30, 640, TREND, n)).toBe(0);
    expect(indexFromPointerX(9999, 640, TREND, n)).toBe(n - 1);
  });
  it("milieu du rect → index médian", () => {
    // xSvg = 410 ; (410−4)·27/812 = 13.5 → round-half-up = 14.
    expect(indexFromPointerX(320, 640, TREND, n)).toBe(14);
  });
  it("rect non layouté (width 0) → null", () => {
    expect(indexFromPointerX(100, 0, TREND, n)).toBeNull();
  });
  it("aller-retour : le pixel exact de X(i) retombe sur i", () => {
    const X = xScaleIndex(TREND, n);
    const rectWidth = 640;
    for (let i = 0; i < n; i++) {
      const px = (X(i) / TREND.w) * rectWidth;
      expect(indexFromPointerX(px, rectWidth, TREND, n)).toBe(i);
    }
  });
});

describe("relativeDayTicks", () => {
  it("jalons [n, 2n/3, n/3] arrondis", () => {
    expect(relativeDayTicks(28)).toEqual([28, 19, 9]);
    expect(relativeDayTicks(90)).toEqual([90, 60, 30]);
  });
});

// ---------------------------------------------------------------------------
// Non-régression pixel-identique : répliques VERBATIM des maths historiques
// des composants (avant D8). L'ordre des opérations flottantes diffère entre
// échelle par index et par domaine — ces répliques verrouillent le contrat.
// ---------------------------------------------------------------------------

function legacyTrend(series: number[]) {
  const w = 820, h = 170, pl = 4, pr = 4, pt = 10, pb = 14;
  const n = series.length;
  const min = Math.min(...series);
  const max = Math.max(...series);
  const span = max - min || 1;
  const X = (i: number) => pl + (i * (w - pl - pr)) / (n - 1);
  const Y = (v: number) => h - pb - ((v - min) / span) * (h - pt - pb);
  const pts = series.map((v, i) => `${X(i).toFixed(1)} ${Y(v).toFixed(1)}`);
  const line = "M" + pts.join(" L");
  const area = `${line} L${X(n - 1).toFixed(1)} ${h - pb} L${X(0).toFixed(1)} ${h - pb} Z`;
  return { line, area, lastX: X(n - 1), lastY: Y(series[n - 1]) };
}

function legacySpark(series: number[]) {
  const w = 120, h = 28, pad = 3;
  const min = Math.min(...series);
  const max = Math.max(...series);
  const span = max - min || 1;
  const X = (i: number) => pad + (i * (w - 2 * pad)) / (series.length - 1);
  const Y = (v: number) => h - pad - ((v - min) / span) * (h - 2 * pad);
  const line = "M" + series.map((v, i) => `${X(i).toFixed(1)} ${Y(v).toFixed(1)}`).join(" L");
  return { line, lastX: X(series.length - 1), lastY: Y(series[series.length - 1]) };
}

function legacyCohort(series: number[], maxY: number) {
  const w = 820, h = 190, pl = 4, pr = 4, pt = 12, pb = 16;
  const maxAge = 60;
  const X = (age: number) => pl + (age / maxAge) * (w - pl - pr);
  const Y = (v: number) => h - pb - (v / maxY) * (h - pt - pb);
  return "M" + series.map((v, age) => `${X(age).toFixed(1)} ${Y(v).toFixed(1)}`).join(" L");
}

function legacyPointer(pointerX: number, rectWidth: number, n: number) {
  const w = 820, pl = 4, pr = 4;
  const xSvg = (pointerX / rectWidth) * w;
  let i = Math.round(((xSvg - pl) * (n - 1)) / (w - pl - pr));
  i = Math.max(0, Math.min(n - 1, i));
  return i;
}

// PRNG déterministe (mulberry32) : valeurs fractionnaires reproductibles.
function mulberry32(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = mulberry32(20260710);
const battery: number[][] = [
  Array.from({ length: 28 }, (_, i) => i * 3), // croissante
  Array.from({ length: 28 }, (_, i) => 100 - i * 2.5), // décroissante
  Array.from({ length: 14 }, () => 7), // plate (span 0)
  [0, 10], // 2 points
  [0, 0, 0, 2, 5, 3, 8, 13, 9, 11, 17, 14, 21, 19], // zéros de début
  Array.from({ length: 90 }, () => Math.round(rnd() * 25000) / 100), // fractionnaire
];

describe("non-régression pixel-identique (répliques legacy)", () => {
  it("TrendChart : line + area + dernier point identiques", () => {
    for (const s of battery) {
      const n = s.length;
      const { min, span } = seriesExtent(s);
      const X = xScaleIndex(TREND, n);
      const Y = yScale(TREND, min, span);
      const line = buildLinePath(s, X, Y);
      const legacy = legacyTrend(s);
      expect(line).toBe(legacy.line);
      expect(buildAreaPath(line, X, n, TREND.h - TREND.pb)).toBe(legacy.area);
      expect(lastPoint(s, X, Y)).toEqual({ x: legacy.lastX, y: legacy.lastY });
    }
  });

  it("Sparkline : line + dernier point identiques", () => {
    for (const s of battery) {
      const { min, span } = seriesExtent(s);
      const X = xScaleIndex(SPARK, s.length);
      const Y = yScale(SPARK, min, span);
      const legacy = legacySpark(s);
      expect(buildLinePath(s, X, Y)).toBe(legacy.line);
      expect(lastPoint(s, X, Y)).toEqual({ x: legacy.lastX, y: legacy.lastY });
    }
  });

  it("CohortChart : path par âge identique (échelle par domaine)", () => {
    for (const s of battery) {
      const maxY = Math.max(1, ...s);
      const X = xScaleDomain(COHORT, 60);
      const Y = yScale(COHORT, 0, maxY);
      expect(buildLinePath(s, X, Y)).toBe(legacyCohort(s, maxY));
    }
  });

  it("pointeur → index : balayage complet du rect identique au legacy", () => {
    for (const n of [2, 14, 28, 90]) {
      for (let px = -10; px <= 650; px += 1) {
        expect(indexFromPointerX(px, 640, TREND, n)).toBe(legacyPointer(px, 640, n));
      }
    }
  });
});
