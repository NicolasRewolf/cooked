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

  if (result === null) return <p className="text-sm text-muted" role="status">Chargement des requêtes Google…</p>;
  if (result === "error") return <div role="alert" className="text-sm">
    <p>Les données Google sont indisponibles.</p>
    <button type="button" className="mt-2 underline underline-offset-4" onClick={() => { setResult(null); setAttempt(attempt + 1); }}>Réessayer</button>
  </div>;
  const complete = result.observed_days === days && result.previous.observed_days === days;
  const noWindow = result.period_start === null;
  return <section aria-label={`Requêtes Google de ${path}`}>
    <h2 className="font-medium">Requêtes Google</h2>
    {result.period_start && result.period_end && result.previous.period_start && result.previous.period_end && <p className="mt-1 text-xs text-muted">
      Du {date(result.period_start)} au {date(result.period_end)} · avant : du {date(result.previous.period_start)} au {date(result.previous.period_end)} · dates Google
    </p>}
    {!noWindow && !complete && <p role="status" className="mt-2 text-xs text-muted">Couverture Google partielle : {result.observed_days}/{days} jours ; période précédente : {result.previous.observed_days}/{days}. Évolutions non calculées.</p>}
    {noWindow ? <p className="mt-3 text-sm text-muted" role="status">Aucune période Google disponible.</p>
      : result.queries.length === 0 ? <p className="mt-3 text-sm text-muted">Aucune requête rapportée pour cette page sur ces périodes.</p>
      : <table className="mt-4 w-full text-sm">
        <caption className="sr-only">Clics et positions des requêtes rapportées par Google</caption>
        <thead className="border-b border-line-strong text-left text-xs text-muted"><tr>
          <th scope="col" className="pb-2 font-medium">Requête</th>
          <th scope="col" className="pb-2 pl-4 text-right font-medium">Clics</th>
          <th scope="col" className="pb-2 pl-4 text-right font-medium">Position moyenne</th>
        </tr></thead>
        <tbody>{result.queries.map((query) => <tr key={query.query} className="border-b border-line">
          <td className="py-3 pr-4 [overflow-wrap:anywhere]">{query.query}</td>
          <td className="py-3 pl-4 text-right font-mono tabular-nums">
            {numbers.format(query.clicks)}
            <span className="mt-1 block text-xs text-muted">Avant : {numbers.format(query.previous_clicks)}{complete && ` · ${signed(query.clicks - query.previous_clicks)}`}</span>
          </td>
          <td className="py-3 pl-4 text-right font-mono tabular-nums">
            {query.position_avg === null ? "—" : numbers.format(query.position_avg)}
            <span className="mt-1 block text-xs text-muted">Avant : {query.previous_position_avg === null ? "—" : numbers.format(query.previous_position_avg)}
              {complete && query.position_avg !== null && query.previous_position_avg !== null && ` · ${signed(query.position_avg - query.previous_position_avg)}`}
            </span>
          </td>
        </tr>)}</tbody>
      </table>}
    <p className="mt-3 text-xs leading-relaxed text-muted">Une position plus basse est meilleure. Google masque certaines requêtes : 0 signifie aucun clic rapporté. Ces clics ne se relient pas individuellement aux contacts.</p>
  </section>;
}
