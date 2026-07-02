// COOKED — form-webhook Edge Function (v11 — audit 02/07/2026 : submissionTime ISO + alerte dropped)
// POST /functions/v1/form-webhook?token=<WEBHOOK_SECRET>
// Reçoit les webhooks Wix Automations (Form Submitted) → insère form_submit.
// verify_jwt=false (Wix ne peut pas envoyer de JWT) ; auth par ?token=.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SECRET_KEY =
  Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// FORM_WEBHOOK_SECRET requis — sans lui n'importe quel POST forgerait des conversions.
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

// T-13 (audit 02/07/2026) — validation ISO-8601 stricte (même logique que
// track/index.ts). submissionTime malformé → fallback now() au lieu de stocker
// une chaîne arbitraire (juste tronquée à 35 char) dans occurred_at.
function iso(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = Date.parse(v);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}

/** Champ Wix typologie — pas de PII, whitelisté dans props. */
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

const jsonError = (status: number, error: string) =>
  new Response(JSON.stringify({ ok: false, error }), {
    status,
    headers: { "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonError(405, "method_not_allowed");
  }

  const url = new URL(req.url);
  const token = url.searchParams.get("token") ?? "";
  if (token !== WEBHOOK_SECRET) {
    console.warn("[form-webhook] invalid token");
    return jsonError(401, "unauthorized");
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonError(400, "invalid_json");
  }

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

  const pageSource =
    s(d?.["field:page_source"], 500) ??
    s(d?.page_source, 500) ??
    s(d?.submission?.pageInfo?.url, 500) ??
    s(body?.pageUrl, 500) ??
    null;

  // T-13 — submissionTime validé ISO (au lieu de s() qui tronquait sans valider).
  const occurredAt =
    iso(d?.submissionTime) ??
    iso(body?.triggeredAt) ??
    iso(body?.submittedAt) ??
    new Date().toISOString();

  // Sprint 37 — attribution : champs cachés cooked_aid/cooked_sid, même
  // validation que l'Edge track. Stockés dans props uniquement (colonnes
  // identité restent webhook-… — invariants Sprint 24/29).
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

  const syntheticSession =
    "webhook-" + (submissionId || crypto.randomUUID());

  // Sprint 30 — hostname spoofing guard sur page_source.
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

  // Sprint 30 — PII stripping (RGPD). On ne garde que les métadonnées non-PII.
  function stripPii(payload: unknown): Record<string, unknown> {
    const safe: Record<string, unknown> = {};
    const d2 = (payload as { data?: Record<string, unknown> })?.data ?? {};
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
      cooked_aid: cookedAid,
      cooked_sid: cookedSid,
      capture_source: "wix-webhook",
      payload_meta: safePayloadMeta,
    },
    occurred_at: occurredAt,
    received_at: new Date().toISOString(),
  };

  // Sprint 25 — insert idempotent (index unique partiel sur submission_id).
  const { error } = await supabase.from("events").insert(row);

  if (error) {
    const code = (error as { code?: string }).code;
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
    console.error(
      `[form-webhook] permanent insert error code=${code} submission=${submissionId} msg=${error.message}`,
    );
    // T-13 (audit 02/07/2026) — un form_submit perdu = une macro-conversion
    // muette. On lève une alerte CRITIQUE (au lieu d'avaler dans un log) pour
    // pouvoir la ré-insérer à la main. On garde le 200 (stop retry Wix).
    try {
      await supabase.from("alerts").insert({
        kind: "form_submit_dropped",
        severity: "critical",
        detail: `form_submit dropped (code=${code}) submission=${submissionId ?? "?"} : ${s(error.message, 300)}`,
      });
    } catch (alertErr) {
      console.error("[form-webhook] failed to raise dropped alert:", alertErr);
    }
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
