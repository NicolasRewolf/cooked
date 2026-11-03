import { describe, expect, it } from "vitest";
import { buildArticleAnalysisPrompt } from "./analysis-prompt";

describe("question copiée depuis une fiche article", () => {
  it("emporte les dates propres aux sources et les versions du calcul", () => {
    const prompt = buildArticleAnalysisPrompt({
      path: "/post/exemple", period: "rolling_28",
      bounds: {
        cooked_start: "2026-10-05", cooked_end: "2026-11-01",
        gsc_start: "2026-10-02", gsc_end: "2026-10-29",
      },
      cpiVersions: ["2.2.5", "2.2.6", "2.2.6"],
      cpiDay: "2026-11-02",
      missingSources: [],
    });
    expect(prompt).toContain("/post/exemple");
    expect(prompt).toContain("Cooked : du 05/10/2026 au 01/11/2026 (jours Paris)");
    expect(prompt).toContain("Google : du 02/10/2026 au 29/10/2026 (jours Pacifique)");
    expect(prompt).toContain("Versions CPI présentes : 2.2.5, 2.2.6");
    expect(prompt).toContain("Instantané CPI affiché : 02/11/2026");
    expect(prompt).toContain("28 jours de trafic organique, indépendante de la fenêtre du tableau");
    expect(prompt).toContain("Retrouve ses bornes exactes");
    expect(prompt).toContain("ruptures de version");
    expect(prompt).toContain("ne prouve pas un appel abouti");
  });

  it("signale les données et versions absentes au lieu d'inventer un état complet", () => {
    const prompt = buildArticleAnalysisPrompt({
      path: "/post/exemple", period: "rolling_90",
      bounds: {
        cooked_start: "2026-08-04", cooked_end: "2026-11-01",
        gsc_start: "2026-08-01", gsc_end: "2026-10-29",
      },
      cpiVersions: [null],
      cpiDay: null,
      missingSources: ["résumé Google", "contacts assistés"],
    });
    expect(prompt).toContain("90 jours");
    expect(prompt).toContain("Versions CPI présentes : indisponibles");
    expect(prompt).toContain("certains points ne sont pas versionnés");
    expect(prompt).toContain("Données indisponibles dans la fiche : résumé Google, contacts assistés");
    expect(prompt).toContain("une donnée absente n'est pas un zéro");
  });
});
