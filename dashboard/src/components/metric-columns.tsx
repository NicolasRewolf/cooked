// D6 — colonnes métriques partagées entre ResourcesTable et ExpertisesTable.
// Un ExpertiseRow EST un ResourceRow (rpc-schemas : extend) → les cellules et
// colonnes communes sont typées sur ResourceRow et s'assemblent dans les deux
// tableaux (contravariance des props de Column). Chaque tableau ne déclare plus
// que ses colonnes distinctives (article/âge/mix/assistés vs page/part paid) et
// compose son ordre. Rendu STRICTEMENT identique aux versions dupliquées.

import type { Column } from "./SortableTable";
import { Trend, dirDotClass } from "./ui";
import { cn } from "@/lib/cn";
import type { ResourceRow } from "@/lib/types";
import { num, seconds, dec, pct, delta } from "@/lib/format";
import { momentumDir, momentumLabelFr, isScored, isOpportuniteContact } from "@/lib/momentum";

// ── Verdict de santé : momentum (relatif au site) + Fiabilité CPI ────────────
// Pour les pages sans conversion (articles éducatifs), le potentiel
// hors-conversion est le bon repère — d'où la ★ opportunité de contact.
export function HealthCell({ r }: { r: ResourceRow }) {
  if (!isScored(r.cpi_grade, r.momentum)) {
    return (
      <span className="font-mono text-[11px] text-dim">—</span>
    );
  }
  const dir = momentumDir(r.momentum!);
  const dot = dirDotClass(dir);
  const word = momentumLabelFr(dir);
  const opportunite = isOpportuniteContact(r.cpi_grade, r.convertit);
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap">
      <span className={cn("h-[7px] w-[7px] shrink-0 rounded-full", dot)} />
      <span className="text-[11.5px] text-[#45423c]">{word}</span>
      {opportunite && (
        <span aria-label="opportunité de contact" className="text-[11px] text-accent">
          ★
        </span>
      )}
    </span>
  );
}

// ── CTR réel vs CTR attendu à la position (courbe du site) ────────────────────
// Démasque un bon classement qui ne ramène pas de clics (titre / méta à revoir).
export function CtrCell({ r }: { r: ResourceRow }) {
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

// ── Registre des colonnes communes ────────────────────────────────────────────
// Constantes quand tout est identique ; factory quand un texte diffère (dwell).

export const santeColumn: Column<ResourceRow> = {
  key: "sante",
  header: "santé",
  align: "left",
  headerInfo:
    "Momentum des clics Google relatif au site : ● monte / ● stable / ● ralentit. ★ opportunité de contact = fort potentiel (capture + lecture) mais pas encore de contact → poser un pont. — = trop peu de trafic organique pour un verdict (Fiabilité C).",
  sortValue: (r) => r.momentum,
  render: (r) => <HealthCell r={r} />,
};

export const visitorsColumn: Column<ResourceRow> = {
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
};

// Le texte ⓘ diffère : ressources (réseaux sociaux exclus) vs expertises
// (entrées organiques uniquement) — chaque tableau passe le sien.
export function dwellColumn(headerInfo: string): Column<ResourceRow> {
  return {
    key: "dwell",
    header: "lecture",
    align: "right",
    headerInfo,
    sortValue: (r) => r.dwell_median_s,
    render: (r) => <span className="font-mono text-[11.5px] text-[#45423c]">{seconds(r.dwell_median_s)}</span>,
  };
}

export const gscClicksColumn: Column<ResourceRow> = {
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
};

export const ctrColumn: Column<ResourceRow> = {
  key: "ctr",
  header: "ctr / att.",
  align: "right",
  subHeader: "réel / attendu",
  headerInfo:
    "CTR réel vs CTR attendu à cette position (courbe de clics du site). En orange : bien classé mais peu cliqué → titre et méta-description à retravailler.",
  sortValue: (r) =>
    r.gsc_ctr_pct != null && r.ctr_expected != null ? r.gsc_ctr_pct - r.ctr_expected : null,
  render: (r) => <CtrCell r={r} />,
};

export const positionColumn: Column<ResourceRow> = {
  key: "position",
  header: "pos.",
  align: "right",
  headerInfo: "Position moyenne Google, pondérée par impressions, toutes requêtes confondues.",
  sortValue: (r) => r.gsc_position_avg,
  render: (r) => (
    <span className="font-mono text-[11.5px] text-[#45423c]">{dec(r.gsc_position_avg)}</span>
  ),
};

export const bestQueryColumn: Column<ResourceRow> = {
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
};

export const contactsColumn: Column<ResourceRow> = {
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
};
