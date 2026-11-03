import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { SeoTable } from "./SeoTable";
import { SeoReadingGuide } from "./SeoReadingGuide";
import { CtrCell, HealthCell, santeColumn } from "./metric-columns";
import { InterventionEffects } from "./InterventionEffects";
import { articleDetailSchema, seoQueryRowSchema } from "@/data/rpc-schemas";
import type { InterventionEffect, ResourceRow } from "@/lib/types";

describe("sorties sans prédiction non qualifiée", () => {
  it("décrit l'absence de contact observé sans promettre un potentiel", () => {
    const html = renderToStaticMarkup(createElement(HealthCell, {
      r: { cpi_grade: "A", momentum: 1.1, convertit: false, contacts: 9, window_kind: "rolling_90" } as ResourceRow,
    }));
    expect(html).toContain("sans contact organique dans le CPI");
    expect(html).toContain("28 jours");
    expect(santeColumn.headerInfo).toContain("indépendamment de la période du tableau");
    expect(santeColumn.headerInfo).not.toMatch(/fort potentiel|poser un pont/);
    const unknown = renderToStaticMarkup(createElement(HealthCell, {
      r: { cpi_grade: "A", momentum: 1.1, convertit: null } as ResourceRow,
    }));
    expect(unknown).not.toContain("★");
  });

  it("décrit un avant/après relatif au site sans en faire une preuve causale", () => {
    const effect = {
      days_post: 28, confidence: "verdict", base_trop_faible: false,
      clics_pct: 50, maree_pct: 25, effet_net_pct: 20,
      pos_pre: 8, pos_post: 7, article_jeune: false,
    } as InterventionEffect;
    const html = renderToStaticMarkup(createElement(InterventionEffects, {
      items: [{ label: "Titre modifié", day: "2026-10-01", effect }],
    }));
    expect(html).toContain("variation relative au site");
    expect(html).toContain("recul de 28 j");
    expect(html).toContain("ne démontre pas");
    expect(html).not.toMatch(/effet net|verdict complet|lecture fiable/);
  });

  it("ne remplace pas une tendance du site absente par une variation nulle", () => {
    const html = renderToStaticMarkup(createElement(InterventionEffects, {
      items: [{ label: "Titre modifié", day: "2026-10-01", effect: {
        days_post: 28, confidence: "verdict", base_trop_faible: false,
        clics_pct: 50, maree_pct: null, effet_net_pct: 20,
      } as InterventionEffect }],
    }));
    expect(html).toContain("comparaison indisponible");
    expect(html).not.toContain("site 0 %");
  });
  it("montre les observations de « oui » sans transformer son volume national en gain", () => {
    const row = seoQueryRowSchema.parse({
      query: "oui", clicks: 3, impressions: 355, position_avg: 3.5, ctr_pct: 0.85,
      nb_pages: 1, top_page: "/post/faute-inexcusable-employeur-indemnisation",
      top_page_clicks: 3, top_page_theme: null, volume_fr: 110000, cpc: null,
      competition_level: null, capture_pct: 0.01, is_quick_win: false,
      clicks_prev: 0, position_prev: null, ctr_expected: 11, opportunity_clicks: 12099,
      gsc_start: "2026-07-20", gsc_end: "2026-10-17",
    });
    const html = renderToStaticMarkup(createElement(SeoTable, { rows: [row] }));
    expect(html).toContain("oui");
    expect(html).toContain("110");
    expect(html).toContain("0,8 %");
    expect(html).not.toMatch(/gain pot|captation|12.?099|quick win/i);
    const guide = renderToStaticMarkup(createElement(SeoReadingGuide));
    expect(guide).toContain("estimation nationale mensuelle");
    expect(guide).toContain("vérifier son intention");
  });
  it("ne colore ni ne prescrit le CTR à partir d'une attente de position moyenne", () => {
    const render = (expected: number) => renderToStaticMarkup(createElement(CtrCell, {
      r: { gsc_ctr_pct: 3, ctr_expected: expected } as ResourceRow,
    }));
    expect(render(50)).toBe(render(1));
    expect(render(50)).toContain("3,0 %");
    expect(render(50)).not.toMatch(/text-alert|text-up|50/);
  });
  it("préserve les versions CPI fournies sans rejeter les anciennes réponses", () => {
    const schema = articleDetailSchema.shape.cpi_series;
    expect(schema.parse([{ d: "2026-10-19", cpi: 42, cpi_version: "2.2.6" }])[0].cpi_version).toBe("2.2.6");
    expect(schema.parse([{ d: "2026-10-19", cpi: 42 }])[0].cpi_version).toBeUndefined();
  });
});
