"use client";

import { useEffect, useState } from "react";
import type { PageQueries as Queries } from "@/lib/page-views";
import type { Period } from "@/lib/page-view-filters";

const numbers = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 });
const date = (value: string) => new Intl.DateTimeFormat("fr-FR", { timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`));
const signed = (value: number) => {
  const rounded = Math.round(value * 100) / 100 || 0;
  return `${rounded > 0 ? "+" : ""}${numbers.format(rounded)}`;
};
const changeColor = (delta: number, lowerIsBetter = false) => delta === 0 ? "text-muted"
  : (lowerIsBetter ? delta < 0 : delta > 0) ? "text-up" : "text-down";

export function PageQueries({ path, days }: { path: string; days: Period }) {
  const [result, setResult] = useState<Queries | "error" | null>(null);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    fetch(`/api/page-queries?${new URLSearchParams({ path, days: String(days) })}`, {
      signal: controller.signal, cache: "no-store",
    }).then(async (response) => {
      if (!response.ok) throw new Error("Google indisponible");
      const data: Queries = await response.json();
      if (!controller.signal.aborted) setResult(data);
    }).catch(() => {
      if (!controller.signal.aborted) setResult("error");
    });
    return () => controller.abort();
  }, [path, days, attempt]);

  if (result === null) return <div className="rounded-lg border border-line bg-panel px-5 py-6" role="status">
    <p className="text-sm text-muted">Chargement des requêtes Google…</p>
    <div aria-hidden="true" className="mt-4 space-y-3">
      <div className="h-2 w-2/5 rounded bg-line" />
      <div className="h-2 w-3/5 rounded bg-paper" />
    </div>
  </div>;
  if (result === "error") return <div role="alert" className="rounded-lg border border-line bg-panel px-5 py-5 text-sm">
    <p>Les données Google sont indisponibles.</p>
    <button type="button" className="mt-3 min-h-9 rounded-md border border-line-strong px-3 font-medium transition-colors duration-150 hover:bg-paper focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink" onClick={() => { setResult(null); setAttempt(attempt + 1); }}>Réessayer</button>
  </div>;
  const complete = result.observed_days === days && result.previous.observed_days === days;
  const noWindow = result.period_start === null;
  return <section aria-label={`Requêtes Google de ${path}`} className="overflow-hidden rounded-lg border border-line bg-panel">
    <div className="flex flex-wrap items-start justify-between gap-3 px-5 py-4">
      <div>
        <h2 className="flex items-center gap-2 text-sm font-semibold">
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" className="size-4 text-muted"><circle cx="10.5" cy="10.5" r="6.5" /><path d="m16 16 4.5 4.5" /></svg>
          Requêtes Google
        </h2>
        {result.period_start && result.period_end && result.previous.period_start && result.previous.period_end && <p className="mt-2 text-xs leading-relaxed text-muted">
          <span className="font-medium text-ink">Du {date(result.period_start)} au {date(result.period_end)}</span>
          <span className="mt-0.5 block">Avant : du {date(result.previous.period_start)} au {date(result.previous.period_end)}</span>
        </p>}
      </div>
      <span className="rounded-md border border-line px-2 py-1 text-xs text-muted">Dates Google</span>
    </div>
    {!noWindow && !complete && <p role="status" className="mx-5 mb-4 rounded-md border border-accent/20 bg-accent-soft px-3 py-2 text-xs leading-relaxed text-ink">Couverture Google partielle : {result.observed_days}/{days} jours ; période précédente : {result.previous.observed_days}/{days}. Évolutions non calculées.</p>}
    {noWindow ? <p className="border-t border-line px-5 py-8 text-sm text-muted" role="status">Aucune période Google disponible.</p>
      : result.queries.length === 0 ? <p className="border-t border-line px-5 py-8 text-sm text-muted">Aucune requête rapportée pour cette page sur ces périodes.</p>
      : <table className="w-full text-sm">
        <caption className="sr-only">Clics et positions des requêtes rapportées par Google</caption>
        <thead className="border-y border-line bg-paper text-left text-xs text-muted"><tr>
          <th scope="col" className="px-5 py-2.5 font-medium">Requête</th>
          <th scope="col" className="w-44 px-5 py-2.5 text-right font-medium">Clics</th>
          <th scope="col" className="w-48 px-5 py-2.5 text-right font-medium">Position moyenne</th>
        </tr></thead>
        <tbody>{result.queries.map((query) => <tr key={query.query} className="border-b border-line last:border-0 hover:bg-paper/60">
          <td className="px-5 py-3 [overflow-wrap:anywhere]">{query.query}</td>
          <td className="px-5 py-3 text-right tabular-nums">
            <span className="font-medium">{numbers.format(query.clicks)}</span>
            <span className="mt-1 block whitespace-nowrap text-xs text-muted">Avant : {numbers.format(query.previous_clicks)}{complete && <>{" · "}<span className={changeColor(query.clicks - query.previous_clicks)}>{signed(query.clicks - query.previous_clicks)}</span></>}</span>
          </td>
          <td className="px-5 py-3 text-right tabular-nums">
            <span className="font-medium">{query.position_avg === null ? "—" : numbers.format(query.position_avg)}</span>
            <span className="mt-1 block whitespace-nowrap text-xs text-muted">Avant : {query.previous_position_avg === null ? "—" : numbers.format(query.previous_position_avg)}
              {complete && query.position_avg !== null && query.previous_position_avg !== null && <>{" · "}<span className={changeColor(query.position_avg - query.previous_position_avg, true)}>{signed(query.position_avg - query.previous_position_avg)}</span></>}
            </span>
          </td>
        </tr>)}</tbody>
      </table>}
    <p className="border-t border-line bg-paper/60 px-5 py-3 text-xs leading-relaxed text-muted">Une position plus basse est meilleure. Google masque certaines requêtes : 0 signifie aucun clic rapporté. Ces clics ne se relient pas individuellement aux contacts.</p>
  </section>;
}
