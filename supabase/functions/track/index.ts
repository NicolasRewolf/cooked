// COOKED — track Edge Function (v25 — 10/07/2026 : C5 _shared/events_row ; D4 _shared/track_row)
// POST /functions/v1/track
// Auth: this function does NOT verify a JWT. Authorization is via the Velo proxy
// which holds the Supabase secret key server-side and forwards it as `apikey`.
// The Edge Function itself uses the auto-injected service-role key to insert.
//
// D4 — toute la construction des rows vit dans _shared/track_row.ts (module
// pur, testé par deno test). Le handler ne garde que : env, HTTP/CORS,
// parsing du batch, appel du builder, INSERT, réponse.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  buildEventRow,
  clientIp,
  hashAnonymous,
  parseUserAgent,
} from "../_shared/track_row.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
// New-format keys (sb_secret_*) populate SUPABASE_SECRET_KEY;
// legacy JWT keys populate SUPABASE_SERVICE_ROLE_KEY. Try new first.
// Sprint 25 — fail-fast at boot if neither is set. Without it the
// service-role insert would 401 silently and we'd lose events with
// only a cryptic Edge log entry.
const SECRET_KEY =
  Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!SECRET_KEY) {
  throw new Error(
    "[track] SUPABASE_SECRET_KEY (or legacy SUPABASE_SERVICE_ROLE_KEY) env var is required — " +
    "set it in the Supabase Dashboard before deploying this function.",
  );
}
// Sprint 25 — fail-fast if ANON_SALT is missing OR still the placeholder.
// Sprint 22 made the browser-supplied UUID primary, but ANON_SALT is
// still used in the IP+UA hash fallback (visitors without localStorage).
// A predictable salt would let anyone re-identify those visitors.
const ANON_SALT = Deno.env.get("ANON_SALT");
if (!ANON_SALT || ANON_SALT === "cooked-default-salt-CHANGE-ME-IN-DASHBOARD") {
  throw new Error(
    "[track] ANON_SALT env var is required and must not be the placeholder — " +
    "set a strong random value in the Supabase Dashboard before deploying.",
  );
}
const ALLOWED_ORIGIN =
  Deno.env.get("ALLOWED_ORIGIN") ?? "https://www.jplouton-avocat.fr";

const supabase = createClient(SUPABASE_URL, SECRET_KEY, {
  auth: { persistSession: false },
});

function corsHeaders(origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, apikey, authorization, x-client-info",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

Deno.serve(async (req) => {
  const reqOrigin = req.headers.get("origin") ?? "";
  const allowOrigin =
    ALLOWED_ORIGIN === "*"
      ? "*"
      : reqOrigin === ALLOWED_ORIGIN
      ? reqOrigin
      : ALLOWED_ORIGIN;
  const cors = corsHeaders(allowOrigin);

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
  const serverHash = await hashAnonymous(ip, ua, ANON_SALT);
  const device = parseUserAgent(ua);

  const now = new Date().toISOString();
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
  }

  if (!rows.length) {
    return jsonError(400, "no_valid_events");
  }

  const { error } = await supabase.from("events").insert(rows);
  if (error) {
    console.error("[track] insert error:", error.message);
    return jsonError(500, error.message);
  }

  return new Response(JSON.stringify({ ok: true, inserted: rows.length }), {
    status: 200,
    headers: { ...cors, "content-type": "application/json" },
  });
});
