import { describe, expect, it } from "vitest";
import { comparableCpiHistory } from "./cpi-history";

describe("trajectoire CPI comparable", () => {
  it("coupe à la dernière rupture de définition, même si une ancienne version réapparaît", () => {
    const points = [
      { d: "2026-10-16", cpi: 30, cpi_version: "2" },
      { d: "2026-10-17", cpi: 60, cpi_version: "1" },
      { d: "2026-10-18", cpi: 40, cpi_version: "2" },
      { d: "2026-10-19", cpi: 41, cpi_version: "2" },
    ];
    expect(comparableCpiHistory(points, "2").map((p) => p.cpi)).toEqual([40, 41]);
  });
  it("ne relie pas des jours absents", () => {
    expect(comparableCpiHistory([
      { d: "2026-10-16", cpi: 30, cpi_version: "2" },
      { d: "2026-10-19", cpi: 41, cpi_version: "2" },
    ], "2").map((p) => p.cpi)).toEqual([41]);
  });
  it("reste prudent avec la RPC historique non versionnée ou un nouveau score sans historique", () => {
    expect(comparableCpiHistory([{ d: "2026-10-19", cpi: 41 }], "2")).toEqual([]);
    expect(comparableCpiHistory([{ d: "2026-10-19", cpi: 41, cpi_version: "1" }], "2")).toEqual([]);
    expect(comparableCpiHistory([{ d: "2026-10-19", cpi: 41, cpi_version: "2" }])).toEqual([]);
  });
});
