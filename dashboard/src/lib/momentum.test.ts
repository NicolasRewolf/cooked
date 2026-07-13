import { describe, expect, it } from "vitest";
import { momentumDir, momentumLabelFr, santeFromMomentum, isScored, isGisement } from "./momentum";

describe("momentumDir", () => {
  it("seuils 1.05 / 0.95", () => {
    expect(momentumDir(1.06)).toBe("up");
    expect(momentumDir(0.94)).toBe("down");
    expect(momentumDir(1.0)).toBe("flat");
  });
});

describe("santeFromMomentum", () => {
  it("gisement avant momentum", () => {
    expect(santeFromMomentum(1.2, "A", false)).toBe("gisement");
  });
  it("nonscore si grade C", () => {
    expect(santeFromMomentum(1.2, "C", true)).toBe("nonscore");
  });
  it("libellé français", () => {
    expect(santeFromMomentum(1.1, "A", true)).toBe(momentumLabelFr("up"));
  });
});

// Prédicats partagés avec HealthCell — un seul foyer, verrouillé ici.
describe("isScored", () => {
  it("faux si grade nul, C, ou momentum nul", () => {
    expect(isScored(null, 1.1)).toBe(false);
    expect(isScored("C", 1.1)).toBe(false);
    expect(isScored("A", null)).toBe(false);
    expect(isScored(undefined, undefined)).toBe(false);
  });
  it("vrai pour A/B avec momentum", () => {
    expect(isScored("A", 1.0)).toBe(true);
    expect(isScored("B", 0.9)).toBe(true);
  });
});

describe("isGisement", () => {
  it("vrai seulement si A/B ET convertit === false", () => {
    expect(isGisement("A", false)).toBe(true);
    expect(isGisement("B", false)).toBe(true);
    expect(isGisement("A", true)).toBe(false);
    expect(isGisement("C", false)).toBe(false);
    expect(isGisement("A", null)).toBe(false); // null n'est pas false
    expect(isGisement(null, false)).toBe(false);
  });
});
