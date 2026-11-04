import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

const mocks = vi.hoisted(() => ({ getUser: vi.fn(), signOut: vi.fn() }));
vi.mock("server-only", () => ({}));
vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({ auth: mocks }),
}));
vi.mock("next/headers", () => ({
  cookies: async () => ({ getAll: () => [], set: vi.fn() }),
}));

import { proxy } from "./proxy";
import { POST } from "./app/auth/signout/route";

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "publishable-test");
  vi.stubEnv("DASHBOARD_ALLOWED_EMAILS", "allowed@example.test");
  mocks.getUser.mockResolvedValue({ data: { user: null } });
  mocks.signOut.mockResolvedValue({ error: null });
});
afterEach(() => vi.unstubAllEnvs());

describe("accès à la page de transition", () => {
  it("redirige une session absente vers la connexion", async () => {
    const response = await proxy(new NextRequest("https://data.example/"));
    expect(response.headers.get("location")).toBe("https://data.example/login");
  });

  it("refuse une adresse hors allowlist", async () => {
    mocks.getUser.mockResolvedValue({ data: { user: { email: "other@example.test" } } });
    const response = await proxy(new NextRequest("https://data.example/"));
    expect(response.headers.get("location")).toBe("https://data.example/login");
  });

  it("accepte une session autorisée sans dépendre de la casse", async () => {
    mocks.getUser.mockResolvedValue({ data: { user: { email: "Allowed@Example.test" } } });
    const response = await proxy(new NextRequest("https://data.example/"));
    expect(response.headers.get("location")).toBeNull();
    expect(response.headers.get("x-middleware-next")).toBe("1");
  });

  it("reste fermé si l’allowlist est vide", async () => {
    vi.stubEnv("DASHBOARD_ALLOWED_EMAILS", "");
    mocks.getUser.mockResolvedValue({ data: { user: { email: "allowed@example.test" } } });
    const response = await proxy(new NextRequest("https://data.example/"));
    expect(response.headers.get("location")).toBe("https://data.example/login");
  });

  it("laisse le formulaire de connexion accessible sans session", async () => {
    const response = await proxy(new NextRequest("https://data.example/login"));
    expect(response.headers.get("location")).toBeNull();
    expect(mocks.getUser).not.toHaveBeenCalled();
  });

  it("déconnecte puis impose un GET vers login après le POST", async () => {
    const response = await POST(new NextRequest("https://data.example/auth/signout", { method: "POST" }));
    expect(mocks.signOut).toHaveBeenCalledOnce();
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toBe("https://data.example/login");
  });

  it("ne nécessite plus de clé service pour valider la configuration", async () => {
    vi.stubEnv("SUPABASE_SECRET_KEY", undefined);
    const { allowedEmails } = await import("./env");
    expect(allowedEmails).toEqual(["allowed@example.test"]);
  });
});
