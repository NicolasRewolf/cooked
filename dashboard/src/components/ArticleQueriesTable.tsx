"use client";

import { SortableTable, type Column } from "./SortableTable";
import { num, dec } from "@/lib/format";
import type { ArticleDetail } from "@/lib/types";

type QueryRow = ArticleDetail["top_queries"][number];

// Les colonnes (avec leurs fonctions render/sortValue) vivent CÔTÉ CLIENT —
// une page serveur ne peut pas passer de fonctions à un composant client
// (leçon du 03/07 : crash RSC en prod, invisible à tsc et au test local gaté).
const columns: Column<QueryRow>[] = [
  {
    key: "query",
    header: "requête",
    align: "left",
    sortValue: (r) => r.query,
    render: (r) => <span className="text-[12px] text-ink">{r.query}</span>,
  },
  {
    key: "impressions",
    header: "affichages",
    align: "right",
    sortValue: (r) => r.impressions,
    render: (r) => <span className="font-mono text-[11.5px] text-[#45423c]">{num(r.impressions)}</span>,
  },
  {
    key: "clicks",
    header: "clics",
    align: "right",
    sortValue: (r) => r.clicks,
    render: (r) => <span className="font-mono text-[12px] font-medium text-ink">{num(r.clicks)}</span>,
  },
  {
    key: "position",
    header: "pos.",
    align: "right",
    sortValue: (r) => r.position,
    render: (r) => <span className="font-mono text-[11.5px] text-[#45423c]">{dec(r.position)}</span>,
  },
  {
    key: "volume",
    header: "vol. / mois",
    align: "right",
    headerInfo:
      "Volume de recherche mensuel France (DataForSEO). n.d. = requête trop rare pour être répertoriée.",
    sortValue: (r) => r.volume_fr,
    render: (r) => (
      <span className="font-mono text-[11px] text-faint">
        {r.volume_fr != null ? num(r.volume_fr) : "n.d."}
      </span>
    ),
  },
];

export function ArticleQueriesTable({ rows }: { rows: QueryRow[] }) {
  return (
    <SortableTable
      columns={columns}
      rows={rows}
      initialSortKey="impressions"
      initialDir="desc"
      minWidth={720}
      emptyLabel="Aucune requête révélée par Google sur la fenêtre (anonymisation)."
    />
  );
}
