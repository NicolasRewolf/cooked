import { dateFr } from "./dates";
import type { ArticleDetail, Period } from "./types";

export type ArticleAnalysisContext = {
  path: string;
  period: Period;
  bounds: ArticleDetail["bounds"];
  cpiVersions: (string | null | undefined)[];
  cpiDay: string | null;
  missingSources: string[];
};

/** Texte transféré par l'utilisateur : conserver la fenêtre réellement affichée. */
export function buildArticleAnalysisPrompt(context: ArticleAnalysisContext): string {
  const { path, period, bounds, missingSources } = context;
  const versions = [...new Set(context.cpiVersions.filter((v): v is string => !!v))];
  const unversioned = context.cpiVersions.some((v) => !v);
  return [
    `Cooked : analyse l'article ${path}, depuis sa fiche dashboard (${period === "rolling_90" ? "90" : "28"} jours).`,
    `Cooked : du ${dateFr(bounds.cooked_start)} au ${dateFr(bounds.cooked_end)} (jours Paris).`,
    `Google : du ${dateFr(bounds.gsc_start)} au ${dateFr(bounds.gsc_end)} (jours Pacifique).`,
    `Instantané CPI affiché : ${context.cpiDay ? dateFr(context.cpiDay) : "indisponible"}. Sa fenêtre couvre 28 jours de trafic organique, indépendante de la fenêtre du tableau. Retrouve ses bornes exactes avant toute comparaison.`,
    `Versions CPI présentes : ${versions.join(", ") || "indisponibles"}${unversioned ? " ; certains points ne sont pas versionnés" : ""}.`,
    `Données indisponibles dans la fiche : ${missingSources.join(", ") || "aucune signalée"}.`,
    "Garde ces bornes pour l'analyse et vérifie leur fraîcheur avant de conclure. Respecte les ruptures de version du CPI ; une donnée absente n'est pas un zéro.",
    "Explique la trajectoire, les requêtes et les composantes du score. Un clic téléphone ne prouve pas un appel abouti ; les contacts ne mesurent pas des clients acquis. Un avant/après ne prouve pas un effet causal.",
    "Propose une seule action si les observations la justifient, ou explique pourquoi attendre. Distingue observations, hypothèses et réserves.",
  ].join("\n");
}
