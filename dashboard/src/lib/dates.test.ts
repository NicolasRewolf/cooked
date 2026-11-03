import { describe, expect, it } from "vitest";
import {
  dateFr,
  dayDiff,
  jjmm,
  jjmmForIndex,
  lastDayLabel,
  parisTodayISO,
  weekIndexOf,
} from "./dates";

describe("jjmm", () => {
  it("formate ISO en JJ/MM", () => {
    expect(jjmm("2026-07-02")).toBe("02/07");
  });
  it("retourne tiret si vide", () => {
    expect(jjmm(null)).toBe("—");
  });
});

it("associe un repère uniquement à une semaine réellement disponible", () => {
  const weeks = ["2026-08-03", "2026-08-17"];
  expect(weekIndexOf(weeks, "2026-08-03")).toBe(0);
  expect(weekIndexOf(weeks, "2026-08-09")).toBe(0);
  expect(weekIndexOf(weeks, "2026-08-12")).toBeNull();
  expect(weekIndexOf(weeks, "2026-08-23")).toBe(1);
  expect(weekIndexOf(weeks, "2026-08-24")).toBeNull();
});

describe("dateFr", () => {
  it("formate ISO complet", () => {
    expect(dateFr("2026-06-29")).toBe("29/06/2026");
  });
});

describe("dayDiff", () => {
  it("compte les jours entre deux ISO", () => {
    expect(dayDiff("2026-06-30", "2026-07-01")).toBe(1);
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
