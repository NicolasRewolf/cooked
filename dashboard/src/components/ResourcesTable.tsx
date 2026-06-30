"use client";

import { useState } from "react";
import { SortableTable, type Column } from "./SortableTable";
import { Badge, ConfidenceBadge, Trend } from "./ui";
import { cn } from "@/lib/cn";
import type { ResourceRow } from "@/lib/types";
import { num, seconds, dec, pct, dateFr, delta, prettyPath } from "@/lib/format";

// Verdict de santé : on lit le momentum (relatif au site) + le grade de confiance.
// Pour ces articles éducatifs, le potentiel hors-conversion est le bon repère
// (le CPI global est tiré vers le bas par la conversion, rare sur les ressources).
function HealthCell({ r }: { r: ResourceRow }) {
  if (r.cpi_grade == null || r.cpi_grade === "C" || r.momentum == null) {
    return (
      <span
        className="text-neutral-300 dark:text-neutral-600"
        title="Trop peu de trafic organique pour un verdict fiable"
      >
        —
      </span>
    );
  }
  const m = r.momentum;
  const dir = m >= 1.05 ? "up" : m <= 0.95 ? "down" : "flat";
  const dot = dir === "up" ? "bg-emerald-500" : dir === "down" ? "bg-amber-500" : "bg-neutral-400";
  const word = dir === "up" ? "monte" : dir === "down" ? "ralentit" : "stable";
  const gisement = (r.cpi_grade === "A" || r.cpi_grade === "B") && r.convertit === false;
  const tip =
    `Santé relative au site · potentiel SEO ${r.potentiel ?? "—"} (capture + rétention + lecture, hors conversion) · ` +
    `momentum ${m.toFixed(2)} (${word}) · score CPI global ${r.cpi ?? "—"}` +
    (gisement ? " · ⭐ gisement : fort potentiel mais pas encore de contact → poser un pont" : "");
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap" title={tip}>
      <span className={cn("h-2 w-2 shrink-0 rounded-full", dot)} />
      <span className="text-neutral-700 dark:text-neutral-300">{word}</span>
      {gisement && <span aria-label="gisement">⭐</span>}
    </span>
  );
}

// CTR réel vs CTR attendu à la position (courbe du site) : démasque un bon
// classement qui ne ramène pas de clics (titre/méta à retravailler).
function CtrCell({ r }: { r: ResourceRow }) {
  if (r.gsc_ctr_pct == null) return <span className="text-neutral-400">—</span>;
  const exp = r.ctr_expected;
  let cls = "text-neutral-700 dark:text-neutral-300";
  if (exp != null) {
    if (r.gsc_ctr_pct >= exp) cls = "text-emerald-600 dark:text-emerald-400";
    else if (r.gsc_ctr_pct < exp * 0.7) cls = "text-amber-600 dark:text-amber-400";
  }
  return (
    <span
      className={cls}
      title={`CTR réel ${pct(r.gsc_ctr_pct)} vs attendu ${pct(exp)} à la position ${dec(
        r.gsc_position_avg,
      )} (courbe du site). En-dessous = titre/méta à retravailler. Position moyenne = indicatif (mélange de requêtes).`}
    >
      {pct(r.gsc_ctr_pct)}
      {exp != null && <span className="ml-1 text-[10px] text-neutral-400">/ {pct(exp, 0)}</span>}
    </span>
  );
}

// Divergence : part du trafic qui vient de la recherche Google (clics GSC vs
// visiteurs Cooked). Faible = l'article vit sur les réseaux/IA/direct (volatil).
function MixBadge({ r }: { r: ResourceRow }) {
  if (r.unique_visitors === 0) return <span className="text-neutral-400">—</span>;
  const ratio = r.gsc_clicks / r.unique_visitors;
  const [tone, label] =
    ratio >= 0.8
      ? (["info", "Google"] as const)
      : ratio >= 0.35
        ? (["neutral", "Mixte"] as const)
        : (["warn", "Hors-Google"] as const);
  return (
    <span
      title={`${num(r.gsc_clicks)} clics Google pour ${num(r.unique_visitors)} visiteurs (${Math.round(
        ratio * 100,
      )} %). Faible = trafic réseaux sociaux / IA / direct, plus volatil que la recherche.`}
    >
      <Badge tone={tone}>{label}</Badge>
    </span>
  );
}

const columns: Column<ResourceRow>[] = [
  {
    key: "article",
    header: "Article",
    align: "left",
    sortValue: (r) => prettyPath(r.path),
    render: (r) => (
      <div className="max-w-[300px]">
        <a
          href={`https://www.jplouton-avocat.fr${r.path}`}
          target="_blank"
          rel="noopener noreferrer"
          className="font-medium text-neutral-900 hover:underline dark:text-neutral-100"
        >
          {prettyPath(r.path)}
        </a>
        <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-neutral-400">
          {r.theme && <span>{r.theme}</span>}
          <ConfidenceBadge grade={r.confidence} />
        </div>
      </div>
    ),
  },
  {
    key: "sante",
    header: "Santé",
    align: "left",
    sortValue: (r) => r.momentum,
    render: (r) => <HealthCell r={r} />,
  },
  {
    key: "days_live",
    header: "Âge",
    align: "right",
    sortValue: (r) => r.days_live,
    render: (r) => (
      <span
        title={`1ʳᵉ vue ${dateFr(r.first_tracker_day)} · 1ʳᵉ impr. Google ${dateFr(r.first_impression_day)}`}
      >
        {r.days_live != null ? `${r.days_live} j` : "—"}
      </span>
    ),
  },
  {
    key: "visitors",
    header: "Visiteurs",
    align: "right",
    sortValue: (r) => r.unique_visitors,
    render: (r) => (
      <div className="flex flex-col items-end leading-tight">
        <span>{num(r.unique_visitors)}</span>
        <Trend d={delta(r.unique_visitors, r.unique_visitors_prev)} />
      </div>
    ),
  },
  {
    key: "dwell",
    header: "Lecture méd.",
    align: "right",
    sortValue: (r) => r.dwell_median_s,
    render: (r) => seconds(r.dwell_median_s),
  },
  {
    key: "gsc_clicks",
    header: "Clics Google",
    align: "right",
    sortValue: (r) => r.gsc_clicks,
    render: (r) => (
      <div className="flex flex-col items-end leading-tight">
        <span>{num(r.gsc_clicks)}</span>
        <Trend d={delta(r.gsc_clicks, r.gsc_clicks_prev)} />
      </div>
    ),
  },
  {
    key: "ctr",
    header: "CTR / attendu",
    align: "right",
    sortValue: (r) =>
      r.gsc_ctr_pct != null && r.ctr_expected != null ? r.gsc_ctr_pct - r.ctr_expected : null,
    render: (r) => <CtrCell r={r} />,
  },
  {
    key: "position",
    header: "Position",
    align: "right",
    sortValue: (r) => r.gsc_position_avg,
    render: (r) => (
      <span title="Moyenne pondérée par impressions, toutes requêtes confondues — peut masquer une requête commerciale en page 3 derrière des informationnelles bien classées.">
        {dec(r.gsc_position_avg)}
      </span>
    ),
  },
  {
    key: "mix",
    header: "Source",
    align: "left",
    sortValue: (r) => (r.unique_visitors > 0 ? r.gsc_clicks / r.unique_visitors : null),
    render: (r) => <MixBadge r={r} />,
  },
  {
    key: "best_query",
    header: "Meilleure requête",
    align: "left",
    sortValue: (r) => r.best_query_volume_fr,
    render: (r) =>
      r.best_query ? (
        <div className="max-w-[220px]">
          <div className="truncate text-neutral-700 dark:text-neutral-300">{r.best_query}</div>
          <div className="text-[11px] text-neutral-400">
            {r.best_query_volume_fr != null ? `${num(r.best_query_volume_fr)} rech./mois` : "volume n.d."}
          </div>
        </div>
      ) : (
        <span className="text-neutral-400">—</span>
      ),
  },
  {
    key: "tel",
    header: "Tél. lecture",
    align: "right",
    sortValue: (r) => r.contacts,
    render: (r) => (
      <span
        className={r.contacts > 0 ? "text-neutral-700 dark:text-neutral-300" : "text-neutral-400"}
        title="Appels tél. déclenchés pendant la lecture de l'article — signal incident, PAS une conversion attribuée (les formulaires ne portent jamais le path d'un article)."
      >
        {num(r.contacts)}
      </span>
    ),
  },
];

export function ResourcesTable({ rows }: { rows: ResourceRow[] }) {
  const [recentOnly, setRecentOnly] = useState(false);
  const filtered = recentOnly ? rows.filter((r) => r.days_live != null && r.days_live <= 60) : rows;
  return (
    <div>
      <label className="mb-3 flex w-fit cursor-pointer items-center gap-2 text-sm text-neutral-600 dark:text-neutral-400">
        <input
          type="checkbox"
          checked={recentOnly}
          onChange={(e) => setRecentOnly(e.target.checked)}
          className="accent-neutral-900 dark:accent-neutral-100"
        />
        Articles récents seulement (≤ 60 j) — ton flux éditorial du mois
      </label>
      <SortableTable columns={columns} rows={filtered} initialSortKey="visitors" initialDir="desc" />
      <p className="mt-2 text-[11px] text-neutral-400">
        <span className="font-medium">Santé</span> = momentum relatif au site (🟢 monte · 🟠 ralentit) ;
        ⭐ = gisement (fort potentiel, pas encore de contact). <span className="font-medium">CTR / attendu</span> :
        en-dessous de l&apos;attendu = titre/méta à retravailler. <span className="font-medium">Source</span> :
        part du trafic venant de Google vs réseaux/IA/direct. Tendances ▲▼ vs période précédente.
      </p>
    </div>
  );
}
