import { describe, expect, it } from "vitest";
import { buildLabGscView, meanBlock } from "./lab-view-models";
import type { LabGscWeekly } from "@/lib/types";

function week(week_start: string, c: [number, number, number, number], i: [number, number, number, number]) {
  return {
    week_start,
    c_ressource: c[0], c_classique: c[1], c_expertise: c[2], c_divers: c[3],
    i_ressource: i[0], i_classique: i[1], i_expertise: i[2], i_divers: i[3],
  };
}

// 14 lundis consécutifs à partir du 01/06/2026.
const WEEKS = Array.from({ length: 14 }, (_, k) => {
  const d = new Date(Date.UTC(2026, 5, 1 + 7 * k));
  return d.toISOString().slice(0, 10);
});

function fixture(): LabGscWeekly {
  return {
    gsc_end: "2026-09-07",
    window_start: WEEKS[0],
    window_end: "2026-09-06",
    // Ressources : 200/sem sur les 4 premières puis 100 ; classiques constants 50 ; expertise 10 ; divers 5.
    weeks: WEEKS.map((w, k) => week(w, [k < 6 ? 200 : 100, 50, 10, 5], [10_000, 1_000, 1_000, 100])),
    annotations: [
      { day: "2026-07-15", kind: "site_change", label: "Refonte", paths: null },
      { day: "2025-01-01", kind: "autre", label: "hors fenêtre", paths: null },
    ],
  };
}

describe("meanBlock", () => {
  it("moyenne des len valeurs finissant à end, 0 si la fenêtre déborde", () => {
    expect(meanBlock([1, 2, 3, 4], 3, 2)).toBe(3.5);
    expect(meanBlock([1, 2, 3, 4], 0, 2)).toBe(0);
    expect(meanBlock([1, 2], 5, 1)).toBe(0);
  });
});

describe("buildLabGscView", () => {
  it("trie les bandes par largeur actuelle et attribue les encres du plus noir au plus clair", () => {
    const v = buildLabGscView(fixture());
    expect(v.bands.map((b) => b.key)).toEqual(["ressource", "classique", "expertise", "divers"]);
    expect(v.bands.map((b) => b.tone)).toEqual(["ink", "muted", "faint", "dim"]);
  });

  it("last4 / ref4 : blocs de 4 semaines, le second 8 semaines plus tôt", () => {
    const v = buildLabGscView(fixture());
    const res = v.bands[0];
    // Dernier bloc = semaines 10..13 → 100 ; référence = semaines 2..5 → 200.
    expect(res.last4).toBe(100);
    expect(res.ref4).toBe(200);
    expect(res.ctrLast4Pct).toBeCloseTo(1);
    expect(res.ctrRef4Pct).toBeCloseTo(2);
    expect(res.peak).toBe(200);
    expect(res.peakWeek).toBe(WEEKS[0]);
  });

  it("totaux = Σ des bandes ; pic et dernière valeur", () => {
    const v = buildLabGscView(fixture());
    expect(v.totals[0]).toBe(265);
    expect(v.totals[13]).toBe(165);
    expect(v.peakTotal).toBe(265);
    expect(v.peakTotalWeek).toBe(WEEKS[0]);
    expect(v.lastTotal).toBe(165);
  });

  it("annotations → marqueurs indexés à la semaine ; hors fenêtre ignorées", () => {
    const v = buildLabGscView(fixture());
    expect(v.markers).toHaveLength(1);
    expect(v.markers[0]).toMatchObject({ index: 6, day: "2026-07-15", kind: "site_change" });
  });

  it("CTR null quand aucune impression", () => {
    const f = fixture();
    f.weeks = f.weeks.map((w) => ({ ...w, i_divers: 0 }));
    const v = buildLabGscView(f);
    const divers = v.bands.find((b) => b.key === "divers")!;
    expect(divers.ctrLast4Pct).toBeNull();
  });

  it("fenêtre vide → vue vide sans NaN", () => {
    const v = buildLabGscView({ ...fixture(), weeks: [], annotations: [] });
    expect(v.bands[0].last4).toBe(0);
    expect(v.peakTotal).toBe(0);
    expect(v.totals).toEqual([]);
  });
});
