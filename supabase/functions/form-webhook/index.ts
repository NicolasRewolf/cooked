// COOKED — form-webhook Edge Function (v10 — Sprint 37, 09/06/2026)\n// Sprint 37: lit les champs cachés cooked_aid/cooked_sid déposés par le\n// tracker → attribution conversion → parcours (~95 % vs 75 % temporal).
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

/** Champ Wix typologie — pas de PII, whitelisté dans props (Sprint 27/05/2026). */
function extractObjetDeMaDemande(d: Record<string, unknown>): string | null {
  const direct =
    s(d["field:objet_de_ma_demande"], 200) ??
    s(d.objet_de_ma_demande, 200);
  if (direct) return direct;

  for (const [key, value] of Object.entries(d)) {
    const k = key.toLowerCase();
    if (
      (k.startsWith("field:") || k.startsWith("field_")) &&
      k.includes("objet") &&
      k.includes("demande")
    ) {
      const v = s(value, 200);
      if (v) return v;
    }
  }

  const subs = d.submissions;
  if (!Array.isArray(subs)) return null;
  for (const item of subs) {
    const row = item as { label?: unknown; value?: unknown };
    const label = String(row.label ?? "").toLowerCase();
    if (label.includes("objet") && label.includes("demande")) {
      return s(row.value, 200);
    }
  }
  return null;
}

/** Candidatures cabinet — ne comptent pas en contact business. */
function isRecruitmentObjet(value: string | null): boolean {
  if (!value) return false;
  const n = value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .trim();
  return n.includes("nous rejoindre");
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

  // Sprint 37 — attribution : le tracker (sprint37) dépose l'identité du
  // visiteur dans deux champs cachés Wix (`cooked_aid`, `cooked_sid`).
  // On les lit ici avec la MÊME validation que l'Edge `track` (8-128 chars
  // alphanum). Ils sont stockés dans props uniquement : les colonnes
  // anonymous_id / session_id de la ligne restent synthétiques (webhook-…)
  // pour préserver les invariants Sprint 24/29 (form_submit jamais classé
  // bot/noise). L'attribution vit en lecture via form_submits_attributed().
  function validId(v: unknown): string | null {
    return typeof v === "string" &&
      v.length >= 8 && v.length <= 128 &&
      /^[a-zA-Z0-9_-]+$/.test(v)
      ? v
      : null;
  }
  const cookedAid =
    validId(d?.["field:cooked_aid"]) ?? validId(d?.cooked_aid) ?? null;
  const cookedSid =
    validId(d?.["field:cooked_sid"]) ?? validId(d?.cooked_sid) ?? null;

  // Generate a synthetic session_id for this server-side event. Format:
  // "webhook-<submission_id_or_random>" — clearly identifies it as a
  // webhook-sourced event so it doesn't collide with browser sessions.
  const syntheticSession =
    "webhook-" + (submissionId || crypto.randomUUID());

  // Sprint 30 — hostname spoofing guard. Wix Automations sends
  // `field:page_source` as a relative path or a same-origin URL. If we
  // pass a protocol-relative string like "//evil.com/foo" to `new URL`
  // with the jplouton base, it resolves to "https://evil.com/foo" → the
  // attacker's hostname would land in our `events.hostname` column and
  // poison per-host analytics. Whitelist the resolved hostname against
  // the canonical site.
  const ALLOWED_HOSTS = new Set([
    "www.jplouton-avocat.fr",
    "jplouton-avocat.fr",
  ]);

  function resolvePageSource(raw: string | null): {
    url: string | null;
    path: string | null;
    hostname: string | null;
  } {
    if (!raw) return { url: null, path: null, hostname: null };
    try {
      const u = new URL(raw, "https://www.jplouton-avocat.fr");
      if (!ALLOWED_HOSTS.has(u.hostname)) {
        // Hostname spoofing attempt — refuse the enrichment but keep the
        // raw string so we can audit the attempt downstream if needed.
        console.warn(
          `[form-webhook] page_source hostname rejected: ${u.hostname}`,
        );
        return { url: raw, path: null, hostname: null };
      }
      return { url: u.toString(), path: u.pathname, hostname: u.hostname };
    } catch {
      return { url: raw, path: null, hostname: null };
    }
  }
  const ps = resolvePageSource(pageSource);

  const objetDeMaDemande = extractObjetDeMaDemande(
    (d ?? {}) as Record<string, unknown>,
  );
  const countsAsMacro = !isRecruitmentObjet(objetDeMaDemande);
  if (!objetDeMaDemande) {
    const fieldKeys = Object.keys((d ?? {}) as Record<string, unknown>).filter(
      (k) => k.toLowerCase().startsWith("field:"),
    );
    console.log(
      `[form-webhook] objet_de_ma_demande absent — field:* keys=${fieldKeys.join(",") || "(none)"}`,
    );
  }

  // Sprint 30 — PII stripping (RGPD hardening). Wix sends the FULL form
  // payload including first_name / last_name / email / phone / message
  // body. Stored as-is in `raw_payload`, those fields make the `events`
  // table a regulated PII store — incompatible with the "exempted
  // measure of audience" status documented in the README/CLAUDE.md. Keep
  // only the meta fields needed for diagnostics (form id, submission id,
  // page where the form was submitted, timing). The actual contact data
  // is already received by the cabinet via Wix's own form-submission
  // workflow — no need for Cooked to duplicate it.
  function stripPii(payload: unknown): Record<string, unknown> {
    const safe: Record<string, unknown> = {};
    const d2 = (payload as { data?: Record<string, unknown> })?.data ?? {};
    // Whitelist only non-PII metadata keys.
    for (const key of [
      "formId",
      "formName",
      "submissionId",
      "submissionTime",
      "field:page_source",
      "field:objet_de_ma_demande",
      "field:cooked_aid",
      "field:cooked_sid",
    ]) {
      if (key in d2) safe[key] = d2[key];
    }
    // Drop submissions[], contact{}, field:first_name, field:last_name,
    // field:email, field:phone, field:message, etc. — none of those
    // ever go into Cooked's analytics table.
    return safe;
  }
  const safePayloadMeta = stripPii(body);

  const row = {
    anonymous_id: "webhook-" + (submissionId || "anon"),
    session_id: syntheticSession,
    name: "form_submit",
    url: ps.url,
    path: ps.path,
    hostname: ps.hostname,
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
      objet_de_ma_demande: objetDeMaDemande,
      counts_as_macro: countsAsMacro,
      cooked_aid: cookedAid,      // Sprint 37 — identité visiteur (champ caché)
      cooked_sid: cookedSid,      // Sprint 37 — session visiteur (champ caché)
      capture_source: "wix-webhook",
      payload_meta: safePayloadMeta, // ⬅️ PII-stripped (Sprint 30)
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
    const code = (error as { code?: string }).code;
    // 23505 = unique_violation → already inserted, this is a retry.
    if (code === "23505") {
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
    // Sprint 30 — any other PG error is treated as a permanent failure
    // (bad payload, schema mismatch, etc.) and returned as 200 to stop
    // the Wix retry loop. Without this, a row that violates a CHECK or
    // NOT NULL constraint would loop forever, drowning the function
    // logs. Log the code+detail and accept the loss — the form
    // submission still reached Me Plouton via Wix Automations' own
    // delivery, this Edge Function only does analytics tracking.
    console.error(
      `[form-webhook] permanent insert error code=${code} submission=${submissionId} msg=${error.message}`,
    );
    return new Response(
      JSON.stringify({
        ok: false,
        error: "dropped",
        code,
        form_id: formId,
        submission_id: submissionId,
      }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({ ok: true, form_id: formId, submission_id: submissionId }),
    { status: 200, headers: { "content-type": "application/json" } }
  );
});
