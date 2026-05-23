"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { ArrowDown, ArrowUp, ArrowUpDown, ChevronLeft, ChevronRight } from "lucide-react";
import { CategoryBadge } from "@/components/category-badge";
import { InfoLabel } from "@/components/info-label";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import {
  BUCKET_LABEL,
  matchesBucket,
  type FilterBucket,
} from "@/lib/page-category";
import { formatInt, formatPct, formatNumber } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { PagesOverviewRow } from "@/lib/cooked";

type SortCol =
  | "clicks"
  | "impressions"
  | "position"
  | "ctr"
  | "sessions"
  | "dwell"
  | "contacts"
  | "pogo";

type SortDir = "asc" | "desc";

type PageSize = 25 | 50 | 100 | "all";
const PAGE_SIZE_OPTIONS: PageSize[] = [25, 50, 100, "all"];

const HINTS = {
  page: "URL de la page sur le site.",
  category: "Type de page (Accueil / Cabinet / Expertise / Article / Ressource).",
  clicks: "Clics depuis Google Search Console sur les 28 derniers jours.",
  impressions:
    "Nombre de fois où la page est apparue dans les résultats Google (28 j).",
  position:
    "Position moyenne dans les résultats Google, pondérée par les impressions (1 = top).",
  ctr:
    "Taux de clic Google = clics / impressions. Benchmark : ~3 % en position 5, ~25 % en position 1.",
  visits:
    "Visites humaines uniques mesurées par Cooked (bots et bruit filtrés).",
  dwell: "Temps moyen passé sur la page par session.",
  contacts:
    "Contacts business macro = appels téléphone (cta_phone_click) + formulaires soumis (form_submit). Conforme à la taxonomie CLAUDE.md cooked. Le clic « Prendre RDV » est une micro-conversion (intent), comptée séparément — pas additionnée ici.",
  pogo:
    "Sessions arrivant de Google qui repartent rapidement (mauvais signal SEO si élevé).",
};

const BUCKETS: FilterBucket[] = [
  "all",
  "cabinet",
  "expertise",
  "article",
  "resource",
];

export function PagesTable({ rows }: { rows: PagesOverviewRow[] }) {
  const [bucket, setBucketState] = useState<FilterBucket>("all");
  const [sortCol, setSortColState] = useState<SortCol>("sessions");
  const [sortDir, setSortDirState] = useState<SortDir>("desc");
  const [pageSize, setPageSizeState] = useState<PageSize>(50);
  const [page, setPage] = useState<number>(1);

  // Reset page=1 dès qu'un filtre / tri / taille change.
  const setBucket = (b: FilterBucket) => { setBucketState(b); setPage(1); };
  const setPageSize = (s: PageSize) => { setPageSizeState(s); setPage(1); };
  const setSortCol = (c: SortCol) => { setSortColState(c); setPage(1); };
  const setSortDir = (d: SortDir | ((p: SortDir) => SortDir)) => {
    setSortDirState(d);
    setPage(1);
  };

  const counts = useMemo(() => {
    const c: Record<FilterBucket, number> = {
      all: rows.length,
      cabinet: 0,
      expertise: 0,
      article: 0,
      resource: 0,
    };
    for (const r of rows) {
      for (const b of BUCKETS) {
        if (b !== "all" && matchesBucket(r.path, b)) c[b]++;
      }
    }
    return c;
  }, [rows]);

  const filteredSorted = useMemo(() => {
    const filtered = rows.filter((r) => matchesBucket(r.path, bucket));
    const dir = sortDir === "asc" ? 1 : -1;
    const get = SORT_GETTERS[sortCol];
    return [...filtered].sort((a, b) => {
      const va = get(a);
      const vb = get(b);
      if (va == null && vb == null) return 0;
      if (va == null) return 1; // nulls toujours en bas
      if (vb == null) return -1;
      if (va < vb) return -1 * dir;
      if (va > vb) return 1 * dir;
      return 0;
    });
  }, [rows, bucket, sortCol, sortDir]);

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
      {/* Filtres */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        {BUCKETS.map((b) => {
          const active = bucket === b;
          return (
            <button
              key={b}
              type="button"
              onClick={() => setBucket(b)}
              className={cn(
                "inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1 font-mono text-xs uppercase tracking-wide transition-colors",
                active
                  ? "border-foreground bg-foreground text-background"
                  : "border-border bg-surface text-muted-foreground hover:text-foreground"
              )}
            >
              {BUCKET_LABEL[b]}
              <span
                className={cn(
                  "rounded px-1 text-[10px]",
                  active
                    ? "bg-background/15 text-background"
                    : "bg-surface-subtle text-muted-foreground"
                )}
              >
                {counts[b]}
              </span>
            </button>
          );
        })}
      </div>

      {/* Tableau */}
      <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-border bg-surface-subtle/50">
              <tr className="text-left font-mono text-xs uppercase tracking-wide text-muted-foreground">
                <th className="px-4 py-3 font-medium">
                  <InfoLabel label="Page" hint={HINTS.page} />
                </th>
                <th className="px-3 py-3 font-medium">
                  <InfoLabel label="Type" hint={HINTS.category} />
                </th>
                <ThSort
                  label="Clics Google"
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
                  label="Visites"
                  hint={HINTS.visits}
                  col="sessions"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Temps moyen"
                  hint={HINTS.dwell}
                  col="dwell"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Contacts"
                  hint={HINTS.contacts}
                  col="contacts"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                />
                <ThSort
                  label="Rebond rapide"
                  hint={HINTS.pogo}
                  col="pogo"
                  active={sortCol}
                  dir={sortDir}
                  onSort={onSort}
                  last
                />
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {pageRows.length === 0 ? (
                <tr>
                  <td
                    colSpan={10}
                    className="px-4 py-10 text-center text-sm text-muted-foreground"
                  >
                    Aucune page dans cette catégorie sur la fenêtre.
                  </td>
                </tr>
              ) : (
                pageRows.map((p) => (
                  <tr
                    key={p.path}
                    className="group transition-colors hover:bg-surface-subtle/40"
                  >
                    <td className="max-w-[260px] truncate px-4 py-3">
                      <Link
                        href={`/p${p.path}`}
                        className="block truncate text-foreground hover:underline"
                        title={p.path}
                      >
                        {p.path}
                      </Link>
                    </td>
                    <td className="px-3 py-3">
                      <CategoryBadge path={p.path} />
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      {formatInt(p.gsc_clicks_28d)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatInt(p.gsc_impressions_28d)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      <PositionBadge value={p.gsc_position_avg_28d} />
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatPct(p.gsc_ctr_pct_28d, 2)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      {formatInt(p.cooked_sessions_28d)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {p.cooked_dwell_avg_s_28d != null
                        ? `${formatNumber(p.cooked_dwell_avg_s_28d, 0)}s`
                        : "—"}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      {p.cooked_contacts_28d > 0 ? (
                        <span className="font-medium text-success">
                          {formatInt(p.cooked_contacts_28d)}
                        </span>
                      ) : (
                        <span className="text-muted-foreground">0</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatPct(p.cooked_pogo_rate_28d, 1)}
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
            ? "0 page"
            : `${formatInt(showingFrom)}–${formatInt(showingTo)} sur ${formatInt(total)}`}
          {" · "}cliquer une colonne pour trier
        </div>

        <div className="flex items-center gap-3">
          {/* Page size */}
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

          {/* Prev / page indicator / next */}
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

/**
 * Header de colonne triable. Le <button> est À LA FOIS le sort trigger
 * et le tooltip trigger (Base UI `render` prop) — pas de bouton imbriqué
 * (HTML interdit nested buttons).
 */
function ThSort({
  label,
  hint,
  col,
  active,
  dir,
  onSort,
  last = false,
}: {
  label: string;
  hint: string;
  col: SortCol;
  active: SortCol;
  dir: SortDir;
  onSort: (c: SortCol) => void;
  last?: boolean;
}) {
  const isActive = active === col;
  const Icon = !isActive ? ArrowUpDown : dir === "asc" ? ArrowUp : ArrowDown;
  return (
    <th
      className={cn("py-3 text-right font-medium", last ? "px-4" : "px-3")}
    >
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

const SORT_GETTERS: Record<
  SortCol,
  (r: PagesOverviewRow) => number | null
> = {
  clicks: (r) => r.gsc_clicks_28d,
  impressions: (r) => r.gsc_impressions_28d,
  position: (r) => r.gsc_position_avg_28d,
  ctr: (r) => r.gsc_ctr_pct_28d,
  sessions: (r) => r.cooked_sessions_28d,
  dwell: (r) => r.cooked_dwell_avg_s_28d,
  contacts: (r) => r.cooked_contacts_28d,
  pogo: (r) => r.cooked_pogo_rate_28d,
};
