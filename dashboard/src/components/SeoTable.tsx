"use client";

import { useState } from "react";
import { SortableTable, type Column } from "./SortableTable";
import { Badge, Trend, dirClass, dirGlyph } from "./ui";
import { cn } from "@/lib/cn";
import type { SeoQueryRow } from "@/lib/types";
import { num, dec, pct, delta, prettyPath } from "@/lib/format";

// Tendance de position : sémantique INVERSÉE — une baisse du chiffre = montée
// dans le classement (bien). gain = prev - now, puis vocabulaire delta partagé.
function PosTrend({ now, prev }: { now: number | null; prev: number | null }) {
  if (now == null || prev == null) return null;
  const gain = prev - now; // > 0 = a gagné des places
  if (Math.abs(gain) < 0.2)
    return <span className={cn("font-mono text-[10px]", dirClass("flat"))}>{dirGlyph("flat")}</span>;
  const dir = gain > 0 ? "up" : "down";
  return (
    <span
      className={cn("font-mono text-[10px] font-medium", dirClass(dir))}
      title={`${dir === "up" ? "+" : "−"}${Math.abs(gain).toFixed(1)} place(s) vs période précédente`}
    >
      {dirGlyph(dir)} {Math.abs(gain).toFixed(1).replace(".", ",")}
    </span>
  );
}

export function SeoTable({ rows }: { rows: SeoQueryRow[] }) {
  const [quickOnly, setQuickOnly] = useState(false);
  const filtered = quickOnly ? rows.filter((r) => r.is_quick_win) : rows;

  const columns: Column<SeoQueryRow>[] = [
    {
      key: "query",
      header: "requête",
      align: "left",
      sortValue: (r) => r.query,
      render: (r) => (
        <div className="max-w-[300px]">
          <div className="flex items-center gap-2">
            <span className="truncate text-[13px] font-medium text-ink">{r.query}</span>
            {r.is_quick_win && <Badge tone="neutral">à examiner</Badge>}
          </div>
          {r.top_page && (
            <div className="truncate font-mono text-[10.5px] text-dim">
              → {prettyPath(r.top_page)}
              {r.top_page_theme ? ` · ${r.top_page_theme}` : ""}
            </div>
          )}
        </div>
      ),
    },
    {
      key: "clicks",
      header: "clics",
      align: "right",
      sortValue: (r) => r.clicks,
      render: (r) => (
        <div className="flex flex-col items-end leading-tight">
          <span className="font-mono text-[12.5px] font-medium text-ink">{num(r.clicks)}</span>
          <Trend d={delta(r.clicks, r.clicks_prev)} />
        </div>
      ),
    },
    {
      key: "impressions",
      header: "affich.",
      align: "right",
      sortValue: (r) => r.impressions,
      render: (r) => <span className="font-mono text-[11.5px] text-faint">{num(r.impressions)}</span>,
    },
    {
      key: "position",
      header: "position",
      align: "right",
      headerInfo:
        "Position moyenne Google, pondérée par impressions. ▲▼ = places gagnées/perdues vs période précédente. La moyenne peut varier avec les pages ou les jours observés.",
      sortValue: (r) => r.position_avg,
      render: (r) => (
        <div className="flex flex-col items-end leading-tight">
          <span
            className="font-mono text-[12px] text-ink-2"
          >
            {dec(r.position_avg)}
          </span>
          <PosTrend now={r.position_avg} prev={r.position_prev} />
        </div>
      ),
    },
    {
      key: "volume",
      header: "vol. dfs",
      align: "right",
      headerInfo:
        "Estimation du volume mensuel en France (DataForSEO), distincte des impressions du site. Ne mesure pas l'audience accessible à l'article. n.d. = volume indisponible.",
      sortValue: (r) => r.volume_fr,
      render: (r) =>
        r.volume_fr != null ? (
          <span className="font-mono text-[11.5px] text-ink-2">{num(r.volume_fr)}</span>
        ) : (
          <span className="text-dim">n.d.</span>
        ),
    },
    {
      key: "ctr",
      header: "ctr",
      align: "right",
      headerInfo:
        "CTR observé = clics / impressions sur la période. Il ne mesure ni la part du marché national ni les clics encore accessibles.",
      sortValue: (r) => r.impressions > 0 ? r.clicks / r.impressions : null,
      render: (r) => <span className="font-mono text-[11.5px] text-ink-2">{pct(r.impressions > 0 ? 100 * r.clicks / r.impressions : null)}</span>,
    },
  ];

  return (
    <div>
      <div className="mb-2.5 flex items-center justify-between gap-4">
        <h2 className="font-mono text-[11px] font-semibold uppercase tracking-[0.05em] text-muted">
          requêtes [{filtered.length}]
        </h2>
        <label className="flex w-fit cursor-pointer items-center gap-2 text-[11.5px] text-muted">
          <input
            type="checkbox"
            checked={quickOnly}
            onChange={(e) => setQuickOnly(e.target.checked)}
            className="accent-accent"
          />
          position 5–15 · volume ≥ 100 seulement
        </label>
      </div>
      <SortableTable columns={columns} rows={filtered} initialSortKey="clicks" initialDir="desc" minWidth={900} />
      <p className="mt-[11px] max-w-[920px] font-mono text-[10.5px] leading-relaxed text-dim">
        ▲▼ tendances vs période précédente (clics · places en position) · ⚠ Google n&apos;expose
        qu&apos;une fraction des requêtes (le reste est anonymisé).
      </p>
    </div>
  );
}
