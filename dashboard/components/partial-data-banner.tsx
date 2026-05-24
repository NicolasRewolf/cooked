import { formatDateFR } from "@/lib/format";

export function PartialDataBanner({
  trackerFirstSeen,
}: {
  trackerFirstSeen: string | null;
}) {
  if (!trackerFirstSeen) return null;

  return (
    <div className="border-b border-warning/30 bg-warning/5 px-6 py-2 text-center text-sm text-muted-foreground">
      Données Cooked partielles sur cette période — capture depuis le{" "}
      <span className="font-medium text-foreground">
        {formatDateFR(trackerFirstSeen)}
      </span>{" "}
      (heure Paris). Les trous se comblent au fil des jours.
    </div>
  );
}
