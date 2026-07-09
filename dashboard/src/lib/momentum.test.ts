import { describe, expect, it } from "vitest";
import { momentumDir, momentumLabelFr, santeFromMomentum } from "./momentum";

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
