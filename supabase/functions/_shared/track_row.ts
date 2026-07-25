/**
 * D4 — row-builder pur pour la Edge Function `track`.
 *
 * Extraction STRICTEMENT iso-comportement de track/index.ts (v25) :
 * gate ALLOWED_EVENTS, parsing UA, hash anonyme salé, clamp horloge ±48 h,
 * cap active_ms, canonicalisation click_internal.target_path, tagging
 * cooked_site=outremer, construction de la row `events`.
 *
 * Module pur : AUCUNE lecture de Deno.env — les secrets (ANON_SALT) sont
 * passés en paramètres par le handler. Testable via `deno test`.
 */

import { canonicalPath } from "./canonical_path.ts";
import {
  type CookedEventRow,
  hostnameOf,
  iso,
  n,
  plainObject,
  resolveAnonId,
  s,
} from "./events_row.ts";

export const ALLOWED_EVENTS = new Set([
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

/** Sel quotidien : la partie date vient de l'horloge passée (défaut : maintenant). */
export function dailySalt(anonSalt: string, at: Date = new Date()): string {
  const today = at.toISOString().slice(0, 10);
  return `${today}|${anonSalt}`;
}

/** Hash IP+UA salé/jour — fallback identité pour les visiteurs sans localStorage. */
export async function hashAnonymous(
  ip: string,
  ua: string,
  anonSalt: string,
  at: Date = new Date(),
): Promise<string> {
  const buf = new TextEncoder().encode(`${ip}|${ua}|${dailySalt(anonSalt, at)}`);
  const hash = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(hash))
    .slice(0, 16)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// n°5 (audit 25/07/2026, R2) — taxonomie ua_bot de refresh_noise_sessions,
// répliquée à l'identique (39 motifs, même ordre que le SQL). Un event
// droppé ici aurait été exclu d'events_human de toute façon : mesuré le
// 25/07/2026 sur 48 h, 90,2 % des écritures matchaient, et 0 event bot-UA
// de plus de 90 minutes restait visible dans events_human.
const BOT_UA_RE = new RegExp(
  [
    "headless",
    "googlebot",
    "bingbot",
    "applebot",
    "duckduckbot",
    "yandexbot",
    "baiduspider",
    "gptbot",
    "claudebot",
    "perplexitybot",
    "chatgpt-user",
    "googleother",
    "semrushbot",
    "ahrefsbot",
    "mj12bot",
    "dotbot",
    "petalbot",
    "bytespider",
    "lighthouse",
    "pingdom",
    "uptimerobot",
    "gtmetrix",
    "facebookexternalhit",
    "linkedinbot",
    "twitterbot",
    "discordbot",
    "telegrambot",
    "slackbot",
    "whatsapp/",
    "crawler",
    "spider",
    "axios/",
    "curl/",
    "wget",
    "python",
    "go-http",
    "node-fetch",
    "httpclient",
    "java/",
  ].join("|"),
  "i",
);

/** true si l'UA appartient à la taxonomie ua_bot (drop avant INSERT). */
export function isBotUa(ua: string): boolean {
  return BOT_UA_RE.test(ua);
}

export function parseUserAgent(ua: string) {
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

export function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return (
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "0.0.0.0"
  );
}

/** Contexte batch calculé une fois par requête par le handler. */
export interface TrackRowContext {
  serverHash: string;
  ua: string;
  device: { device_type: string; os: string; browser: string };
  /** new Date().toISOString() au moment du batch. */
  now: string;
}

export type TrackRowResult =
  | { ok: true; row: CookedEventRow }
  | { ok: false; reason: "missing_fields" | "disallowed_name" };

/**
 * Construit une row `events` depuis un event browser brut.
 * Retourne { ok: false, reason } pour les events droppés (le handler compte
 * et log les drops, comme avant l'extraction).
 */
// deno-lint-ignore no-explicit-any
export function buildEventRow(e: any, ctx: TrackRowContext): TrackRowResult {
  const name = s(e?.name, 50);
  const session_id = s(e?.session_id, 64);
  if (!name || !session_id) return { ok: false, reason: "missing_fields" };
  if (!ALLOWED_EVENTS.has(name)) return { ok: false, reason: "disallowed_name" };

  // 16/06/2026 — click_internal.target_path : même canonicalisation que `path`.
  const props = plainObject(e.props);
  if (name === "click_internal" && typeof props.target_path === "string") {
    props.target_path = canonicalPath(props.target_path) ?? props.target_path;
  }

  // T-13 (audit 02/07/2026) — clamp horloge client. iso() valide le parsing
  // mais pas la plausibilité : 102 events > 24h dans le passé en juin →
  // mauvais jour calendaire Paris. Si l'écart au serveur dépasse 48h, on
  // remplace par now() et on trace props.clock_clamped pour l'audit.
  let occurred_at = iso(e.occurred_at) ?? ctx.now;
  if (
    occurred_at !== ctx.now &&
    Math.abs(Date.parse(occurred_at) - Date.parse(ctx.now)) > 48 * 3600 * 1000
  ) {
    occurred_at = ctx.now;
    props.clock_clamped = true;
  }
  // T-13 — cap engagement_tick.active_ms à 60 000 ms (onglet en veille = dwell gonflé).
  if (
    name === "engagement_tick" && typeof props.active_ms === "number" &&
    props.active_ms > 60000
  ) {
    props.active_ms = 60000;
  }

  const eventUrl = s(e.url, 2048);
  const eventHost = hostnameOf(eventUrl);
  if (eventHost === "outremer.jplouton-avocat.fr") {
    props.cooked_site = "outremer";
  }

  return {
    ok: true,
    row: {
      anonymous_id: resolveAnonId(e?.anonymous_id, ctx.serverHash),
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
      user_agent: ctx.ua.slice(0, 500),
      device_type: ctx.device.device_type,
      os: ctx.device.os,
      browser: ctx.device.browser,
      viewport_width: n(e.viewport_width),
      viewport_height: n(e.viewport_height),
      props,
      occurred_at,
      received_at: ctx.now,
    },
  };
}
