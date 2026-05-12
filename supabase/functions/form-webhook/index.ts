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
const WEBHOOK_SECRET =
  Deno.env.get("FORM_WEBHOOK_SECRET") ?? "change-me-in-dashboard";

const supabase = createClient(SUPABASE_URL, SECRET_KEY, {
  auth: { persistSession: false },
});

function s(v: unknown, max = 500): string | null {
  if (v == null) return null;
  const str = String(v);
  return str.length > max ? str.slice(0, max) : str;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  // Verify webhook secret in query param
  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";
  if (token !== WEBHOOK_SECRET) {
    console.warn("form-webhook: invalid token");
    return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  // Parse Wix Automations payload
  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ ok: false, error: "invalid_json" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  // Wix Automations payload shape varies. We extract what we can find
  // (form name/id, submission id, page where it was submitted) without
  // assuming a specific schema. The full raw payload is stored in props
  // for forensic analysis.
  const formId =
    s(body?.formName, 200) ??
    s(body?.formId, 200) ??
    s(body?.form?.name, 200) ??
    s(body?.form?.id, 200) ??
    "wix-form-webhook";

  const submissionId =
    s(body?.submissionId, 200) ??
    s(body?.submission?.id, 200) ??
    s(body?.id, 200) ??
    null;

  // Try to extract the page where the form was submitted. Wix Automations
  // often expose this under `submission.pageInfo` or `data.page_source`
  // (which we set ourselves in a hidden field via faq-system.js).
  const pageSource =
    s(body?.submission?.pageInfo?.url, 500) ??
    s(body?.data?.page_source, 500) ??
    s(body?.submission?.data?.page_source, 500) ??
    s(body?.pageUrl, 500) ??
    null;

  const occurredAt = s(body?.triggeredAt, 35)
    ?? s(body?.submittedAt, 35)
    ?? new Date().toISOString();

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

  const { error } = await supabase.from("events").insert(row);

  if (error) {
    console.error("form-webhook insert error:", error.message);
    return new Response(
      JSON.stringify({ ok: false, error: error.message }),
      { status: 500, headers: { "content-type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ ok: true, form_id: formId, submission_id: submissionId }),
    { status: 200, headers: { "content-type": "application/json" } }
  );
});
