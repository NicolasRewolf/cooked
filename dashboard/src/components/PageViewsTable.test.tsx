// @vitest-environment jsdom
import { act, useSyncExternalStore, type MouseEvent, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PageViews } from "@/lib/page-views";

const navigation = vi.hoisted(() => ({ push: vi.fn() }));

// Next expose les changements History à useSearchParams sans requête RSC.
// Ici le DOM et ses clics sont réels ; seule cette intégration du routeur est simulée.
vi.mock("next/navigation", () => ({
  useSearchParams() {
    const query = useSyncExternalStore(
      (listener) => {
        window.addEventListener("popstate", listener);
        return () => window.removeEventListener("popstate", listener);
      },
      () => window.location.search,
      () => "",
    );
    return new URLSearchParams(query);
  },
}));
vi.mock("next/link", () => ({
  default: ({ href, prefetch, children, ...props }: {
    href: string; prefetch?: boolean; children: ReactNode;
  }) => <a {...props} href={href} data-prefetch={String(prefetch)} onClick={(event: MouseEvent) => {
    event.preventDefault();
    navigation.push(href);
  }}>{children}</a>,
}));

import { PageViewsTable } from "./PageViewsTable";

const data: PageViews & { inventoryStale: boolean } = {
  period_start: "2026-08-06", period_end: "2026-11-03", expected_days: 90, observed_days: 90,
  inventory_checked_at: "2026-11-04T09:50:00Z", inventoryStale: false,
  unattributed_phone_events: 2, unattributed_form_events: 1,
  previous: { period_start: "2026-05-08", period_end: "2026-08-05", observed_days: 90, unattributed_phone_events: 0, unattributed_form_events: 0 },
  pages: [
    { path: "/post/ressource", page_type: "post", category: "ressource", views: 7 },
    { path: "/post/proces", page_type: "post", category: "actualite", views: 10 },
    { path: "/expertises", page_type: "hub", category: null, views: 0 },
    { path: "/droit-penal", page_type: "expertise", category: null, views: 12 },
    { path: "/", page_type: "home", category: null, views: 20 },
  ].map((row) => ({ ...row, entries: row.views, phone_visits: 0, form_visits: 0, contact_visits: 0,
    contact_rate_pct: row.views > 0 ? 0 : null,
    previous: { views: 0, entries: 0, phone_visits: 0, form_visits: 0, contact_visits: 0, contact_rate_pct: null },
  })),
};
let container: HTMLDivElement;
let root: Root;
const fetchSpy = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
  fetchSpy.mockReset();
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("fetch", fetchSpy);
  window.history.replaceState(null, "", "/?days=90&type=all");
  const push = window.history.pushState.bind(window.history);
  vi.spyOn(window.history, "pushState").mockImplementation((state, unused, url) => {
    push(state, unused, url);
    window.dispatchEvent(new PopStateEvent("popstate", { state }));
  });
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function button(label: string): HTMLButtonElement {
  const found = [...container.querySelectorAll("button")].find((node) => node.textContent === label);
  if (!found) throw new Error(`Bouton absent : ${label}`);
  return found;
}
function displayedPaths() {
  return [...container.querySelectorAll<HTMLAnchorElement>("tbody a")].map((node) => new URL(node.href).pathname);
}
async function historyMove(direction: "back" | "forward") {
  await act(() => new Promise<void>((resolve) => {
    window.addEventListener("popstate", () => resolve(), { once: true });
    window.history[direction]();
  }));
}

describe("filtres locaux du tableau", () => {
  it("un clic filtre immédiatement les lignes et l’URL sans navigation serveur ni fetch", async () => {
    await act(() => root.render(<PageViewsTable data={data} />));
    expect(displayedPaths()).toHaveLength(5);

    await act(() => button("Ressources et notions juridiques").click());
    expect(displayedPaths()).toEqual(["/post/ressource"]);
    expect(window.location.search).toBe("?days=90&type=resources");
    expect(button("Ressources et notions juridiques").getAttribute("aria-pressed")).toBe("true");

    await act(() => button("Articles").click());
    expect(displayedPaths()).toEqual(["/post/proces"]);
    expect(window.location.search).toBe("?days=90&type=articles");

    await act(() => button("Expertises").click());
    expect(displayedPaths()).toEqual(["/droit-penal", "/expertises"]);
    expect(container.querySelector("tbody tr:last-child td:nth-child(2) > span")?.textContent).toBe("0");
    expect(navigation.push).not.toHaveBeenCalled();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("précédent/suivant rétablit le filtre sans requête serveur", async () => {
    await act(() => root.render(<PageViewsTable data={data} />));
    await act(() => button("Ressources et notions juridiques").click());
    await act(() => button("Articles").click());
    await historyMove("back");
    expect(displayedPaths()).toEqual(["/post/ressource"]);
    await historyMove("back");
    expect(displayedPaths()).toHaveLength(5);
    await historyMove("forward");
    expect(displayedPaths()).toEqual(["/post/ressource"]);
    expect(navigation.push).not.toHaveBeenCalled();
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("ouvre le filtre partagé et réserve la navigation aux changements de période", async () => {
    window.history.replaceState(null, "", "/?days=90&type=resources");
    await act(() => root.render(<PageViewsTable data={data} />));
    expect(displayedPaths()).toEqual(["/post/ressource"]);
    const historyLength = window.history.length;
    await act(() => button("Ressources et notions juridiques").click());
    expect(window.history.length).toBe(historyLength);
    const periods = [...container.querySelectorAll<HTMLAnchorElement>('nav[aria-label="Période"] a')];
    expect(periods).toHaveLength(2); // La période déjà chargée n’est pas un lien de rechargement.
    expect(periods.every((link) => link.dataset.prefetch === "false")).toBe(true);
    await act(() => periods.find((link) => link.textContent === "60 jours")!.click());
    expect(navigation.push).toHaveBeenCalledExactlyOnceWith("/?days=60&type=resources");
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});


describe("lecture des mesures éditoriales", () => {
  it("affiche les zéros, le taux inconnu, les comparaisons et le détail des contacts", async () => {
    await act(() => root.render(<PageViewsTable data={data} />));
    expect(container.textContent).toContain("Avant : du 08/05/2026 au 05/08/2026");
    const first = container.querySelector("tbody tr")!;
    expect(first.querySelector("td:nth-child(2)")?.textContent).toContain("20Avant : 0 · +20");
    expect(first.querySelector("td:last-child > span")?.textContent).toBe("0 %");
    expect(container.querySelector("tbody tr:last-child td:last-child > span")?.textContent).toBe("—");
    expect(first.querySelector("summary")?.textContent).toBe("Téléphone / formulaires");
    expect(first.querySelector("details")?.textContent).toContain("ne s’additionnent pas");
    expect(container.textContent).toContain("Ce sont des événements, pas des visites à ajouter au tableau");
    expect(container.textContent).not.toContain("Infinity");
  });
  it("utilise des points pour les taux et aucun delta quand la couverture est partielle", async () => {
    const value = { ...data, pages: [{ ...data.pages[0], contact_rate_pct: 25, previous: { ...data.pages[0].previous, contact_rate_pct: 10 } }] };
    await act(() => root.render(<PageViewsTable data={value} />));
    expect(container.querySelector("tbody td:last-child")?.textContent).toBe("25 %Avant : 10 % · +15 pt");
    await act(() => root.render(<PageViewsTable data={{ ...value, previous: { ...value.previous, observed_days: 60 } }} />));
    expect(container.textContent).toContain("évolutions ne sont pas calculées");
    expect(container.querySelector("tbody td:last-child")?.textContent).toBe("25 %Avant : 10 %");
    expect(container.querySelector("tbody td:nth-child(2)")?.textContent).not.toContain("·");
  });
});

function googleButton(path: string): HTMLButtonElement {
  return container.querySelector<HTMLButtonElement>(`button[aria-label="Requêtes Google : ${path}"]`)!;
}
const queryResult = (query: string) => ({
  path: "/post/ressource", expected_days: 90, observed_days: 90,
  period_start: "2026-08-04", period_end: "2026-11-01",
  previous: { period_start: "2026-05-06", period_end: "2026-08-03", observed_days: 90 },
  queries: [{ query, clicks: 0, previous_clicks: 4, position_avg: null, previous_position_avg: 5 }],
});
function deferredResponse() {
  let resolve!: (response: Response) => void;
  const promise = new Promise<Response>((done) => { resolve = done; });
  return { promise, resolve };
}

describe("détail Google à la demande", () => {
  it("distingue une fenêtre Google indisponible d’une page sans requête rapportée", async () => {
    fetchSpy.mockResolvedValue(Response.json({
      ...queryResult(""), period_start: null, period_end: null, observed_days: 0,
      previous: { period_start: null, period_end: null, observed_days: 0 }, queries: [],
    }));
    await act(() => root.render(<PageViewsTable data={data} />));
    await act(() => googleButton("/post/ressource").click());
    const detail = container.querySelector('section[aria-label="Requêtes Google de /post/ressource"]')!;
    expect(detail.textContent).toContain("Aucune période Google disponible");
    expect(detail.textContent).not.toContain("Aucune requête rapportée");
    expect(detail.textContent).not.toContain("Couverture Google partielle");
  });
  it("ne lit Google qu’à l’ouverture et affiche dates, pertes et positions inconnues", async () => {
    fetchSpy.mockResolvedValue(Response.json(queryResult("requête perdue")));
    await act(() => root.render(<PageViewsTable data={data} />));
    expect(fetchSpy).not.toHaveBeenCalled();
    await act(() => googleButton("/post/ressource").click());
    expect(fetchSpy).toHaveBeenCalledOnce();
    expect(fetchSpy.mock.calls[0][0]).toBe("/api/page-queries?path=%2Fpost%2Fressource&days=90");
    expect(container.textContent).toContain("requête perdue");
    expect(container.textContent).toContain("04/08/2026 au 01/11/2026");
    const detail = container.querySelector('section[aria-label="Requêtes Google de /post/ressource"]')!;
    expect(detail.textContent).toContain("Avant : 4 · -4");
    expect(detail.querySelector("tbody td:last-child")?.textContent).toContain("—");
    await act(() => googleButton("/post/ressource").click());
    expect(detail.isConnected).toBe(false);
    expect(fetchSpy.mock.calls[0][1].signal.aborted).toBe(true);
  });
  it("ignore une réponse tardive après ouverture d’une autre page", async () => {
    const first = deferredResponse();
    const second = deferredResponse();
    fetchSpy.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    await act(() => root.render(<PageViewsTable data={data} />));
    await act(() => googleButton("/post/ressource").click());
    await act(() => googleButton("/post/proces").click());
    expect(fetchSpy.mock.calls[0][1].signal.aborted).toBe(true);
    await act(async () => { second.resolve(Response.json(queryResult("deuxième page"))); });
    await act(async () => { first.resolve(Response.json(queryResult("ancienne page"))); });
    expect(container.textContent).toContain("deuxième page");
    expect(container.textContent).not.toContain("ancienne page");
    expect(container.querySelectorAll('section[aria-label^="Requêtes Google de"]')).toHaveLength(1);
  });
  it("ferme et annule le détail au changement de filtre ou de période", async () => {
    fetchSpy.mockImplementation(() => new Promise(() => {}));
    await act(() => root.render(<PageViewsTable data={data} />));
    await act(() => googleButton("/post/ressource").click());
    await act(() => button("Articles").click());
    expect(fetchSpy.mock.calls[0][1].signal.aborted).toBe(true);
    expect(container.textContent).not.toContain("Chargement des requêtes Google");
    await act(() => googleButton("/post/proces").click());
    await act(() => root.render(<PageViewsTable data={{ ...data, expected_days: 30 }} />));
    expect(fetchSpy.mock.calls[1][1].signal.aborted).toBe(true);
    expect(container.textContent).not.toContain("Chargement des requêtes Google");
    expect(fetchSpy).toHaveBeenCalledTimes(2);
  });
  it("distingue une erreur de l’absence de requêtes, puis permet de réessayer", async () => {
    fetchSpy.mockResolvedValueOnce(new Response("private-detail", { status: 503 }));
    await act(() => root.render(<PageViewsTable data={data} />));
    await act(() => googleButton("/post/ressource").click());
    expect(container.textContent).toContain("Les données Google sont indisponibles");
    expect(container.textContent).not.toContain("private-detail");
    fetchSpy.mockResolvedValueOnce(Response.json({ ...queryResult(""), observed_days: 60, queries: [] }));
    await act(() => button("Réessayer").click());
    expect(container.textContent).toContain("Aucune requête rapportée");
    expect(container.textContent).toContain("Évolutions non calculées");
    expect(fetchSpy).toHaveBeenCalledTimes(2);
  });
});
