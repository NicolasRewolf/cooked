// Dates JJ/MM et arithmétique calendaire (Europe/Paris + UTC minuit pour les écarts).
// Foyer unique — ne pas ré-encoder slice(0,10).split("-") dans les composants.

const MS_PER_DAY = 86_400_000;

/** "2026-07-02" → "02/07" (ou "—" si vide). */
export function jjmm(iso?: string | null): string {
  if (!iso) return "—";
  const [, m, d] = iso.slice(0, 10).split("-");
  return m && d ? `${d}/${m}` : iso;
}

/** Alias sémantique (annotations, timelines). */
export const dayShort = jjmm;

/** timestamptz ISO → "02/07 à 14:30" (heure de Paris). */
export function jjmmHeure(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  const date = d.toLocaleDateString("fr-FR", { timeZone: "Europe/Paris", day: "2-digit", month: "2-digit" });
  const heure = d.toLocaleTimeString("fr-FR", { timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit" });
  return `${date} à ${heure}`;
}

/** Jour calendaire courant en Europe/Paris → "YYYY-MM-DD". */
export function parisTodayISO(now: Date = new Date()): string {
  return now.toLocaleDateString("en-CA", { timeZone: "Europe/Paris" });
}

/** Écart en jours entiers (parse à minuit UTC → pas de DST). */
export function dayDiff(fromISO: string, toISO: string): number {
  const a = Date.parse(`${fromISO.slice(0, 10)}T00:00:00Z`);
  const b = Date.parse(`${toISO.slice(0, 10)}T00:00:00Z`);
  return Math.round((b - a) / MS_PER_DAY);
}

/** Alias historique (FreshnessBanner). */
export const dayGap = dayDiff;

/** "2026-06-29" → "29/06/2026" */
export function dateFr(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.slice(0, 10).split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

/** Date JJ/MM du point d'index i : lastDay − (n−1−i) jours (UTC pur, déterministe). */
export function jjmmForIndex(lastDay: string | null | undefined, i: number, n: number): string | null {
  if (!lastDay) return null;
  const base = Date.parse(`${lastDay.slice(0, 10)}T00:00:00Z`);
  if (Number.isNaN(base)) return null;
  const d = new Date(base - (n - 1 - i) * MS_PER_DAY);
  const dd = String(d.getUTCDate()).padStart(2, "0");
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  return `${dd}/${mm}`;
}

/** Dernier jour couvert → "au JJ/MM" ou repli "dern.". */
export function lastDayLabel(lastDay?: string | null): string {
  if (!lastDay) return "dern.";
  const short = jjmm(lastDay);
  return short === "—" ? "dern." : `au ${short}`;
}
