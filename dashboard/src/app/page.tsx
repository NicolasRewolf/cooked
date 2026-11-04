import Link from "next/link";
import { filterPages, getPageViews, pageTypes, pageUrl, parseFilters, periods } from "@/lib/page-views";

export const dynamic = "force-dynamic";

const dateFormat = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris" });
const numberFormat = new Intl.NumberFormat("fr-FR");

export default async function Page({ searchParams }: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const filters = parseFilters(await searchParams);
  const data = await getPageViews(filters.days);
  const pages = filterPages(data.pages, filters.type);
  const partial = data.observed_days < data.expected_days;
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
        <p className="text-sm text-muted">
          Du {day(data.period_start)} au {day(data.period_end)} · jours clos, Paris
        </p>
      </div>

      <div className="my-7 flex flex-wrap gap-x-8 gap-y-4">
        <nav aria-label="Période">
          <p className="mb-2 text-xs font-medium text-muted">Période</p>
          <div className="flex gap-1">
            {periods.map((days) => (
              <Link key={days} href={`/?days=${days}&type=${filters.type}`} prefetch={false}
                aria-current={filters.days === days ? "true" : undefined}
                className={choice(filters.days === days)}>{days} jours</Link>
            ))}
          </div>
        </nav>
        <nav aria-label="Type de page">
          <p className="mb-2 text-xs font-medium text-muted">Type de page</p>
          <div className="flex flex-wrap gap-1">
            {pageTypes.map((type) => (
              <Link key={type.value} href={`/?days=${filters.days}&type=${type.value}`} prefetch={false}
                aria-current={filters.type === type.value ? "true" : undefined}
                className={choice(filters.type === type.value)}>{type.label}</Link>
            ))}
          </div>
        </nav>
      </div>

      {(partial || data.inventoryStale) && (
        <div className="mb-5 border-l-2 border-accent bg-panel px-4 py-3 text-sm" role="status">
          {partial && <p>Collecte partielle : {data.observed_days} jours avec données sur {data.expected_days}. Les vues affichées couvrent uniquement les données reçues.</p>}
          {data.inventoryStale && <p>L’inventaire des pages n’a pas été confirmé récemment. Des publications récentes peuvent manquer.</p>}
        </div>
      )}

      <div className="mb-2 flex items-center justify-between gap-4 text-xs text-muted">
        <p>{numberFormat.format(pages.length)} {pages.length === 1 ? "page publiée" : "pages publiées"}</p>
        <p>Vues décroissantes</p>
      </div>
      <table className="w-full table-fixed border-collapse bg-panel text-sm">
        <caption className="sr-only">URL publiées et vues du {day(data.period_start)} au {day(data.period_end)}</caption>
        <thead className="border-y border-line-strong text-left">
          <tr>
            <th scope="col" className="px-4 py-3 font-medium sm:px-5">URL</th>
            <th scope="col" className="w-24 px-4 py-3 text-right font-medium sm:w-32 sm:px-5" aria-sort="descending">Vues</th>
          </tr>
        </thead>
        <tbody>
          {pages.map((page) => (
            <tr key={page.path} className="border-b border-line hover:bg-paper">
              <td className="px-4 py-3 sm:px-5">
                <a href={pageUrl(page.path)} target="_blank" rel="noopener noreferrer"
                  className="break-words [overflow-wrap:anywhere] hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent">
                  <span className="text-muted">www.jplouton-avocat.fr</span>{page.path}
                </a>
              </td>
              <td className="px-4 py-3 text-right font-mono tabular-nums sm:px-5">{numberFormat.format(page.views)}</td>
            </tr>
          ))}
          {pages.length === 0 && (
            <tr><td colSpan={2} className="px-5 py-10 text-center text-muted">Aucune page publiée dans cette catégorie.</td></tr>
          )}
        </tbody>
      </table>
      <p className="mt-4 text-xs leading-relaxed text-muted">Une vue correspond à un affichage de page enregistré après filtrage des bots. Les consultations répétées comptent.</p>
    </main>
  );
}
