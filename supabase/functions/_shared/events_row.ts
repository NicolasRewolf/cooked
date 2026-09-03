/** Shared event-row helpers for track + form-webhook Edge Functions (C5). */

export function s(v: unknown, max = 500): string | null {
  if (v == null) return null;
  const str = String(v);
  return str.length > max ? str.slice(0, max) : str;
}

export function iso(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = Date.parse(v);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}

export function n(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

export function plainObject(v: unknown): Record<string, unknown> {
  return v != null && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
}

export function hostnameOf(url: string | null | undefined): string | null {
  if (!url) return null;
  try {
    return new URL(url).hostname || null;
  } catch {
    return null;
  }
}

/** cooked_aid / cooked_sid / browser anonymous_id — même regex que track. */
export function validId(v: unknown): string | null {
  return typeof v === "string" &&
      v.length >= 8 &&
      v.length <= 128 &&
      /^[a-zA-Z0-9_-]+$/.test(v)
    ? v
    : null;
}

export function resolveAnonId(
  browserAid: unknown,
  serverHash: string,
): string {
  return validId(browserAid) ?? serverHash;
}

export interface CookedEventRow {
  anonymous_id: string;
  session_id: string;
  name: string;
  url: string | null;
  path: string | null;
  hostname: string | null;
  title: string | null;
  referrer: string | null;
  referrer_hostname: string | null;
  utm_source: string | null;
  utm_medium: string | null;
  utm_campaign: string | null;
  utm_term: string | null;
  utm_content: string | null;
  user_agent: string;
  device_type: string;
  os: string | null;
  browser: string | null;
  viewport_width: number | null;
  viewport_height: number | null;
  props: Record<string, unknown>;
  occurred_at: string;
  received_at: string;
}
