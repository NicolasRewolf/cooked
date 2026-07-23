// Verdict momentum relatif au site — un seul foyer de seuils (table + fiche CPI).

export const MOMENTUM_UP = 1.05;
export const MOMENTUM_DOWN = 0.95;

/** Fiabilité CPI S/A/B/C — « fiable » = pas C (norme 23/07/2026). */
export type Fiabilite = "S" | "A" | "B" | "C";

export function isFiabiliteFiable(
  grade: string | null | undefined,
): boolean {
  return grade === "S" || grade === "A" || grade === "B";
}

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
  return isFiabiliteFiable(cpiGrade) && momentum != null;
}

/** Opportunité de contact (ex-gisement) : Fiabilité S/A/B + pas encore de contact. */
export function isOpportuniteContact(
  cpiGrade: string | null | undefined,
  convertit: boolean | null | undefined,
): boolean {
  return isFiabiliteFiable(cpiGrade) && convertit === false;
}

/** @deprecated alias — préférer isOpportuniteContact */
export const isGisement = isOpportuniteContact;

export function santeFromMomentum(
  momentum: number | null | undefined,
  cpiGrade: string | null | undefined,
  convertit: boolean | null | undefined,
): SanteFilterValue | "opportunite_contact" {
  if (!isScored(cpiGrade, momentum)) return "nonscore";
  if (isOpportuniteContact(cpiGrade, convertit)) return "opportunite_contact";
  return momentumLabelFr(momentumDir(momentum!)) as SanteFilterValue;
}
