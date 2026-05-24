import Link from "next/link";
import { TrendingUp } from "lucide-react";
import { InfoLabel } from "@/components/info-label";
import { formatInt, formatNumber } from "@/lib/format";
import type { GscDfsOpportunityRow } from "@/lib/cooked";

/**
 * Liste des opportunités SEO : requêtes où le site est en position 5-15
 * sur des requêtes à fort volume. Triées par "lost_potential" (clics
 * manqués si on était en position 1).
 *
 * Affichée en haut de /queries pour pousser à l'action.
 */
export function SeoOpportunities({
  rows,
  periodLabel = "période sélectionnée",
}: {
  rows: GscDfsOpportunityRow[];
  periodLabel?: string;
}) {
  if (rows.length === 0) {
    return (
      <section className="rounded-lg border border-dashed border-border bg-surface p-5 text-sm text-muted-foreground">
        Aucune opportunité immédiate (pas de requête en position 5–15 avec
        un volume France ≥ 100). Sera populé après le 1er sync DataForSEO.
      </section>
    );
  }

  return (
    <section className="rounded-lg border border-success/30 bg-success/5 p-5 shadow-xs">
      <div className="mb-3 flex items-baseline justify-between">
        <h2 className="flex items-center gap-2 font-heading text-base font-medium tracking-tight text-success">
          <TrendingUp className="h-4 w-4" aria-hidden="true" />
          <InfoLabel
            label={`Opportunités SEO — top ${rows.length}`}
            hint={`Requêtes où le site est en position 5–15 sur Google avec ≥ 100 recherches mensuelles France. Lost potential = clics manqués sur ${periodLabel} si on était en position 1 (CTR Sistrix benchmark). Trié par lost potential décroissant.`}
          />
        </h2>
      </div>

      <div className="overflow-hidden rounded-md border border-success/20 bg-surface">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-success/15 bg-success/5">
              <tr className="text-left font-mono text-xs uppercase tracking-wide text-muted-foreground">
                <th className="px-4 py-2.5 font-medium">Requête</th>
                <th className="px-3 py-2.5 text-right font-medium">Pos.</th>
                <th className="px-3 py-2.5 text-right font-medium">Clics</th>
                <th className="px-3 py-2.5 text-right font-medium">Volume FR</th>
                <th className="px-3 py-2.5 text-right font-medium">CPC</th>
                <th className="px-3 py-2.5 text-right font-medium text-success">
                  Lost potential
                </th>
                <th className="px-4 py-2.5 font-medium">Top page</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {rows.map((r) => (
                <tr
                  key={r.query}
                  className="transition-colors hover:bg-success/5"
                >
                  <td className="max-w-[260px] truncate px-4 py-2.5 text-foreground">
                    {r.query}
                  </td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums">
                    {formatNumber(r.our_position, 1)}
                  </td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums text-muted-foreground">
                    {formatInt(r.our_clicks)}
                  </td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums">
                    {formatInt(r.volume_fr)}
                  </td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums text-muted-foreground">
                    {r.cpc != null ? `${formatNumber(r.cpc, 2)} €` : "—"}
                  </td>
                  <td className="px-3 py-2.5 text-right font-mono tabular-nums font-medium text-success">
                    +{formatInt(r.lost_potential)}
                  </td>
                  <td className="max-w-[220px] truncate px-4 py-2.5">
                    {r.top_page ? (
                      <Link
                        href={`/p${r.top_page}`}
                        className="block truncate text-foreground hover:underline"
                        title={r.top_page}
                      >
                        {r.top_page}
                      </Link>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
