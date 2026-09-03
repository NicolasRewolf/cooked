// Lab — view-model PUR du Stream Ribbon « clics Google par type de page ».
// Entrée = contrat Zod de dashboard_lab_gsc_weekly ; sortie = props PLATES pour le
// composant client (frontière RSC : jamais de fonction dans les props).

import { weekIndexOf } from "@/lib/stream-geometry";
import type { LabGscWeek, LabGscWeekly } from "@/lib/types";

export type LabBandKey = "ressource" | "classique" | "expertise" | "divers";

/** Nuance d'encre (token globals.css) : la bande la plus large aujourd'hui est la plus noire. */
export type LabTone = "ink" | "muted" | "faint" | "dim";
const TONES: LabTone[] = ["ink", "muted", "faint", "dim"];

export const LAB_BAND_LABELS: Record<LabBandKey, string> = {
  ressource: "Articles ressources",
  classique: "Articles classiques",
  expertise: "Pages expertise",
  divers: "Cabinet & divers",
};

export interface LabBand {
  key: LabBandKey;
  label: string;
  tone: LabTone;
  /** Clics par semaine (même longueur que `weeks`). */
  clicks: number[];
  /** Impressions par semaine. */
  impressions: number[];
  /** Moyenne hebdo des 4 dernières semaines closes. */
  last4: number;
  /** Moyenne hebdo des 4 semaines closes 8 semaines plus tôt (référence). */
  ref4: number;
  /** CTR (0-100) sur les mêmes blocs de 4 semaines ; null si 0 impression. */
  ctrLast4Pct: number | null;
  ctrRef4Pct: number | null;
  /** Pic hebdo et sa semaine (ISO lundi). */
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
  /** Lundis ISO, ordre chronologique. */
  weeks: string[];
  gscEnd: string;
  windowStart: string;
  windowEnd: string;
  /** Bandes triées : la plus large sur les 4 dernières semaines en premier (= en haut, encre la plus noire). */
  bands: LabBand[];
  totals: number[];
  peakTotal: number;
  peakTotalWeek: string;
  lastTotal: number;
  markers: LabMarker[];
}

const KEYS: LabBandKey[] = ["ressource", "classique", "expertise", "divers"];
const CLICK_COL: Record<LabBandKey, keyof LabGscWeek> = {
  ressource: "c_ressource",
  classique: "c_classique",
  expertise: "c_expertise",
  divers: "c_divers",
};
const IMPR_COL: Record<LabBandKey, keyof LabGscWeek> = {
  ressource: "i_ressource",
  classique: "i_classique",
  expertise: "i_expertise",
  divers: "i_divers",
};

/** Moyenne des `len` valeurs se terminant à l'index `end` (inclus) ; 0 si la fenêtre sort du tableau. */
export function meanBlock(values: number[], end: number, len: number): number {
  const start = end - len + 1;
  if (start < 0 || end >= values.length || len <= 0) return 0;
  let s = 0;
  for (let i = start; i <= end; i++) s += values[i];
  return s / len;
}

function sumBlock(values: number[], end: number, len: number): number {
  return meanBlock(values, end, len) * len;
}

function ctrPct(clicks: number, impressions: number): number | null {
  return impressions > 0 ? (clicks / impressions) * 100 : null;
}

export function buildLabGscView(data: LabGscWeekly): LabGscView {
  const weeks = data.weeks.map((w) => w.week_start);
  const n = weeks.length;
  const last = n - 1;
  const ref = last - 8; // bloc de 4 semaines qui se termine 8 semaines avant le dernier bloc

  const raw = KEYS.map((key) => {
    const clicks = data.weeks.map((w) => Number(w[CLICK_COL[key]]));
    const impressions = data.weeks.map((w) => Number(w[IMPR_COL[key]]));
    let peakIdx = 0;
    for (let i = 1; i < n; i++) if (clicks[i] > clicks[peakIdx]) peakIdx = i;
    return {
      key,
      label: LAB_BAND_LABELS[key],
      clicks,
      impressions,
      last4: meanBlock(clicks, last, 4),
      ref4: meanBlock(clicks, ref, 4),
      ctrLast4Pct: ctrPct(sumBlock(clicks, last, 4), sumBlock(impressions, last, 4)),
      ctrRef4Pct: ctrPct(sumBlock(clicks, ref, 4), sumBlock(impressions, ref, 4)),
      peak: n ? clicks[peakIdx] : 0,
      peakWeek: n ? weeks[peakIdx] : "",
    };
  });
  // Tri stable : plus large aujourd'hui en premier ; égalité → ordre canonique.
  const sorted = raw
    .map((b, i) => ({ b, i }))
    .sort((a, z) => z.b.last4 - a.b.last4 || a.i - z.i)
    .map(({ b }, rank) => ({ ...b, tone: TONES[Math.min(rank, TONES.length - 1)] }));

  const totals = weeks.map((_, i) => raw.reduce((s, b) => s + b.clicks[i], 0));
  let peakIdx = 0;
  for (let i = 1; i < n; i++) if (totals[i] > totals[peakIdx]) peakIdx = i;

  const markers: LabMarker[] = [];
  for (const a of data.annotations) {
    const index = weekIndexOf(weeks, a.day);
    if (index === null) continue;
    markers.push({ index, day: a.day, kind: a.kind, label: a.label });
  }

  return {
    weeks,
    gscEnd: data.gsc_end,
    windowStart: data.window_start,
    windowEnd: data.window_end,
    bands: sorted,
    totals,
    peakTotal: n ? totals[peakIdx] : 0,
    peakTotalWeek: n ? weeks[peakIdx] : "",
    lastTotal: n ? totals[last] : 0,
    markers,
  };
}
