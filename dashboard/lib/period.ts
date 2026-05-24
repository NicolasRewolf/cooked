/**
 * Périodes business du dashboard — alignées sur cooked_period_bounds() Postgres.
 * URL : ?period=today|week|month|rolling_28|rolling_90
 */

export const PERIOD_KINDS = [
  "today",
  "week",
  "month",
  "rolling_28",
  "rolling_90",
] as const;

export type PeriodKind = (typeof PERIOD_KINDS)[number];

export const DEFAULT_PERIOD: PeriodKind = "rolling_28";

const LABELS: Record<PeriodKind, string> = {
  today: "Aujourd'hui",
  week: "Semaine en cours",
  month: "Mois en cours",
  rolling_28: "28 derniers jours",
  rolling_90: "3 derniers mois",
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

export function periodLabel(kind: PeriodKind): string {
  return LABELS[kind];
}

export function periodSubtitle(kind: PeriodKind): string {
  switch (kind) {
    case "today":
      return "Ce que le cabinet a généré aujourd'hui (heure Paris).";
    case "week":
      return "Ce que le cabinet a généré depuis lundi (semaine en cours, Paris).";
    case "month":
      return "Ce que le cabinet a généré depuis le 1er du mois (Paris).";
    case "rolling_90":
      return "Ce que le cabinet a généré sur les 3 derniers mois (90 jours).";
    default:
      return "Ce que le cabinet a généré sur les 28 derniers jours.";
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

export function prevPeriodCompareLabel(kind: PeriodKind): string {
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
