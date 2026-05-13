// COOKED — track Edge Function
// POST /functions/v1/track
// Auth: this function does NOT verify a JWT. Authorization is via the Velo proxy
// which holds the Supabase secret key server-side and forwards it as `apikey`.
// The Edge Function itself uses the auto-injected service-role key to insert.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
// New-format keys (sb_secret_*) populate SUPABASE_SECRET_KEY;
// legacy JWT keys populate SUPABASE_SERVICE_ROLE_KEY. Try new first.
const SECRET_KEY =
  Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_SALT = Deno.env.get("ANON_SALT") ?? "cooked-default-salt-CHANGE-ME-IN-DASHBOARD";
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
  "form_submit",       // Wix Form successfully submitted (server-side
                       // signal). Inserted DIRECTLY into `events` by the
                       // `form-webhook` Edge Function (POST from Wix
                       // Automations). The `track` endpoint never
                       // receives this event from the browser — it's
                       // kept in ALLOWED_EVENTS as a defensive
                       // safety net only.
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

// Sprint 13 — normalize `path` to decoded form so it joins cleanly with
// the rest of the SEO stack (GSC returns decoded URLs by convention; the
// browser's `location.pathname` returns percent-encoded strings for paths
// that contain non-ASCII characters). Without this, "/post/durée-…" from
// GSC would never match "/post/dur%C3%A9e-…" from the tracker.
//
// Note: only `path` is decoded — the full `url` stays as-is to preserve
// the original transport form for debugging.
function decodePathSafe(p: string | null): string | null {
  if (p == null) return null;
  try {
    return decodeURIComponent(p);
  } catch {
    // Malformed percent-encoding (e.g. lone "%") — keep original to avoid
    // silently dropping the row.
    return p;
  }
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
  const anonymous_id = await hashAnonymous(ip, ua);
  const { device_type, os, browser } = parseUserAgent(ua);

  const now = new Date().toISOString();
  const rows = [];

  for (const e of events) {
    const name = s(e?.name, 50);
    const session_id = s(e?.session_id, 64);
    if (!name || !session_id) continue;
    if (!ALLOWED_EVENTS.has(name)) continue;

    rows.push({
      anonymous_id,
      session_id,
      name,
      url: s(e.url, 2048),
      path: decodePathSafe(s(e.path, 2048)),
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
      props: e.props && typeof e.props === "object" ? e.props : {},
      occurred_at: s(e.occurred_at, 35) ?? now,
      received_at: now,
    });
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
