"use client";

import { useState } from "react";
import { SortableTable, type Column } from "./SortableTable";
import { Badge } from "./ui";
import type { SeoQueryRow } from "@/lib/types";
import { num, dec, pct, prettyPath } from "@/lib/format";

const columns: Column<SeoQueryRow>[] = [
  {
    key: "query",
    header: "Requête",
    align: "left",
    sortValue: (r) => r.query,
    render: (r) => (
      <div className="max-w-[300px]">
        <div className="flex items-center gap-2">
          <span className="font-medium text-neutral-900 dark:text-neutral-100">{r.query}</span>
          {r.is_quick_win && <Badge tone="good">quick win</Badge>}
        </div>
        {r.top_page && (
          <div className="truncate text-[11px] text-neutral-400">→ {prettyPath(r.top_page)}</div>
        )}
      </div>
    ),
  },
  { key: "clicks", header: "Clics", align: "right", sortValue: (r) => r.clicks, render: (r) => num(r.clicks) },
  {
    key: "impressions",
    header: "Affichages",
    align: "right",
    sortValue: (r) => r.impressions,
    render: (r) => num(r.impressions),
  },
  {
    key: "position",
    header: "Position",
    align: "right",
    sortValue: (r) => r.position_avg,
    render: (r) => dec(r.position_avg),
  },
  {
    key: "volume",
    header: "Volume DFS / mois",
    align: "right",
    sortValue: (r) => r.volume_fr,
    render: (r) => (r.volume_fr != null ? num(r.volume_fr) : <span className="text-neutral-400">n.d.</span>),
  },
  {
    key: "capture",
    header: "Captation",
    align: "right",
    sortValue: (r) => r.capture_pct,
    render: (r) => pct(r.capture_pct),
  },
];

export function SeoTable({ rows }: { rows: SeoQueryRow[] }) {
  const [quickOnly, setQuickOnly] = useState(false);
  const filtered = quickOnly ? rows.filter((r) => r.is_quick_win) : rows;
  return (
    <div>
      <label className="mb-3 flex w-fit cursor-pointer items-center gap-2 text-sm text-neutral-600 dark:text-neutral-400">
        <input
          type="checkbox"
          checked={quickOnly}
          onChange={(e) => setQuickOnly(e.target.checked)}
          className="accent-neutral-900 dark:accent-neutral-100"
        />
        Quick wins seulement (position 5–15 · volume ≥ 100)
      </label>
      <SortableTable columns={columns} rows={filtered} initialSortKey="clicks" initialDir="desc" />
    </div>
  );
}
