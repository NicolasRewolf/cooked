// Réception des événements observables : requête HTTP → filtrage → écriture → réponse.
// Les règles de construction des événements restent dans track_row.ts.
import { ingestKeyMatches, requireIngestKey } from "./ingest_gate.ts";
import { IngestDropBuffer } from "./ingest_drops.ts";
import type { CookedEventRow } from "./events_row.ts";
import {
  buildEventRow,
  clientIp,
  hashAnonymous,
  isBotUa,
  parseUserAgent,
} from "./track_row.ts";

export interface TrackDeliveryDependencies {
  ingestKey: string;
  anonSalt: string;
  allowedOrigin?: string;
  insertEvents(rows: CookedEventRow[]): PromiseLike<{ error: { message: string } | null }>;
  recordDrop(reason: string, n: number): PromiseLike<{ error: { message: string } | null }>;
  now?: () => Date;
}

/** Un handler par isolat : le compteur de rejets est partagé entre ses requêtes. */
export function createTrackHandler(deps: TrackDeliveryDependencies): (req: Request) => Promise<Response> {
  if (!deps.anonSalt || deps.anonSalt === "cooked-default-salt-CHANGE-ME-IN-DASHBOARD") {
    throw new Error(
      "[track] ANON_SALT env var is required and must not be the placeholder — " +
      "set a strong random value in the Supabase Dashboard before deploying.",
    );
  }
  const ingestKey = requireIngestKey(deps.ingestKey);
  const cors = {
    "Access-Control-Allow-Origin": deps.allowedOrigin ?? "https://www.jplouton-avocat.fr",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, apikey, authorization, x-client-info, x-cooked-key",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  const clock = deps.now ?? (() => new Date());
  const dropBuffer = new IngestDropBuffer(async (reason, n) => {
    const { error } = await deps.recordDrop(reason, n);
    if (error) console.error("[track] record_ingest_drop error:", error.message);
  }, () => clock().getTime());

  return async (req) => {
    const jsonError = (status: number, error: string) =>
      new Response(JSON.stringify({ ok: false, error }), {
        status,
        headers: { ...cors, "content-type": "application/json" },
      });

    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (req.method !== "POST") {
      return jsonError(405, "method_not_allowed");
    }

    if (!ingestKeyMatches(ingestKey, req.headers.get("x-cooked-key"))) {
      return jsonError(401, "unauthorized");
    }

    let body: any;
    try {
      body = await req.json();
    } catch {
      return jsonError(400, "invalid_json");
    }

    const events: any[] = Array.isArray(body?.events)
      ? body.events
      : Array.isArray(body)
      ? body
      : [body];

    if (!events.length || events.length > 50) {
      return jsonError(400, "invalid_batch_size");
    }

    const ip = clientIp(req);
    const ua = req.headers.get("user-agent") ?? "";

    // v26 (audit 25/07/2026, n°5/R2) — les crawlers/headless ne sont plus
    // écrits : leur UA matche la taxonomie ua_bot que refresh_noise_sessions
    // appliquait après coup (90 % des writes). Compteur ingest_drops pour
    // l'audit ; réponse 200 pour ne rien révéler au bot (et éviter tout retry).
    if (isBotUa(ua)) {
      await dropBuffer.add("bot_ua", events.length);
      return new Response(JSON.stringify({ ok: true, inserted: 0 }), {
        status: 200,
        headers: { ...cors, "content-type": "application/json" },
      });
    }

    const serverHash = await hashAnonymous(ip, ua, deps.anonSalt, clock());
    const device = parseUserAgent(ua);

    const now = clock().toISOString();
    const rows = [];
    let droppedMissingFields = 0;
    let droppedDisallowedName = 0;

    for (const e of events) {
      const built = buildEventRow(e, { serverHash, ua, device, now });
      if (!built.ok) {
        if (built.reason === "missing_fields") droppedMissingFields++;
        else droppedDisallowedName++;
        continue;
      }
      rows.push(built.row);
    }

    if (droppedMissingFields > 0 || droppedDisallowedName > 0) {
      console.warn(
        `[track] dropped events in batch (size=${events.length}): ` +
        `missing_fields=${droppedMissingFields} disallowed_name=${droppedDisallowedName}`,
      );
      // v26 — mêmes drops qu'avant, désormais comptés (auditabilité n°5).
      for (const [reason, cnt] of [
        ["missing_fields", droppedMissingFields],
        ["disallowed_name", droppedDisallowedName],
      ] as const) {
        if (cnt > 0) await dropBuffer.add(reason, cnt);
      }
    }

    if (!rows.length) {
      return jsonError(400, "no_valid_events");
    }

    const { error } = await deps.insertEvents(rows);
    if (error) {
      console.error("[track] insert error:", error.message);
      return jsonError(500, error.message);
    }

    return new Response(JSON.stringify({ ok: true, inserted: rows.length }), {
      status: 200,
      headers: { ...cors, "content-type": "application/json" },
    });
  };
}
