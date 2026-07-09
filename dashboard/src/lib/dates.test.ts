import { describe, expect, it } from "vitest";
import {
  dateFr,
  dayDiff,
  dayGap,
  jjmm,
  jjmmForIndex,
  lastDayLabel,
  parisTodayISO,
} from "./dates";

describe("jjmm", () => {
  it("formate ISO en JJ/MM", () => {
    expect(jjmm("2026-07-02")).toBe("02/07");
  });
  it("retourne tiret si vide", () => {
    expect(jjmm(null)).toBe("—");
  });
});

describe("dateFr", () => {
  it("formate ISO complet", () => {
    expect(dateFr("2026-06-29")).toBe("29/06/2026");
  });
});

describe("dayDiff / dayGap", () => {
  it("compte les jours entre deux ISO", () => {
    expect(dayDiff("2026-06-30", "2026-07-01")).toBe(1);
    expect(dayGap("2026-06-30", "2026-07-02")).toBe(2);
  });
});

describe("jjmmForIndex", () => {
  it("recule depuis lastDay", () => {
    expect(jjmmForIndex("2026-07-03", 0, 3)).toBe("01/07");
    expect(jjmmForIndex("2026-07-03", 2, 3)).toBe("03/07");
  });
});

describe("lastDayLabel", () => {
  it("préfixe au JJ/MM", () => {
    expect(lastDayLabel("2026-07-03")).toBe("au 03/07");
    expect(lastDayLabel(null)).toBe("dern.");
  });
});

describe("parisTodayISO", () => {
  it("utilise Europe/Paris", () => {
    const fixed = new Date("2026-07-09T10:00:00Z");
    expect(parisTodayISO(fixed)).toBe("2026-07-09");
  });
});
