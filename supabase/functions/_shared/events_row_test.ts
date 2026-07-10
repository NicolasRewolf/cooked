import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  hostnameOf,
  iso,
  plainObject,
  resolveAnonId,
  s,
  validId,
} from "./events_row.ts";

Deno.test("s truncates and nulls", () => {
  assertEquals(s(null), null);
  assertEquals(s("hello"), "hello");
  assertEquals(s("x".repeat(10), 5), "xxxxx");
});

Deno.test("iso accepts valid ISO strings", () => {
  assertEquals(iso(42), null);
  assertEquals(iso("not-a-date"), null);
  assertEquals(iso("2026-07-08T10:00:00.000Z"), "2026-07-08T10:00:00.000Z");
});

Deno.test("validId enforces cooked id shape", () => {
  assertEquals(validId("short"), null);
  assertEquals(validId("a".repeat(129)), null);
  assertEquals(validId("bad id!"), null);
  assertEquals(validId("abc12345_ok"), "abc12345_ok");
});

Deno.test("resolveAnonId prefers browser id", () => {
  assertEquals(resolveAnonId("browser-id-12345678", "server-hash"), "browser-id-12345678");
  assertEquals(resolveAnonId("bad", "server-hash"), "server-hash");
});

Deno.test("plainObject rejects arrays", () => {
  assertEquals(plainObject([1, 2]), {});
  assertEquals(plainObject({ a: 1 }), { a: 1 });
});

Deno.test("hostnameOf parses URLs", () => {
  assertEquals(hostnameOf(null), null);
  assertEquals(hostnameOf("https://www.jplouton-avocat.fr/post/foo"), "www.jplouton-avocat.fr");
  assertEquals(hostnameOf("not-a-url"), null);
});
