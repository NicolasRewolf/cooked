import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ requireUser: vi.fn(), createClient: vi.fn(), rpc: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("@/lib/auth", () => ({ requireUser: mocks.requireUser }));
vi.mock("@supabase/supabase-js", () => ({ createClient: mocks.createClient }));

import { filterPages, getPageViews, pageUrl, pageViewsSchema, parseFilters, type PageViews } from "./page-views";

const rows: PageViews["pages"] = [
  { path: "/post/ressource", page_type: "post", category: "ressource", views: 7 },
  { path: "/expertises", page_type: "hub", category: null, views: 0 },
  { path: "/post/proces", page_type: "post", category: "actualite", views: 7 },
  { path: "/post/sans-categorie", page_type: "post", category: null, views: 3 },
  { path: "/droit-penal", page_type: "expertise", category: null, views: 12 },
  { path: "/", page_type: "home", category: null, views: 20 },
  { path: "/blog/categories/ressources", page_type: "category", category: "ressource", views: 1 },
];
const valid: PageViews = {
  period_start: "2026-10-05", period_end: "2026-11-03", expected_days: 30, observed_days: 30,
  inventory_checked_at: "2026-11-04T09:50:08.864047+00:00", pages: rows,
};

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
  vi.stubEnv("SUPABASE_SECRET_KEY", "synthetic-server-key");
  mocks.requireUser.mockResolvedValue({ email: "allowed@example.test" });
  mocks.createClient.mockReturnValue({ rpc: mocks.rpc });
  mocks.rpc.mockResolvedValue({ data: valid, error: null });
});
afterEach(() => vi.unstubAllEnvs());

describe("filtres du tableau", () => {
  it("ouvre toutes les pages sur 90 jours par défaut", () => {
    expect(parseFilters({})).toEqual({ days: 90, type: "all" });
  });

  it.each([30, 60, 90])("accepte la période %i", (days) => {
    expect(parseFilters({ days: String(days), type: "resources" })).toEqual({ days, type: "resources" });
  });

  it.each(["0", "365", "30junk", ["30", "60"]])("ignore une période invalide ou répétée (%j)", (days) => {
    expect(parseFilters({ days, type: "unknown" })).toEqual({ days: 90, type: "all" });
  });

  it("n’accepte pas une catégorie répétée", () => {
    expect(parseFilters({ type: ["articles", "resources"] }).type).toBe("all");
  });

  it("conserve les zéros et trie par vues puis chemin sans modifier les données", () => {
    const original = rows.map((row) => row.path);
    expect(filterPages(rows, "all").map((row) => row.path)).toEqual([
      "/", "/droit-penal", "/post/proces", "/post/ressource", "/post/sans-categorie",
      "/blog/categories/ressources", "/expertises",
    ]);
    expect(rows.map((row) => row.path)).toEqual(original);
  });

  it("regroupe les hubs et pages d’expertise", () => {
    expect(filterPages(rows, "expertises").map((row) => row.path)).toEqual(["/droit-penal", "/expertises"]);
  });

  it("sépare les articles des ressources, sans inclure la page de catégorie", () => {
    const articles = filterPages(rows, "articles");
    const resources = filterPages(rows, "resources");
    expect(articles.map((row) => row.path)).toEqual(["/post/proces", "/post/sans-categorie"]);
    expect(resources.map((row) => row.path)).toEqual(["/post/ressource"]);
    expect(articles.some((row) => resources.includes(row))).toBe(false);
  });

  it("construit un lien sur le site fixe, y compris pour les chemins spéciaux", () => {
    expect(pageUrl("/post/droit-pénal")).toBe("https://www.jplouton-avocat.fr/post/droit-p%C3%A9nal");
    expect(new URL(pageUrl("//outside.example/a")).hostname).toBe("www.jplouton-avocat.fr");
    expect(pageUrl("/post/a?b#c")).toContain("/post/a%3Fb%23c");
  });
});

describe("lecture serveur des vues", () => {
  it("vérifie l’accès avant la RPC, avec uniquement la période demandée", async () => {
    expect(await getPageViews(30)).toEqual({ ...valid, inventoryStale: false });
    expect(mocks.rpc).toHaveBeenCalledWith("page_view_counts", { p_days: 30 });
    expect(mocks.requireUser.mock.invocationCallOrder[0]).toBeLessThan(mocks.createClient.mock.invocationCallOrder[0]);
    expect(mocks.createClient).toHaveBeenCalledWith("https://example.supabase.co", "synthetic-server-key", {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  });

  it("ne construit aucun client métier si l’accès est refusé", async () => {
    mocks.requireUser.mockRejectedValue(new Error("redirect-login"));
    await expect(getPageViews(30)).rejects.toThrow("redirect-login");
    expect(mocks.createClient).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it("exige la clé serveur seulement au moment de la lecture", async () => {
    vi.stubEnv("SUPABASE_SECRET_KEY", undefined);
    await expect(getPageViews(30)).rejects.toThrow("non configurée");
    expect(mocks.requireUser).toHaveBeenCalledOnce();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it("une erreur DB ne devient pas une liste vide et ne révèle pas son message", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: "private-database-detail" } });
    await expect(getPageViews(30)).rejects.toThrow(/^Lecture des vues indisponible$/);
  });

  it("un rejet réseau reste une erreur de lecture", async () => {
    mocks.rpc.mockRejectedValue(new Error("private-network-detail"));
    await expect(getPageViews(30)).rejects.toThrow(/^Lecture des vues indisponible$/);
  });

  it("refuse une réponse d’une autre période", async () => {
    await expect(getPageViews(60)).rejects.toThrow("Réponse des vues invalide");
  });

  it.each([
    { ...valid, pages: [{ ...rows[0], views: "7" }] },
    { ...valid, pages: [{ ...rows[0], views: -1 }] },
    { ...valid, pages: [{ ...rows[0], category: undefined }] },
    { ...valid, period_start: "2026-02-30" },
    { ...valid, observed_days: 31 },
    { ...valid, period_end: "2026-11-04" },
    null,
  ])("refuse un contrat invalide (%j)", async (data) => {
    mocks.rpc.mockResolvedValue({ data, error: null });
    await expect(getPageViews(30)).rejects.toThrow("Réponse des vues invalide");
  });

  it.each([
    [null, true],
    ["2026-11-01T22:59:59Z", true],
    ["2026-11-01T23:00:00Z", false],
    ["2026-11-02T12:00:00+01:00", false],
  ])("signale l’inventaire au-delà de deux jours Paris (%j)", async (inventory_checked_at, stale) => {
    mocks.rpc.mockResolvedValue({ data: { ...valid, inventory_checked_at }, error: null });
    expect((await getPageViews(30)).inventoryStale).toBe(stale);
  });

  it("utilise les jours Paris même pendant le changement d’heure d’été", async () => {
    mocks.rpc.mockResolvedValue({ data: {
      ...valid, period_start: "2026-03-02", period_end: "2026-03-31",
      inventory_checked_at: "2026-03-29T22:00:00Z",
    }, error: null });
    expect((await getPageViews(30)).inventoryStale).toBe(false);
  });

  it("accepte une couverture partielle et un inventaire non confirmé sans les masquer", () => {
    expect(pageViewsSchema.parse({ ...valid, observed_days: 0, inventory_checked_at: null }))
      .toMatchObject({ observed_days: 0, inventory_checked_at: null });
  });
});
