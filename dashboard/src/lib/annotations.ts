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

// M4 — interventions VISIBLES sur le graphe visiteurs mais PAS ENCORE couvertes
// par les données Google : day > gsc_end (droppée du graphe clics par buildMarkers)
// tout en restant dans la fenêtre visiteurs [cooked_start, cooked_end]. Sert la
// note ⚑ posée sous le graphe « Clics Google » pour expliquer l'asymétrie avec le
// graphe visiteurs. Retour PLAT ({ day, label } déjà prêts à afficher), aucune
// fonction — même si ici on rend côté serveur, on garde la discipline.
export function uncoveredByGsc(
  interventions: Annotation[],
  gscEnd: string | null | undefined,
  visStart: string | null | undefined,
  visEnd: string | null | undefined,
): { day: string; label: string }[] {
  if (!gscEnd) return [];
  const out: { day: string; label: string }[] = [];
  for (const a of interventions) {
    if (dayDiff(gscEnd, a.day) <= 0) continue; // day <= gsc_end → déjà couvert par Google
    if (visStart && dayDiff(visStart, a.day) < 0) continue; // avant la fenêtre visiteurs
    if (visEnd && dayDiff(a.day, visEnd) < 0) continue; // après la fenêtre visiteurs (hors des 2 graphes)
    out.push({ day: a.day, label: a.label });
  }
  return out;
}
