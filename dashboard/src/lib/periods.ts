import type { Period } from "@/lib/types";

// Périodes snapshotées (refresh quotidien). rolling_28 / rolling_90 uniquement en V1 ;
// week/month pourront être ajoutées au snapshot ultérieurement.
export const PERIODS: { value: Period; label: string }[] = [
  { value: "rolling_28", label: "28 derniers jours" },
  { value: "rolling_90", label: "3 derniers mois" },
];

const VALID = new Set(PERIODS.map((p) => p.value));

export function parsePeriod(value: string | undefined, fallback: Period = "rolling_90"): Period {
  return value && VALID.has(value as Period) ? (value as Period) : fallback;
}
