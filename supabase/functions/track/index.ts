// COOKED — track Edge Function
// POST /functions/v1/track
// Auth: this function does NOT verify a JWT. Authorization is via the Velo proxy
// which holds the Supabase secret key server-side and forwards it as `apikey`.
// The Edge Function itself uses the auto-injected service-role key to insert.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

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

const ALLOWED_EVENTS = new Set([
  "pageview",
  "scroll_depth",
  "engagement_tick",
  "web_vitals",
  "click_outbound",
  "page_exit",
  // Phase 1 conversion tracking (added Sprint 10):
  "cta_phone_click",   // tap on <a href="tel:...">
  "cta_email_click",   // tap on <a href="mailto:..."> — kept allowed for
                       // defensive reasons but the tracker no longer
                       // emits this event since Plouton doesn't expose
                       // any mailto: link on the site.
  // Phase 1.5 — internal booking-page CTA (Sprint 10):
  "cta_booking_click", // click on any internal link pointing to
                       // /honoraires-rendez-vous (i.e. "Je prends RDV",
                       // "Contactez-nous", "Honoraires & RDV", …)
  // Phase 2 — form submission (Sprint 18):
  // ⚠️ form_submit is intentionally NOT listed here (Sprint 29 hardening).
  // It is inserted server-to-server via the dedicated `form-webhook` Edge
  // Function (POST from Wix Automations, secret-gated). Allowing the
  // browser-facing `/track` endpoint to accept it would let anyone forge
  // conversions by curl'ing the public endpoint — confirmed exploit path
  // identified during the 2026-05-21 audit. Reject silently below.
  // Phase 3 — Wix anchor-menu tracking (Sprint 19):
  "cta_anchor_click",  // click on an in-page anchor (sticky index, FAQ
                       // jump, "back to top"). Captures three shapes:
                       //   1. href="#section"        (classic)
                       //   2. href=current-path with `data-anchor`
                       //      attribute set by Wix Studio's anchor-
                       //      menu widget (no URL hash, scrolls via JS)
                       //   3. sticky-container fallback (clicks on any
                       //      interactive element inside a position:
                       //      sticky / fixed container that wasn't
                       //      classified by handlers 1/2)
                       // Props: target_section (slugified label or
                       // hash), anchor (aria-label or text), placement
                       // (header / footer / sticky / body), source
                       // (click | hashchange | sticky-fallback),
                       // data_anchor (Wix-internal ID, optional).
  // Phase 4 — internal navigation attribution (Sprint 36):
  "click_internal",    // click on an internal <a> to ANOTHER page (not the
                       // booking page → that stays cta_booking_click). Props:
                       // target_path, href, anchor (label), placement
                       // (header / footer / sticky / body). Adds the "which
                       // UI element drove this hop" attribution that the
                       // pageview sequence alone can't give.
]);

function dailySalt(): string {
  const today = new Date().toISOString().slice(0, 10);
  return `${today}|${ANON_SALT}`;
}

async function hashAnonymous(ip: string, ua: string): Promise<string> {
  const buf = new TextEncoder().encode(`${ip}|${ua}|${dailySalt()}`);
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash))
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function parseUserAgent(ua: string) {
  const isTablet = /iPad|Tablet|PlayBook/i.test(ua);
  const isMobile = !isTablet && /Mobi|Android|iPhone|iPod/i.test(ua);
  const device_type = isTablet ? "tablet" : isMobile ? "mobile" : "desktop";

  let os = "unknown";
  if (/Windows/i.test(ua)) os = "Windows";
  else if (/Mac OS X/i.test(ua)) os = "macOS";
  else if (/iPhone|iPad|iPod/i.test(ua)) os = "iOS";
  else if (/Android/i.test(ua)) os = "Android";
  else if (/Linux/i.test(ua)) os = "Linux";

  let browser = "unknown";
  if (/Edg\//i.test(ua)) browser = "Edge";
  else if (/OPR\//i.test(ua)) browser = "Opera";
  else if (/Chrome\//i.test(ua) && !/Chromium/i.test(ua)) browser = "Chrome";
  else if (/Firefox\//i.test(ua)) browser = "Firefox";
  else if (/Safari\//i.test(ua)) browser = "Safari";

  return { device_type, os, browser };
}

function hostnameOf(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    return new URL(url).hostname || null;
  } catch {
    return null;
  }
}

function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return (
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "0.0.0.0"
  );
}

function clientCountry(req: Request): string | null {
  return (
    req.headers.get("cf-ipcountry") ??
    req.headers.get("x-vercel-ip-country") ??
    req.headers.get("x-country") ??
    null
  );
}

function s(v: unknown, max = 500): string | null {
  if (v == null) return null;
  const str = String(v);
  return str.length > max ? str.slice(0, max) : str;
}

function n(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

// Sprint 30 — strict ISO-8601 timestamp validation. Without this, any
// 35-char string was accepted (e.g. "hello") and Postgres later rejected
// the entire batch of 50 events with a single cryptic error. Now we
// quietly fall back to server `now()` when occurred_at is malformed.
function iso(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = Date.parse(v);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}

// Sprint 30 — `typeof [] === "object"` was letting arrays slip into the
// `props` jsonb column. Downstream RPCs that do `props->>'foo'` would
// then silently return NULL with no trace. Coerce arrays + non-objects
// to an empty object.
function plainObject(v: unknown): Record<string, unknown> {
  return v != null && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
}

// Sprint 13 + GSC contract — canonical path for Cooked × GSC joins.
// Matches scripts/gsc_common.canonical_path() and SQL canonical_path(text):
// decode → Unicode NFC → strip trailing slash (except root).
// Only `path` is normalized; `url` stays as sent for debugging.
function canonicalPath(p: string | null): string | null {
  if (p == null) return null;
  let path: string;
  try {
    path = decodeURIComponent(p);
  } catch {
    path = p;
  }
  path = path.normalize("NFC");
  if (path.length > 1 && path.endsWith("/")) {
    path = path.slice(0, -1);
  }
  return path || "/";
}

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

  // Helper for JSON error responses — keeps the contract identical to
  // form-webhook so downstream log analysis can grep `ok:false` uniformly.
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
  const country = clientCountry(req);
  // Sprint 22 — prefer browser-supplied anonymous_id (stable localStorage UUID)
  // over the server-side IP hash. The IP hash was unreliable because Wix Velo
  // routes each request through a different serverless worker (different outbound
  // IP per request → different hash per engagement_tick → 6+ anonymous_ids per
  // session for 93 % of sessions).
  // Validation: accept any alphanumeric string 8–128 chars (covers our rid()
  // format and standard UUIDs). If absent or invalid, fall back to the hash so
  // old events already stored remain consistent.
  const serverHash = await hashAnonymous(ip, ua);
  const { device_type, os, browser } = parseUserAgent(ua);

  function resolveAnonId(browserAid: unknown): string {
    if (
      typeof browserAid === "string" &&
      browserAid.length >= 8 &&
      browserAid.length <= 128 &&
      /^[a-zA-Z0-9_-]+$/.test(browserAid)
    ) {
      return browserAid;
    }
    return serverHash;
  }

  const now = new Date().toISOString();
  const rows = [];
  // Sprint 30 — track silently-dropped events for ops visibility. Without
  // these counters, a tracker regression that emits e.g. `pageView` (camelCase)
  // would silently drop 100 % of events with zero log signal.
  let droppedMissingFields = 0;
  let droppedDisallowedName = 0;

  for (const e of events) {
    const name = s(e?.name, 50);
    const session_id = s(e?.session_id, 64);
    if (!name || !session_id) { droppedMissingFields++; continue; }
    if (!ALLOWED_EVENTS.has(name)) { droppedDisallowedName++; continue; }

    rows.push({
      anonymous_id: resolveAnonId(e?.anonymous_id),
      session_id,
      name,
      url: s(e.url, 2048),
      path: canonicalPath(s(e.path, 2048)),
      hostname: hostnameOf(s(e.url, 2048)),
      title: s(e.title, 500),
      referrer: s(e.referrer, 2048),
      referrer_hostname: hostnameOf(s(e.referrer, 2048)),
      utm_source: s(e.utm_source, 100),
      utm_medium: s(e.utm_medium, 100),
      utm_campaign: s(e.utm_campaign, 200),
      utm_term: s(e.utm_term, 200),
      utm_content: s(e.utm_content, 200),
      user_agent: ua.slice(0, 500),
      device_type,
      os,
      browser,
      viewport_width: n(e.viewport_width),
      viewport_height: n(e.viewport_height),
      country,
      props: plainObject(e.props),                  // Sprint 30 — arrays rejected
      occurred_at: iso(e.occurred_at) ?? now,       // Sprint 30 — strict ISO
      received_at: now,
    });
  }

  // Sprint 30 — emit a single warn per batch if drops happened. Cheap, grepable.
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
