// D7 — view-models PURS : entrées = types Zod du contrat RPC (C4), sorties =
// objets de vue prêts à rendre. Aucune I/O ici — les pages font
// fetch (data/dashboard.ts) → build (ce fichier) → render (components/).
// Testable par vitest sans mocker Supabase.

import type { KpiItem } from "@/components/KpiHeader";
import { buildMarkers } from "@/lib/annotations";
import { num, pct, delta } from "@/lib/format";
import type {
  Annotation,
  AssistedRow,
  ExpertiseKpis,
  ResourceKpis,
  ResourceRow,
  ResourcesTrend,
  SeoKpis,
  TrendMarker,
} from "@/lib/types";

// ---------------------------------------------------------------------------
// Articles ressources (/)
// ---------------------------------------------------------------------------

/** Fusion des « contacts assistés » (attribution page d'entrée) dans les lignes.
 *  Une ligne sans correspondance est renvoyée telle quelle (même référence). */
export function mergeAssisted(rows: ResourceRow[], assisted: AssistedRow[]): ResourceRow[] {
  const byPath = new Map(assisted.map((a) => [a.path, a]));
  return rows.map((r) => {
    const a = byPath.get(r.path);
    return a ? { ...r, assisted_contacts: a.assisted_contacts, assisted_prev: a.assisted_prev } : r;
  });
}

export interface ResourcesView {
  rows: ResourceRow[];
  items: KpiItem[];
  markers: TrendMarker[];
}

export function buildResourcesView(input: {
  kpis: ResourceKpis | null;
  rows: ResourceRow[];
  trend: ResourcesTrend | null;
  assisted: AssistedRow[];
  annotations: Annotation[];
}): ResourcesView {
  const { kpis, trend, assisted, annotations } = input;
  // B1 — toutes les annotations de la fenêtre sur le graphe visiteurs (pas de filtre path ici).
  const markers = buildMarkers(annotations, kpis?.cooked_start, trend?.visitors_daily?.length ?? 0);
  const rows = mergeAssisted(input.rows, assisted);

  const items: KpiItem[] = kpis
    ? [
        { label: "Visiteurs uniques", value: num(kpis.visitors_n), delta: delta(kpis.visitors_n, kpis.visitors_prev), series: trend?.visitors_daily },
        { label: "Pages vues", value: num(kpis.pageviews_n), delta: delta(kpis.pageviews_n, kpis.pageviews_prev), series: trend?.pageviews_daily },
        {
          label: "Contacts",
          value: num(kpis.contacts_n),
          delta: delta(kpis.contacts_n, kpis.contacts_prev),
          series: trend?.contacts_daily,
          tooltip: "Actions faites sur la page (appel ou formulaire).",
        },
        { label: "Clics Google", value: num(kpis.gsc_clicks_n), delta: delta(kpis.gsc_clicks_n, kpis.gsc_clicks_prev), series: trend?.gsc_clicks_daily },
        { label: "Affichages Google", value: num(kpis.gsc_impressions_n), delta: delta(kpis.gsc_impressions_n, kpis.gsc_impressions_prev), series: trend?.gsc_impressions_daily },
      ]
    : [];

  return { rows, items, markers };
}

// ---------------------------------------------------------------------------
// Pages expertise (/expertises)
// ---------------------------------------------------------------------------

export interface ExpertisesView {
  items: KpiItem[];
}

export function buildExpertisesView(input: {
  kpis: ExpertiseKpis | null;
  trend: ResourcesTrend | null;
}): ExpertisesView {
  const { kpis, trend } = input;

  const paidShare =
    kpis && kpis.total_entries_n > 0 ? (100 * kpis.paid_entries_n) / kpis.total_entries_n : null;
  const orgShare =
    kpis && kpis.total_entries_n > 0 ? (100 * kpis.organic_entries_n) / kpis.total_entries_n : null;

  const items: KpiItem[] = kpis
    ? [
        { label: "Visiteurs uniques", value: num(kpis.visitors_n), delta: delta(kpis.visitors_n, kpis.visitors_prev), series: trend?.visitors_daily },
        {
          label: "Part payante",
          value: pct(paidShare, 0),
          hint: orgShare != null ? `${pct(orgShare, 0)} organique` : undefined,
          tooltip:
            "Canal d'acquisition des sessions expertise (1er pageview de la session). Le reste = referral / direct / réseaux. Spam Baidu exclu.",
        },
        {
          label: "Contacts",
          value: num(kpis.contacts_n),
          delta: delta(kpis.contacts_n, kpis.contacts_prev),
          series: trend?.contacts_daily,
          tooltip: "Actions faites sur la page (appel ou formulaire).",
        },
        { label: "Clics Google", value: num(kpis.gsc_clicks_n), delta: delta(kpis.gsc_clicks_n, kpis.gsc_clicks_prev), series: trend?.gsc_clicks_daily },
        { label: "Affichages Google", value: num(kpis.gsc_impressions_n), delta: delta(kpis.gsc_impressions_n, kpis.gsc_impressions_prev), series: trend?.gsc_impressions_daily },
      ]
    : [];

  return { items };
}

// ---------------------------------------------------------------------------
// SEO · requêtes (/seo)
// ---------------------------------------------------------------------------

export interface SeoView {
  items: KpiItem[];
  /** Décalage Google en jours entiers (≥ 0), null si KPIs indisponibles. */
  lagDays: number | null;
  /** Libellés formatés du pied de tableau (deux univers de clics). */
  clicksPathTotalLabel: string;
  clicksNamedNonbrandedLabel: string;
}

/** `now` injectable pour les tests — les pages laissent le défaut
 *  (Server Component rendu à la requête : heure courante lue une fois). */
export function buildSeoView(seo: SeoKpis | null, now: number = Date.now()): SeoView {
  const lagDays = seo
    ? Math.max(0, Math.floor((now - new Date(seo.gsc_end).getTime()) / 86_400_000))
    : null;

  // B2/B3 : total quick wins calculé SQL (indépendant du cap du tableau) ; 2 niveaux de clics distincts.
  const items: KpiItem[] = [
    { label: "Clics Google", value: num(seo?.clicks_path_total ?? 0), hint: "toutes requêtes · marque incluse" },
    { label: "Affichages Google", value: num(seo?.impressions_path_total ?? 0), hint: "niveau page" },
    { label: "Requêtes connues", value: num(seo?.total_queries ?? 0), hint: "hors marque (fraction nommée par Google)" },
    { label: "Quick wins", value: num(seo?.total_quick_wins ?? 0), hint: "position 5–15 · volume ≥ 100" },
  ];

  return {
    items,
    lagDays,
    clicksPathTotalLabel: num(seo?.clicks_path_total ?? 0),
    clicksNamedNonbrandedLabel: num(seo?.clicks_named_nonbranded ?? 0),
  };
}
