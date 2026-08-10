// COOKED — form-webhook Edge Function (v13 — 10/08/2026 : Pont SECIB, identité
// prospect en clair → crm_prospects ; v12 — 10/07/2026 : C5 _shared/events_row ;
// D4 _shared/form_row)
// POST /functions/v1/form-webhook?token=<WEBHOOK_SECRET>
// Reçoit les webhooks Wix Automations (Form Submitted) → insère form_submit
// (events, sans PII) + la row prospect (crm_prospects, PII en clair, RLS
// deny-all — décision produit du 10/08/2026, jamais bloquante pour l'event).
// verify_jwt=false (Wix ne peut pas envoyer de JWT) ; auth par ?token=.
//
// D4 — toute la construction des rows vit dans _shared/form_row.ts (module
// pur, testé par deno test ; vecteurs « nous rejoindre » :
// contracts/recruitment_objet_vectors.json). Le handler ne garde que :
// env, auth token, parsing JSON, appel des builders, INSERTs, réponse.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { s } from "../_shared/events_row.ts";
import { buildFormSubmitRow, buildProspectRow } from "../_shared/form_row.ts";

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

  const build = buildFormSubmitRow(body);
  const { row, formId, submissionId } = build;

  // v13 — Pont SECIB : identité prospect → crm_prospects, AVANT l'insert
  // events pour que l'identité survive même à un form_submit droppé (T-13).
  // Jamais bloquant : un échec ici ne change rien à la réponse Wix.
  // Dédup Wix retry : index unique partiel sur wix_submission_id (23505 ignoré).
  try {
    const prospect = buildProspectRow(body, build);
    if (prospect) {
      const { error: pErr } = await supabase
        .from("crm_prospects")
        .insert(prospect);
      if (pErr && pErr.code !== "23505") {
        console.error(
          `[form-webhook] crm_prospects insert failed code=${pErr.code} submission=${submissionId ?? "?"}: ${pErr.message}`,
        );
      }
    } else {
      console.log(
        `[form-webhook] aucune identité prospect extraite submission=${submissionId ?? "?"}`,
      );
    }
  } catch (prospectErr) {
    console.error("[form-webhook] prospect capture crashed:", prospectErr);
  }

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
