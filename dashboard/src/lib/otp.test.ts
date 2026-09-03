import { describe, expect, it } from "vitest";
import { otpSignInPayload } from "./otp";

describe("otpSignInPayload (g-06)", () => {
  it("n'autorise jamais la création de compte par le formulaire public", () => {
    const p = otpSignInPayload("  nicolas@example.test ", "https://data.example/auth/callback?next=%2F");
    expect(p.options.shouldCreateUser).toBe(false);
    expect(p.email).toBe("nicolas@example.test");
    expect(p.options.emailRedirectTo).toBe("https://data.example/auth/callback?next=%2F");
  });
});
