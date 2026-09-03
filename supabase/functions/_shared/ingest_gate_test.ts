// T-18 — la gate x-cooked-key ne peut pas s'éteindre en silence.
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ingestKeyMatches, requireIngestKey } from "./ingest_gate.ts";

Deno.test("requireIngestKey — absent, vide ou trop court ⇒ throw (fail-fast au boot)", () => {
  for (const v of [undefined, null, "", "   ", "court"]) {
    assertThrows(() => requireIngestKey(v), Error, "COOKED_INGEST_KEY");
  }
});

Deno.test("requireIngestKey — clé valide renvoyée trimée", () => {
  assertEquals(requireIngestKey("  0123456789abcdef0123  "), "0123456789abcdef0123");
});

Deno.test("ingestKeyMatches — égalité stricte, jamais vrai sans en-tête", () => {
  const k = "0123456789abcdef0123";
  assert(ingestKeyMatches(k, k));
  assert(!ingestKeyMatches(k, null));
  assert(!ingestKeyMatches(k, ""));
  assert(!ingestKeyMatches(k, k + "x"));
});
