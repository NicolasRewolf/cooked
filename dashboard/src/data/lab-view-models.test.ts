import { describe, expect, it } from "vitest";
import { buildLabGscView, summarizeLabSelection } from "./lab-view-models";
import type { LabGscWeekly } from "@/lib/types";

function fixture(): LabGscWeekly {
  return {
    gsc_end: "2026-11-02",
    window_start: "2026-08-24",
    window_end: "2026-11-01",
    weeks: Array.from({ length: 10 }, (_, i) => ({
      week_start: new Date(Date.UTC(2026, 7, 24 + i * 7)).toISOString().slice(0, 10),
      // Les deux premières semaines seraient une mauvaise référence pour l'évolution.
      c_ressource: i < 2 ? 400 : i < 6 ? 10 : 20,
      c_classique: 10, c_expertise: 5, c_divers: 0,
      // Dernier bloc : 80 clics / 200 impressions, malgré des CTR hebdomadaires différents.
      i_ressource: i === 9 ? 140 : 20,
      i_classique: 100, i_expertise: 100, i_divers: 0,
    })),
    annotations: [
      { day: "2026-10-26", kind: "site_change", label: "Mise en ligne", paths: null },
      { day: "2026-10-30", kind: "note", label: "Relecture", paths: null },
      { day: "2026-11-02", kind: "note", label: "Hors fenêtre", paths: null },
    ],
  };
}

describe("indicateurs du Lab", () => {
  it("compare les blocs contigus des catégories visibles en indiquant leurs dates réelles", () => {
    const view = buildLabGscView(fixture());
    const summary = summarizeLabSelection(view, ["ressource", "classique"]);
    expect(summary.latest).toEqual({ start: "2026-10-26", end: "2026-11-01", clicks: 30 });
    expect(summary.current).toEqual({ start: "2026-10-05", end: "2026-11-01", clicks: 120 });
    expect(summary.previous).toEqual({ start: "2026-09-07", end: "2026-10-04", clicks: 80 });
    expect(summary.changePct).toBe(50);
    expect(summary.totals).toEqual([410, 410, 20, 20, 20, 20, 30, 30, 30, 30]);
    expect(summary.leaders).toEqual(["ressource"]);
    expect(summary.leaderSharePct).toBeCloseTo(100 * 80 / 120);

    const single = summarizeLabSelection(view, ["classique"]);
    expect(single.latest?.clicks).toBe(10);
    expect(single.changePct).toBe(0);
    expect(single.leaderSharePct).toBe(100);
  });

  it("préserve toutes les premières catégories ex æquo", () => {
    const input = fixture();
    for (const w of input.weeks) w.c_ressource = w.c_classique;
    const result = summarizeLabSelection(buildLabGscView(input), ["classique", "ressource", "expertise"]);
    expect(result.leaders).toEqual(["ressource", "classique"]);
    expect(result.leaderSharePct).toBe(40);
  });

  it("distingue un bloc mesuré à zéro d'une évolution ou d'une part indéfinie", () => {
    const view = buildLabGscView(fixture());
    const zero = summarizeLabSelection(view, ["divers"]);
    expect(zero.current?.clicks).toBe(0);
    expect(zero.latest?.clicks).toBe(0);
    expect(zero.changePct).toBeNull();
    expect(zero.leaders).toEqual([]);
    expect(zero.leaderSharePct).toBeNull();
    expect(summarizeLabSelection(view, []).latest).toBeNull();
  });

  it("suspend le calcul si une semaine manque dans le bloc ou en fin de fenêtre", () => {
    const input = fixture();
    input.weeks.splice(7, 1);
    const summary = summarizeLabSelection(buildLabGscView(input), ["ressource"]);
    expect(summary.latest?.clicks).toBe(20);
    expect(summary.current).toBeNull();
    expect(summary.changePct).toBeNull();
    expect(summary.leaders).toEqual([]);
    expect(summary.previous?.clicks).toBe(40);
    input.weeks.pop();
    const missingLast = summarizeLabSelection(buildLabGscView(input), ["ressource"]);
    expect(missingLast.latest).toBeNull();
    expect(missingLast.current).toBeNull();
    const empty = summarizeLabSelection(buildLabGscView({ ...input, weeks: [] }), ["ressource"]);
    expect(empty.totals).toEqual([]);
    expect(empty.previous).toBeNull();
  });

  it("conserve le CTR pondéré du bloc, le pic et tous les repères d'une même semaine", () => {
    const view = buildLabGscView(fixture());
    const resources = view.bands.find((band) => band.key === "ressource")!;
    expect(resources.ctrLast4Pct).toBe(40);
    expect(resources.peak).toBe(400);
    expect(resources.peakWeek).toBe("2026-08-24");
    expect(view.bands.find((band) => band.key === "divers")?.ctrLast4Pct).toBeNull();
    expect(view.markers.map(({ index, label }) => [index, label])).toEqual([
      [9, "Mise en ligne"], [9, "Relecture"],
    ]);
  });
});
