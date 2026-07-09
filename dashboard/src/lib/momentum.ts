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

export function santeFromMomentum(
  momentum: number | null | undefined,
  cpiGrade: string | null | undefined,
  convertit: boolean | null | undefined,
): SanteFilterValue | "gisement" {
  if (cpiGrade == null || cpiGrade === "C" || momentum == null) return "nonscore";
  if ((cpiGrade === "A" || cpiGrade === "B") && convertit === false) return "gisement";
  return momentumLabelFr(momentumDir(momentum)) as SanteFilterValue;
}
