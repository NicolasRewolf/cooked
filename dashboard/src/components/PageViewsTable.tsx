"use client";

import Link from "next/link";
import { Fragment, useEffect, useRef, useState, useTransition } from "react";
import { PageQueries } from "./PageQueries";
import { useRouter, useSearchParams } from "next/navigation";
import { filterPages, pageTypes, pageUrl, parseFilters, periods, type PageTypeFilter } from "@/lib/page-view-filters";
import type { PageViews } from "@/lib/page-views";

const dateFormat = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris" });
const numberFormat = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 });

function Metric({ value, previous, compare, rate = false }: { value: number | null; previous: number | null; compare: boolean; rate?: boolean }) {
  const format = (number: number | null) => number === null ? "—" : `${numberFormat.format(number)}${rate ? " %" : ""}`;
  const delta = value === null || previous === null ? null : value - previous;
  return <>
    <span>{format(value)}</span>
    <span className="mt-1 block text-xs text-muted">Avant : {format(previous)}
      {compare && delta !== null && ` · ${delta > 0 ? "+" : ""}${numberFormat.format(delta)}${rate ? " pt" : ""}`}
    </span>
  </>;
}

export function PageViewsTable({ data }: { data: PageViews & { inventoryStale: boolean } }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const navigating = useRef(false);
  const [requestedDays, setRequestedDays] = useState(data.expected_days);
  useEffect(() => { if (!isPending) navigating.current = false; }, [isPending]);
  const searchParams = useSearchParams();
  const requestedTypes = searchParams.getAll("type");
  const type = parseFilters({ type: requestedTypes.length === 1 ? requestedTypes[0] : undefined }).type;
  const pages = filterPages(data.pages, type);
  const [queryPage, setQueryPage] = useState<{ path: string; days: number; end: string } | null>(null);
  const openPath = queryPage?.days === data.expected_days && queryPage.end === data.period_end ? queryPage.path : null;

  function selectType(nextType: PageTypeFilter) {
    if (nextType === type) return;
    setQueryPage(null);
    const params = new URLSearchParams(searchParams.toString());
    params.set("type", nextType);
    // Next synchronise useSearchParams avec History ; aucune navigation serveur.
    window.history.pushState(null, "", `?${params.toString()}`);
  }
  const partial = data.observed_days < data.expected_days || data.previous.observed_days < data.expected_days;
  const day = (value: string) => dateFormat.format(new Date(`${value}T12:00:00Z`));
  const choice = (selected: boolean) => `inline-flex min-h-11 items-center border px-3 py-2 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${selected
    ? "border-accent bg-accent text-ink"
    : "border-line-strong bg-panel text-muted hover:border-ink hover:text-ink"}`;

  return (
    <main className="mx-auto max-w-6xl px-5 py-8 sm:px-8 sm:py-10">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="font-mono text-xs text-muted">jplouton-avocat.fr</p>
          <h1 className="mt-2 text-2xl font-semibold tracking-tight sm:text-3xl">Pages du site</h1>
        </div>
        <div className="text-sm text-muted">
          <p>Du {day(data.period_start)} au {day(data.period_end)} · jours clos, Paris</p>
          <p className="mt-1 text-xs">Avant : du {day(data.previous.period_start)} au {day(data.previous.period_end)}</p>
        </div>
      </div>

      <div className="my-7 flex flex-wrap gap-x-8 gap-y-4">
        <nav aria-label="Période" aria-busy={isPending}>
          <p className="mb-2 text-xs font-medium text-muted">Période</p>
          <div className="flex gap-1">
            {periods.map((days) => (
              days === data.expected_days
                ? <span key={days} aria-current="true" className={choice(true)}>{days} jours</span>
                : <Link key={days} href={`/?days=${days}&type=${type}`} prefetch={false}
                    aria-disabled={isPending} tabIndex={isPending ? -1 : undefined}
                    onClick={(event) => { if (isPending || navigating.current) event.preventDefault(); }}
                    onNavigate={(event) => {
                      event.preventDefault();
                      if (isPending || navigating.current) return;
                      navigating.current = true;
                      setRequestedDays(days);
                      setQueryPage(null);
                      startTransition(() => router.push(`/?days=${days}&type=${type}`));
                    }}
                    className={`${choice(false)} ${isPending ? "cursor-wait opacity-60" : ""}`}>{days} jours</Link>
            ))}
          </div>
          {isPending && <p role="status" className="mt-2 text-xs text-muted">Chargement des {requestedDays} jours…</p>}
        </nav>
        <nav aria-label="Type de page">
          <p className="mb-2 text-xs font-medium text-muted">Type de page</p>
          <div className="flex flex-wrap gap-1">
            {pageTypes.map((option) => (
              <button key={option.value} type="button" onClick={() => selectType(option.value)}
                aria-pressed={type === option.value}
                className={choice(type === option.value)}>{option.label}</button>
            ))}
          </div>
        </nav>
      </div>

      {(partial || data.inventoryStale) && (
        <div className="mb-5 border-l-2 border-accent bg-panel px-4 py-3 text-sm" role="status">
          {partial && <p>Collecte partielle : {data.observed_days}/{data.expected_days} jours ; période précédente : {data.previous.observed_days}/{data.expected_days}. Les nombres couvrent les données reçues ; les évolutions ne sont pas calculées.</p>}
          {data.inventoryStale && <p>L’inventaire des pages n’a pas été confirmé récemment. Des publications récentes peuvent manquer.</p>}
        </div>
      )}

      <div className="mb-2 flex items-center justify-between gap-4 text-xs text-muted">
        <p>{numberFormat.format(pages.length)} {pages.length === 1 ? "page publiée" : "pages publiées"}</p>
        <p>Vues décroissantes</p>
      </div>
      <div className="overflow-x-auto">
      <table className="w-full min-w-[760px] table-fixed border-collapse bg-panel text-sm">
        <caption className="sr-only">URL publiées et mesures du {day(data.period_start)} au {day(data.period_end)}, comparées à la période précédente</caption>
        <thead className="border-y border-line-strong text-left">
          <tr>
            <th scope="col" className="w-[38%] px-4 py-3 font-medium">URL</th>
            <th scope="col" className="px-3 py-3 text-right font-medium" aria-sort="descending">Vues</th>
            <th scope="col" className="px-3 py-3 text-right font-medium">Entrées</th>
            <th scope="col" className="px-3 py-3 text-right font-medium">Visites avec contact</th>
            <th scope="col" className="px-3 py-3 text-right font-medium">Taux</th>
          </tr>
        </thead>
        <tbody>
          {pages.map((page, index) => (
            <Fragment key={page.path}>
            <tr className="border-b border-line align-top hover:bg-paper">
              <td className="px-4 py-3">
                <a href={pageUrl(page.path)} target="_blank" rel="noopener noreferrer"
                  className="break-words [overflow-wrap:anywhere] hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent">
                  <span className="text-muted">www.jplouton-avocat.fr</span>{page.path}
                </a>
                <button type="button" aria-expanded={openPath === page.path} aria-controls={openPath === page.path ? `queries-${index}` : undefined}
                  aria-label={`Requêtes Google : ${page.path}`}
                  className="mt-2 block min-h-7 text-xs text-muted underline underline-offset-4 hover:text-ink"
                  onClick={() => setQueryPage(openPath === page.path ? null : { path: page.path, days: data.expected_days, end: data.period_end })}>
                  {openPath === page.path ? "Fermer les requêtes Google" : "Requêtes Google"}
                </button>
              </td>
              <td className="px-3 py-3 text-right font-mono tabular-nums"><Metric value={page.views} previous={page.previous.views} compare={!partial} /></td>
              <td className="px-3 py-3 text-right font-mono tabular-nums"><Metric value={page.entries} previous={page.previous.entries} compare={!partial} /></td>
              <td className="px-3 py-3 text-right font-mono tabular-nums">
                <Metric value={page.contact_visits} previous={page.previous.contact_visits} compare={!partial} />
                <details className="mt-2 text-xs">
                  <summary className="cursor-pointer text-muted underline underline-offset-4">Téléphone / formulaires</summary>
                  <div className="mt-2 space-y-2 text-left leading-relaxed">
                    <p>Clic téléphone : <Metric value={page.phone_visits} previous={page.previous.phone_visits} compare={!partial} /></p>
                    <p>Formulaire : <Metric value={page.form_visits} previous={page.previous.form_visits} compare={!partial} /></p>
                    <p className="font-sans text-muted">Une même visite peut faire les deux ; ces nombres ne s’additionnent pas.</p>
                  </div>
                </details>
              </td>
              <td className="px-3 py-3 text-right font-mono tabular-nums"><Metric value={page.contact_rate_pct} previous={page.previous.contact_rate_pct} compare={!partial} rate /></td>
            </tr>
            {openPath === page.path && <tr id={`queries-${index}`}><td colSpan={5} className="border-b border-line-strong bg-paper px-5 py-5">
              <PageQueries key={`${page.path}:${data.expected_days}:${data.period_end}`} path={page.path} days={data.expected_days} />
            </td></tr>}
            </Fragment>
          ))}
          {pages.length === 0 && <tr><td colSpan={5} className="px-5 py-10 text-center text-muted">Aucune page publiée dans cette catégorie.</td></tr>}
        </tbody>
      </table>
      </div>
      <p className="mt-4 text-xs leading-relaxed text-muted">Une vue est un affichage après filtrage des bots. Les entrées sont les visites commencées sur la page ; le taux rapporte celles ayant un contact observé à ces entrées. Un clic téléphone ne prouve pas un appel abouti. Sans entrée, le taux est inconnu (—).</p>
      {(data.unattributed_phone_events + data.unattributed_form_events + data.previous.unattributed_phone_events + data.previous.unattributed_form_events > 0) &&
        <p className="mt-3 text-xs leading-relaxed text-muted">Hors attribution aux pages, sur tout le site : {numberFormat.format(data.unattributed_phone_events)} clics téléphone et {numberFormat.format(data.unattributed_form_events)} formulaires (avant : {numberFormat.format(data.previous.unattributed_phone_events)} et {numberFormat.format(data.previous.unattributed_form_events)}). Ce sont des événements, pas des visites à ajouter au tableau.</p>}
    </main>
  );
}
