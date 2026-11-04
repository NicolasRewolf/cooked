// COOKED — form-webhook Edge Function (v17 — 04/11/2026 : événement uniquement,
// accusé HTTP 200 après insertion ou doublon ; échec/état incertain → 503).
// POST /functions/v1/form-webhook?token=<WEBHOOK_SECRET>
// Wix Automations → events, avec le même payload analytics filtré.
// L'index unique sur submission_id rend la reprise idempotente.
// verify_jwt=false : authentification par secret, jamais de payload en log.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createFormWebhookHandler } from "../_shared/form_delivery.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SECRET_KEY =
  Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
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

Deno.serve(createFormWebhookHandler({
  secret: WEBHOOK_SECRET,
  insertEvent: (row) => supabase.from("events").insert(row),
  raiseAlert: (detail) =>
    supabase.rpc("raise_cooked_alert", {
      p_kind: "form_submit_dropped",
      p_sev: "critical",
      p_detail: detail,
    }),
}));
