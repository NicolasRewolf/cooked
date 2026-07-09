import { describe, expect, it } from "vitest";
import { buildMarkers } from "./annotations";
import type { Annotation } from "./types";

describe("buildMarkers", () => {
  const annotations: Annotation[] = [
    { day: "2026-07-02", kind: "site_change", label: "MAJ titre", paths: ["/post/a"] },
  ];

  it("indexe depuis startISO", () => {
    const markers = buildMarkers(annotations, "2026-07-01", 3);
    expect(markers).toHaveLength(1);
    expect(markers[0].index).toBe(1);
    expect(markers[0].label).toContain("02/07");
  });

  it("ignore hors fenêtre", () => {
    expect(buildMarkers(annotations, "2026-07-05", 2)).toHaveLength(0);
  });
});
