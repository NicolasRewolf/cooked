import { cn } from "@/lib/cn";
import { dateFr } from "@/lib/format";

// Affiche la fraîcheur réelle de la donnée. Le dashboard dit toujours à quel point il est à jour.
export function FreshnessBanner({
  cookedEnd,
  gscLastDay,
  lagDays,
  isPartial,
}: {
  cookedEnd: string;
  gscLastDay: string | null;
  lagDays: number | null;
  isPartial: boolean;
}) {
  const stale = (lagDays ?? 0) > 2 || isPartial;
  return (
    <div
      className={cn(
        "rounded-lg border px-3 py-2 text-xs",
        stale
          ? "border-amber-300 bg-amber-50 text-amber-800 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-300"
          : "border-neutral-200 bg-neutral-50 text-neutral-600 dark:border-neutral-800 dark:bg-neutral-900 dark:text-neutral-400",
      )}
    >
      Mesure du site arrêtée au <strong>{dateFr(cookedEnd)}</strong> · Google arrêté au{" "}
      <strong>{dateFr(gscLastDay)}</strong>
      {lagDays != null ? ` (décalage ${lagDays} j)` : ""}
      {isPartial ? " · période en cours (comparaison N-1 partielle)" : ""}
    </div>
  );
}
