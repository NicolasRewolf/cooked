"use client";

import { SortableTable, type Column } from "./SortableTable";
import { ConfidenceBadge } from "./ui";
import type { ResourceRow } from "@/lib/types";
import { num, seconds, dec, dateFr, prettyPath } from "@/lib/format";

const columns: Column<ResourceRow>[] = [
  {
    key: "article",
    header: "Article",
    align: "left",
    sortValue: (r) => prettyPath(r.path),
    render: (r) => (
      <div className="max-w-[320px]">
        <a
          href={`https://www.jplouton-avocat.fr${r.path}`}
          target="_blank"
          rel="noopener noreferrer"
          className="font-medium text-neutral-900 hover:underline dark:text-neutral-100"
        >
          {prettyPath(r.path)}
        </a>
        {r.theme && <div className="text-[11px] text-neutral-400">{r.theme}</div>}
      </div>
    ),
  },
  {
    key: "days_live",
    header: "Âge",
    align: "right",
    sortValue: (r) => r.days_live,
    render: (r) => (
      <span title={`1ʳᵉ vue ${dateFr(r.first_tracker_day)} · 1ʳᵉ impr. Google ${dateFr(r.first_impression_day)}`}>
        {r.days_live != null ? `${r.days_live} j` : "—"}
      </span>
    ),
  },
  {
    key: "visitors",
    header: "Visiteurs",
    align: "right",
    sortValue: (r) => r.unique_visitors,
    render: (r) => num(r.unique_visitors),
  },
  {
    key: "dwell",
    header: "Lecture méd.",
    align: "right",
    sortValue: (r) => r.dwell_median_s,
    render: (r) => seconds(r.dwell_median_s),
  },
  {
    key: "gsc_clicks",
    header: "Clics Google",
    align: "right",
    sortValue: (r) => r.gsc_clicks,
    render: (r) => num(r.gsc_clicks),
  },
  {
    key: "gsc_impressions",
    header: "Affichages",
    align: "right",
    sortValue: (r) => r.gsc_impressions,
    render: (r) => num(r.gsc_impressions),
  },
  {
    key: "position",
    header: "Position",
    align: "right",
    sortValue: (r) => r.gsc_position_avg,
    render: (r) => dec(r.gsc_position_avg),
  },
  {
    key: "best_query",
    header: "Meilleure requête",
    align: "left",
    sortValue: (r) => r.best_query_volume_fr,
    render: (r) =>
      r.best_query ? (
        <div className="max-w-[240px]">
          <div className="truncate text-neutral-700 dark:text-neutral-300">{r.best_query}</div>
          <div className="text-[11px] text-neutral-400">
            {r.best_query_volume_fr != null ? `${num(r.best_query_volume_fr)} rech./mois` : "volume n.d."}
          </div>
        </div>
      ) : (
        <span className="text-neutral-400">—</span>
      ),
  },
  {
    key: "contacts",
    header: "Contacts",
    align: "right",
    sortValue: (r) => r.contacts,
    render: (r) => num(r.contacts),
  },
  {
    key: "confidence",
    header: "Fiab.",
    align: "right",
    sortValue: (r) => r.confidence,
    render: (r) => <ConfidenceBadge grade={r.confidence} />,
  },
];

export function ResourcesTable({ rows }: { rows: ResourceRow[] }) {
  return <SortableTable columns={columns} rows={rows} initialSortKey="visitors" initialDir="desc" />;
}
