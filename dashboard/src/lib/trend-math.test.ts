import { describe, expect, it } from "vitest";
import { linearTrend } from "./trend-math";

describe("linearTrend", () => {
  it("ignore les zéros de début", () => {
    const series = [0, 0, 1, 2, 3, 4, 5, 6];
    const tr = linearTrend(series);
    expect(tr).not.toBeNull();
    expect(tr!.i0).toBe(2);
    expect(tr!.dir).toBe("up");
  });

  it("null si trop peu de points mesurés", () => {
    expect(linearTrend([0, 0, 1, 2])).toBeNull();
  });
});
