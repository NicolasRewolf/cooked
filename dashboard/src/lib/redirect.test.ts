import { describe, expect, it } from "vitest";
import { safeNext } from "./redirect";

describe("safeNext", () => {
  it("accepte un chemin interne", () => {
    expect(safeNext("/article/foo")).toBe("/article/foo");
  });
  it("rejette protocol-relative", () => {
    expect(safeNext("//evil.com")).toBe("/");
  });
  it("rejette backslash", () => {
    expect(safeNext("/\\evil.com")).toBe("/");
  });
  it("rejette null", () => {
    expect(safeNext(null)).toBe("/");
  });
});
