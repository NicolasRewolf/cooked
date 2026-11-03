"use client";

import { useState } from "react";
import { LabChart } from "@/components/LabChart";
import {
  summarizeLabSelection, type LabBandKey, type LabGscView, type LabMarker,
} from "@/data/lab-view-models";
import { dateFr } from "@/lib/dates";
import { num, pct } from "@/lib/format";

const names: Record<LabBandKey, string> = {
  ressource: "Ressources", classique: "Classiques", divers: "Cabinet & divers", expertise: "Expertises",
};
const eyebrow = "font-mono text-[11px] font-semibold tracking-[0.09em] text-muted uppercase";
const focus = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-alert";

function Swatch({ band }: { band: LabBandKey }) {
  return (
    <span aria-hidden="true" className="inline-block size-2.5 shrink-0"
      style={{ backgroundColor: `var(--color-lab-${band})` }} />
  );
}

function periodLabel(period: { start: string; end: string }) {
  return `${dateFr(period.start)} – ${dateFr(period.end)}`;
}

export function LabExplorer({ view }: { view: LabGscView }) {
  const [selected, setSelected] = useState<LabBandKey[]>(() => view.bands.map((band) => band.key));
  const [mode, setMode] = useState<"volume" | "share">("volume");
  const [weekIndex, setWeekIndex] = useState(view.weeks.length - 1);
  const visible = view.bands.filter((band) => selected.includes(band.key));
  const summary = summarizeLabSelection(view, selected);
  const weekTotal = summary.totals[weekIndex];
  const notesByWeek = new Map<number, LabMarker[]>();
  for (const note of view.markers) {
    const group = notesByWeek.get(note.index);
    if (group) group.push(note);
    else notesByWeek.set(note.index, [note]);
  }
  const weekNotes = notesByWeek.get(weekIndex) ?? [];

  function toggleBand(key: LabBandKey) {
    setSelected((current) => current.includes(key)
      ? current.filter((band) => band !== key)
      : [...current, key]);
  }

  return (
    <>
      <dl aria-label="Indicateurs des catégories visibles"
        className="mb-5 grid grid-cols-2 border-t-2 border-b border-t-ink border-b-line-strong sm:mb-7 sm:grid-cols-3">
        <div className="min-w-0 py-3 pr-3 sm:py-5">
          <dt className="text-sm font-semibold">Dernière semaine</dt>
          <dd className="mt-1 text-[clamp(28px,3vw,42px)] leading-tight font-semibold tracking-[-0.045em]">
            {num(summary.latest?.clicks)}
          </dd>
          <dd className="mt-1 text-xs text-muted">
            {summary.latest ? <>clics · {periodLabel(summary.latest)}</> : "Données indisponibles"}
          </dd>
        </div>
        <div className="min-w-0 border-l border-line-strong px-3 py-3 sm:px-5 sm:py-5">
          <dt className="text-sm font-semibold">Évolution sur 4 semaines</dt>
          <dd className="mt-1 whitespace-nowrap text-[clamp(28px,3vw,42px)] leading-tight font-semibold tracking-[-0.045em]">
            {summary.changePct !== null && summary.changePct > 0 ? "+" : ""}{pct(summary.changePct)}
          </dd>
          <dd className="mt-1 text-xs text-muted">
            {summary.current && summary.previous ? (
              <>{periodLabel(summary.current)}<br />comparé au {periodLabel(summary.previous)}
                {summary.previous.clicks === 0 && <><br />Aucun clic sur la période de référence.</>}
              </>
            ) : "Deux périodes complètes de 4 semaines sont nécessaires."}
          </dd>
        </div>
        <div className="col-span-2 flex flex-wrap items-baseline gap-x-2 border-t border-line-strong py-3 sm:col-span-1 sm:block sm:border-t-0 sm:border-l sm:py-5 sm:pl-5">
          <dt className="text-sm font-semibold">{summary.leaders.length > 1 ? "Catégories en tête" : "Première catégorie"}</dt>
          <dd className="text-lg leading-tight font-semibold tracking-[-0.04em] sm:mt-1 sm:text-[clamp(24px,3vw,40px)]">
            {summary.leaders.map((key) => names[key]).join(" · ") || "—"}
          </dd>
          <dd className="text-xs text-muted sm:mt-1">
            {summary.leaderSharePct !== null
              ? <>{pct(summary.leaderSharePct)} des clics {summary.leaders.length > 1 && "chacune "}· 4 dernières semaines</>
              : summary.current ? "Aucun clic sur la sélection." : "Quatre semaines complètes sont nécessaires."}
          </dd>
        </div>
      </dl>

      <section className="border border-line-strong bg-panel" aria-labelledby="lab-chart-heading">
        <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 px-4 pt-4 sm:px-6 sm:pt-5">
          <h2 id="lab-chart-heading" className="text-[22px] leading-tight font-semibold tracking-[-0.035em]">
            Évolution hebdomadaire
          </h2>
          <div className="inline-flex bg-field p-0.5" role="group" aria-label="Mode du graphique">
            {(["volume", "share"] as const).map((option) => (
              <button type="button" key={option} aria-pressed={mode === option} onClick={() => setMode(option)}
                className={`${focus} min-h-10 cursor-pointer px-3 text-sm font-semibold aria-pressed:bg-ink aria-pressed:text-panel`}>
                {option === "volume" ? "Volume" : "Répartition"}
              </button>
            ))}
          </div>
        </div>
        <div className="flex flex-wrap gap-2 px-4 pt-3 pb-4 sm:px-6" role="group" aria-label="Catégories visibles">
          {view.bands.map((band) => {
            const active = selected.includes(band.key);
            return (
              <button key={band.key} type="button" aria-pressed={active} disabled={active && selected.length === 1}
                onClick={() => toggleBand(band.key)}
                className={`${focus} inline-flex min-h-9 cursor-pointer items-center gap-2 border border-line-strong bg-field px-2.5 text-[13px] font-medium text-muted line-through hover:border-muted disabled:cursor-default aria-pressed:bg-panel aria-pressed:text-ink aria-pressed:no-underline`}>
                <Swatch band={band.key} />{names[band.key]}
              </button>
            );
          })}
        </div>

        <div className="grid border-y border-line-strong md:grid-cols-[minmax(0,1fr)_clamp(205px,20%,250px)]">
          <LabChart weeks={view.weeks} bands={visible} markers={view.markers} mode={mode}
            weekIndex={weekIndex} onWeekChange={setWeekIndex} />
          <aside aria-live="polite" aria-atomic="true"
            className="border-t border-line-strong bg-inset p-4 md:border-t-0 md:border-l md:p-5">
            <h3 className={eyebrow}>Semaine lue</h3>
            <p className="mt-1 inline-block pr-2 text-[22px] leading-tight font-semibold tracking-[-0.035em] md:block">
              Du {dateFr(view.weeks[weekIndex])}
            </p>
            <p className="inline-block text-[13px] text-muted md:mt-1">{num(weekTotal)} clics sur la sélection</p>
            <dl className="mt-3 grid gap-x-5 gap-y-1.5 min-[450px]:grid-cols-2 md:grid-cols-1">
              {visible.map((band) => (
                <div key={band.key} className="flex items-baseline justify-between gap-2 text-[13px]">
                  <dt className="flex items-center gap-2"><Swatch band={band.key} />{names[band.key]}</dt>
                  <dd className="font-mono text-xs font-semibold whitespace-nowrap">{mode === "volume"
                    ? num(band.clicks[weekIndex]) : pct(weekTotal > 0 ? 100 * band.clicks[weekIndex] / weekTotal : null)}</dd>
                </div>
              ))}
            </dl>
          </aside>
        </div>

        <section aria-labelledby="lab-journal" className="grid gap-3 p-4 sm:px-6 lg:grid-cols-[1fr_1.2fr]">
          <div>
            <h3 id="lab-journal" className={eyebrow}>Journal · {num(view.markers.length)} {view.markers.length === 1 ? "repère" : "repères"}</h3>
            {view.markers.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1.5" role="group" aria-label="Semaines annotées">
                {Array.from(notesByWeek, ([index, notes]) => (
                  <button type="button" key={index} aria-pressed={index === weekIndex} onClick={() => setWeekIndex(index)}
                    aria-label={`Lire ${notes.length} ${notes.length === 1 ? "repère" : "repères"} de la semaine du ${dateFr(view.weeks[index])}`}
                    className={`${focus} min-h-9 cursor-pointer border border-line-strong px-2 text-xs hover:border-muted aria-pressed:border-alert aria-pressed:bg-accent-tint`}>
                    {dateFr(view.weeks[index])}{notes.length > 1 && <span className="ml-1 text-muted">({notes.length})</span>}
                  </button>
                ))}
              </div>
            )}
          </div>
          <div className="self-start border-l-2 border-accent pl-3 text-[13px]" aria-live="polite">
            {weekNotes.length > 0 ? (
              <ul className="space-y-2">
                {weekNotes.map((marker, i) => (
                  <li key={i}><strong>{dateFr(marker.day)}</strong><p className="break-words">{marker.label}</p></li>
                ))}
              </ul>
            ) : (
              <p className="text-muted">{view.markers.length
                ? "Aucun repère cette semaine. Choisissez une date du journal pour lire les événements associés."
                : "Aucun événement consigné pour cette période."}</p>
            )}
          </div>
        </section>
      </section>

      <details className="mt-4 border-t border-line-strong py-3 text-sm">
        <summary className={`${focus} w-fit cursor-pointer font-semibold`}>Méthode et limites de lecture</summary>
        <div className="mt-3 max-w-[85ch] space-y-2 leading-relaxed text-muted">
          <p>Ces clics proviennent de Google Search Console, requêtes de marque incluses. Les semaines vont du lundi au dimanche. Les données Google sont disponibles jusqu’au {dateFr(view.gscEnd)}. Les articles dont la catégorie est inconnue sont comptés dans « Cabinet &amp; divers ».</p>
          <p>Les indicateurs du haut suivent les catégories visibles. L’évolution compare les quatre dernières semaines closes aux quatre précédentes. La première catégorie est celle qui a reçu le plus de clics sur les quatre dernières semaines.</p>
          <p>En vue Répartition, la part de chaque catégorie est calculée sur les clics des catégories visibles. Une semaine sans clic n’a pas de répartition.</p>
          <p>Les dates du journal situent les événements dans le temps. Une variation après un événement ne suffit pas à lui attribuer un effet. Un clic Google et une visite dans Cooked mesurent deux étapes distinctes.</p>
        </div>
      </details>
      <details className="border-t border-line-strong py-3 text-sm">
        <summary className={`${focus} w-fit cursor-pointer font-semibold`}>Taux de clics et pics par catégorie</summary>
        <p className="mt-2 text-xs text-muted">Le taux de clics (CTR) rapporte les clics aux impressions sur les quatre dernières semaines. Le pic est calculé sur toute la période affichée.</p>
        <table className="mt-3 w-full max-w-[720px] text-left text-xs sm:text-sm">
          <thead className="text-muted"><tr><th scope="col" className="py-2">Catégorie</th><th scope="col">CTR</th><th scope="col">Pic hebdomadaire</th></tr></thead>
          <tbody>{visible.map((band) => (
            <tr key={band.key} className="border-t border-line">
              <th scope="row" className="py-2 pr-2 font-medium">{names[band.key]}</th>
              <td className="pr-3 whitespace-nowrap">{pct(band.ctrLast4Pct, 2)}</td>
              <td>{num(band.peak)} clics {band.peak > 0 && <>· {dateFr(band.peakWeek)}</>}</td>
            </tr>
          ))}</tbody>
        </table>
      </details>
    </>
  );
}
