import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import vectors from "../../../contracts/canonical_path_vectors.json" with { type: "json" };
import { canonicalPath } from "./canonical_path.ts";

for (const row of vectors.path_cases) {
  Deno.test(`canonicalPath path ${row.id}`, () => {
    assertEquals(canonicalPath(row.input), row.expected);
  });
}

Deno.test("canonicalPath null", () => {
  assertEquals(canonicalPath(null), vectors.edge_null_case.expected);
});
