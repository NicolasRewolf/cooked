"use client";

import { useState } from "react";
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
  { key: "visitors", header: "Visiteurs", align: "right", sortValue: (r) => r.unique_visitors, render: (r) => num(r.unique_visitors) },
  { key: "dwell", header: "Lecture méd.", align: "right", sortValue: (r) => r.dwell_median_s, render: (r) => seconds(r.dwell_median_s) },
  { key: "gsc_clicks", header: "Clics Google", align: "right", sortValue: (r) => r.gsc_clicks, render: (r) => num(r.gsc_clicks) },
  { key: "gsc_impressions", header: "Affichages", align: "right", sortValue: (r) => r.gsc_impressions, render: (r) => num(r.gsc_impressions) },
  {
    key: "position",
    header: "Position",
    align: "right",
    sortValue: (r) => r.gsc_position_avg,
    render: (r) => (
      <span title="Moyenne pondérée par impressions, toutes requêtes confondues — peut masquer une requête commerciale en page 3 derrière des informationnelles bien classées.">
        {dec(r.gsc_position_avg)}
      </span>
    ),
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
    key: "tel",
    header: "Tél. lecture",
    align: "right",
    sortValue: (r) => r.contacts,
    render: (r) => (
      <span
        className={r.contacts > 0 ? "text-neutral-700 dark:text-neutral-300" : "text-neutral-400"}
        title="Appels tél. déclenchés pendant la lecture de l'article — signal incident, PAS une conversion attribuée (les formulaires ne portent jamais le path d'un article)."
      >
        {num(r.contacts)}
      </span>
    ),
  },
  { key: "confidence", header: "Fiab.", align: "right", sortValue: (r) => r.confidence, render: (r) => <ConfidenceBadge grade={r.confidence} /> },
];

export function ResourcesTable({ rows }: { rows: ResourceRow[] }) {
  const [recentOnly, setRecentOnly] = useState(false);
  const filtered = recentOnly ? rows.filter((r) => r.days_live != null && r.days_live <= 60) : rows;
  return (
    <div>
      <label className="mb-3 flex w-fit cursor-pointer items-center gap-2 text-sm text-neutral-600 dark:text-neutral-400">
        <input
          type="checkbox"
          checked={recentOnly}
          onChange={(e) => setRecentOnly(e.target.checked)}
          className="accent-neutral-900 dark:accent-neutral-100"
        />
        Articles récents seulement (≤ 60 j) — ton flux éditorial du mois
      </label>
      <SortableTable columns={columns} rows={filtered} initialSortKey="visitors" initialDir="desc" />
    </div>
  );
}
