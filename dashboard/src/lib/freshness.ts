// Fraîcheur affichée par le bandeau (T-10, mission 02/09/2026, constat g-03).
// Le niveau se juge sur la FIN DES DONNÉES (cooked_end), pas sur l'âge du calcul :
// un instantané recalculé chaque heure sur des données arrêtées à J-2 n'est pas frais.
// Module pur : aucune lecture d'horloge ici, l'appelant passe `now`.

import { dayDiff, parisTodayISO } from "./dates";

export type FreshnessLevel = "ok" | "warn" | "alert";

export type FreshnessInput = {
  gscLastDay: string | null;
  lagDays: number | null;
  cookedEnd?: string;
  refreshedAt?: string | null;
  live?: boolean;
  now: Date;
};

export type FreshnessState = {
  level: FreshnessLevel;
  reason: "stale_snapshot" | "cooked_end_late" | "gsc_late" | "fresh";
  /** Jours entre cooked_end et aujourd'hui (Paris) ; null si inconnu ou lens live. */
  cookedGap: number | null;
  /** Heures depuis le dernier calcul ; null si inconnu. */
  ageHours: number | null;
  lag: number;
};

export const GSC_LAG_MAX_DAYS = 3;
export const SNAPSHOT_STALE_HOURS = 36;
/** Heure Paris à partir de laquelle des données à J-2 sont anormales (la séquence
 *  cooked_refresh_after_gsc suit l'ingestion GSC, attendue 06:00 UTC, dérive observée ≤ +12 h). */
export const COOKED_END_LATE_HOUR = 16;

/** Heure Paris (0-23) de `now`. */
export function parisHour(now: Date): number {
  return Number(now.toLocaleTimeString("en-GB", { timeZone: "Europe/Paris", hour: "2-digit", hour12: false }));
}

export function freshnessState(input: FreshnessInput): FreshnessState {
  const lag = input.lagDays ?? 0;
  const ageHours = input.refreshedAt
    ? Math.floor((input.now.getTime() - new Date(input.refreshedAt).getTime()) / 3_600_000)
    : null;
  const cookedGap = !input.live && input.cookedEnd ? dayDiff(input.cookedEnd, parisTodayISO(input.now)) : null;

  if (!input.live && ageHours != null && ageHours > SNAPSHOT_STALE_HOURS) {
    return { level: "alert", reason: "stale_snapshot", cookedGap, ageHours, lag };
  }
  // Fin des données site : J-1 attendu après la séquence ; J-2 le matin est normal ;
  // J-2 après 16 h Paris ou J-3 à toute heure = la séquence n'a pas suivi.
  if (cookedGap != null && (cookedGap >= 3 || (cookedGap === 2 && parisHour(input.now) >= COOKED_END_LATE_HOUR))) {
    return { level: "warn", reason: "cooked_end_late", cookedGap, ageHours, lag };
  }
  if (lag > GSC_LAG_MAX_DAYS) {
    return { level: "warn", reason: "gsc_late", cookedGap, ageHours, lag };
  }
  return { level: "ok", reason: "fresh", cookedGap, ageHours, lag };
}
