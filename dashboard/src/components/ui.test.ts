import { describe, expect, it } from "vitest";
import { dirClass, dirDotClass, dirGlyph } from "./ui";

// Vocabulaire delta unifié : tout écart ici casserait le rendu pixel-identique
// de Trend / DeltaTag / PosTrend / points momentum.
describe("dirGlyph", () => {
  it("▲ / ▼ / ▬", () => {
    expect(dirGlyph("up")).toBe("▲");
    expect(dirGlyph("down")).toBe("▼");
    expect(dirGlyph("flat")).toBe("▬");
  });
});

describe("dirClass (texte)", () => {
  it("up vert · down rouge · flat estompé", () => {
    expect(dirClass("up")).toBe("text-up");
    expect(dirClass("down")).toBe("text-down");
    expect(dirClass("flat")).toBe("text-faint");
  });
});

describe("dirDotClass (point momentum)", () => {
  it("la baisse est un avertissement (bg-warn), pas une alerte", () => {
    expect(dirDotClass("up")).toBe("bg-up");
    expect(dirDotClass("down")).toBe("bg-warn");
    expect(dirDotClass("flat")).toBe("bg-faint");
  });
});
