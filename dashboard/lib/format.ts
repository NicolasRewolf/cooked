/**
 * lib/format.ts — Helpers de formatage FR.
 *
 * Règles CLAUDE.md Cooked :
 *  - dates : JJ/MM/AAAA dans l'UI (jamais ISO)
 *  - timezone : Europe/Paris partout (les valeurs DB sont en UTC)
 *  - heures : HH:MM Paris
 *  - nombres : espace fine pour les milliers, virgule décimale
 */

const PARIS_TZ = "Europe/Paris";

/** "2026-05-22 11:39:14.058133" (UTC) → "22/05/2026" Paris */
export function formatDateFR(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: PARIS_TZ,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(d);
}

/** "...11:39:14" UTC → "22/05/2026 13:39" Paris (DST-safe) */
export function formatDateTimeFR(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("fr-FR", {
    timeZone: PARIS_TZ,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(d);
}

export function formatInt(n: number | null | undefined): string {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 }).format(n);
}

export function formatPct(
  n: number | null | undefined,
  digits = 1
): string {
  if (n == null) return "—";
  return `${new Intl.NumberFormat("fr-FR", {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(n)} %`;
}

export function formatNumber(
  n: number | null | undefined,
  digits = 2
): string {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-FR", {
    minimumFractionDigits: 0,
    maximumFractionDigits: digits,
  }).format(n);
}

export function formatDurationSeconds(s: number | null | undefined): string {
  if (s == null) return "—";
  if (s < 60) return `${formatNumber(s, 0)}s`;
  const min = Math.floor(s / 60);
  const sec = Math.round(s % 60);
  return `${min}min ${sec.toString().padStart(2, "0")}s`;
}

/** "1.5h" / "23min" / "3j" pour les âges humains */
export function formatAge(hours: number | null | undefined): string {
  if (hours == null) return "—";
  if (hours < 1) return `${Math.round(hours * 60)}min`;
  if (hours < 48) return `${formatNumber(hours, 1)}h`;
  return `${Math.round(hours / 24)}j`;
}
