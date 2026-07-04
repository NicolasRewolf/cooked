"use client";

import { useState, useMemo } from "react";
import { cn } from "@/lib/cn";
import { Info } from "./Info";

export interface Column<T> {
  key: string;
  header: string;
  /** Sous-libellé discret sous l'en-tête (données plates, non-uppercase). */
  subHeader?: string;
  /** Texte de l'explication ⓘ rendue à côté de l'en-tête (données plates). */
  headerInfo?: string;
  align?: "left" | "right";
  render: (row: T) => React.ReactNode;
  sortValue?: (row: T) => number | string | null;
}

// Table triable « instrument » : chaque en-tête sortable est un bouton (tri asc/desc,
// flèche sur la colonne active). Défilement horizontal au besoin (min-width).
export function SortableTable<T>({
  columns,
  rows,
  initialSortKey,
  initialDir = "desc",
  minWidth = 1080,
  emptyLabel = "Aucune donnée.",
  onSortChange,
}: {
  columns: Column<T>[];
  rows: T[];
  initialSortKey?: string;
  initialDir?: "asc" | "desc";
  minWidth?: number;
  emptyLabel?: string;
  /** M2 — notifie le parent (client) du tri courant pour le refléter dans l'URL.
   *  Callback entre DEUX composants client : autorisé (la règle RSC ne vaut que
   *  pour la frontière serveur→client). */
  onSortChange?: (key: string, dir: "asc" | "desc") => void;
}) {
  const [sortKey, setSortKey] = useState<string | undefined>(initialSortKey);
  const [dir, setDir] = useState<"asc" | "desc">(initialDir);

  const sorted = useMemo(() => {
    const col = columns.find((c) => c.key === sortKey);
    if (!col?.sortValue) return rows;
    const factor = dir === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const va = col.sortValue!(a);
      const vb = col.sortValue!(b);
      if (va == null && vb == null) return 0;
      if (va == null) return 1; // nulls last
      if (vb == null) return -1;
      if (typeof va === "number" && typeof vb === "number") return (va - vb) * factor;
      return String(va).localeCompare(String(vb), "fr") * factor;
    });
  }, [columns, rows, sortKey, dir]);

  function toggle(key: string) {
    const nextDir: "asc" | "desc" = sortKey === key ? (dir === "asc" ? "desc" : "asc") : "desc";
    setSortKey(key);
    setDir(nextDir);
    onSortChange?.(key, nextDir);
  }

  if (rows.length === 0) return <p className="py-6 text-sm text-muted">{emptyLabel}</p>;

  return (
    <div className="overflow-x-auto border border-line bg-panel">
      <table className="w-full border-collapse" style={{ minWidth }}>
        <thead>
          <tr className="border-b border-line-strong bg-zebra">
            {columns.map((c) => {
              const sortable = !!c.sortValue;
              const active = sortKey === c.key;
              return (
                <th
                  key={c.key}
                  aria-sort={active ? (dir === "asc" ? "ascending" : "descending") : "none"}
                  className={cn(
                    "whitespace-nowrap px-3 py-2.5 align-top font-mono text-[10px] uppercase tracking-[0.02em]",
                    c.align === "right" ? "text-right" : "text-left",
                    active ? "text-ink" : "text-faint",
                  )}
                >
                  <div
                    className={cn(
                      "flex items-center gap-1",
                      c.align === "right" ? "justify-end" : "justify-start",
                    )}
                  >
                    {sortable ? (
                      <button
                        type="button"
                        onClick={() => toggle(c.key)}
                        className="select-none uppercase transition-colors hover:text-accent"
                      >
                        {c.header}
                        {active ? (dir === "asc" ? " ↑" : " ↓") : ""}
                      </button>
                    ) : (
                      c.header
                    )}
                    {c.headerInfo ? <Info>{c.headerInfo}</Info> : null}
                  </div>
                  {c.subHeader ? (
                    <div
                      className={cn(
                        "mt-0.5 font-normal normal-case tracking-normal text-[9.5px] text-dim",
                        c.align === "right" ? "text-right" : "text-left",
                      )}
                    >
                      {c.subHeader}
                    </div>
                  ) : null}
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {sorted.map((row, i) => (
            <tr
              key={i}
              className="border-b border-[#f2f2f0] transition-colors last:border-0 hover:bg-[#fafaf8]"
            >
              {columns.map((c) => (
                <td
                  key={c.key}
                  className={cn(
                    "px-3 py-2.5 align-middle",
                    c.align === "right" ? "text-right" : "text-left",
                  )}
                >
                  {c.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
