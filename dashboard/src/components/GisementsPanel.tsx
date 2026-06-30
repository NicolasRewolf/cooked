import type { SeoQueryRow } from "@/lib/types";
import { num, prettyPath } from "@/lib/format";

// Panneau « gisements » : classe les requêtes par gain potentiel / mois (clics à
// aller chercher si la requête passait top 3 au CTR du site). Réponse directe à
// « où concentrer l'effort SEO ». Affiché en tête de la page SEO.
export function GisementsPanel({ rows, limit = 5 }: { rows: SeoQueryRow[]; limit?: number }) {
  const top = [...rows]
    .filter((r) => (r.opportunity_clicks ?? 0) > 0)
    .sort((a, b) => (b.opportunity_clicks ?? 0) - (a.opportunity_clicks ?? 0))
    .slice(0, limit);

  if (top.length === 0) return null;
  const max = top[0].opportunity_clicks ?? 1;

  return (
    <div className="mt-[18px] border border-line bg-panel">
      <div className="flex items-center gap-2 border-b border-[#efefed] px-4 py-3">
        <span className="text-[12px] text-accent">★</span>
        <h2 className="text-[12px] font-semibold text-ink">Gisements — gain potentiel / mois</h2>
        <span className="font-mono text-[10.5px] text-dim">
          clics à aller chercher si la requête passait top 3 au CTR du site
        </span>
      </div>
      <div className="px-4 pb-3.5 pt-1.5">
        {top.map((r) => (
          <div key={r.query} className="flex items-center gap-3.5 border-b border-[#f4f4f2] py-2 last:border-0">
            <div className="w-[230px] shrink-0 overflow-hidden">
              <div className="truncate text-[12.5px] font-medium text-ink">{r.query}</div>
              <div className="mt-0.5 truncate font-mono text-[10px] text-dim">
                {r.top_page ? prettyPath(r.top_page) : r.top_page_theme ?? ""}
              </div>
            </div>
            <div className="relative h-2 flex-1 bg-[#f2f2f0]">
              <div
                className="h-2 bg-accent"
                style={{ width: `${Math.round(((r.opportunity_clicks ?? 0) / max) * 100)}%` }}
              />
            </div>
            <div className="w-[70px] shrink-0 text-right font-mono text-[13px] font-semibold text-accent">
              +{num(r.opportunity_clicks)}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
