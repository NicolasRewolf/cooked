import Link from "next/link";
import { Nav } from "@/components/nav";
import { DateBanner } from "@/components/date-banner";
import { CategoryBadge } from "@/components/category-badge";
import { InfoLabel } from "@/components/info-label";
import { gscPagesOverview, pipelineHealth, siteKpisCompare } from "@/lib/cooked";
import {
  formatInt,
  formatPct,
  formatNumber,
} from "@/lib/format";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const HINTS = {
  page: "URL de la page sur le site.",
  category: "Type de page (Accueil / Cabinet / Expertise / Article).",
  clicks: "Clics depuis Google Search Console sur les 28 derniers jours.",
  impressions:
    "Nombre de fois où la page est apparue dans les résultats Google (28 j).",
  position:
    "Position moyenne dans les résultats Google, pondérée par les impressions (1 = top).",
  ctr:
    "Taux de clic Google = clics / impressions. Benchmark : ~3 % en position 5, ~25 % en position 1.",
  visits:
    "Visites humaines uniques mesurées par Cooked (bots et bruit filtrés).",
  dwell:
    "Temps moyen passé sur la page par session.",
  conversions:
    "Contacts business : appels téléphone (cta_phone_click) + formulaires soumis (form_submit).",
  pogo:
    "Sessions arrivant de Google qui repartent rapidement (mauvais signal SEO si élevé).",
};

export default async function PagesList() {
  const [pages, health, kpis] = await Promise.all([
    gscPagesOverview(30),
    pipelineHealth(),
    siteKpisCompare(28),
  ]);

  return (
    <>
      <Nav />
      <DateBanner
        periodStart={kpis.period_n_start}
        periodEnd={kpis.period_n_end}
        gscLastDay={health.gsc_last_day}
        gscDataAgeDays={health.gsc_data_age_days}
      />
      <main className="mx-auto w-full max-w-6xl px-6 py-10">
        <header className="mb-8">
          <h1 className="font-heading text-2xl font-medium tracking-tight">
            Pages — top 30 sur 28 jours
          </h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Croisement Google Search Console × comportement Cooked. Trié
            par clics organiques.
          </p>
        </header>

        <div className="overflow-hidden rounded-lg border border-border bg-surface shadow-xs">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="border-b border-border bg-surface-subtle/50">
                <tr className="text-left font-mono text-xs uppercase tracking-wide text-muted-foreground">
                  <th className="px-4 py-3 font-medium">
                    <InfoLabel label="Page" hint={HINTS.page} />
                  </th>
                  <th className="px-3 py-3 font-medium">
                    <InfoLabel label="Type" hint={HINTS.category} />
                  </th>
                  <th className="px-3 py-3 text-right font-medium">
                    <InfoLabel label="Clics Google" hint={HINTS.clicks} />
                  </th>
                  <th className="px-3 py-3 text-right font-medium">
                    <InfoLabel label="Impressions" hint={HINTS.impressions} />
                  </th>
                  <th className="px-3 py-3 text-right font-medium">
                    <InfoLabel label="Position" hint={HINTS.position} />
                  </th>
                  <th className="px-3 py-3 text-right font-medium">
                    <InfoLabel label="CTR" hint={HINTS.ctr} />
                  </th>
                  <th className="px-3 py-3 text-right font-medium">
                    <InfoLabel label="Visites" hint={HINTS.visits} />
                  </th>
                  <th className="px-3 py-3 text-right font-medium">
                    <InfoLabel label="Temps moyen" hint={HINTS.dwell} />
                  </th>
                  <th className="px-3 py-3 text-right font-medium">
                    <InfoLabel label="Contacts" hint={HINTS.conversions} />
                  </th>
                  <th className="px-4 py-3 text-right font-medium">
                    <InfoLabel label="Rebond rapide" hint={HINTS.pogo} />
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border-subtle)]">
                {pages.map((p) => (
                  <tr
                    key={p.path}
                    className="group transition-colors hover:bg-surface-subtle/40"
                  >
                    <td className="max-w-[260px] truncate px-4 py-3">
                      <Link
                        href={`/p${p.path}`}
                        className="block truncate text-foreground hover:underline"
                        title={p.path}
                      >
                        {p.path}
                      </Link>
                    </td>
                    <td className="px-3 py-3">
                      <CategoryBadge path={p.path} />
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      {formatInt(p.gsc_clicks_28d)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatInt(p.gsc_impressions_28d)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      <PositionBadge value={p.gsc_position_avg_28d} />
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatPct(p.gsc_ctr_pct_28d, 2)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      {formatInt(p.cooked_sessions_28d)}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {p.cooked_dwell_avg_s_28d != null
                        ? `${formatNumber(p.cooked_dwell_avg_s_28d, 0)}s`
                        : "—"}
                    </td>
                    <td className="px-3 py-3 text-right font-mono tabular-nums">
                      {p.cooked_conversions_28d > 0 ? (
                        <span className="font-medium text-success">
                          {formatInt(p.cooked_conversions_28d)}
                        </span>
                      ) : (
                        <span className="text-muted-foreground">0</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right font-mono tabular-nums text-muted-foreground">
                      {formatPct(p.cooked_pogo_rate_28d, 1)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        <p className="mt-4 font-mono text-xs text-muted-foreground">
          {pages.length} pages affichées · cliquer une ligne pour la fiche
          détaillée.
        </p>
      </main>
    </>
  );
}

function PositionBadge({ value }: { value: number | null }) {
  if (value == null) return <span className="text-muted-foreground">—</span>;
  const tone =
    value < 3
      ? "text-success"
      : value < 11
        ? "text-foreground"
        : "text-muted-foreground";
  return <span className={tone}>{formatNumber(value, 1)}</span>;
}
