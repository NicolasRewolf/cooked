"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { replaceUrlParams } from "@/lib/url";
import { SortableTable, type Column } from "./SortableTable";
import { Badge, ConfidenceBadge, Trend } from "./ui";
import { cn } from "@/lib/cn";
import type { ResourceRow } from "@/lib/types";
import { num, seconds, dec, pct, delta, prettyPath } from "@/lib/format";

// ── Verdict de santé : momentum (relatif au site) + grade de confiance ───────
// Pour ces articles éducatifs, le potentiel hors-conversion est le bon repère.
function HealthCell({ r }: { r: ResourceRow }) {
  if (r.cpi_grade == null || r.cpi_grade === "C" || r.momentum == null) {
    return (
      <span className="font-mono text-[11px] text-dim">—</span>
    );
  }
  const m = r.momentum;
  const dir = m >= 1.05 ? "up" : m <= 0.95 ? "down" : "flat";
  const dot = dir === "up" ? "bg-up" : dir === "down" ? "bg-warn" : "bg-faint";
  const word = dir === "up" ? "monte" : dir === "down" ? "ralentit" : "stable";
  const gisement = (r.cpi_grade === "A" || r.cpi_grade === "B") && r.convertit === false;
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap">
      <span className={cn("h-[7px] w-[7px] shrink-0 rounded-full", dot)} />
      <span className="text-[11.5px] text-[#45423c]">{word}</span>
      {gisement && (
        <span aria-label="gisement" className="text-[11px] text-accent">
          ★
        </span>
      )}
    </span>
  );
}

// ── CTR réel vs CTR attendu à la position (courbe du site) ────────────────────
// Démasque un bon classement qui ne ramène pas de clics (titre / méta à revoir).
function CtrCell({ r }: { r: ResourceRow }) {
  if (r.gsc_ctr_pct == null) return <span className="text-dim">—</span>;
  const exp = r.ctr_expected;
  let cls = "text-[#45423c]";
  if (exp != null) {
    if (r.gsc_ctr_pct >= exp) cls = "text-up";
    else if (r.gsc_ctr_pct < exp * 0.7) cls = "text-alert";
  }
  return (
    <span className="whitespace-nowrap">
      <span className={cn("font-mono text-[11.5px] font-medium", cls)}>{pct(r.gsc_ctr_pct)}</span>
      {exp != null && <span className="font-mono text-[9.5px] text-dim"> / {pct(exp, 0)}</span>}
    </span>
  );
}

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
            className="font-mono text-[10px] text-dim transition-colors hover:text-accent"
            title="Voir la page publiée"
          >
            ↗
          </a>
        </div>
      </div>
    ),
  },
  {
    key: "sante",
    header: "santé",
    align: "left",
    headerInfo:
      "Momentum des clics Google relatif au site : ● monte / ● stable / ● ralentit. ★ gisement = fort potentiel (capture + lecture) mais pas encore de contact → poser un pont. — = trop peu de trafic organique pour un verdict.",
    sortValue: (r) => r.momentum,
    render: (r) => <HealthCell r={r} />,
  },
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
  {
    key: "visitors",
    header: "visiteurs",
    align: "right",
    sortValue: (r) => r.unique_visitors,
    render: (r) => (
      <div className="flex flex-col items-end leading-tight">
        <span className="font-mono text-[12.5px] font-medium text-ink">{num(r.unique_visitors)}</span>
        <Trend d={delta(r.unique_visitors, r.unique_visitors_prev)} />
      </div>
    ),
  },
  {
    key: "dwell",
    header: "lecture",
    align: "right",
    headerInfo:
      "Temps de lecture médian (réseaux sociaux exclus — leurs passages d'1 s faussent la médiane).",
    sortValue: (r) => r.dwell_median_s,
    render: (r) => <span className="font-mono text-[11.5px] text-[#45423c]">{seconds(r.dwell_median_s)}</span>,
  },
  {
    key: "gsc_clicks",
    header: "clics",
    align: "right",
    sortValue: (r) => r.gsc_clicks,
    render: (r) => (
      <div className="flex flex-col items-end leading-tight">
        <span className="font-mono text-[12px] font-medium text-ink">{num(r.gsc_clicks)}</span>
        <Trend d={delta(r.gsc_clicks, r.gsc_clicks_prev)} />
      </div>
    ),
  },
  {
    key: "ctr",
    header: "ctr / att.",
    align: "right",
    subHeader: "réel / attendu",
    headerInfo:
      "CTR réel vs CTR attendu à cette position (courbe de clics du site). En orange : bien classé mais peu cliqué → titre et méta-description à retravailler.",
    sortValue: (r) =>
      r.gsc_ctr_pct != null && r.ctr_expected != null ? r.gsc_ctr_pct - r.ctr_expected : null,
    render: (r) => <CtrCell r={r} />,
  },
  {
    key: "position",
    header: "pos.",
    align: "right",
    headerInfo: "Position moyenne Google, pondérée par impressions, toutes requêtes confondues.",
    sortValue: (r) => r.gsc_position_avg,
    render: (r) => (
      <span className="font-mono text-[11.5px] text-[#45423c]">{dec(r.gsc_position_avg)}</span>
    ),
  },
  {
    key: "mix",
    header: "source",
    align: "left",
    headerInfo:
      "Part du trafic venant de Google (clics Google / visiteurs). Faible = l'article vit sur réseaux / IA / direct, plus volatil que la recherche.",
    sortValue: (r) => (r.unique_visitors > 0 ? r.gsc_clicks / r.unique_visitors : null),
    render: (r) => <MixBadge r={r} />,
  },
  {
    key: "best_query",
    header: "meilleure requête",
    align: "left",
    sortValue: (r) => r.best_query_volume_fr,
    render: (r) =>
      r.best_query ? (
        <div className="max-w-[180px]">
          <div className="truncate text-[11.5px] text-[#45423c]">{r.best_query}</div>
          <div className="font-mono text-[9.5px] text-dim">
            {r.best_query_volume_fr != null ? `${num(r.best_query_volume_fr)} rech./mois` : "volume n.d."}
          </div>
        </div>
      ) : (
        <span className="text-dim">—</span>
      ),
  },
  {
    key: "contacts",
    header: "contacts",
    align: "right",
    subHeader: "sur la page",
    headerInfo:
      "Appels ou formulaires effectués PENDANT la visite de cette page. C'est l'endroit du geste qui reçoit le crédit.",
    sortValue: (r) => r.contacts,
    render: (r) => (
      <span
        className={cn("font-mono text-[11.5px] font-semibold", r.contacts > 0 ? "text-ink" : "text-dim")}
      >
        {num(r.contacts)}
      </span>
    ),
  },
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
  if (r.cpi_grade == null || r.cpi_grade === "C" || r.momentum == null) return "nonscore";
  if ((r.cpi_grade === "A" || r.cpi_grade === "B") && r.convertit === false) return "gisement";
  if (r.momentum >= 1.05) return "monte";
  if (r.momentum <= 0.95) return "ralentit";
  return "stable";
}

export function ResourcesTable({ rows }: { rows: ResourceRow[] }) {
  const searchParams = useSearchParams();
  // Période courante → propagée aux liens de fiche (sauf défaut rolling_90).
  const periodQ = searchParams.get("period") === "rolling_28" ? "?period=rolling_28" : "";

  // État de vue initialisé DEPUIS l'URL (reload = état restauré). Init lazy : lu une
  // seule fois ; le remount sur changement de route/période le relit. Le bouton Retour
  // du navigateur restaure les filtres car on revient sur une entrée d'historique
  // porteuse de ces params (la fiche est une AUTRE route → remount → ré-init).
  const [recentOnly, setRecentOnly] = useState(() => searchParams.get("recents") === "1");
  const [search, setSearch] = useState(() => searchParams.get("q") ?? "");
  const [theme, setTheme] = useState<string>(() => searchParams.get("theme") ?? "tous");
  const [sante, setSante] = useState<SanteFilter>(() => {
    const s = searchParams.get("sante");
    const valid = ["monte", "stable", "ralentit", "gisement", "nonscore"];
    return s && valid.includes(s) ? (s as SanteFilter) : "tous";
  });
  const [sortKey, setSortKey] = useState(() => searchParams.get("sort") ?? "visitors");
  const [sortDir, setSortDir] = useState<"asc" | "desc">(() =>
    searchParams.get("dir") === "asc" ? "asc" : "desc",
  );

  // État de vue → URL via replaceState (AUCUN refetch serveur), débounce 300 ms.
  // On saute le 1er run (l'URL reflète déjà l'init) ; les valeurs par défaut sont omises.
  const firstRun = useRef(true);
  useEffect(() => {
    if (firstRun.current) {
      firstRun.current = false;
      return;
    }
    const t = setTimeout(() => {
      replaceUrlParams({
        q: search.trim() || null,
        theme: theme === "tous" ? null : theme,
        sante: sante === "tous" ? null : sante,
        recents: recentOnly ? "1" : null,
        sort: sortKey === "visitors" ? null : sortKey,
        dir: sortDir === "desc" ? null : sortDir,
      });
    }, 300);
    return () => clearTimeout(t);
  }, [search, theme, sante, recentOnly, sortKey, sortDir]);

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
            onChange={(e) => setSearch(e.target.value)}
            placeholder="rechercher (titre, requête)…"
            className={cn(selectCls, "w-[190px]")}
            aria-label="Rechercher un article"
          />
          <select value={theme} onChange={(e) => setTheme(e.target.value)} className={selectCls} aria-label="Filtrer par thème">
            <option value="tous">Tous les thèmes</option>
            {themes.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
          <select
            value={sante}
            onChange={(e) => setSante(e.target.value as SanteFilter)}
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
              onChange={(e) => setRecentOnly(e.target.checked)}
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
        onSortChange={(k, d) => {
          setSortKey(k);
          setSortDir(d);
        }}
      />
      <p className="mt-[11px] font-mono text-[10.5px] leading-relaxed text-dim">
        ▲▼ tendances vs période précédente · cliquer un titre ouvre la fiche de l&apos;article
      </p>
    </div>
  );
}
