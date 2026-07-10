import { describe, expect, it } from "vitest";
import { ctrColumn, dwellColumn, santeColumn, visitorsColumn } from "./metric-columns";
import type { ResourceRow } from "@/lib/types";

const row = (partial: Partial<ResourceRow>): ResourceRow => partial as ResourceRow;

describe("ctrColumn.sortValue", () => {
  it("trie par écart CTR réel − attendu", () => {
    expect(ctrColumn.sortValue!(row({ gsc_ctr_pct: 3, ctr_expected: 5 }))).toBe(-2);
    expect(ctrColumn.sortValue!(row({ gsc_ctr_pct: 8, ctr_expected: 5 }))).toBe(3);
  });
  it("null si l'un des deux manque (nulls last dans SortableTable)", () => {
    expect(ctrColumn.sortValue!(row({ gsc_ctr_pct: null, ctr_expected: 5 }))).toBeNull();
    expect(ctrColumn.sortValue!(row({ gsc_ctr_pct: 3, ctr_expected: null }))).toBeNull();
  });
});

describe("dwellColumn (factory)", () => {
  it("clé/entête stables, texte ⓘ injecté par le tableau appelant", () => {
    const col = dwellColumn("texte spécifique au tableau");
    expect(col.key).toBe("dwell");
    expect(col.header).toBe("lecture");
    expect(col.align).toBe("right");
    expect(col.headerInfo).toBe("texte spécifique au tableau");
  });
});

describe("colonnes communes — clés de tri stables (contrat des URLs ?sort=)", () => {
  it("les clés restent celles des deux tableaux d'origine", () => {
    expect(santeColumn.key).toBe("sante");
    expect(visitorsColumn.key).toBe("visitors");
    expect(santeColumn.sortValue!(row({ momentum: 1.2 }))).toBe(1.2);
    expect(visitorsColumn.sortValue!(row({ unique_visitors: 42 }))).toBe(42);
  });
});
