import { cn } from "@/lib/cn";
import { dateFr } from "@/lib/format";

// Dit toujours à quel point la donnée est à jour, et SÉPARE l'alerte (problème réel)
// du simple caveat (jour en cours partiel, comparaison incomplète) — qui sont normaux.
// Ambre = vrai souci : retard Google anormal (>2j) ou snapshot périmé (>36h).
export function FreshnessBanner({
  gscLastDay,
  lagDays,
  cookedEnd,
  refreshedAt,
  currentDayPartial = false,
  noPrevBaseline = false,
  live = false,
}: {
  gscLastDay: string | null;
  lagDays: number | null;
  cookedEnd?: string;
  refreshedAt?: string | null;
  currentDayPartial?: boolean;
  noPrevBaseline?: boolean;
  live?: boolean;
}) {
  const ageHours = refreshedAt ? Math.floor((Date.now() - new Date(refreshedAt).getTime()) / 3_600_000) : null;
  const staleSnapshot = ageHours != null && ageHours > 36;
  const realLag = (lagDays ?? 0) > 2;
  const amber = staleSnapshot || realLag;

  const caveats: string[] = [];
  if (currentDayPartial) caveats.push("jour en cours partiel");
  if (noPrevBaseline) caveats.push("comparaison N-1 incomplète");

  const refreshText =
    ageHours == null ? null : ageHours < 1 ? "actualisé à l'instant" : `actualisé il y a ${ageHours} h`;

  return (
    <div
      className={cn(
        "rounded-lg border px-3 py-2 text-xs",
        amber
          ? "border-amber-300 bg-amber-50 text-amber-800 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-300"
          : "border-neutral-200 bg-neutral-50 text-neutral-600 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-400",
      )}
    >
      {live ? (
        <>Données SEO en direct · Google arrêté au <strong>{dateFr(gscLastDay)}</strong></>
      ) : (
        <>
          Mesure du site au <strong>{dateFr(cookedEnd)}</strong>
          {refreshText ? ` (${refreshText})` : ""} · Google au <strong>{dateFr(gscLastDay)}</strong>
        </>
      )}
      {lagDays != null ? ` (J-${lagDays})` : ""}
      {staleSnapshot ? " · ⚠ snapshot périmé, le refresh quotidien a peut-être échoué" : ""}
      {caveats.length ? ` · ${caveats.join(" · ")}` : ""}
    </div>
  );
}
