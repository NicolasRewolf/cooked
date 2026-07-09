"use client";

import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { replaceUrlParams } from "@/lib/url";
import { SortableTable, type Column } from "./SortableTable";
import { ConfidenceBadge } from "./ui";
import { cn } from "@/lib/cn";
import type { ExpertiseRow } from "@/lib/types";
import { num, seconds, dec, pct, delta, prettyPath } from "@/lib/format";
import { momentumDir, momentumLabelFr } from "@/lib/momentum";
import { Trend } from "./ui";

// ── Verdict de santé : momentum (relatif au site) + grade de confiance ───────
function HealthCell({ r }: { r: ExpertiseRow }) {
  if (r.cpi_grade == null || r.cpi_grade === "C" || r.momentum == null) {
    return (
      <span className="font-mono text-[11px] text-dim">—</span>
    );
  }
  const m = r.momentum;
  const dir = momentumDir(m);
  const dot = dir === "up" ? "bg-up" : dir === "down" ? "bg-warn" : "bg-faint";
  const word = momentumLabelFr(dir);
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
function CtrCell({ r }: { r: ExpertiseRow }) {
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

// ── Part payante de la page (canal d'acquisition Adwords) ─────────────────────
// Fort = la page vit sur Adwords → la lecture organique repose sur peu de visiteurs.
function PaidCell({ r }: { r: ExpertiseRow }) {
  if (r.paid_share_pct == null) return <span className="text-dim">—</span>;
  const p = r.paid_share_pct;
  const cls = p >= 70 ? "text-warn" : p <= 30 ? "text-up" : "text-[#45423c]";
  return (
    <span className={cn("font-mono text-[11.5px] font-medium", cls)}>{pct(p, 0)}</span>
  );
}

const columns: Column<ExpertiseRow>[] = [
  {
    key: "page",
    header: "page expertise",
    align: "left",
    sortValue: (r) => prettyPath(r.path),
    render: (r) => (
      <div className="max-w-[240px]">
        <a
          href={`https://www.jplouton-avocat.fr${r.path}`}
          target="_blank"
          rel="noopener noreferrer"
          className="block truncate text-[12.5px] font-medium text-ink transition-colors hover:text-accent"
        >
          {prettyPath(r.path)}
        </a>
        <div className="mt-[3px] flex items-center gap-[7px]">
          {r.theme && <span className="font-mono text-[10.5px] text-dim">{r.theme}</span>}
          <ConfidenceBadge grade={r.confidence} />
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
    key: "paid",
    header: "part paid",
    align: "right",
    headerInfo:
      "Part des sessions voyant cette page arrivées par Google Ads (canal d'entrée de session). Élevé = la page vit de la pub, pas du SEO.",
    sortValue: (r) => r.paid_share_pct,
    render: (r) => <PaidCell r={r} />,
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
      "Temps de lecture médian des entrées organiques uniquement — le trafic Ads a un autre comportement.",
    sortValue: (r) => r.dwell_median_s,
    render: (r) => (
      <span className="font-mono text-[11.5px] text-[#45423c]">{seconds(r.dwell_median_s)}</span>
    ),
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
];

export function ExpertisesTable({ rows }: { rows: ExpertiseRow[] }) {
  const searchParams = useSearchParams();
  // Tri dans l'URL (mêmes conventions que les articles ; pas de filtres ici).
  const [sortKey, setSortKey] = useState(() => searchParams.get("sort") ?? "visitors");
  const [sortDir, setSortDir] = useState<"asc" | "desc">(() =>
    searchParams.get("dir") === "asc" ? "asc" : "desc",
  );
  const firstRun = useRef(true);
  useEffect(() => {
    if (firstRun.current) {
      firstRun.current = false;
      return;
    }
    replaceUrlParams({
      sort: sortKey === "visitors" ? null : sortKey,
      dir: sortDir === "desc" ? null : sortDir,
    });
  }, [sortKey, sortDir]);

  return (
    <div>
      <h2 className="mb-2.5 font-mono text-[11px] font-semibold uppercase tracking-[0.05em] text-muted">
        expertises [{rows.length}]
      </h2>
      <SortableTable
        columns={columns}
        rows={rows}
        initialSortKey={sortKey}
        initialDir={sortDir}
        minWidth={1040}
        onSortChange={(k, d) => {
          setSortKey(k);
          setSortDir(d);
        }}
      />
      <p className="mt-[11px] font-mono text-[10.5px] leading-relaxed text-dim">
        ▲▼ tendances vs période précédente
      </p>
    </div>
  );
}
