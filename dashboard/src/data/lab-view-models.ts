import { dayDiff, weekIndexOf } from "@/lib/dates";
import type { LabGscWeekly } from "@/lib/types";

export type LabBandKey = "ressource" | "classique" | "expertise" | "divers";

export const LAB_BAND_LABELS: Record<LabBandKey, string> = {
  ressource: "Ressources",
  classique: "Classiques",
  expertise: "Expertises",
  divers: "Cabinet & divers",
};

export interface LabBand {
  key: LabBandKey;
  clicks: number[];
  /** Σ clics / Σ impressions sur les quatre dernières semaines de la fenêtre. */
  ctrLast4Pct: number | null;
  peak: number;
  peakWeek: string;
}

export interface LabMarker {
  index: number;
  day: string;
  kind: string;
  label: string;
}

export interface LabGscView {
  /** Lundis ISO réellement présents dans la réponse, par ordre chronologique. */
  weeks: string[];
  gscEnd: string;
  windowStart: string;
  windowEnd: string;
  bands: LabBand[];
  markers: LabMarker[];
}

const KEYS: LabBandKey[] = ["ressource", "classique", "divers", "expertise"];

type WeekBlock = { start: string; end: string; first: number; last: number };

/** La RPC groupe uniquement les semaines présentes. Ne pas remplacer une semaine manquante par une autre. */
function completeBlock(weeks: string[], windowEnd: string, size: number, weeksAgo = 0): WeekBlock | null {
  const last = weeks.findIndex((week) => dayDiff(week, windowEnd) === 6 + 7 * weeksAgo);
  const first = last - size + 1;
  if (first < 0) return null;
  for (let i = first; i < last; i++) {
    if (dayDiff(weeks[i], weeks[i + 1]) !== 7) return null;
  }
  const sunday = new Date(`${weeks[last]}T00:00:00Z`);
  sunday.setUTCDate(sunday.getUTCDate() + 6);
  return { start: weeks[first], end: sunday.toISOString().slice(0, 10), first, last };
}

function sumBlock(values: number[], block: WeekBlock) {
  return values.slice(block.first, block.last + 1).reduce((sum, n) => sum + n, 0);
}

function measuredBlock(values: number[], block: WeekBlock | null) {
  return block && { start: block.start, end: block.end, clicks: sumBlock(values, block) };
}

/** Agrège exclusivement les catégories visibles, sur les semaines closes de la fenêtre fournie par Cooked. */
export function summarizeLabSelection(view: LabGscView, selected: readonly LabBandKey[]) {
  const bands = view.bands.filter((band) => selected.includes(band.key));
  const totals = bands.length ? view.weeks.map((_, i) => bands.reduce((sum, band) => sum + band.clicks[i], 0)) : [];
  const currentBlock = bands.length ? completeBlock(view.weeks, view.windowEnd, 4) : null;
  const previousBlock = bands.length ? completeBlock(view.weeks, view.windowEnd, 4, 4) : null;
  const latest = measuredBlock(totals, bands.length ? completeBlock(view.weeks, view.windowEnd, 1) : null);
  const current = measuredBlock(totals, currentBlock);
  const previous = measuredBlock(totals, previousBlock);
  const changePct = current && previous && previous.clicks > 0
    ? ((current.clicks - previous.clicks) / previous.clicks) * 100 : null;

  const leaders: LabBandKey[] = [];
  let leaderSharePct: number | null = null;
  if (currentBlock && current && current.clicks > 0) {
    const entries = bands.map((band) => ({ key: band.key, clicks: sumBlock(band.clicks, currentBlock) }));
    const maxClicks = Math.max(...entries.map((entry) => entry.clicks));
    leaders.push(...entries.filter((entry) => entry.clicks === maxClicks).map((entry) => entry.key));
    leaderSharePct = (maxClicks / current.clicks) * 100;
  }
  return { totals, latest, current, previous, changePct, leaders, leaderSharePct };
}

export function buildLabGscView(data: LabGscWeekly): LabGscView {
  const weeks = data.weeks.map((w) => w.week_start);
  const current = completeBlock(weeks, data.window_end, 4);
  const bands = KEYS.map((key) => {
    const clicks = data.weeks.map((w) => w[`c_${key}`]);
    const impressions = data.weeks.map((w) => w[`i_${key}`]);
    const currentImpressions = current ? sumBlock(impressions, current) : 0;
    const peak = clicks.length ? Math.max(...clicks) : 0;
    return {
      key,
      clicks,
      ctrLast4Pct: current && currentImpressions > 0 ? (100 * sumBlock(clicks, current)) / currentImpressions : null,
      peak,
      peakWeek: weeks[clicks.indexOf(peak)] ?? "",
    };
  });
  const markers: LabMarker[] = [];
  for (const annotation of data.annotations) {
    const index = weekIndexOf(weeks, annotation.day);
    if (index !== null) markers.push({ index, day: annotation.day, kind: annotation.kind, label: annotation.label });
  }
  return { weeks, gscEnd: data.gsc_end, windowStart: data.window_start, windowEnd: data.window_end, bands, markers };
}
