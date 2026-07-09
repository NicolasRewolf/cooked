import { describe, expect, it } from "vitest";
import { delta } from "./format";

describe("delta", () => {
  it("na si prev nul", () => {
    expect(delta(5, 0).dir).toBe("na");
  });
  it("calcule hausse", () => {
    expect(delta(110, 100).label).toBe("+10 %");
    expect(delta(110, 100).dir).toBe("up");
  });
  it("flat sous 1%", () => {
    expect(delta(100.5, 100).dir).toBe("flat");
  });
});
