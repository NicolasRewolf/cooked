// T-19 — le compteur ingest_drops se vide par seuil ou par délai, jamais à chaque requête.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FLUSH_EVERY, IngestDropBuffer } from "./ingest_drops.ts";

Deno.test("IngestDropBuffer — agrège jusqu'au seuil puis un seul appel par raison", async () => {
  const calls: [string, number][] = [];
  let t = 1_000_000;
  const buf = new IngestDropBuffer(async (r, n) => { calls.push([r, n]); }, () => t);
  for (let i = 0; i < FLUSH_EVERY - 1; i++) assertEquals(await buf.add("bot_ua", 1), false);
  assertEquals(calls.length, 0);
  assertEquals(await buf.add("bot_ua", 1), true);
  assertEquals(calls, [["bot_ua", FLUSH_EVERY]]);
  assertEquals(buf.size, 0);
});

Deno.test("IngestDropBuffer — vide aussi après 60 s, toutes raisons confondues", async () => {
  const calls: [string, number][] = [];
  let t = 1_000_000;
  const buf = new IngestDropBuffer(async (r, n) => { calls.push([r, n]); }, () => t);
  await buf.add("bot_ua", 3);
  await buf.add("missing_fields", 2);
  t += 61_000;
  assertEquals(await buf.add("bot_ua", 1), true);
  assertEquals(calls.sort(), [["bot_ua", 4], ["missing_fields", 2]]);
});

Deno.test("IngestDropBuffer — n ≤ 0 ignoré", async () => {
  const buf = new IngestDropBuffer(async () => {});
  assertEquals(await buf.add("bot_ua", 0), false);
  assertEquals(buf.size, 0);
});
