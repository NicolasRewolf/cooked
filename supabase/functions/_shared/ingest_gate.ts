// T-18 (mission 02/09/2026, b-02) — gate d'ingestion `x-cooked-key` : fail-fast.
// Avant : `Deno.env.get("COOKED_INGEST_KEY") ?? ""` puis `if (COOKED_INGEST_KEY) {…}` — un secret
// absent côté Supabase éteignait la gate en silence (tout continuait de marcher, rien ne le disait),
// alors que SUPABASE_SECRET_KEY et ANON_SALT, eux, font échouer le boot. Même discipline ici.

export const MIN_INGEST_KEY_LENGTH = 16;

export function requireIngestKey(value: string | undefined | null): string {
  const v = (value ?? "").trim();
  if (v.length < MIN_INGEST_KEY_LENGTH) {
    throw new Error(
      "[track] COOKED_INGEST_KEY env var is required (≥ " + MIN_INGEST_KEY_LENGTH +
        " chars) — set it in the Supabase Dashboard (and in the Wix Secrets Manager for the Velo proxy) " +
        "before deploying this function. The gate never runs open.",
    );
  }
  return v;
}

export function ingestKeyMatches(expected: string, presented: string | null | undefined): boolean {
  return typeof presented === "string" && presented.length === expected.length && presented === expected;
}
