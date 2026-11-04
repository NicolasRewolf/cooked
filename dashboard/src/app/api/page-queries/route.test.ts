import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { redirect } from "next/navigation";
const mocks = vi.hoisted(() => ({ requireUser: vi.fn(), createClient: vi.fn(), rpc: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("@/lib/auth", () => ({ requireUser: mocks.requireUser }));
vi.mock("@supabase/supabase-js", () => ({ createClient: mocks.createClient }));
import { GET } from "./route";
const data = {
  path: "/post/droit-pénal", expected_days: 30, observed_days: 0,
  period_start: null, period_end: null,
  previous: { period_start: null, period_end: null, observed_days: 0 }, queries: [],
};
const request = (query: string) => new Request(`https://dashboard.example/api/page-queries?${query}`);
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
  vi.stubEnv("SUPABASE_SECRET_KEY", "synthetic-server-key");
  mocks.requireUser.mockResolvedValue({ email: "allowed@example.test" });
  mocks.createClient.mockReturnValue({ rpc: mocks.rpc });
  mocks.rpc.mockResolvedValue({ data, error: null });
});
afterEach(() => vi.unstubAllEnvs());

describe("GET /api/page-queries", () => {
  it("authentifie puis lit une page et renvoie les agrégats sans cache", async () => {
    const response = await GET(request("path=%2Fpost%2Fdroit-p%C3%A9nal&days=30"));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(data);
    expect(response.headers.get("Cache-Control")).toBe("private, no-store");
    expect(mocks.rpc).toHaveBeenCalledExactlyOnceWith("page_query_counts", { p_path: "/post/droit-pénal", p_days: 30 });
    expect(mocks.requireUser.mock.invocationCallOrder[0]).toBeLessThan(mocks.createClient.mock.invocationCallOrder[0]);
  });
  it("préserve le refus Auth sans lecture ni transformation en succès", async () => {
    mocks.requireUser.mockImplementation(() => redirect("/login"));
    await expect(GET(request("path=%2F&days=30"))).rejects.toThrow("NEXT_REDIRECT");
    expect(mocks.createClient).not.toHaveBeenCalled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it.each([
    "path=%2F", "days=30", "path=%2F&days=31", "path=%2F&days=30&days=60",
    "path=%2F&path=%2Fpost&days=30", "path=https%3A%2F%2Fevil.test&days=30",
    "path=%2F%2Fevil.test&days=30", "path=%2Ffoo%3Fx&days=30", "path=%2Ffoo%23x&days=30",
    "path=%2Ffoo%5Cx&days=30", "path=%2Ffoo%0Ax&days=30", "path=%2F&days=30&extra=x",
  ])("refuse les paramètres invalides sans lecture (%s)", async (query) => {
    expect((await GET(request(query))).status).toBe(400);
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it("ne révèle pas une erreur DB et ne renvoie pas un faux zéro", async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: "private database detail" } });
    const response = await GET(request("path=%2F&days=30"));
    expect(response.status).toBe(503);
    const body = await response.text();
    expect(body).toContain("indisponibles");
    expect(body).not.toContain("private");
    expect(body).not.toContain("queries");
  });
});
