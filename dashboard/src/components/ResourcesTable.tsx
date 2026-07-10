"use client";

import { useMemo } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { SortableTable, type Column } from "./SortableTable";
import { Badge, ConfidenceBadge } from "./ui";
import {
  bestQueryColumn,
  contactsColumn,
  ctrColumn,
  dwellColumn,
  gscClicksColumn,
  positionColumn,
  santeColumn,
  visitorsColumn,
} from "./metric-columns";
import { useTableViewState, type UrlParamsReader } from "./useTableViewState";
import { cn } from "@/lib/cn";
import type { ResourceRow } from "@/lib/types";
import { num, prettyPath } from "@/lib/format";
import { santeFromMomentum } from "@/lib/momentum";

// ── Source : part du trafic venant de Google (clics GSC vs visiteurs Cooked) ──
// Faible = l'article vit sur réseaux / IA / direct (plus volatil que la recherche).
function MixBadge({ r }: { r: ResourceRow }) {
  if (r.unique_visitors === 0) return <span className="text-dim">—</span>;
  const ratio = r.gsc_clicks / r.unique_visitors;
  const [tone, label] =
    ratio >= 0.8
      ? (["info", "Google"] as const)
      : ratio >= 0.35
        ? (["neutral", "Mixte"] as const)
        : (["warn", "Hors-Google"] as const);
  return <Badge tone={tone}>{label}</Badge>;
}

// Colonnes distinctives des articles (le reste vient de metric-columns).
// periodQ = « ?period=… » à propager aux liens de fiche (vide si période par défaut).
function buildColumns(periodQ: string): Column<ResourceRow>[] {
  return [
  {
    key: "article",
    header: "article",
    align: "left",
    sortValue: (r) => prettyPath(r.path),
    render: (r) => (
      <div className="max-w-[230px]">
        <Link
          href={`/article/${encodeURIComponent(r.path.replace(/^\/post\//, ""))}${periodQ}`}
          className="block truncate text-[12.5px] font-medium text-ink transition-colors hover:text-accent"
          title="Ouvrir la fiche de l'article (trajectoire, requêtes, santé, assistés)"
        >
          {prettyPath(r.path)}
        </Link>
        <div className="mt-[3px] flex items-center gap-[7px]">
          {r.theme && <span className="font-mono text-[10.5px] text-dim">{r.theme}</span>}
          <ConfidenceBadge grade={r.confidence} />
          <a
            href={`https://www.jplouton-avocat.fr${r.path}`}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Voir la page publiée (nouvel onglet)"
            className="-m-1 inline-flex items-center p-1 font-mono text-[10px] leading-none text-dim transition-colors hover:text-accent"
            title="Voir la page publiée"
          >
            ↗
          </a>
        </div>
      </div>
    ),
  },
  santeColumn,
  {
    key: "days_live",
    header: "âge",
    align: "right",
    headerInfo:
      "Âge SEO réel : jours depuis la première impression Google (pas la date de publication Wix, qui peut être antidatée).",
    sortValue: (r) => r.days_live,
    render: (r) => (
      <span className="font-mono text-[11.5px] text-faint">
        {r.days_live != null ? `${r.days_live} j` : "—"}
      </span>
    ),
  },
  visitorsColumn,
  dwellColumn(
    "Temps de lecture médian (réseaux sociaux exclus — leurs passages d'1 s faussent la médiane).",
  ),
  gscClicksColumn,
  ctrColumn,
  positionColumn,
  {
    key: "mix",
    header: "source",
    align: "left",
    headerInfo:
      "Part du trafic venant de Google (clics Google / visiteurs). Faible = l'article vit sur réseaux / IA / direct, plus volatil que la recherche.",
    sortValue: (r) => (r.unique_visitors > 0 ? r.gsc_clicks / r.unique_visitors : null),
    render: (r) => <MixBadge r={r} />,
  },
  bestQueryColumn,
  contactsColumn,
  {
    key: "assisted",
    header: "assistés",
    align: "right",
    subHeader: "entrés par l'article",
    headerInfo:
      "Contacts (appel ou formulaire) de visiteurs dont la session a COMMENCÉ par cet article — même visite. Le contenu qui a gagné le prospect reçoit le crédit.",
    sortValue: (r) => r.assisted_contacts ?? null,
    render: (r) => (
      <span
        className={cn(
          "font-mono text-[11.5px] font-semibold",
          (r.assisted_contacts ?? 0) > 0 ? "text-accent" : "text-dim",
        )}
      >
        {r.assisted_contacts != null ? num(r.assisted_contacts) : "—"}
      </span>
    ),
  },
  ];
}

type SanteFilter = "tous" | "monte" | "stable" | "ralentit" | "gisement" | "nonscore";

function santeOf(r: ResourceRow): Exclude<SanteFilter, "tous"> {
  return santeFromMomentum(r.momentum, r.cpi_grade, r.convertit);
}

// Filtres de vue ⇄ URL (fonctions de portée module : identité stable pour le hook).
interface ResourcesFilters {
  q: string;
  theme: string;
  sante: SanteFilter;
  recents: boolean;
}

function filtersFromUrl(sp: UrlParamsReader): ResourcesFilters {
  const s = sp.get("sante");
  const valid = ["monte", "stable", "ralentit", "gisement", "nonscore"];
  return {
    q: sp.get("q") ?? "",
    theme: sp.get("theme") ?? "tous",
    sante: s && valid.includes(s) ? (s as SanteFilter) : "tous",
    recents: sp.get("recents") === "1",
  };
}

function filtersToUrl(f: ResourcesFilters): Record<string, string | null> {
  return {
    q: f.q.trim() || null,
    theme: f.theme === "tous" ? null : f.theme,
    sante: f.sante === "tous" ? null : f.sante,
    recents: f.recents ? "1" : null,
  };
}

const resourcesFiltersSpec = { init: filtersFromUrl, toUrl: filtersToUrl };

export function ResourcesTable({ rows }: { rows: ResourceRow[] }) {
  const searchParams = useSearchParams();
  // Période courante → propagée aux liens de fiche (sauf défaut rolling_90).
  const periodQ = searchParams.get("period") === "rolling_28" ? "?period=rolling_28" : "";

  // État de vue (filtres + tri) ⇄ URL — machine partagée, débounce 300 ms.
  const { sortKey, sortDir, onSortChange, filters, setFilter } = useTableViewState({
    defaultSortKey: "visitors",
    filters: resourcesFiltersSpec,
    debounceMs: 300,
  });
  const { q: search, theme, sante, recents: recentOnly } = filters;

  const columns = useMemo(() => buildColumns(periodQ), [periodQ]);

  const themes = useMemo(
    () => Array.from(new Set(rows.map((r) => r.theme).filter((t): t is string => !!t))).sort((a, b) => a.localeCompare(b, "fr")),
    [rows],
  );

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return rows.filter((r) => {
      if (recentOnly && !(r.days_live != null && r.days_live <= 60)) return false;
      if (theme !== "tous" && r.theme !== theme) return false;
      if (sante !== "tous" && santeOf(r) !== sante) return false;
      if (q) {
        const hay = `${prettyPath(r.path)} ${r.path} ${r.best_query ?? ""}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [rows, recentOnly, search, theme, sante]);

  const selectCls =
    "border border-line bg-panel px-2 py-1 font-mono text-[11px] text-muted focus:border-accent focus:outline-none";

  return (
    <div>
      <div className="mb-2.5 flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <h2 className="font-mono text-[11px] font-semibold uppercase tracking-[0.05em] text-muted">
          articles [{filtered.length}
          {filtered.length !== rows.length ? `/${rows.length}` : ""}]
        </h2>
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <input
            type="search"
            value={search}
            onChange={(e) => setFilter("q", e.target.value)}
            placeholder="rechercher (titre, requête)…"
            className={cn(selectCls, "w-[190px]")}
            aria-label="Rechercher un article"
          />
          <select value={theme} onChange={(e) => setFilter("theme", e.target.value)} className={selectCls} aria-label="Filtrer par thème">
            <option value="tous">Tous les thèmes</option>
            {themes.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
          <select
            value={sante}
            onChange={(e) => setFilter("sante", e.target.value as SanteFilter)}
            className={selectCls}
            aria-label="Filtrer par santé"
          >
            <option value="tous">Toutes les santés</option>
            <option value="monte">● monte</option>
            <option value="stable">● stable</option>
            <option value="ralentit">● ralentit</option>
            <option value="gisement">★ gisement</option>
            <option value="nonscore">— non scoré</option>
          </select>
          <label className="flex w-fit cursor-pointer items-center gap-2 text-[11.5px] text-muted">
            <input
              type="checkbox"
              checked={recentOnly}
              onChange={(e) => setFilter("recents", e.target.checked)}
              className="accent-accent"
            />
            récents (≤ 60 j d&apos;âge SEO)
          </label>
        </div>
      </div>
      <SortableTable
        columns={columns}
        rows={filtered}
        initialSortKey={sortKey}
        initialDir={sortDir}
        minWidth={1160}
        onSortChange={onSortChange}
      />
      <p className="mt-[11px] font-mono text-[10.5px] leading-relaxed text-dim">
        ▲▼ tendances vs période précédente · cliquer un titre ouvre la fiche de l&apos;article
      </p>
    </div>
  );
}
