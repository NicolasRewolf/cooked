"use client";

import { useState } from "react";
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
      <span className="font-mono text-[11px] text-dim" title="Trop peu de trafic organique pour un verdict fiable">
        —
      </span>
    );
  }
  const m = r.momentum;
  const dir = m >= 1.05 ? "up" : m <= 0.95 ? "down" : "flat";
  const dot = dir === "up" ? "bg-up" : dir === "down" ? "bg-warn" : "bg-faint";
  const word = dir === "up" ? "monte" : dir === "down" ? "ralentit" : "stable";
  const gisement = (r.cpi_grade === "A" || r.cpi_grade === "B") && r.convertit === false;
  const tip =
    `Santé relative au site · potentiel SEO ${r.potentiel ?? "—"} (capture + rétention + lecture, hors conversion) · ` +
    `momentum ${m.toFixed(2)} (${word}) · score CPI global ${r.cpi ?? "—"}` +
    (gisement ? " · ★ gisement : fort potentiel mais pas encore de contact → poser un pont" : "");
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap" title={tip}>
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
    <span
      className="whitespace-nowrap"
      title={`CTR réel ${pct(r.gsc_ctr_pct)} vs attendu ${pct(exp)} à la position ${dec(
        r.gsc_position_avg,
      )} (courbe du site). En-dessous = titre / méta à retravailler.`}
    >
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
  return (
    <span
      title={`${num(r.gsc_clicks)} clics Google pour ${num(r.unique_visitors)} visiteurs (${Math.round(
        ratio * 100,
      )} %). Faible = trafic réseaux / IA / direct, plus volatil.`}
    >
      <Badge tone={tone}>{label}</Badge>
    </span>
  );
}

const columns: Column<ResourceRow>[] = [
  {
    key: "article",
    header: "article",
    align: "left",
    sortValue: (r) => prettyPath(r.path),
    render: (r) => (
      <div className="max-w-[230px]">
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
  { key: "sante", header: "santé", align: "left", sortValue: (r) => r.momentum, render: (r) => <HealthCell r={r} /> },
  {
    key: "days_live",
    header: "âge",
    align: "right",
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
    sortValue: (r) =>
      r.gsc_ctr_pct != null && r.ctr_expected != null ? r.gsc_ctr_pct - r.ctr_expected : null,
    render: (r) => <CtrCell r={r} />,
  },
  {
    key: "position",
    header: "pos.",
    align: "right",
    sortValue: (r) => r.gsc_position_avg,
    render: (r) => (
      <span
        className="font-mono text-[11.5px] text-[#45423c]"
        title="Moyenne pondérée par impressions, toutes requêtes confondues."
      >
        {dec(r.gsc_position_avg)}
      </span>
    ),
  },
  {
    key: "mix",
    header: "source",
    align: "left",
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
    key: "tel",
    header: "tél.",
    align: "right",
    sortValue: (r) => r.contacts,
    render: (r) => (
      <span
        className={cn("font-mono text-[11.5px] font-semibold", r.contacts > 0 ? "text-ink" : "text-dim")}
        title="Appels tél. déclenchés pendant la lecture — signal incident, PAS une conversion attribuée."
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
      <div className="mb-2.5 flex items-center justify-between gap-4">
        <h2 className="font-mono text-[11px] font-semibold uppercase tracking-[0.05em] text-muted">
          articles [{filtered.length}]
        </h2>
        <label className="flex w-fit cursor-pointer items-center gap-2 text-[11.5px] text-muted">
          <input
            type="checkbox"
            checked={recentOnly}
            onChange={(e) => setRecentOnly(e.target.checked)}
            className="accent-accent"
          />
          récents seulement (≤ 60 j)
        </label>
      </div>
      <SortableTable columns={columns} rows={filtered} initialSortKey="visitors" initialDir="desc" minWidth={1080} />
      <p className="mt-[11px] max-w-[920px] font-mono text-[10.5px] leading-relaxed text-dim">
        <strong className="font-semibold text-faint">santé</strong> = momentum vs site (● monte / ●
        ralentit · ★ gisement : fort potentiel, pas encore de contact) ·{" "}
        <strong className="font-semibold text-faint">ctr / att.</strong> en orange = bien classé mais
        titre / méta à retravailler · <strong className="font-semibold text-faint">source</strong> =
        part du trafic venant de Google vs réseaux / IA / direct · tendances ▲▼ vs période précédente.
      </p>
    </div>
  );
}
