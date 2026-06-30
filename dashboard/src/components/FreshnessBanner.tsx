import { cn } from "@/lib/cn";
import { dateFr } from "@/lib/format";

// Dit toujours à quel point la donnée est à jour, et SÉPARE l'alerte (problème réel)
// du simple caveat (jour en cours partiel, comparaison incomplète) — qui sont normaux.
// Ambre = vrai souci : retard Google anormal (>2j) ou snapshot périmé (>36h).
// Style « instrument » : bande mono, pastille d'état (vert normal · accent live · ambre alerte).
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
  const ageHours = refreshedAt
    // eslint-disable-next-line react-hooks/purity -- Server Component rendu à la requête : heure courante lue une fois
    ? Math.floor((Date.now() - new Date(refreshedAt).getTime()) / 3_600_000)
    : null;
  const staleSnapshot = ageHours != null && ageHours > 36;
  const realLag = (lagDays ?? 0) > 2;
  const amber = staleSnapshot || realLag;

  const caveats: string[] = [];
  if (currentDayPartial) caveats.push("jour en cours partiel");
  if (noPrevBaseline) caveats.push("comparaison N-1 incomplète");

  const refreshText =
    ageHours == null ? null : ageHours < 1 ? "refresh < 1 h" : `refresh −${ageHours} h`;

  const dotClass = amber ? "bg-warn" : live ? "bg-accent" : "bg-up";

  return (
    <div
      className={cn(
        "inline-flex items-center gap-2.5 border px-3 py-2",
        amber ? "border-warn/40 bg-warn/5" : "border-line bg-panel",
      )}
    >
      <span
        className={cn("h-1.5 w-1.5 shrink-0 rounded-full", dotClass)}
        style={{ boxShadow: `0 0 0 3px ${amber ? "rgba(199,122,30,.14)" : live ? "rgba(255,79,4,.14)" : "rgba(47,122,82,.14)"}` }}
      />
      <span className="font-mono text-[11px] leading-snug text-muted">
        {live ? (
          <>
            SEO live · GOOGLE → <strong className="font-semibold text-ink">{dateFr(gscLastDay)}</strong>
          </>
        ) : (
          <>
            SITE → <strong className="font-semibold text-ink">{dateFr(cookedEnd)}</strong>
            {refreshText ? ` · ${refreshText}` : ""} · GOOGLE →{" "}
            <strong className="font-semibold text-ink">{dateFr(gscLastDay)}</strong>
          </>
        )}
        {lagDays != null ? ` [J-${lagDays}${amber ? "" : " OK"}]` : ""}
        {staleSnapshot ? " · ⚠ snapshot périmé, le refresh quotidien a peut-être échoué" : ""}
        {caveats.length ? ` · ${caveats.join(" · ")}` : ""}
      </span>
    </div>
  );
}
