// Verdict momentum relatif au site — un seul foyer de seuils (table + fiche CPI).

export const MOMENTUM_UP = 1.05;
export const MOMENTUM_DOWN = 0.95;

export type MomentumDir = "up" | "down" | "flat";

export function momentumDir(m: number): MomentumDir {
  if (m >= MOMENTUM_UP) return "up";
  if (m <= MOMENTUM_DOWN) return "down";
  return "flat";
}

export function momentumLabelFr(dir: MomentumDir): string {
  if (dir === "up") return "monte";
  if (dir === "down") return "ralentit";
  return "stable";
}

export function momentumBadgeFr(dir: MomentumDir): string {
  if (dir === "up") return "↗ monte";
  if (dir === "down") return "↘ ralentit";
  return "→ stable";
}

export type SanteFilterValue = "monte" | "stable" | "ralentit" | "nonscore";

// Prédicats de santé — source UNIQUE, partagée par le filtre (santeFromMomentum)
// et la cellule rendue (HealthCell). Toute évolution du seuil se fait ici, une fois.
export function isScored(
  cpiGrade: string | null | undefined,
  momentum: number | null | undefined,
): boolean {
  return cpiGrade != null && cpiGrade !== "C" && momentum != null;
}

export function isGisement(
  cpiGrade: string | null | undefined,
  convertit: boolean | null | undefined,
): boolean {
  return (cpiGrade === "A" || cpiGrade === "B") && convertit === false;
}

export function santeFromMomentum(
  momentum: number | null | undefined,
  cpiGrade: string | null | undefined,
  convertit: boolean | null | undefined,
): SanteFilterValue | "gisement" {
  if (!isScored(cpiGrade, momentum)) return "nonscore";
  if (isGisement(cpiGrade, convertit)) return "gisement";
  return momentumLabelFr(momentumDir(momentum!)) as SanteFilterValue;
}
