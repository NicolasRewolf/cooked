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
      <span className="text-[11.5px] text-ink-2">{word}</span>
      {opportunite && (
        <span aria-label="opportunité de contact" className="text-[11px] text-accent">
          ★
        </span>
      )}
    </span>
  );
}

// CTR observé uniquement : une courbe appliquée à la position moyenne ne
// constitue pas une attente valide pour un mélange de requêtes.
export function CtrCell({ r }: { r: ResourceRow }) {
  if (r.gsc_ctr_pct == null) return <span className="text-dim">—</span>;
  return (
    <span className="whitespace-nowrap font-mono text-[11.5px] font-medium text-ink-2">{pct(r.gsc_ctr_pct)}</span>
  );
}

// ── Totaux de pied de tableau ─────────────────────────────────────────────────
// Reçoivent les lignes VISIBLES (filtre + tri déjà appliqués) : le pied décrit ce
// qu'on regarde, pas le jeu complet.
//
// Ce qu'on NE totalise PAS, volontairement :
//  · position — une position moyenne inter-pages est le piège n°2 du playbook
//    (pondérée impressions, elle mélange des requêtes sans rapport) ;
//  · lecture — une médiane de médianes n'est pas une médiane.
//  · visiteurs — une personne peut visiter plusieurs pages.
// Le CTR, lui, s'agrège correctement : Σ clics / Σ impressions.
/** Somme d'un champ sur les lignes visibles (null / undefined comptent pour 0). */
export function sumBy(
  rows: ResourceRow[],
  f: (r: ResourceRow) => number | null | undefined,
): number {
  return rows.reduce((acc, r) => acc + (f(r) ?? 0), 0);
}

/** CTR agrégé d'un ensemble de pages = Σ clics / Σ impressions (en %).
 *  Surtout PAS la moyenne des CTR par page : elle pèse pareil une page à
 *  10 impressions et une page à 10 000. `null` si aucune impression. */
export function aggregateCtrPct(rows: ResourceRow[]): number | null {
  const imp = sumBy(rows, (r) => r.gsc_impressions);
  if (imp === 0) return null;
  return (sumBy(rows, (r) => r.gsc_clicks) / imp) * 100;
}

const sum = sumBy;

function Total({ children }: { children: React.ReactNode }) {
  return <span className="font-mono text-[11.5px] font-semibold text-ink-2">{children}</span>;
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
  headerInfo: "Visiteurs uniques de chaque page. Ils ne s'additionnent pas entre pages : le distinct du périmètre complet figure dans le KPI supérieur.",
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
    render: (r) => <span className="font-mono text-[11.5px] text-ink-2">{seconds(r.dwell_median_s)}</span>,
  };
}

export const gscClicksColumn: Column<ResourceRow> = {
  key: "gsc_clicks",
  header: "clics",
  align: "right",
  sortValue: (r) => r.gsc_clicks,
  total: (rows) => <Total>{num(sum(rows, (r) => r.gsc_clicks))}</Total>,
  render: (r) => (
    <div className="flex flex-col items-end leading-tight">
      <span className="font-mono text-[12px] font-medium text-ink">{num(r.gsc_clicks)}</span>
      <Trend d={delta(r.gsc_clicks, r.gsc_clicks_prev)} />
    </div>
  ),
};

export const ctrColumn: Column<ResourceRow> = {
  key: "ctr",
  header: "ctr",
  align: "right",
  subHeader: "observé",
  headerInfo:
    "Clics Google / impressions Google. Ce taux décrit les requêtes observées ; il ne suffit pas à conclure qu'un titre ou une méta-description doit changer.",
  sortValue: (r) => r.gsc_ctr_pct,
  render: (r) => <CtrCell r={r} />,
  total: (rows) => {
    const ctr = aggregateCtrPct(rows);
    return ctr == null ? <span className="text-dim">—</span> : <Total>{pct(ctr)}</Total>;
  },
};

export const positionColumn: Column<ResourceRow> = {
  key: "position",
  header: "pos.",
  align: "right",
  headerInfo: "Position moyenne Google, pondérée par impressions, toutes requêtes confondues.",
  sortValue: (r) => r.gsc_position_avg,
  render: (r) => (
    <span className="font-mono text-[11.5px] text-ink-2">{dec(r.gsc_position_avg)}</span>
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
        <div className="truncate text-[11.5px] text-ink-2">{r.best_query}</div>
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
    "Clics sur un lien téléphone ou formulaires hors recrutement, attribués à la page du geste. Un clic téléphone ne confirme pas un appel abouti.",
  sortValue: (r) => r.contacts,
  total: (rows) => <Total>{num(sum(rows, (r) => r.contacts))}</Total>,
  render: (r) => (
    <span
      className={cn("font-mono text-[11.5px] font-semibold", r.contacts > 0 ? "text-ink" : "text-dim")}
    >
      {num(r.contacts)}
    </span>
  ),
};
