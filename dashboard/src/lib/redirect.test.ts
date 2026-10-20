import { describe, expect, it } from "vitest";
import { safeNext } from "./redirect";

describe("safeNext", () => {
  it("accepte un chemin interne", () => {
    expect(safeNext("/article/foo")).toBe("/article/foo");
  });
  it("rejette protocol-relative", () => {
    expect(safeNext("//evil.com")).toBe("/");
  });
  it("rejette backslash", () => {
    expect(safeNext("/\\evil.com")).toBe("/");
  });
  it("rejette null", () => {
    expect(safeNext(null)).toBe("/");
  });
  it.each(["/\n/evil.com", "/\t/evil.com", "/\r/evil.com", "/\0/evil.com", "/\u007f/evil.com", "/a/..//evil.com", "https://evil.com"])("rejette %j après normalisation URL", (next) => {
    const destination = safeNext(next);
    expect(destination).toBe("/");
    expect(new URL(destination, "https://data.rewolf.studio").origin).toBe("https://data.rewolf.studio");
  });
  it("valide le paramètre décodé fourni par le callback", () => {
    const next = new URL("https://data.rewolf.studio/auth/callback?next=/%0A/example.org").searchParams.get("next");
    expect(safeNext(next)).toBe("/");
  });
  it.each(["/seo?period=rolling_28#queries", "/article/un%20titre", "/expertises"])("préserve la destination interne %j", (next) => {
    expect(safeNext(next)).toBe(next);
  });
});
