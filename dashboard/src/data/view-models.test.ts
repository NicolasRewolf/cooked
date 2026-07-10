import { describe, expect, it } from "vitest";
import {
  buildExpertisesView,
  buildResourcesView,
  buildSeoView,
  mergeAssisted,
} from "./view-models";
import type {
  Annotation,
  AssistedRow,
  ExpertiseKpis,
  ResourceKpis,
  ResourceRow,
  ResourcesTrend,
  SeoKpis,
} from "@/lib/types";

// ---------------------------------------------------------------------------
// Fixtures (valeurs < 1000 pour éviter les espaces insécables d'Intl fr-FR)
// ---------------------------------------------------------------------------

function makeRow(path: string, extra: Partial<ResourceRow> = {}): ResourceRow {
  return {
    path,
    theme: "pénal",
    unique_visitors: 10,
    pageviews: 12,
    dwell_median_s: 45,
    scroll_median: 50,
    gsc_clicks: 3,
    gsc_impressions: 100,
    gsc_position_avg: 8.2,
    gsc_ctr_pct: 3,
    best_query: "garde à vue",
    best_query_clicks: 2,
    best_query_volume_fr: 500,
    best_query_cpc: 1.2,
    contacts: 0,
    booking_intent: 1,
    first_impression_day: "2026-01-01",
    first_tracker_day: "2026-06-01",
    days_live: 120,
    confidence: "B",
    unique_visitors_prev: 8,
    gsc_clicks_prev: 2,
    cpi: 42,
    cpi_grade: "B",
    momentum: 1.02,
    potentiel: 55,
    convertit: false,
    ctr_expected: 4.5,
    cooked_start: "2026-06-10",
    cooked_end: "2026-07-07",
    gsc_start: "2026-06-08",
    gsc_end: "2026-07-05",
    ...extra,
  };
}

const resourceKpis: ResourceKpis = {
  label_fr: "28 derniers jours",
  cooked_start: "2026-06-10",
  cooked_end: "2026-07-07",
  gsc_start: "2026-06-08",
  gsc_end: "2026-07-05",
  gsc_last_day: "2026-07-05",
  lag_days: 2,
  is_partial: false,
  visitors_n: 900,
  visitors_prev: 750,
  pageviews_n: 950,
  pageviews_prev: 950,
  contacts_n: 4,
  contacts_prev: 0,
  gsc_clicks_n: 320,
  gsc_clicks_prev: 400,
  gsc_impressions_n: 999,
  gsc_impressions_prev: 998,
  refreshed_at: "2026-07-08T08:00:00+00:00",
  current_day_partial: false,
  no_prev_baseline: false,
};

const trend: ResourcesTrend = {
  visitors_daily: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  pageviews_daily: [11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
  contacts_daily: [0, 0, 1, 0, 0, 0, 2, 0, 0, 1],
  gsc_clicks_daily: [3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
  gsc_impressions_daily: [9, 9, 9, 9, 9, 9, 9, 9, 9, 9],
};

// ---------------------------------------------------------------------------
// mergeAssisted — le chemin Map
// ---------------------------------------------------------------------------

describe("mergeAssisted", () => {
  const rows = [makeRow("/post/a"), makeRow("/post/b")];
  const assisted: AssistedRow[] = [
    { path: "/post/a", assisted_contacts: 3, assisted_prev: 1 },
    { path: "/post/inconnu", assisted_contacts: 9, assisted_prev: 9 },
  ];

  it("fusionne les contacts assistés sur la ligne correspondante", () => {
    const out = mergeAssisted(rows, assisted);
    expect(out[0].assisted_contacts).toBe(3);
    expect(out[0].assisted_prev).toBe(1);
  });

  it("laisse intacte (même référence) une ligne sans correspondance", () => {
    const out = mergeAssisted(rows, assisted);
    expect(out[1]).toBe(rows[1]);
    expect(out[1].assisted_contacts).toBeUndefined();
  });

  it("ignore les paths assistés absents des lignes", () => {
    const out = mergeAssisted(rows, assisted);
    expect(out).toHaveLength(2);
  });

  it("liste assistée vide ⇒ lignes inchangées", () => {
    const out = mergeAssisted(rows, []);
    expect(out[0]).toBe(rows[0]);
    expect(out[1]).toBe(rows[1]);
  });
});

// ---------------------------------------------------------------------------
// buildResourcesView
// ---------------------------------------------------------------------------

describe("buildResourcesView", () => {
  const annotations: Annotation[] = [
    { day: "2026-06-15", kind: "site_change", label: "Refonte", paths: null },
    { day: "2026-08-01", kind: "presse", label: "Hors fenêtre", paths: null },
  ];

  it("cas nominal : 5 KPIs, deltas et séries branchés", () => {
    const view = buildResourcesView({
      kpis: resourceKpis,
      rows: [makeRow("/post/a")],
      trend,
      assisted: [],
      annotations: [],
    });
    expect(view.items.map((i) => i.label)).toEqual([
      "Visiteurs uniques",
      "Pages vues",
      "Contacts",
      "Clics Google",
      "Affichages Google",
    ]);
    expect(view.items[0].value).toBe("900");
    expect(view.items[0].delta).toMatchObject({ dir: "up", label: "+20 %" });
    expect(view.items[0].series).toBe(trend.visitors_daily);
    expect(view.items[1].delta?.dir).toBe("flat"); // 950 vs 950
    expect(view.items[2].delta).toMatchObject({ dir: "na", label: "—" }); // prev = 0
    expect(view.items[2].tooltip).toBe("Actions faites sur la page (appel ou formulaire).");
    expect(view.items[3].delta?.dir).toBe("down"); // 320 vs 400
    expect(view.items[4].series).toBe(trend.gsc_impressions_daily);
  });

  it("fusionne les contacts assistés dans les lignes", () => {
    const view = buildResourcesView({
      kpis: resourceKpis,
      rows: [makeRow("/post/a"), makeRow("/post/b")],
      trend,
      assisted: [{ path: "/post/b", assisted_contacts: 2, assisted_prev: 0 }],
      annotations: [],
    });
    expect(view.rows[0].assisted_contacts).toBeUndefined();
    expect(view.rows[1].assisted_contacts).toBe(2);
  });

  it("pose les marqueurs d'annotation dans la fenêtre, exclut hors fenêtre", () => {
    const view = buildResourcesView({
      kpis: resourceKpis,
      rows: [],
      trend,
      assisted: [],
      annotations,
    });
    expect(view.markers).toEqual([
      { index: 5, label: "15/06 — Refonte", kind: "site_change" },
    ]);
  });

  it("kpis null ⇒ items vides, pas de marqueurs", () => {
    const view = buildResourcesView({
      kpis: null,
      rows: [makeRow("/post/a")],
      trend,
      assisted: [],
      annotations,
    });
    expect(view.items).toEqual([]);
    expect(view.markers).toEqual([]);
    expect(view.rows).toHaveLength(1);
  });

  it("trend null ⇒ séries absentes (pas de sparkline), pas de marqueurs", () => {
    const view = buildResourcesView({
      kpis: resourceKpis,
      rows: [],
      trend: null,
      assisted: [],
      annotations,
    });
    expect(view.items[0].series).toBeUndefined();
    expect(view.markers).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// buildExpertisesView
// ---------------------------------------------------------------------------

const expertiseKpis: ExpertiseKpis = {
  ...resourceKpis,
  paid_entries_n: 71,
  organic_entries_n: 12,
  total_entries_n: 100,
};

describe("buildExpertisesView", () => {
  it("cas nominal : part payante + hint organique", () => {
    const { items } = buildExpertisesView({ kpis: expertiseKpis, trend });
    expect(items.map((i) => i.label)).toEqual([
      "Visiteurs uniques",
      "Part payante",
      "Contacts",
      "Clics Google",
      "Affichages Google",
    ]);
    expect(items[1].value).toBe("71 %");
    expect(items[1].hint).toBe("12 % organique");
    expect(items[1].delta).toBeUndefined();
    expect(items[1].series).toBeUndefined();
    expect(items[0].series).toBe(trend.visitors_daily);
  });

  it("total_entries_n = 0 ⇒ part payante « — », pas de hint", () => {
    const { items } = buildExpertisesView({
      kpis: { ...expertiseKpis, paid_entries_n: 0, organic_entries_n: 0, total_entries_n: 0 },
      trend,
    });
    expect(items[1].value).toBe("—");
    expect(items[1].hint).toBeUndefined();
  });

  it("kpis null ⇒ items vides", () => {
    expect(buildExpertisesView({ kpis: null, trend }).items).toEqual([]);
  });

  it("trend null ⇒ séries absentes", () => {
    const { items } = buildExpertisesView({ kpis: expertiseKpis, trend: null });
    expect(items[0].series).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// buildSeoView
// ---------------------------------------------------------------------------

const seoKpis: SeoKpis = {
  total_queries: 180,
  total_quick_wins: 14,
  clicks_named_nonbranded: 260,
  clicks_path_total: 610,
  impressions_path_total: 999,
  gsc_start: "2026-06-08",
  gsc_end: "2026-07-05",
};

describe("buildSeoView", () => {
  it("cas nominal : 4 KPIs + lag en jours entiers", () => {
    const now = Date.parse("2026-07-08T10:00:00Z"); // 3 j + 10 h après gsc_end
    const view = buildSeoView(seoKpis, now);
    expect(view.lagDays).toBe(3);
    expect(view.items.map((i) => [i.label, i.value])).toEqual([
      ["Clics Google", "610"],
      ["Affichages Google", "999"],
      ["Requêtes connues", "180"],
      ["Quick wins", "14"],
    ]);
    expect(view.items[0].hint).toBe("toutes requêtes · marque incluse");
    expect(view.items[3].hint).toBe("position 5–15 · volume ≥ 100");
    expect(view.clicksPathTotalLabel).toBe("610");
    expect(view.clicksNamedNonbrandedLabel).toBe("260");
  });

  it("horloge en avance sur gsc_end ⇒ lag borné à 0", () => {
    const now = Date.parse("2026-07-04T10:00:00Z");
    expect(buildSeoView(seoKpis, now).lagDays).toBe(0);
  });

  it("seo null ⇒ lag null et KPIs à zéro (rendu identique à l'existant)", () => {
    const view = buildSeoView(null, Date.parse("2026-07-08T10:00:00Z"));
    expect(view.lagDays).toBeNull();
    expect(view.items.map((i) => i.value)).toEqual(["0", "0", "0", "0"]);
    expect(view.clicksPathTotalLabel).toBe("0");
    expect(view.clicksNamedNonbrandedLabel).toBe("0");
  });
});
