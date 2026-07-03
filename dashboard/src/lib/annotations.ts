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
// série, `n` = longueur. index = jour - start. On ÉCARTE tout ce qui tombe hors
// de la fenêtre de CE graphe : trop ancien (idx < 0) OU postérieur au dernier
// jour couvert (idx >= n). Ce dernier cas masque une intervention sur le graphe
// « Clics Google » tant que day > gsc_end (le graphe GSC a 2 j de retard) : elle
// apparaîtra quand la fenêtre GSC la rattrapera, et éviter de la poser sous un
// point ANTÉRIEUR à l'intervention (sinon la lecture avant/après B2 se trompe).
// Le graphe visiteurs, lui, la montre dès J0 — c'est le témoin immédiat.
// Données plates : aucune fonction ne traverse la frontière serveur→client.
export function buildMarkers(
  annotations: Annotation[],
  startISO: string | null | undefined,
  n: number,
): TrendMarker[] {
  if (!startISO || n < 2) return [];
  const out: TrendMarker[] = [];
  for (const a of annotations) {
    const idx = dayDiff(startISO, a.day);
    if (idx < 0 || idx >= n) continue; // hors fenêtre de ce graphe
    out.push({ index: idx, label: `${dayShort(a.day)} — ${a.label}`, kind: a.kind });
  }
  return out;
}

// Fiche article : annotations ciblant ce path OU globales (paths NULL/vide,
// ex. passage TV qui concerne tout le site).
export function annotationsForPath(annotations: Annotation[], path: string): Annotation[] {
  return annotations.filter((a) => !a.paths || a.paths.length === 0 || a.paths.includes(path));
}
