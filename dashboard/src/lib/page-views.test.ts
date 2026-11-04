import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({ requireUser: vi.fn(), createClient: vi.fn(), rpc: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("@/lib/auth", () => ({ requireUser: mocks.requireUser }));
vi.mock("@supabase/supabase-js", () => ({ createClient: mocks.createClient }));

import { getPageViews, getPageQueries, pageViewsSchema, pageQueriesSchema, type PageViews, type PageQueries } from "./page-views";
import { filterPages, pageUrl, parseFilters } from "./page-view-filters";

const emptyMetrics = { views: 0, entries: 0, phone_visits: 0, form_visits: 0, contact_visits: 0, contact_rate_pct: null };
const rows: PageViews["pages"] = [
  { path: "/post/ressource", page_type: "post", category: "ressource", views: 7 },
  { path: "/expertises", page_type: "hub", category: null, views: 0 },
  { path: "/post/proces", page_type: "post", category: "actualite", views: 7 },
  { path: "/post/sans-categorie", page_type: "post", category: null, views: 3 },
  { path: "/droit-penal", page_type: "expertise", category: null, views: 12 },
  { path: "/", page_type: "home", category: null, views: 20 },
  { path: "/blog/categories/ressources", page_type: "category", category: "ressource", views: 1 },
].map((page) => ({ ...emptyMetrics, ...page, previous: { ...emptyMetrics } }));
const valid: PageViews = {
  period_start: "2026-10-05", period_end: "2026-11-03", expected_days: 30, observed_days: 30,
  inventory_checked_at: "2026-11-04T09:50:08.864047+00:00", pages: rows,
  unattributed_phone_events: 2, unattributed_form_events: 1,
  previous: { period_start: "2026-09-05", period_end: "2026-10-04", observed_days: 30, unattributed_phone_events: 0, unattributed_form_events: 0 },
};

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(console, "error").mockImplementation(() => {});
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
  vi.stubEnv("SUPABASE_SECRET_KEY", "synthetic-server-key");
  mocks.requireUser.mockResolvedValue({ email: "allowed@example.test" });
  mocks.createClient.mockReturnValue({ rpc: mocks.rpc });
  mocks.rpc.mockResolvedValue({ data: valid, error: null });
});
afterEach(() => { vi.unstubAllEnvs(); vi.restoreAllMocks(); });

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

describe("tri des mesures du tableau", () => {
  const sortable: PageViews["pages"] = [
    { path: "/b", views: 90, entries: 80, contact_visits: 20, contact_rate_pct: 25 },
    { path: "/zero", views: 10, entries: 2, contact_visits: 0, contact_rate_pct: 0 },
    { path: "/a", views: 100, entries: 40, contact_visits: 10, contact_rate_pct: 25 },
    { path: "/unknown", views: 0, entries: 0, contact_visits: 0, contact_rate_pct: null },
    { path: "/c", views: 9, entries: 8, contact_visits: 1, contact_rate_pct: 12.5 },
  ].map((page) => ({ ...rows[0], ...page, phone_visits: page.contact_visits, form_visits: 0 }));

  it.each([
    { column: "views", asc: ["/unknown", "/c", "/zero", "/b", "/a"], desc: ["/a", "/b", "/zero", "/c", "/unknown"] },
    { column: "entries", asc: ["/unknown", "/zero", "/c", "/a", "/b"], desc: ["/b", "/a", "/c", "/zero", "/unknown"] },
    { column: "contact_visits", asc: ["/unknown", "/zero", "/c", "/a", "/b"], desc: ["/b", "/a", "/c", "/unknown", "/zero"] },
    { column: "contact_rate_pct", asc: ["/zero", "/c", "/a", "/b", "/unknown"], desc: ["/a", "/b", "/c", "/zero", "/unknown"] },
  ] as const)("trie $column numériquement dans les deux sens, sans changer les mesures", ({ column, asc, desc }) => {
    const original = structuredClone(sortable);
    expect(filterPages(sortable, "all", { column, direction: "asc" }).map((row) => row.path)).toEqual(asc);
    expect(filterPages(sortable, "all", { column, direction: "desc" }).map((row) => row.path)).toEqual(desc);
    expect(sortable).toEqual(original);
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
    await expect(getPageViews(30)).rejects.toThrow(/^Lecture des données indisponible$/);
  });

  it("journalise uniquement RPC, SQLSTATE et statut pour identifier une annulation SQL", async () => {
    mocks.rpc.mockResolvedValue({ data: null, status: 500, error: {
      code: "57014", message: "private-database-detail", details: "private-payload", hint: "private-hint",
    } });
    await expect(getPageViews(30)).rejects.toThrow(/^Lecture des données indisponible$/);
    expect(console.error).toHaveBeenCalledExactlyOnceWith("cooked_rpc_failed", {
      rpc: "page_view_counts", sqlstate: "57014", status: 500,
    });
  });

  it("écarte les diagnostics hors format sans écrire les paramètres ni l’erreur brute", async () => {
    mocks.rpc.mockResolvedValue({ data: null, status: "private-status", error: { code: "private-code", message: "private-message" } });
    await expect(getPageQueries("/post/private-path", 30)).rejects.toThrow(/^Lecture des données indisponible$/);
    expect(console.error).toHaveBeenCalledExactlyOnceWith("cooked_rpc_failed", {
      rpc: "page_query_counts", sqlstate: null, status: null,
    });
  });

  it("un rejet réseau reste une erreur de lecture", async () => {
    mocks.rpc.mockRejectedValue(new Error("private-network-detail"));
    await expect(getPageViews(30)).rejects.toThrow(/^Lecture des données indisponible$/);
    expect(console.error).toHaveBeenCalledExactlyOnceWith("cooked_rpc_failed", {
      rpc: "page_view_counts", sqlstate: null, status: null,
    });
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
      previous: { ...valid.previous, period_start: "2026-01-31", period_end: "2026-03-01" },
      inventory_checked_at: "2026-03-29T22:00:00Z",
    }, error: null });
    expect((await getPageViews(30)).inventoryStale).toBe(false);
  });

  it("accepte une couverture partielle et un inventaire non confirmé sans les masquer", () => {
    expect(pageViewsSchema.parse({ ...valid, observed_days: 0, inventory_checked_at: null }))
      .toMatchObject({ observed_days: 0, inventory_checked_at: null });
  });
});


describe("cohérence des contacts et des périodes", () => {
  const metrics = { views: 40, entries: 20, phone_visits: 4, form_visits: 3, contact_visits: 5, contact_rate_pct: 25 };
  const withMetrics = (value: object) => ({ ...valid, pages: [{ ...rows[0], ...metrics, ...value }] });
  it("accepte le recouvrement téléphone/formulaire sans additionner les visites", () => {
    expect(pageViewsSchema.parse(withMetrics({})).pages[0].contact_visits).toBe(5);
  });
  it("refuse davantage d’entrées que de vues, sur chacune des périodes", () => {
    expect(pageViewsSchema.safeParse(withMetrics({ views: 19 })).success).toBe(false);
    expect(pageViewsSchema.safeParse(withMetrics({ previous: { ...metrics, views: 19 } })).success).toBe(false);
    expect(pageViewsSchema.safeParse(withMetrics({ views: 20, previous: { ...metrics, views: 20 } })).success).toBe(true);
  });
  it("refuse une URL présente plusieurs fois dans la réponse", () => {
    expect(pageViewsSchema.safeParse({ ...valid, pages: [...rows, { ...rows[0], views: 8 }] }).success).toBe(false);
  });
  it.each([
    { entries: -1 }, { phone_visits: -1 }, { form_visits: -1 }, { contact_visits: -1 },
    { entries: 4 }, { phone_visits: 6 }, { form_visits: 6 }, { contact_visits: 8, contact_rate_pct: 40 },
    { contact_rate_pct: 0.25 }, { contact_rate_pct: null }, { contact_rate_pct: 101 },
    { entries: 0, phone_visits: 0, form_visits: 0, contact_visits: 0, contact_rate_pct: 0 },
  ])("refuse les comptes ou taux incohérents %j", (changes) => {
    expect(pageViewsSchema.safeParse(withMetrics(changes)).success).toBe(false);
  });
  it("conserve le vrai taux zéro et l’inconnu sans entrée", () => {
    expect(pageViewsSchema.parse(withMetrics({ phone_visits: 0, form_visits: 0, contact_visits: 0, contact_rate_pct: 0 })).pages[0].contact_rate_pct).toBe(0);
    expect(pageViewsSchema.parse(withMetrics(emptyMetrics)).pages[0].contact_rate_pct).toBeNull();
    expect(pageViewsSchema.parse(withMetrics({ entries: 3, phone_visits: 1, form_visits: 0, contact_visits: 1, contact_rate_pct: 33.33 })).pages[0].contact_rate_pct).toBe(33.33);
  });
  it("vérifie aussi les comptes précédents et les non-attribués", () => {
    expect(pageViewsSchema.safeParse(withMetrics({ previous: { ...emptyMetrics, contact_visits: 1 } })).success).toBe(false);
    expect(pageViewsSchema.safeParse({ ...valid, unattributed_form_events: -1 }).success).toBe(false);
    expect(pageViewsSchema.safeParse({ ...valid, previous: { ...valid.previous, unattributed_phone_events: -1 } }).success).toBe(false);
  });
  it.each([
    { period_start: "2026-09-06" }, { period_end: "2026-10-03" },
    { period_start: "2026-09-06", period_end: "2026-10-05" }, { observed_days: 31 },
  ])("refuse des périodes précédentes non contiguës ou incohérentes %j", (previous) => {
    expect(pageViewsSchema.safeParse({ ...valid, previous: { ...valid.previous, ...previous } }).success).toBe(false);
  });
});

const google: PageQueries = {
  path: "/post/ressource", expected_days: 30, observed_days: 30,
  period_start: "2026-10-03", period_end: "2026-11-01",
  previous: { period_start: "2026-09-03", period_end: "2026-10-02", observed_days: 30 },
  queries: [{ query: "droit pénal", clicks: 3, previous_clicks: 0, position_avg: 4.5, previous_position_avg: null }],
};

describe("lecture des requêtes Google", () => {
  it("vérifie la session avant de demander une seule page et sa période", async () => {
    mocks.rpc.mockResolvedValue({ data: google, error: null });
    expect(await getPageQueries("/post/ressource", 30)).toEqual(google);
    expect(mocks.rpc).toHaveBeenCalledExactlyOnceWith("page_query_counts", { p_path: "/post/ressource", p_days: 30 });
    expect(mocks.requireUser.mock.invocationCallOrder[0]).toBeLessThan(mocks.createClient.mock.invocationCallOrder[0]);
  });
  it("n’accède pas à Google si la session est refusée", async () => {
    mocks.requireUser.mockRejectedValue(new Error("redirect-login"));
    await expect(getPageQueries("/", 30)).rejects.toThrow("redirect-login");
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("refuse une autre période et les contrats invalides", async () => {
    mocks.rpc.mockResolvedValue({ data: google, error: null });
    await expect(getPageQueries("/", 60)).rejects.toThrow("Réponse Google invalide");
    mocks.rpc.mockResolvedValue({ data: { ...google, queries: [{ ...google.queries[0], clicks: -1 }] }, error: null });
    await expect(getPageQueries("/", 30)).rejects.toThrow("Réponse Google invalide");
  });
  it("accepte l’absence complète de source et les positions inconnues", () => {
    expect(pageQueriesSchema.safeParse({ ...google, period_start: null, period_end: null, observed_days: 0,
      previous: { period_start: null, period_end: null, observed_days: 0 }, queries: [],
    }).success).toBe(true);
    expect(pageQueriesSchema.parse(google).queries[0].previous_position_avg).toBeNull();
  });
  it.each([
    { period_start: null }, { period_start: "2026-10-04" }, { observed_days: 31 },
    { previous: { ...google.previous, observed_days: 31 } },
    { previous: { ...google.previous, period_end: "2026-10-01" } },
    { queries: [{ ...google.queries[0], previous_clicks: -1 }] },
    { queries: [{ ...google.queries[0], position_avg: -1 }] },
    { queries: [{ ...google.queries[0], previous_position_avg: Infinity }] },
  ])("refuse un contrat Google incohérent %j", (changes) => {
    expect(pageQueriesSchema.safeParse({ ...google, ...changes }).success).toBe(false);
  });
});
