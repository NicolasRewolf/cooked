import { describe, expect, it } from "vitest";
import {
  annotationSchema,
  assistedQuarterSchema,
  interventionEffectSchema,
  periodSchema,
  resourceRowSchema,
  resourcesTrendRowSchema,
  resourcesTrendRpcSchema,
  resourceKpisSchema,
} from "./rpc-schemas";

describe("periodSchema", () => {
  it("accepte les fenêtres connues", () => {
    expect(periodSchema.parse("rolling_28")).toBe("rolling_28");
  });
  it("rejette une fenêtre inconnue", () => {
    expect(periodSchema.safeParse("rolling_7").success).toBe(false);
  });
});

const resourceRowFixture = {
  path: "/post/test",
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
  first_impression_day: "2025-01-01",
  first_tracker_day: "2025-06-01",
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
  cooked_start: "2026-06-01",
  cooked_end: "2026-06-28",
  gsc_start: "2026-06-01",
  gsc_end: "2026-06-25",
};

describe("resourceRowSchema", () => {
  it("valide une ligne ressource", () => {
    expect(resourceRowSchema.parse(resourceRowFixture).path).toBe("/post/test");
  });
  it("rejette un champ manquant", () => {
    const { path: _p, ...rest } = resourceRowFixture;
    expect(resourceRowSchema.safeParse(rest).success).toBe(false);
  });
});

describe("resourceKpisSchema", () => {
  it("prend la première ligne", () => {
    const row = resourceKpisSchema.parse([
      {
        label_fr: "28 j",
        cooked_start: "2026-06-01",
        cooked_end: "2026-06-28",
        gsc_start: "2026-06-01",
        gsc_end: "2026-06-25",
        gsc_last_day: "2026-06-25",
        lag_days: 3,
        is_partial: false,
        visitors_n: 100,
        visitors_prev: 90,
        pageviews_n: 200,
        pageviews_prev: 180,
        contacts_n: 2,
        contacts_prev: 1,
        gsc_clicks_n: 50,
        gsc_clicks_prev: 45,
        gsc_impressions_n: 5000,
        gsc_impressions_prev: 4800,
        refreshed_at: "2026-06-29T10:00:00Z",
        current_day_partial: false,
        no_prev_baseline: false,
      },
    ]);
    expect(row?.visitors_n).toBe(100);
  });
});

describe("resourcesTrendRpcSchema", () => {
  const trend = {
    visitors_daily: [1, 2, 3],
    pageviews_daily: [2, 3, 4],
    contacts_daily: [0, 0, 1],
    gsc_clicks_daily: [1, 1, 2],
    gsc_impressions_daily: [10, 12, 11],
  };

  it("accepte objet seul", () => {
    expect(resourcesTrendRpcSchema.parse(trend).visitors_daily).toHaveLength(3);
  });
  it("accepte tableau singleton", () => {
    expect(resourcesTrendRpcSchema.parse([trend]).gsc_clicks_daily[2]).toBe(2);
  });
});

describe("interventionEffectSchema", () => {
  it("valide le contrat B2", () => {
    const row = interventionEffectSchema.parse({
      path: "/post/a",
      day: "2026-06-10",
      gsc_last: "2026-06-25",
      days_post: 14,
      confidence: "indicatif",
      base_trop_faible: false,
      article_jeune: false,
      age_gsc_jours: 90,
      pre_total_clics: 100,
      page_clics_jour_pre: 2,
      page_clics_jour_post: 3,
      pos_pre: 8,
      pos_post: 7,
      clics_pct: 50,
      maree_pct: 10,
      effet_net_pct: 36,
    });
    expect(row.confidence).toBe("indicatif");
  });
});

describe("annotationSchema", () => {
  it("paths nullable", () => {
    expect(annotationSchema.parse({ day: "2026-06-01", kind: "media", label: "TV", paths: null }).kind).toBe(
      "media",
    );
  });
});

describe("assistedQuarterSchema", () => {
  it("target nullable", () => {
    expect(assistedQuarterSchema.parse({ quarter: "T3 2026", quarter_start: "2026-07-01", value: 3, target: null }).value).toBe(3);
  });
});
