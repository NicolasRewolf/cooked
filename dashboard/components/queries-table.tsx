"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
import { InfoLabel } from "@/components/info-label";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { formatInt, formatNumber, formatPct } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { GscGlobalQueryRow } from "@/lib/cooked";
import { hrefWithPeriod, type PeriodKind } from "@/lib/period";

type SortCol =
  | "clicks"
  | "impressions"
  | "position"
  | "ctr"
  | "nb_pages"
  | "top_clicks"
  | "volume_fr"
  | "cpc"
  | "click_yield";

type SortDir = "asc" | "desc";

type PageSize = 25 | 50 | 100 | "all";
const PAGE_SIZE_OPTIONS: PageSize[] = [25, 50, 100, "all"];

const HINTS = {
  query: "Requête tapée par l'utilisateur dans Google.",
  clicks: "Clics totaux depuis Google vers le site sur la fenêtre.",
  impressions: "Nombre d'apparitions de la requête dans les résultats Google.",
  position:
    "Position moyenne dans les résultats Google, pondérée par les impressions (1 = top).",
  ctr:
    "Taux de clic = clics / impressions. Faible CTR + bonne position = opportunité (title/meta peu attractifs).",
  nb_pages:
    "Nombre de pages du site qui rankent sur cette requête. > 1 = potentiel cannibalisation interne.",
  top_page:
    "Page qui capture le plus de clics pour cette requête. Cliquer pour ouvrir la fiche page.",
  volume_fr:
    "Volume mensuel moyen de recherches en France pour cette requête (DataForSEO, sync hebdo). Estimation ± 30 %. Vide pour les requêtes long-tail / brand qui ne sont pas dans le top 500.",
  cpc:
    "Coût par clic en AdWords pour cette requête en France (€). Indique combien le cabinet paierait par lead s'il achetait cette requête. Proxy de la valeur business d'un clic SEO.",
  click_yield:
    "Part du volume mensuel capturée par le site = 100 × clicks / (volume × jours/30). Plus haut = on capte mieux notre share. > 100 % possible si plusieurs pages rankent (cannibalisation interne) ou si DFS sous-estime le volume.",
};

export function QueriesTable({
  rows,
  period,
}: {
  rows: GscGlobalQueryRow[];
  period: PeriodKind;
}) {
  const [sortCol, setSortColState] = useState<SortCol>("clicks");
  const [sortDir, setSortDirState] = useState<SortDir>("desc");
  const [pageSize, setPageSizeState] = useState<PageSize>(50);
  const [page, setPage] = useState<number>(1);
  const [search, setSearchState] = useState<string>("");

  const setPageSize = (s: PageSize) => {
    setPageSizeState(s);
    setPage(1);
  };
  const setSortCol = (c: SortCol) => {
    setSortColState(c);
    setPage(1);
  };
  const setSortDir = (d: SortDir | ((p: SortDir) => SortDir)) => {
    setSortDirState(d);
    setPage(1);
  };
  const setSearch = (v: string) => {
    setSearchState(v);
    setPage(1);
  };

  const filteredSorted = useMemo(() => {
    const needle = search.trim().toLowerCase();
    const filtered = needle
      ? rows.filter((r) => r.query.toLowerCase().includes(needle))
      : rows;
    const dir = sortDir === "asc" ? 1 : -1;
    const get = SORT_GETTERS[sortCol];
    return [...filtered].sort((a, b) => {
      const va = get(a);
      const vb = get(b);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      if (va < vb) return -1 * dir;
      if (va > vb) return 1 * dir;
      return 0;
    });
  }, [rows, search, sortCol, sortDir]);

  const onSort = (col: SortCol) => {
    if (col === sortCol) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortCol(col);
      setSortDir("desc");
    }
  };

  // Pagination
  const total = filteredSorted.length;
  const perPage = pageSize === "all" ? total || 1 : pageSize;
  const totalPages = Math.max(1, Math.ceil(total / perPage));
  const safePage = Math.min(page, totalPages);
  const startIdx = (safePage - 1) * perPage;
  const pageRows = filteredSorted.slice(startIdx, startIdx + perPage);
  const showingFrom = total === 0 ? 0 : startIdx + 1;
  const showingTo = Math.min(startIdx + perPage, total);

  return (
    <>
      {/* Barre de recherche */}
      <div className="mb-4 flex items-center gap-3">
        <input
          type="search"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Filtrer les requêtes…"
          className="w-72 rounded-md border border-border bg-surface px-3 py-1.5 font-mono text-xs text-foreground placeholder:text-muted-foreground focus:border-foreground focus:outline-none"
        />
        <span className="font-mono text-xs text-muted-foreground">
          {formatInt(rows.length)} requêtes capturées · filtrage live
        </span>
      </div>

      {/* Tableau */}
      <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-border bg-surface-subtle/50">
              <tr className="text-left font-mono text-xs uppercase tracking-wide text-muted-foreground">
                <th className="px-4 py-3 font-medium">
                  <InfoLabel label="Requête" hint={HINTS.query} />
                </th>
                <ThSort
                  label="Clics"
                  hint={HINTS.clicks}
                  col="clicks"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Impressions"
                  hint={HINTS.impressions}
                  col="impressions"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Position"
                  hint={HINTS.position}
                  col="position"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="CTR"
                  hint={HINTS.ctr}
                  col="ctr"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Pages"
                  hint={HINTS.nb_pages}
                  col="nb_pages"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Volume FR"
                  hint={HINTS.volume_fr}
                  col="volume_fr"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="CPC"
                  hint={HINTS.cpc}
                  col="cpc"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Click yield"
                  hint={HINTS.click_yield}
                  col="click_yield"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <th className="px-4 py-3 font-medium">
                  <InfoLabel label="Top page" hint={HINTS.top_page} />
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {pageRows.length === 0 ? (
                <tr>
                  <td
                    colSpan={10}
                    className="px-4 py-10 text-center text-sm text-muted-foreground"
                  >
                    Aucune requête ne matche le filtre.
                  </td>
                </tr>
              ) : (
                pageRows.map((q) => (
                  <tr
                    key={q.query}
                    className="group transition-colors hover:bg-surface-subtle/40"
                  >
                    <td className="max-w-[300px] truncate px-4 py-3">
                      <span className="text-foreground" title={q.query}>
                        {q.query}
                      </span>
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      {formatInt(q.clicks)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatInt(q.impressions)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      <PositionBadge value={q.position_avg} />
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatPct(q.ctr_pct, 2)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      <PagesCell n={q.nb_pages_targeted} />
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {q.volume_fr != null ? formatInt(q.volume_fr) : "—"}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {q.cpc != null ? `${formatNumber(q.cpc, 2)} €` : "—"}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      <ClickYieldCell pct={q.click_yield_pct} />
                    </td>
                    <td className="max-w-[260px] truncate px-4 py-3">
                      {q.top_page ? (
                        <Link
                          href={hrefWithPeriod(`/p${q.top_page}`, period)}
                          className="block truncate text-foreground hover:underline"
                          title={q.top_page}
                        >
                          {q.top_page}
                        </Link>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Pagination */}
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 font-mono text-xs text-muted-foreground">
        <div>
          {total === 0
            ? "0 requête"
            : `${formatInt(showingFrom)}–${formatInt(showingTo)} sur ${formatInt(total)}`}
          {" · "}cliquer une colonne pour trier
        </div>

        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1">
            <span>Lignes</span>
            {PAGE_SIZE_OPTIONS.map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setPageSize(s)}
                className={cn(
                  "rounded px-1.5 py-0.5 transition-colors",
                  pageSize === s
                    ? "bg-foreground text-background"
                    : "hover:text-foreground"
                )}
              >
                {s === "all" ? "Tout" : s}
              </button>
            ))}
          </div>

          {totalPages > 1 && (
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={safePage === 1}
                className="inline-flex h-6 items-center rounded border border-border bg-surface px-1.5 transition-colors enabled:hover:text-foreground disabled:opacity-40"
                aria-label="Page précédente"
              >
                <ChevronLeft className="h-3.5 w-3.5" />
              </button>
              <span className="px-1 tabular-nums">
                {safePage} / {totalPages}
              </span>
              <button
                type="button"
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={safePage === totalPages}
                className="inline-flex h-6 items-center rounded border border-border bg-surface px-1.5 transition-colors enabled:hover:text-foreground disabled:opacity-40"
                aria-label="Page suivante"
              >
                <ChevronRight className="h-3.5 w-3.5" />
              </button>
            </div>
          )}
        </div>
      </div>
    </>
  );
}

function ThSort({
  label,
  hint,
  col,
  active,
  dir,
  onSort,
}: {
  label: string;
  hint: string;
  col: SortCol;
  active: SortCol;
  dir: SortDir;
  onSort: (c: SortCol) => void;
}) {
  const isActive = active === col;
  const Icon = !isActive ? ArrowUpDown : dir === "asc" ? ArrowUp : ArrowDown;
  return (
    <th className="px-3 py-3 text-right font-medium">
      <Tooltip>
        <TooltipTrigger
          render={
            <button
              type="button"
              onClick={() => onSort(col)}
              className={cn(
                "inline-flex items-center justify-end gap-1 cursor-pointer bg-transparent p-0 transition-colors hover:text-foreground",
                isActive && "text-foreground"
              )}
            >
              {label}
              <Icon
                className={cn(
                  "h-3 w-3",
                  isActive ? "opacity-100" : "opacity-40"
                )}
                aria-hidden="true"
              />
            </button>
          }
        />
        <TooltipContent
          side="top"
          className="max-w-xs text-left text-xs leading-relaxed"
        >
          {hint}
        </TooltipContent>
      </Tooltip>
    </th>
  );
}

function PositionBadge({ value }: { value: number | null }) {
  if (value == null) return <span className="text-muted-foreground">—</span>;
  const tone =
    value < 3
      ? "text-success"
      : value < 11
        ? "text-foreground"
        : "text-muted-foreground";
  return <span className={tone}>{formatNumber(value, 1)}</span>;
}

function PagesCell({ n }: { n: number }) {
  // Plus de 1 page rankée = potentiel cannibalisation (warning doux).
  const tone = n > 3 ? "text-warning" : "text-muted-foreground";
  return <span className={tone}>{formatInt(n)}</span>;
}

function ClickYieldCell({ pct }: { pct: number | null }) {
  if (pct == null) return <span className="text-muted-foreground">—</span>;
  // Capping visuel : > 100 % = aberrant (cannibalisation ou DFS sous-estimé)
  if (pct > 100) {
    return (
      <span
        className="text-warning"
        title="Click yield > 100 % — souvent plusieurs pages rankent sur la même requête, ou DFS sous-estime le volume"
      >
        {formatNumber(pct, 0)} %
      </span>
    );
  }
  // Bon yield ≥ 10 % en vert, sinon neutre
  const tone = pct >= 10 ? "text-success" : "text-muted-foreground";
  return <span className={tone}>{formatNumber(pct, pct < 1 ? 2 : 1)} %</span>;
}

const SORT_GETTERS: Record<
  SortCol,
  (r: GscGlobalQueryRow) => number | null
> = {
  clicks: (r) => r.clicks,
  impressions: (r) => r.impressions,
  position: (r) => r.position_avg,
  ctr: (r) => r.ctr_pct,
  nb_pages: (r) => r.nb_pages_targeted,
  top_clicks: (r) => r.top_page_clicks,
  volume_fr: (r) => r.volume_fr,
  cpc: (r) => r.cpc,
  click_yield: (r) => r.click_yield_pct,
};
