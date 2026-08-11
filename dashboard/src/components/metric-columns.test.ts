import { describe, expect, it } from "vitest";
import {
  aggregateCtrPct,
  ctrColumn,
  dwellColumn,
  positionColumn,
  santeColumn,
  sumBy,
  visitorsColumn,
} from "./metric-columns";
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

describe("totaux de pied de tableau", () => {
  it("sumBy traite null / undefined comme 0", () => {
    const rows = [
      row({ contacts: 3 }),
      row({ contacts: 0 }),
      row({ assisted_contacts: undefined }),
    ];
    expect(sumBy(rows, (r) => r.contacts)).toBe(3);
    expect(sumBy(rows, (r) => r.assisted_contacts)).toBe(0);
    expect(sumBy([], (r) => r.contacts)).toBe(0);
  });

  it("aggregateCtrPct = Σ clics / Σ impressions, PAS la moyenne des CTR par page", () => {
    // Une petite page à fort CTR ne doit pas peser autant qu'une grosse page :
    // moyenne naïve des CTR = (50 + 1) / 2 = 25,5 % — le bon chiffre est 1,05 %.
    const rows = [
      row({ gsc_clicks: 5, gsc_impressions: 10 }), // 50 %
      row({ gsc_clicks: 100, gsc_impressions: 9_990 }), // ~1 %
    ];
    expect(aggregateCtrPct(rows)).toBeCloseTo(1.0501, 3);
  });

  it("aggregateCtrPct null si aucune impression (évite la division par zéro)", () => {
    expect(aggregateCtrPct([row({ gsc_clicks: 0, gsc_impressions: 0 })])).toBeNull();
    expect(aggregateCtrPct([])).toBeNull();
  });

  it("les colonnes qui NE totalisent pas restent sans total (position, lecture)", () => {
    // Garde-fou : une position moyenne inter-pages est le piège n°2 du playbook,
    // une médiane de médianes n'est pas une médiane. Ne pas « compléter » le pied.
    expect(positionColumn.total).toBeUndefined();
    expect(dwellColumn("x").total).toBeUndefined();
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
