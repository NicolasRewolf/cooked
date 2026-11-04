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
    <span className="text-base font-semibold tracking-tight text-ink">{format(value)}</span>
    <span className="mt-1.5 block whitespace-nowrap text-[11px] font-normal text-muted">Avant : {format(previous)}
      {compare && delta !== null && <>{" · "}<span className={delta > 0 ? "text-up" : delta < 0 ? "text-down" : "text-muted"}>{`${delta > 0 ? "+" : ""}${numberFormat.format(delta)}${rate ? " pt" : ""}`}</span></>}
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
  const choice = (selected: boolean) => `inline-flex min-h-10 items-center justify-center rounded-md px-3.5 py-2 text-sm font-medium transition-colors duration-150 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${selected
    ? "bg-panel text-ink shadow-sm ring-1 ring-line"
    : "text-muted hover:bg-panel/70 hover:text-ink"}`;

  return (
    <main className="mx-auto max-w-[1440px] px-4 py-8 sm:px-8 sm:py-10 lg:px-10">
      <div className="flex flex-wrap items-end justify-between gap-x-8 gap-y-5">
        <div>
          <p className="mb-2 text-xs font-medium text-muted">Performance éditoriale</p>
          <h1 className="text-3xl font-semibold tracking-tight">Pages du site</h1>
          <p className="mt-2 text-sm text-muted">Comprendre ce qui attire vos lecteurs et les amène à prendre contact.</p>
        </div>
        <div className="shrink-0 sm:text-right">
        <nav aria-label="Période" aria-busy={isPending}>
          <span className="sr-only">Période</span>
          <div className="inline-flex gap-1 rounded-lg bg-line/60 p-1">
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
        </div>
      </div>

      <div className="mb-6 mt-6 flex flex-wrap items-center justify-between gap-2 border-t border-line pt-4 text-xs text-muted">
        <p className="font-medium text-ink">Du {day(data.period_start)} au {day(data.period_end)} <span className="font-normal text-muted">· jours clos, Paris</span></p>
        <p>Avant : du {day(data.previous.period_start)} au {day(data.previous.period_end)}</p>
      </div>

      <div className="mb-5">
        <nav aria-label="Type de page">
          <div className="flex flex-wrap gap-1.5">
            {pageTypes.map((option) => (
              <button key={option.value} type="button" onClick={() => selectType(option.value)}
                aria-pressed={type === option.value}
                className={`inline-flex min-h-10 items-center rounded-lg border px-3.5 py-2 text-sm font-medium transition-colors duration-150 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink ${type === option.value ? "border-ink bg-ink text-white" : "border-line bg-panel text-muted hover:border-line-strong hover:text-ink"}`}>{option.label}</button>
            ))}
          </div>
        </nav>
      </div>

      {(partial || data.inventoryStale) && (
        <div className="mb-5 rounded-lg border border-accent/30 bg-accent/5 px-4 py-3 text-sm leading-relaxed" role="status">
          {partial && <p>Collecte partielle : {data.observed_days}/{data.expected_days} jours ; période précédente : {data.previous.observed_days}/{data.expected_days}. Les nombres couvrent les données reçues ; les évolutions ne sont pas calculées.</p>}
          {data.inventoryStale && <p>L’inventaire des pages n’a pas été confirmé récemment. Des publications récentes peuvent manquer.</p>}
        </div>
      )}

      <div className="overflow-hidden rounded-xl border border-line bg-panel shadow-[0_1px_2px_rgba(0,0,0,0.02)]">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-5 py-4 text-xs text-muted">
        <p className="flex items-center gap-2"><span className="font-medium text-ink">{numberFormat.format(pages.length)} {pages.length === 1 ? "page publiée" : "pages publiées"}</span><span className="text-line-strong" aria-hidden="true">/</span><span>y compris sans vue</span></p>
        <p>Triées par vues décroissantes</p>
      </div>
      <div className="max-h-[70vh] overflow-auto focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-ink" role="region" aria-label="Tableau des pages" tabIndex={0}>
      <table className="w-full min-w-[1080px] table-fixed border-collapse text-sm">
        <caption className="sr-only">URL publiées et mesures du {day(data.period_start)} au {day(data.period_end)}, comparées à la période précédente</caption>
        <thead className="sticky top-0 z-10 border-b border-line bg-paper text-left text-xs text-muted">
          <tr>
            <th scope="col" className="w-[36%] px-5 py-3.5 font-medium">Page</th>
            <th scope="col" className="w-[15%] px-4 py-3.5 text-right font-medium" aria-sort="descending">Vues <span aria-hidden="true">↓</span></th>
            <th scope="col" className="w-[15%] px-4 py-3.5 text-right font-medium">Entrées</th>
            <th scope="col" className="w-[18%] px-4 py-3.5 text-right font-medium">Visites avec contact</th>
            <th scope="col" className="w-[16%] px-5 py-3.5 text-right font-medium">Taux de contact</th>
          </tr>
        </thead>
        <tbody>
          {pages.map((page, index) => (
            <Fragment key={page.path}>
            <tr className={`group border-b border-line align-top transition-colors duration-150 last:border-0 ${openPath === page.path ? "bg-paper" : "hover:bg-paper/70"}`}>
              <td className="px-5 py-4">
                <a href={pageUrl(page.path)} target="_blank" rel="noopener noreferrer"
                  title={pageUrl(page.path)}
                  className="block font-medium leading-relaxed [overflow-wrap:anywhere] hover:text-accent-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent">
                  {page.path === "/" ? "Accueil · /" : page.path}
                </a>
                <button type="button" aria-expanded={openPath === page.path} aria-controls={openPath === page.path ? `queries-${index}` : undefined}
                  aria-label={`Requêtes Google : ${page.path}`}
                  className="mt-1.5 inline-flex min-h-7 items-center gap-1.5 rounded text-xs text-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
                  onClick={() => setQueryPage(openPath === page.path ? null : { path: page.path, days: data.expected_days, end: data.period_end })}>
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg>
                  {openPath === page.path ? "Fermer les requêtes Google" : "Requêtes Google"}
                  <span aria-hidden="true" className={`ml-0.5 transition-transform duration-150 ${openPath === page.path ? "rotate-180" : ""}`}>⌄</span>
                </button>
              </td>
              <td className="px-4 py-4 text-right tabular-nums"><Metric value={page.views} previous={page.previous.views} compare={!partial} /></td>
              <td className="px-4 py-4 text-right tabular-nums"><Metric value={page.entries} previous={page.previous.entries} compare={!partial} /></td>
              <td className="px-4 py-4 text-right tabular-nums">
                <Metric value={page.contact_visits} previous={page.previous.contact_visits} compare={!partial} />
                <details className="mt-1.5 text-xs">
                  <summary className="min-h-7 cursor-pointer rounded pt-1 text-[11px] text-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink">Téléphone / formulaires</summary>
                  <div className="mt-2 space-y-3 rounded-lg border border-line bg-panel p-3 text-left leading-relaxed">
                    <p>Clic téléphone : <Metric value={page.phone_visits} previous={page.previous.phone_visits} compare={!partial} /></p>
                    <p>Formulaire : <Metric value={page.form_visits} previous={page.previous.form_visits} compare={!partial} /></p>
                    <p className="font-sans text-muted">Une même visite peut faire les deux ; ces nombres ne s’additionnent pas.</p>
                  </div>
                </details>
              </td>
              <td className="px-4 py-4 text-right tabular-nums"><Metric value={page.contact_rate_pct} previous={page.previous.contact_rate_pct} compare={!partial} rate /></td>
            </tr>
            {openPath === page.path && <tr id={`queries-${index}`}><td colSpan={5} className="border-b border-line bg-paper p-5">
              <PageQueries key={`${page.path}:${data.expected_days}:${data.period_end}`} path={page.path} days={data.expected_days} />
            </td></tr>}
            </Fragment>
          ))}
          {pages.length === 0 && <tr><td colSpan={5} className="px-5 py-10 text-center text-muted">Aucune page publiée dans cette catégorie.</td></tr>}
        </tbody>
      </table>
      </div>
      </div>
      <p className="mt-5 text-xs leading-relaxed text-muted">Une vue est un affichage après filtrage des bots. Les entrées sont les visites commencées sur la page ; le taux rapporte celles ayant un contact observé à ces entrées. Un clic téléphone ne prouve pas un appel abouti. Sans entrée, le taux est inconnu (—).</p>
      {(data.unattributed_phone_events + data.unattributed_form_events + data.previous.unattributed_phone_events + data.previous.unattributed_form_events > 0) &&
        <p className="mt-3 text-xs leading-relaxed text-muted">Hors attribution aux pages, sur tout le site : {numberFormat.format(data.unattributed_phone_events)} clics téléphone et {numberFormat.format(data.unattributed_form_events)} formulaires (avant : {numberFormat.format(data.previous.unattributed_phone_events)} et {numberFormat.format(data.previous.unattributed_form_events)}). Ce sont des événements, pas des visites à ajouter au tableau.</p>}
    </main>
  );
}
