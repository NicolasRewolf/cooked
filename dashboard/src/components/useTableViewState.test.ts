import { describe, expect, it } from "vitest";
import { initSortFromUrl, sortParamsToUrl } from "./useTableViewState";

describe("initSortFromUrl", () => {
  it("URL vide → clé par défaut, desc", () => {
    expect(initSortFromUrl(new URLSearchParams(), "visitors")).toEqual({
      sortKey: "visitors",
      sortDir: "desc",
    });
  });
  it("lit sort et dir depuis l'URL", () => {
    expect(initSortFromUrl(new URLSearchParams("sort=gsc_clicks&dir=asc"), "visitors")).toEqual({
      sortKey: "gsc_clicks",
      sortDir: "asc",
    });
  });
  it("dir invalide → desc (fail-safe)", () => {
    expect(initSortFromUrl(new URLSearchParams("dir=haut"), "visitors").sortDir).toBe("desc");
  });
});

describe("sortParamsToUrl", () => {
  it("valeurs par défaut omises (null = param retiré)", () => {
    expect(sortParamsToUrl("visitors", "desc", "visitors")).toEqual({ sort: null, dir: null });
  });
  it("tri non-défaut sérialisé", () => {
    expect(sortParamsToUrl("contacts", "asc", "visitors")).toEqual({
      sort: "contacts",
      dir: "asc",
    });
  });
  it("clé par défaut mais asc → seul dir écrit", () => {
    expect(sortParamsToUrl("visitors", "asc", "visitors")).toEqual({ sort: null, dir: "asc" });
  });
});
