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
  pages: [
    { path: "/post/ressource", page_type: "post", category: "ressource", views: 7 },
    { path: "/post/proces", page_type: "post", category: "actualite", views: 10 },
    { path: "/expertises", page_type: "hub", category: null, views: 0 },
    { path: "/droit-penal", page_type: "expertise", category: null, views: 12 },
    { path: "/", page_type: "home", category: null, views: 20 },
  ],
};
let container: HTMLDivElement;
let root: Root;
const fetchSpy = vi.fn();

beforeEach(() => {
  vi.clearAllMocks();
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
    expect(container.querySelector("tbody tr:last-child td:last-child")?.textContent).toBe("0");
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
