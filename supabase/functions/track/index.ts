// COOKED — track Edge Function (v32 — 04/11/2026 : réception HTTP testable, comptages inchangés).
// POST /functions/v1/track — gate x-cooked-key via le proxy Velo, sans vérification JWT.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { createTrackHandler } from "../_shared/track_delivery.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SECRET_KEY =
  Deno.env.get("SUPABASE_SECRET_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!SECRET_KEY) {
  throw new Error(
    "[track] SUPABASE_SECRET_KEY (or legacy SUPABASE_SERVICE_ROLE_KEY) env var is required — " +
    "set it in the Supabase Dashboard before deploying this function.",
  );
}

const supabase = createClient(SUPABASE_URL, SECRET_KEY, {
  auth: { persistSession: false },
});

Deno.serve(createTrackHandler({
  ingestKey: Deno.env.get("COOKED_INGEST_KEY") ?? "",
  anonSalt: Deno.env.get("ANON_SALT") ?? "",
  allowedOrigin: Deno.env.get("ALLOWED_ORIGIN"),
  insertEvents: (rows) => supabase.from("events").insert(rows),
  recordDrop: (reason, n) => supabase.rpc("record_ingest_drop", { p_reason: reason, p_n: n }),
}));
