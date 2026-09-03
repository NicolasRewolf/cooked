import { Info } from "./Info";
import type { AssistedQuarter } from "@/lib/types";
import { jjmm } from "@/lib/dates";

const TOOLTIP =
  "Contacts (appel ou formulaire) de visiteurs entrés par un article ressource — " +
  "attribution page d'entrée, trimestre calendaire clos à hier. Pas d'objectif posé pour l'instant.";

const TOOLTIP_UNAVAILABLE =
  "Le compteur du trimestre n'a pas pu être lu. La page reste utilisable ; on réessaie au prochain chargement.";

export function ObjectiveLine({ q }: { q: AssistedQuarter | null }) {
  if (!q) {
    return (
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 font-mono text-[11.5px] text-muted">
        <span>
          <span className="uppercase tracking-[0.04em] text-faint">Contacts nourris par les articles</span>
          {" · "}
          <span className="text-dim">objectif indisponible</span>
        </span>
        <Info>{TOOLTIP_UNAVAILABLE}</Info>
      </div>
    );
  }

  const hasTarget = q.target != null && q.target > 0;
  const pct = hasTarget ? Math.round((100 * q.value) / q.target!) : 0;

  return (
    <div className="flex flex-wrap items-center gap-x-2 gap-y-1 font-mono text-[11.5px] text-muted">
      <span>
        <span className="uppercase tracking-[0.04em] text-faint">Contacts nourris par les articles</span>
        {" · "}
        {q.quarter} (depuis le {jjmm(q.quarter_start)}) : <span className="font-semibold text-ink">{q.value}</span>
        {hasTarget ? (
          <>
            {" / "}
            <span className="font-semibold text-ink">{q.target}</span>
          </>
        ) : null}
      </span>

      {hasTarget && (
        <span className="inline-flex items-center gap-2">
          <span className="relative block h-[3px] w-24 bg-line" aria-hidden>
            <span
              className="absolute inset-y-0 left-0 bg-accent"
              style={{ width: `${Math.min(100, pct)}%` }}
            />
          </span>
          <span className="text-dim">{pct} %</span>
        </span>
      )}

      <Info>{TOOLTIP}</Info>
    </div>
  );
}
