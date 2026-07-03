import type { Annotation, TrendMarker } from "@/lib/types";

// "2026-07-02" -> "02/07"
export function dayShort(iso: string): string {
  const [, m, d] = iso.slice(0, 10).split("-");
  return m && d ? `${d}/${m}` : iso;
}

// Diff en jours entiers entre deux dates ISO (parse à UTC minuit -> pas de DST).
function dayDiff(fromISO: string, toISO: string): number {
  const a = Date.parse(`${fromISO.slice(0, 10)}T00:00:00Z`);
  const b = Date.parse(`${toISO.slice(0, 10)}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

// Annotations -> marqueurs PLATS pour TrendChart. `startISO` = 1er jour de la
// série, `n` = longueur. index = jour - start ; annotations avant le début
// écartées ; annotations récentes au-delà de la fin (ex. lag GSC) clampées au
// dernier point (le tooltip garde la vraie date). Données plates : aucune
// fonction ne traverse la frontière serveur→client.
export function buildMarkers(
  annotations: Annotation[],
  startISO: string | null | undefined,
  n: number,
): TrendMarker[] {
  if (!startISO || n < 2) return [];
  const out: TrendMarker[] = [];
  for (const a of annotations) {
    const idx = dayDiff(startISO, a.day);
    if (idx < 0) continue; // trop ancien pour cette série
    out.push({ index: Math.min(idx, n - 1), label: `${dayShort(a.day)} — ${a.label}`, kind: a.kind });
  }
  return out;
}

// Fiche article : annotations ciblant ce path OU globales (paths NULL/vide,
// ex. passage TV qui concerne tout le site).
export function annotationsForPath(annotations: Annotation[], path: string): Annotation[] {
  return annotations.filter((a) => !a.paths || a.paths.length === 0 || a.paths.includes(path));
}
