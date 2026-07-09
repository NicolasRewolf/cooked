import type { Annotation, TrendMarker } from "@/lib/types";
import { dayDiff, dayShort } from "@/lib/dates";

export { dayShort };

export function buildMarkers(
  annotations: Annotation[],
  startISO: string | null | undefined,
  n: number,
): TrendMarker[] {
  if (!startISO || n < 2) return [];
  const out: TrendMarker[] = [];
  for (const a of annotations) {
    const idx = dayDiff(startISO, a.day);
    if (idx < 0 || idx >= n) continue;
    out.push({ index: idx, label: `${dayShort(a.day)} — ${a.label}`, kind: a.kind });
  }
  return out;
}

export function annotationsForPath(annotations: Annotation[], path: string): Annotation[] {
  return annotations.filter((a) => !a.paths || a.paths.length === 0 || a.paths.includes(path));
}

export function uncoveredByGsc(
  interventions: Annotation[],
  gscEnd: string | null | undefined,
  visStart: string | null | undefined,
  visEnd: string | null | undefined,
): { day: string; label: string }[] {
  if (!gscEnd) return [];
  const out: { day: string; label: string }[] = [];
  for (const a of interventions) {
    if (dayDiff(gscEnd, a.day) <= 0) continue;
    if (visStart && dayDiff(visStart, a.day) < 0) continue;
    if (visEnd && dayDiff(a.day, visEnd) < 0) continue;
    out.push({ day: a.day, label: a.label });
  }
  return out;
}
