import { dayDiff } from "./dates";

type CpiPoint = { d: string; cpi: number; cpi_version?: string | null };

/** Une ligne ne doit relier ni deux définitions ni deux périodes séparées.
 *  Avant migration, les points non versionnés restent lisibles par Zod mais ne
 *  donnent pas lieu à une trajectoire dont la comparabilité serait inconnue. */
export function comparableCpiHistory(points: CpiPoint[], currentVersion?: string | null): CpiPoint[] {
  if (!currentVersion) return [];
  const sorted = [...points].sort((a, b) => a.d.localeCompare(b.d));
  let start = sorted.length;
  for (let i = sorted.length - 1; i >= 0; i--) {
    if (sorted[i].cpi_version !== currentVersion) break;
    if (i < sorted.length - 1 && dayDiff(sorted[i].d, sorted[i + 1].d) !== 1) break;
    start = i;
  }
  return sorted.slice(start);
}
