import { describe, expect, it } from "vitest";
import {
  momentumDir,
  momentumLabelFr,
  santeFromMomentum,
  isScored,
  isOpportuniteContact,
  isGisement,
} from "./momentum";

describe("momentumDir / label", () => {
  it("seuils", () => {
    expect(momentumDir(1.1)).toBe("up");
    expect(momentumDir(0.9)).toBe("down");
    expect(momentumDir(1.0)).toBe("flat");
    expect(momentumLabelFr("up")).toBe("monte");
  });
});

describe("santeFromMomentum", () => {
  it("opportunité de contact avant momentum", () => {
    expect(santeFromMomentum(1.2, "A", false)).toBe("opportunite_contact");
    expect(santeFromMomentum(1.2, "S", false)).toBe("opportunite_contact");
  });
  it("nonscore si Fiabilité C", () => {
    expect(santeFromMomentum(1.2, "C", false)).toBe("nonscore");
  });
  it("momentum sinon", () => {
    expect(santeFromMomentum(1.2, "B", true)).toBe("monte");
  });
});

describe("isScored", () => {
  it("faux si grade nul, C, ou momentum nul", () => {
    expect(isScored(null, 1)).toBe(false);
    expect(isScored("C", 1)).toBe(false);
    expect(isScored("A", null)).toBe(false);
    expect(isScored("S", 1)).toBe(true);
  });
});

describe("isOpportuniteContact", () => {
  it("Fiabilité S/A/B sans contact", () => {
    expect(isOpportuniteContact("S", false)).toBe(true);
    expect(isOpportuniteContact("A", false)).toBe(true);
    expect(isOpportuniteContact("B", false)).toBe(true);
    expect(isOpportuniteContact("A", true)).toBe(false);
    expect(isOpportuniteContact("C", false)).toBe(false);
    expect(isOpportuniteContact("A", null)).toBe(false);
    expect(isOpportuniteContact(null, false)).toBe(false);
  });
  it("alias isGisement", () => {
    expect(isGisement("A", false)).toBe(true);
  });
});
