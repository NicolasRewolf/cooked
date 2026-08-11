"use client";

import { SortableTable, type Column } from "./SortableTable";
import { ConfidenceBadge } from "./ui";
import {
  bestQueryColumn,
  contactsColumn,
  ctrColumn,
  dwellColumn,
  gscClicksColumn,
  positionColumn,
  santeColumn,
  visitorsColumn,
} from "./metric-columns";
import { useTableViewState } from "./useTableViewState";
import { cn } from "@/lib/cn";
import type { ExpertiseRow } from "@/lib/types";
import { pct, prettyPath } from "@/lib/format";

// ── Part payante de la page (canal d'acquisition Adwords) ─────────────────────
// Fort = la page vit sur Adwords → la lecture organique repose sur peu de visiteurs.
function PaidCell({ r }: { r: ExpertiseRow }) {
  if (r.paid_share_pct == null) return <span className="text-dim">—</span>;
  const p = r.paid_share_pct;
  const cls = p >= 70 ? "text-warn" : p <= 30 ? "text-up" : "text-ink-2";
  return (
    <span className={cn("font-mono text-[11.5px] font-medium", cls)}>{pct(p, 0)}</span>
  );
}

// Colonnes distinctives des expertises (le reste vient de metric-columns).
const columns: Column<ExpertiseRow>[] = [
  {
    key: "page",
    header: "page expertise",
    align: "left",
    sortValue: (r) => prettyPath(r.path),
    render: (r) => (
      <div className="max-w-[240px]">
        <a
          href={`https://www.jplouton-avocat.fr${r.path}`}
          target="_blank"
          rel="noopener noreferrer"
          className="block truncate text-[12.5px] font-medium text-ink transition-colors hover:text-accent"
        >
          {prettyPath(r.path)}
        </a>
        <div className="mt-[3px] flex items-center gap-[7px]">
          {r.theme && <span className="font-mono text-[10.5px] text-dim">{r.theme}</span>}
          <ConfidenceBadge grade={r.confidence} />
        </div>
      </div>
    ),
  },
  santeColumn,
  {
    key: "paid",
    header: "part paid",
    align: "right",
    headerInfo:
      "Part des sessions voyant cette page arrivées par Google Ads (canal d'entrée de session). Élevé = la page vit de la pub, pas du SEO.",
    sortValue: (r) => r.paid_share_pct,
    render: (r) => <PaidCell r={r} />,
  },
  visitorsColumn,
  dwellColumn(
    "Temps de lecture médian des entrées organiques uniquement — le trafic Ads a un autre comportement.",
  ),
  gscClicksColumn,
  ctrColumn,
  positionColumn,
  bestQueryColumn,
  contactsColumn,
];

export function ExpertisesTable({ rows }: { rows: ExpertiseRow[] }) {
  // Tri dans l'URL (mêmes conventions que les articles ; pas de filtres ici).
  const { sortKey, sortDir, onSortChange } = useTableViewState({ defaultSortKey: "visitors" });

  return (
    <div>
      <h2 className="mb-2.5 font-mono text-[11px] font-semibold uppercase tracking-[0.05em] text-muted">
        expertises [{rows.length}]
      </h2>
      <SortableTable
        columns={columns}
        rows={rows}
        initialSortKey={sortKey}
        initialDir={sortDir}
        minWidth={1040}
        onSortChange={onSortChange}
      />
      <p className="mt-[11px] font-mono text-[10.5px] leading-relaxed text-dim">
        ▲▼ tendances vs période précédente
      </p>
    </div>
  );
}
