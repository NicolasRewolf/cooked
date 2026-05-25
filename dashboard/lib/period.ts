/**
 * Périodes business du dashboard — alignées sur cooked_period_bounds() Postgres.
 * URL : ?period=today|week|month|rolling_28|rolling_90
 */

import type { DataLens } from "@/lib/data-lens";

export const PERIOD_KINDS = [
  "today",
  "week",
  "month",
  "rolling_28",
  "rolling_90",
] as const;

export type PeriodKind = (typeof PERIOD_KINDS)[number];

export const DEFAULT_PERIOD: PeriodKind = "rolling_28";

/** Boutons + bandeau — zone Activité (calendrier Paris, Cooked live). */
const LABELS_LIVE: Record<PeriodKind, string> = {
  today: "Aujourd'hui",
  week: "Semaine en cours",
  month: "Mois en cours",
  rolling_28: "28 derniers jours",
  rolling_90: "3 derniers mois",
};

/** Boutons — zone Google (fenêtres ancrées sur gsc_last_day). */
const LABELS_GSC: Record<PeriodKind, string> = {
  today: "Dernier jour",
  week: "Semaine",
  month: "Mois",
  rolling_28: "28 j",
  rolling_90: "90 j",
};

/** Boutons — zone Croisement (même ancrage GSC, lecture mixte). */
const LABELS_CROSS: Record<PeriodKind, string> = {
  today: "Dernier jour aligné",
  week: "Semaine alignée",
  month: "Mois aligné",
  rolling_28: "28 j alignés",
  rolling_90: "90 j alignés",
};

export function isPeriodKind(value: string | undefined): value is PeriodKind {
  return PERIOD_KINDS.includes(value as PeriodKind);
}

export function parsePeriod(
  searchParams: { period?: string } | undefined
): PeriodKind {
  const raw = searchParams?.period;
  if (raw && isPeriodKind(raw)) return raw;
  return DEFAULT_PERIOD;
}

/** Libellé court de la période (boutons, titres KPI) — dépend de la zone. */
export function periodLabel(kind: PeriodKind, lens: DataLens = "live"): string {
  if (lens === "gsc") return LABELS_GSC[kind];
  if (lens === "cross") return LABELS_CROSS[kind];
  return LABELS_LIVE[kind];
}

/** Une ligne sous les boutons quand la sémantique n'est pas calendaire « aujourd'hui ». */
export function periodSelectorHint(lens: DataLens): string | null {
  if (lens === "gsc") {
    return "Les fenêtres se terminent au dernier jour ingéré par Google — pas à aujourd'hui (Paris).";
  }
  if (lens === "cross") {
    return "Même fin de fenêtre que Google ; Cooked est lu sur les mêmes dates.";
  }
  return null;
}

export function periodSubtitle(kind: PeriodKind, lens: DataLens = "live"): string {
  if (lens === "gsc") {
    switch (kind) {
      case "today":
        return "Dernier jour consolidé par Google (pas « aujourd'hui » calendaire).";
      case "week":
        return "Google — depuis le lundi de la semaine du dernier jour GSC.";
      case "month":
        return "Google — depuis le 1er du mois du dernier jour GSC.";
      case "rolling_90":
        return "Google — 90 jours se terminant au dernier jour ingéré.";
      default:
        return "Google — 28 jours se terminant au dernier jour ingéré.";
    }
  }
  if (lens === "cross") {
    switch (kind) {
      case "today":
        return "Croisement sur le dernier jour où Google et Cooked sont alignés.";
      case "week":
        return "Croisement honnête — même fenêtre calendaire, fin au dernier jour GSC.";
      case "month":
        return "Croisement — du 1er du mois au dernier jour GSC consolidé.";
      case "rolling_90":
        return "Croisement — 90 j inclusifs, fin au dernier jour GSC.";
      default:
        return "Croisement — 28 j inclusifs, fin au dernier jour GSC.";
    }
  }
  switch (kind) {
    case "today":
      return "Activité site à jour — aujourd'hui (heure Paris).";
    case "week":
      return "Activité site depuis lundi (semaine en cours, Paris).";
    case "month":
      return "Activité site depuis le 1er du mois (Paris).";
    case "rolling_90":
      return "Activité site sur les 3 derniers mois (90 jours).";
    default:
      return "Activité site sur les 28 derniers jours.";
  }
}

/**
 * Jours inclusifs pour séries journalières (gsc_page_daily_series, etc.)
 * quand la RPC n'accepte pas encore period_kind.
 * Les agrégats métier passent par cooked_period_bounds côté Postgres.
 */
export function periodChartDays(kind: PeriodKind, todayParis = new Date()): number {
  const d = new Date(
    todayParis.toLocaleString("en-US", { timeZone: "Europe/Paris" })
  );
  switch (kind) {
    case "today":
      return 1;
    case "week": {
      const dow = d.getDay();
      const mondayOffset = dow === 0 ? 6 : dow - 1;
      return mondayOffset + 1;
    }
    case "month":
      return d.getDate();
    case "rolling_90":
      return 90;
    default:
      return 28;
  }
}

export function hrefWithPeriod(path: string, period: PeriodKind): string {
  const base = path.split("?")[0] ?? path;
  const params = new URLSearchParams();
  params.set("period", period);
  return `${base}?${params.toString()}`;
}

export function prevPeriodCompareLabel(
  kind: PeriodKind,
  lens: DataLens = "live"
): string {
  if (lens === "gsc" || lens === "cross") {
    switch (kind) {
      case "today":
        return "jour précédent (GSC)";
      case "week":
        return "semaine précédente (même plage, fin GSC)";
      case "month":
        return "mois précédent (même plage, fin GSC)";
      case "rolling_90":
        return "90 j précédents (fin GSC)";
      default:
        return "28 j précédents (fin GSC)";
    }
  }
  switch (kind) {
    case "today":
      return "hier";
    case "week":
      return "semaine précédente (même plage)";
    case "month":
      return "mois précédent (même plage)";
    case "rolling_90":
      return "90 j précédents";
    default:
      return "28 j précédents";
  }
}
