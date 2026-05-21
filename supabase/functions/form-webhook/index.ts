// COOKED — form-webhook Edge Function
// POST /functions/v1/form-webhook?token=<WEBHOOK_SECRET>
//
// Receives Wix Automations webhooks fired when a Wix Form is successfully
// submitted (Wix Admin → Automations → Trigger: Form Submitted → Action:
// Send via webhook → URL: this endpoint with `?token=<secret>`).
//
// Why a webhook and not a browser-side intercept (masterPage.js):
//   Wix Forms V2 intercepts submissions at a JS layer that's hard to
//   reach reliably (form `submit` event is eaten, success message DOM
//   render is inconsistent, beacon endpoints can change). The official
//   Wix Automations webhook fires server-side after a successful
//   submission — 100% reliable, never affected by frontend changes.
//
// Trade-off:
//   - We get a guaranteed signal that a form was really submitted.
//   - But we lose browser context: no session_id, no real anonymous_id,
//     no referrer, no utm_*. The webhook fires server-to-server from
//     Wix to Supabase, not from the visitor's browser.
//   - This is fine for the "how many real conversions per day" metric.
//     The other Cooked events (pageview/scroll/dwell) still track the
//     visitor's session up to the moment of submit.
//
// Security:
//   - The endpoint requires a `?token=<WEBHOOK_SECRET>` query param.
//   - The secret is set as an Edge Function environment variable
//     `FORM_WEBHOOK_SECRET`.
//   - Requests without the right token are rejected with 401.
//
// Auth: verify_jwt = false (Wix Automations cannot send a Supabase JWT).
// The function uses the auto-injected service role to insert into events.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SECRET_KEY =
  Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// FORM_WEBHOOK_SECRET is REQUIRED — without it the endpoint would accept
// any POST and let an attacker manufacture fake `form_submit` rows.
// Throw at startup so a missing secret fails loudly (Supabase logs) instead
// of silently authorising the placeholder default.
const WEBHOOK_SECRET = Deno.env.get("FORM_WEBHOOK_SECRET");
if (!WEBHOOK_SECRET) {
  throw new Error(
    "[form-webhook] FORM_WEBHOOK_SECRET env var is required — set it in the " +
    "Supabase Dashboard before re-deploying this function.",
  );
}

const supabase = createClient(SUPABASE_URL, SECRET_KEY, {
  auth: { persistSession: false },
});

function s(v: unknown, max = 500): string | null {
  if (v == null) return null;
  const str = String(v);
  return str.length > max ? str.slice(0, max) : str;
}

// All non-2xx responses follow the same shape as `track/index.ts` so log
// analysis can grep `ok:false` uniformly across both functions.
const jsonError = (status: number, error: string) =>
  new Response(JSON.stringify({ ok: false, error }), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonError(405, "method_not_allowed");
  }

  // Verify webhook secret in query param
  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";
  if (token !== WEBHOOK_SECRET) {
    console.warn("[form-webhook] invalid token");
    return jsonError(401, "unauthorized");
  }

  // Parse Wix Automations payload
  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonError(400, "invalid_json");
  }

  // Wix Automations payload (observed shape, May 2026):
  //   {
  //     "data": {
  //       "formId":       "4e919573-...",         // Wix internal form UUID
  //       "formName":     "Prise de contact ...", // user-facing name
  //       "submissionId": "d66fdb73-...",
  //       "submissionTime": "2026-05-12T08:00:03.260Z",
  //       "field:page_source": "honoraires-rendez-vous",
  //       "field:first_name": "Nicolas", ...
  //       "contact": { ... },
  //       "submissions": [ {label, value}, ... ]
  //     }
  //   }
  // The hidden field `page_source` is set client-side by
  // public/faq-system.js (initPageSource).
  const d = body?.data ?? body;

  const formId =
    s(d?.formName, 200) ??
    s(d?.formId, 200) ??
    s(body?.formName, 200) ??
    s(body?.formId, 200) ??
    "wix-form-webhook";

  const submissionId =
    s(d?.submissionId, 200) ??
    s(body?.submissionId, 200) ??
    null;

  // page_source: try the hidden field first (faq-system.js sets this),
  // then several other shapes that Wix Automations might use.
  const pageSource =
    s(d?.["field:page_source"], 500) ??
    s(d?.page_source, 500) ??
    s(d?.submission?.pageInfo?.url, 500) ??
    s(body?.pageUrl, 500) ??
    null;

  const occurredAt =
    s(d?.submissionTime, 35) ??
    s(body?.triggeredAt, 35) ??
    s(body?.submittedAt, 35) ??
    new Date().toISOString();

  // Generate a synthetic session_id for this server-side event. Format:
  // "webhook-<submission_id_or_random>" — clearly identifies it as a
  // webhook-sourced event so it doesn't collide with browser sessions.
  const syntheticSession =
    "webhook-" + (submissionId || crypto.randomUUID());

  const row = {
    anonymous_id: "webhook-" + (submissionId || "anon"),
    session_id: syntheticSession,
    name: "form_submit",
    url: pageSource,
    path: pageSource ? new URL(pageSource, "https://www.jplouton-avocat.fr").pathname : null,
    hostname: pageSource ? new URL(pageSource, "https://www.jplouton-avocat.fr").hostname : null,
    title: null,
    referrer: null,
    referrer_hostname: null,
    utm_source: null,
    utm_medium: null,
    utm_campaign: null,
    utm_term: null,
    utm_content: null,
    user_agent: "Wix-Automation-Webhook",
    device_type: "server",
    os: null,
    browser: null,
    viewport_width: null,
    viewport_height: null,
    country: null,
    props: {
      form_id: formId,
      submission_id: submissionId,
      page_source: pageSource,
      capture_source: "wix-webhook",
      raw_payload: body, // full payload kept for forensic analysis
    },
    occurred_at: occurredAt,
    received_at: new Date().toISOString(),
  };

  // Sprint 25 — idempotent insert. Wix Automations can retry a webhook
  // delivery on its own timeout/5xx. The partial UNIQUE index
  // `events_form_submit_submission_id_uniq` ensures the second attempt
  // collides (PG error code 23505) and we return 200 so Wix stops
  // retrying — the row already exists.
  const { error } = await supabase.from("events").insert(row);

  if (error) {
    // 23505 = unique_violation → already inserted, this is a retry.
    if ((error as { code?: string }).code === "23505") {
      console.log(
        `[form-webhook] duplicate submission_id=${submissionId} (Wix retry) — ignored`,
      );
      return new Response(
        JSON.stringify({
          ok: true,
          form_id: formId,
          submission_id: submissionId,
          dedup: true,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    console.error("[form-webhook] insert error:", error.message);
    return jsonError(500, error.message);
  }

  return new Response(
    JSON.stringify({ ok: true, form_id: formId, submission_id: submissionId }),
    { status: 200, headers: { "content-type": "application/json" } }
  );
});
