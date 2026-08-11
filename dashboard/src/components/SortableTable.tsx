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
  /** Cellule de pied de tableau. Reçoit les lignes VISIBLES (triées et déjà
   *  filtrées par le parent) — un total doit refléter ce qu'on regarde, pas le
   *  jeu complet. Si au moins une colonne en définit une, un <tfoot> collant
   *  est rendu (d'après la « calculation row » de beautiful-ui). */
  total?: (rows: T[]) => React.ReactNode;
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
  stickyFirstColumn = true,
  maxHeight = "min(70vh, 760px)",
}: {
  columns: Column<T>[];
  rows: T[];
  initialSortKey?: string;
  initialDir?: "asc" | "desc";
  minWidth?: number;
  emptyLabel?: string;
  /** 1re colonne figée à gauche pendant le défilement horizontal (le libellé de
   *  la ligne reste lisible sur une table large). */
  stickyFirstColumn?: boolean;
  /** Hauteur max de la zone de défilement — c'est ELLE qui rend l'en-tête
   *  collant utile (sans plafond, le conteneur ne défile jamais verticalement
   *  et `sticky top-0` n'a aucun effet). */
  maxHeight?: string;
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

  // Un <tfoot> collant n'est rendu que si au moins une colonne définit un total.
  const hasTotals = columns.some((c) => c.total);

  // Cellule figée à gauche : fond opaque obligatoire (elle passe SOUS les autres
  // cellules au défilement) + liseré d'ombre qui matérialise la coupure.
  const stickyCell = "sticky left-0 shadow-sticky";

  return (
    <div className="border border-line bg-panel">
      {/* `overflow-auto` + plafond de hauteur = zone de défilement dans les deux
          axes, condition nécessaire pour que thead/tfoot/1re colonne collent. */}
      <div className="overflow-auto" style={{ maxHeight }}>
      <table
        className="w-full"
        style={{ minWidth, borderCollapse: "separate", borderSpacing: 0 }}
      >
        <thead>
          <tr>
            {columns.map((c, i) => {
              const sortable = !!c.sortValue;
              const active = sortKey === c.key;
              const frozen = stickyFirstColumn && i === 0;
              return (
                <th
                  key={c.key}
                  aria-sort={active ? (dir === "asc" ? "ascending" : "descending") : "none"}
                  className={cn(
                    "sticky top-0 z-[5] whitespace-nowrap border-b border-line-strong bg-inset px-3 py-2.5 align-top font-mono text-[10px] uppercase tracking-[0.02em]",
                    frozen && `${stickyCell} z-[7]`,
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
            <tr key={i} className="group transition-colors hover:bg-hover">
              {columns.map((c, ci) => {
                const frozen = stickyFirstColumn && ci === 0;
                return (
                  <td
                    key={c.key}
                    className={cn(
                      "border-b border-line-soft px-3 py-2.5 align-middle transition-colors group-last:border-0",
                      // La cellule figée a son propre fond (sinon les cellules qui
                      // défilent dessous restent visibles au travers) — il faut
                      // donc lui rejouer le survol de la ligne à la main.
                      frozen && `${stickyCell} z-[2] bg-panel group-hover:bg-hover`,
                      c.align === "right" ? "text-right" : "text-left",
                    )}
                  >
                    {c.render(row)}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
        {hasTotals ? (
          <tfoot>
            <tr>
              {columns.map((c, i) => {
                const frozen = stickyFirstColumn && i === 0;
                return (
                  <td
                    key={c.key}
                    className={cn(
                      "sticky bottom-0 z-[4] whitespace-nowrap border-t border-line-strong bg-inset px-3 py-2 align-middle font-mono text-[11px] text-muted",
                      frozen && `${stickyCell} z-[6]`,
                      c.align === "right" ? "text-right" : "text-left",
                    )}
                  >
                    {c.total ? c.total(sorted) : null}
                  </td>
                );
              })}
            </tr>
          </tfoot>
        ) : null}
      </table>
      </div>
    </div>
  );
}
