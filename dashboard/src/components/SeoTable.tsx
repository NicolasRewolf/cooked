"use client";

import { useState } from "react";
import { SortableTable, type Column } from "./SortableTable";
import { Badge, Trend } from "./ui";
import { cn } from "@/lib/cn";
import type { SeoQueryRow } from "@/lib/types";
import { num, dec, pct, delta, prettyPath } from "@/lib/format";

// Tendance de position : une baisse du chiffre = montée dans le classement (bien).
function PosTrend({ now, prev }: { now: number | null; prev: number | null }) {
  if (now == null || prev == null) return null;
  const gain = prev - now; // > 0 = a gagné des places
  if (Math.abs(gain) < 0.2) return <span className="text-[11px] text-neutral-400">▬</span>;
  const up = gain > 0;
  const cls = up
    ? "text-emerald-600 dark:text-emerald-400"
    : "text-red-600 dark:text-red-400";
  return (
    <span
      className={cn("text-[11px] font-medium tabular-nums", cls)}
      title={`${up ? "+" : "−"}${Math.abs(gain).toFixed(1)} place(s) vs période précédente`}
    >
      {up ? "▲" : "▼"} {Math.abs(gain).toFixed(1)}
    </span>
  );
}

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
          <div className="truncate text-[11px] text-neutral-400">
            → {prettyPath(r.top_page)}
            {r.top_page_theme ? <span className="text-neutral-500"> · {r.top_page_theme}</span> : ""}
          </div>
        )}
      </div>
    ),
  },
  {
    key: "clicks",
    header: "Clics",
    align: "right",
    sortValue: (r) => r.clicks,
    render: (r) => (
      <div className="flex flex-col items-end leading-tight">
        <span>{num(r.clicks)}</span>
        <Trend d={delta(r.clicks, r.clicks_prev)} />
      </div>
    ),
  },
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
    render: (r) => (
      <div className="flex flex-col items-end leading-tight">
        <span title={r.ctr_expected != null ? `CTR attendu à cette position : ${pct(r.ctr_expected)}` : undefined}>
          {dec(r.position_avg)}
        </span>
        <PosTrend now={r.position_avg} prev={r.position_prev} />
      </div>
    ),
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
  {
    key: "opportunity",
    header: "Gain pot. / mois",
    align: "right",
    sortValue: (r) => r.opportunity_clicks,
    render: (r) =>
      r.opportunity_clicks == null || r.opportunity_clicks <= 0 ? (
        <span className="text-neutral-400">—</span>
      ) : (
        <span
          className={
            r.is_quick_win
              ? "font-medium text-emerald-700 dark:text-emerald-400"
              : "text-neutral-700 dark:text-neutral-300"
          }
          title="Clics/mois supplémentaires estimés si la requête atteignait le top 3 au CTR moyen du site (volume DFS × CTR position 3 − clics actuels mensualisés). Combine gain de classement et gain de CTR."
        >
          +{num(r.opportunity_clicks)}
        </span>
      ),
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
      <p className="mt-2 text-[11px] text-neutral-400">
        Tendances ▲▼ vs période précédente (clics, et places gagnées en position).
        <span className="font-medium"> Gain pot. / mois</span> = clics estimés à aller chercher si la
        requête passait en top 3 au CTR du site — trie les quick wins par enjeu réel, pas par volume brut.
      </p>
    </div>
  );
}
