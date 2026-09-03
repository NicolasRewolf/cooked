import { describe, expect, it } from "vitest";
import {
  bandPath,
  monthTicks,
  smoothPath,
  stackSilhouette,
  streamScale,
  totals,
  weekIndexOf,
  widestIndex,
} from "./stream-geometry";
import { xScaleIndex, type ChartBox } from "./chart-geometry";

const BOX: ChartBox = { w: 820, h: 300, pl: 4, pr: 4, pt: 20, pb: 40 };

describe("totals", () => {
  it("somme index par index, tronque à la série la plus courte", () => {
    expect(totals([[1, 2, 3], [10, 20, 30]])).toEqual([11, 22, 33]);
    expect(totals([[1, 2, 3], [10, 20]])).toEqual([11, 22]);
    expect(totals([])).toEqual([]);
  });
});

describe("stackSilhouette", () => {
  it("la rivière est symétrique autour de l'axe central et sa largeur = total", () => {
    const series = [
      [100, 50, 0],
      [100, 150, 200],
    ];
    const bands = stackSilhouette(series, BOX);
    const sc = streamScale(BOX, 200);
    const cy = 20 + (300 - 20 - 40) / 2; // 140
    for (let i = 0; i < 3; i++) {
      const total = series[0][i] + series[1][i];
      expect(bands[0].top[i]).toBeCloseTo(cy - (total * sc) / 2);
      expect(bands[1].bottom[i]).toBeCloseTo(cy + (total * sc) / 2);
      // Bandes contiguës.
      expect(bands[1].top[i]).toBeCloseTo(bands[0].bottom[i]);
      // Largeur de bande = valeur × échelle.
      expect(bands[0].bottom[i] - bands[0].top[i]).toBeCloseTo(series[0][i] * sc);
    }
    // Le total max remplit exactement la zone de tracé.
    expect(bands[0].top[2]).toBeCloseTo(20);
    expect(bands[1].bottom[2]).toBeCloseTo(260);
  });

  it("séries toutes nulles → bandes plates sur l'axe, sans NaN", () => {
    const bands = stackSilhouette([[0, 0], [0, 0]], BOX);
    expect(bands[0].top).toEqual([140, 140]);
    expect(bands[1].bottom).toEqual([140, 140]);
  });
});

describe("smoothPath / bandPath", () => {
  it("un point → M seul ; deux points → M + L", () => {
    expect(smoothPath([[1, 2]])).toBe("M1.0 2.0");
    expect(smoothPath([[1, 2], [3, 4]])).toBe("M1.0 2.0 L3.0 4.0");
  });
  it("quadratiques par points milieux, arrondi au dixième", () => {
    expect(smoothPath([[0, 0], [10, 10], [20, 0]])).toBe("M0.0 0.0 Q10.0 10.0 15.0 5.0 L20.0 0.0");
  });
  it("bandPath ferme le contour (Z) et ne contient pas de M intermédiaire", () => {
    const X = xScaleIndex(BOX, 3);
    const d = bandPath({ top: [10, 12, 14], bottom: [30, 32, 34] }, X);
    expect(d.startsWith("M")).toBe(true);
    expect(d.endsWith(" Z")).toBe(true);
    expect(d.indexOf("M", 1)).toBe(-1);
  });
  it("bande vide → chemin vide", () => {
    expect(bandPath({ top: [], bottom: [] }, xScaleIndex(BOX, 1))).toBe("");
  });
});

describe("widestIndex", () => {
  it("ignore les marges et prend le premier max", () => {
    const v = [100, 0, 0, 0, 5, 9, 9, 1, 0, 0, 0, 0, 100];
    expect(widestIndex(v, 4)).toBe(5);
  });
  it("série courte → milieu", () => {
    expect(widestIndex([1, 2, 3], 4)).toBe(1);
    expect(widestIndex([], 4)).toBe(0);
  });
});

describe("monthTicks", () => {
  it("un repère par mois entamé, année sur le premier et sur janvier", () => {
    const weeks = ["2025-12-15", "2025-12-22", "2025-12-29", "2026-01-05", "2026-01-12", "2026-02-02"];
    expect(monthTicks(weeks)).toEqual([
      { index: 3, label: "janv. 2026" },
      { index: 5, label: "févr." },
    ]);
  });
  it("le premier repère porte l'année même hors janvier", () => {
    expect(monthTicks(["2026-04-27", "2026-05-04"])).toEqual([{ index: 1, label: "mai 2026" }]);
  });
});

describe("weekIndexOf", () => {
  const weeks = ["2026-08-03", "2026-08-10", "2026-08-17"];
  it("lundi → sa semaine, dimanche → la même", () => {
    expect(weekIndexOf(weeks, "2026-08-10")).toBe(1);
    expect(weekIndexOf(weeks, "2026-08-16")).toBe(1);
  });
  it("avant la fenêtre ou après le dernier dimanche → null", () => {
    expect(weekIndexOf(weeks, "2026-08-02")).toBeNull();
    expect(weekIndexOf(weeks, "2026-08-23")).toBe(2); // dernier dimanche = dans la fenêtre
    expect(weekIndexOf(weeks, "2026-08-24")).toBeNull();
    expect(weekIndexOf([], "2026-08-24")).toBeNull();
  });
});
