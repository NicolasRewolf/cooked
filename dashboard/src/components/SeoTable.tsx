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
  if (Math.abs(gain) < 0.2) return <span className="font-mono text-[10px] text-faint">▬</span>;
  const up = gain > 0;
  return (
    <span
      className={cn("font-mono text-[10px] font-medium", up ? "text-up" : "text-down")}
      title={`${up ? "+" : "−"}${Math.abs(gain).toFixed(1)} place(s) vs période précédente`}
    >
      {up ? "▲" : "▼"} {Math.abs(gain).toFixed(1).replace(".", ",")}
    </span>
  );
}

export function SeoTable({ rows }: { rows: SeoQueryRow[] }) {
  const [quickOnly, setQuickOnly] = useState(false);
  const filtered = quickOnly ? rows.filter((r) => r.is_quick_win) : rows;
  const maxCapture = Math.max(1, ...rows.map((r) => r.capture_pct ?? 0));

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
            {r.is_quick_win && <Badge tone="good">quick win</Badge>}
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
      sortValue: (r) => r.position_avg,
      render: (r) => (
        <div className="flex flex-col items-end leading-tight">
          <span
            className="font-mono text-[12px] text-[#45423c]"
            title={r.ctr_expected != null ? `CTR attendu à cette position : ${pct(r.ctr_expected)}` : undefined}
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
      sortValue: (r) => r.volume_fr,
      render: (r) =>
        r.volume_fr != null ? (
          <span className="font-mono text-[11.5px] text-[#45423c]">{num(r.volume_fr)}</span>
        ) : (
          <span className="text-dim">n.d.</span>
        ),
    },
    {
      key: "capture",
      header: "captation",
      align: "right",
      sortValue: (r) => r.capture_pct,
      render: (r) => (
        <div className="flex flex-col items-end gap-1">
          <span className="font-mono text-[11.5px] text-[#45423c]">{pct(r.capture_pct)}</span>
          <span className="block h-[2px] w-12 bg-[#eeeeec]">
            <span
              className="block h-[2px] bg-[#b9b4aa]"
              style={{ width: `${Math.round(((r.capture_pct ?? 0) / maxCapture) * 100)}%` }}
            />
          </span>
        </div>
      ),
    },
    {
      key: "opportunity",
      header: "gain pot.",
      align: "right",
      sortValue: (r) => r.opportunity_clicks,
      render: (r) =>
        r.opportunity_clicks == null || r.opportunity_clicks <= 0 ? (
          <span className="text-dim">—</span>
        ) : (
          <span
            className={cn(
              "font-mono text-[12.5px] font-semibold",
              r.is_quick_win ? "text-up" : "text-[#45423c]",
            )}
            title="Clics/mois estimés si la requête atteignait le top 3 au CTR moyen du site. Combine gain de classement et gain de CTR."
          >
            +{num(r.opportunity_clicks)}
          </span>
        ),
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
          quick wins seulement (position 5–15 · volume ≥ 100)
        </label>
      </div>
      <SortableTable columns={columns} rows={filtered} initialSortKey="clicks" initialDir="desc" minWidth={900} />
      <p className="mt-[11px] max-w-[920px] font-mono text-[10.5px] leading-relaxed text-dim">
        tendances ▲▼ vs période précédente (clics · places gagnées en position) ·{" "}
        <strong className="font-semibold text-faint">gain pot.</strong> = clics/mois estimés si la
        requête passait en top 3 au CTR du site — trie les quick wins par enjeu réel, pas par volume
        brut · ⚠ Google n&apos;expose qu&apos;une fraction des requêtes (reste anonymisé).
      </p>
    </div>
  );
}
