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
  "cta_email_click",   // tap on <a href="mailto:...">
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

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405, headers: cors });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response("invalid json", { status: 400, headers: cors });
  }

  const events: any[] = Array.isArray(body?.events)
    ? body.events
    : Array.isArray(body)
    ? body
    : [body];

  if (!events.length || events.length > 50) {
    return new Response("invalid batch size", { status: 400, headers: cors });
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
      path: s(e.path, 2048),
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
    return new Response("no valid events", { status: 400, headers: cors });
  }

  const { error } = await supabase.from("events").insert(rows);
  if (error) {
    console.error("insert error", error.message);
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500,
      headers: { ...cors, "content-type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ ok: true, inserted: rows.length }), {
    status: 200,
    headers: { ...cors, "content-type": "application/json" },
  });
});
