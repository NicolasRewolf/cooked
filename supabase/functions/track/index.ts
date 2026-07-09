// COOKED — track Edge Function (v24 — 08/07/2026 : tag cooked_site outremer)
// POST /functions/v1/track
// Auth: this function does NOT verify a JWT. Authorization is via the Velo proxy
// which holds the Supabase secret key server-side and forwards it as `apikey`.
// The Edge Function itself uses the auto-injected service-role key to insert.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { canonicalPath } from "../_shared/canonical_path.ts";

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
  "cta_phone_click",
  "cta_email_click",
  "cta_booking_click",
  "cta_anchor_click",
  "click_internal",
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

function s(v: unknown, max = 500): string | null {
  if (v == null) return null;
  const str = String(v);
  return str.length > max ? str.slice(0, max) : str;
}

function n(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

// Sprint 30 — strict ISO-8601 timestamp validation.
function iso(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = Date.parse(v);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}

// Sprint 30 — coerce arrays + non-objects to an empty object for props jsonb.
function plainObject(v: unknown): Record<string, unknown> {
  return v != null && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
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
  let droppedMissingFields = 0;
  let droppedDisallowedName = 0;

  for (const e of events) {
    const name = s(e?.name, 50);
    const session_id = s(e?.session_id, 64);
    if (!name || !session_id) { droppedMissingFields++; continue; }
    if (!ALLOWED_EVENTS.has(name)) { droppedDisallowedName++; continue; }

    // 16/06/2026 — click_internal.target_path : même canonicalisation que `path`.
    const props = plainObject(e.props);
    if (name === "click_internal" && typeof props.target_path === "string") {
      props.target_path = canonicalPath(props.target_path) ?? props.target_path;
    }

    // T-13 (audit 02/07/2026) — clamp horloge client. iso() valide le parsing
    // mais pas la plausibilité : 102 events > 24h dans le passé en juin →
    // mauvais jour calendaire Paris. Si l'écart au serveur dépasse 48h, on
    // remplace par now() et on trace props.clock_clamped pour l'audit.
    let occurred_at = iso(e.occurred_at) ?? now;
    if (occurred_at !== now &&
        Math.abs(Date.parse(occurred_at) - Date.parse(now)) > 48 * 3600 * 1000) {
      occurred_at = now;
      props.clock_clamped = true;
    }
    // T-13 — cap engagement_tick.active_ms à 60 000 ms (onglet en veille = dwell gonflé).
    if (name === "engagement_tick" && typeof props.active_ms === "number" &&
        props.active_ms > 60000) {
      props.active_ms = 60000;
    }

    const eventUrl = s(e.url, 2048);
    const eventHost = hostnameOf(eventUrl);
    if (eventHost === "outremer.jplouton-avocat.fr") {
      props.cooked_site = "outremer";
    }

    rows.push({
      anonymous_id: resolveAnonId(e?.anonymous_id),
      session_id,
      name,
      url: eventUrl,
      path: canonicalPath(s(e.path, 2048)),
      hostname: eventHost,
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
      props,
      occurred_at,
      received_at: now,
    });
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
