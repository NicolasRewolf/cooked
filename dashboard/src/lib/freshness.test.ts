import { describe, expect, it } from "vitest";
import { freshnessState, parisHour } from "./freshness";

// Heure Paris → Date UTC (été : UTC+2).
const paris = (iso: string) => new Date(`${iso}+02:00`);

describe("freshnessState — fin des données (g-03)", () => {
  it("rejeu du 28/08/2026 : données à J-2 après 16 h Paris → orange", () => {
    // Le 28/08 la séquence est partie à 21:00 Paris ; jusque-là cooked_end = 26/08.
    const s = freshnessState({
      gscLastDay: "2026-08-25", lagDays: 3, cookedEnd: "2026-08-26",
      refreshedAt: "2026-08-27T18:05:00Z", now: paris("2026-08-28T17:00:00"),
    });
    expect(s.level).toBe("warn");
    expect(s.reason).toBe("cooked_end_late");
    expect(s.cookedGap).toBe(2);
  });
  it("rejeu du 28/08/2026 : le matin, J-2 est l'état normal → vert", () => {
    const s = freshnessState({
      gscLastDay: "2026-08-25", lagDays: 3, cookedEnd: "2026-08-26",
      refreshedAt: "2026-08-27T18:05:00Z", now: paris("2026-08-28T09:00:00"),
    });
    expect(s.level).toBe("ok");
    expect(s.cookedGap).toBe(2);
  });
  it("J-3 à toute heure → orange, même si le calcul est récent", () => {
    const s = freshnessState({
      gscLastDay: "2026-08-31", lagDays: 3, cookedEnd: "2026-08-31",
      refreshedAt: "2026-09-03T00:30:00Z", now: paris("2026-09-03T03:00:00"),
    });
    expect(s.level).toBe("warn");
    expect(s.reason).toBe("cooked_end_late");
    expect(s.cookedGap).toBe(3);
  });
  it("après la séquence : J-1 → vert", () => {
    const s = freshnessState({
      gscLastDay: "2026-08-31", lagDays: 3, cookedEnd: "2026-09-02",
      refreshedAt: "2026-09-03T15:00:00Z", now: paris("2026-09-03T22:00:00"),
    });
    expect(s.level).toBe("ok");
    expect(s.cookedGap).toBe(1);
  });
  it("calcul > 36 h prime (rouge)", () => {
    const s = freshnessState({
      gscLastDay: "2026-08-31", lagDays: 3, cookedEnd: "2026-09-01",
      refreshedAt: "2026-09-01T15:00:00Z", now: paris("2026-09-03T22:00:00"),
    });
    expect(s.level).toBe("alert");
    expect(s.reason).toBe("stale_snapshot");
  });
  it("Google en retard > 3 j → orange (gsc_late)", () => {
    const s = freshnessState({
      gscLastDay: "2026-08-28", lagDays: 5, cookedEnd: "2026-09-02",
      refreshedAt: "2026-09-03T15:00:00Z", now: paris("2026-09-03T22:00:00"),
    });
    expect(s.level).toBe("warn");
    expect(s.reason).toBe("gsc_late");
  });
  it("lens live : pas de cooked_end, seul Google compte", () => {
    const s = freshnessState({ gscLastDay: "2026-08-31", lagDays: 3, live: true, now: paris("2026-09-03T22:00:00") });
    expect(s.level).toBe("ok");
    expect(s.cookedGap).toBeNull();
  });
});

describe("parisHour", () => {
  it("lit l'heure de Paris (été)", () => {
    expect(parisHour(new Date("2026-08-28T15:00:00Z"))).toBe(17);
  });
  it("minuit Paris = 22 h UTC la veille", () => {
    expect(parisHour(new Date("2026-08-27T22:30:00Z"))).toBe(0);
  });
});
