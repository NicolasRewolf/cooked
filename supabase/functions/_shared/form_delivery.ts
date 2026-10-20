/**
 * form-webhook v16 — HTTP acknowledgement follows durable delivery.
 * Both tables have a unique submission ID: retrying a partial/uncertain
 * delivery is safe. Only SQLSTATE 23505 is acknowledged as already stored.
 * No database message or request content may enter logs/alerts.
 */
import { type CookedEventRow, plainObject } from "./events_row.ts";
import { buildFormSubmitRow, buildProspectRow } from "./form_row.ts";

type WriteResult = { error: { code?: string } | null };

export interface FormDeliveryDependencies {
  secret: string;
  insertEvent(row: CookedEventRow): PromiseLike<WriteResult>;
  insertProspect(row: Record<string, unknown>): PromiseLike<WriteResult>;
  raiseAlert(detail: string): PromiseLike<{ error: unknown }>;
  log?(message: string): void;
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...(status === 503 ? { "retry-after": "60" } : {}),
    },
  });
}

/** Codes only: error.message/details may contain the submitted identity. */
function safeCode(error: unknown): string {
  const code = plainObject(error).code;
  return typeof code === "string" && /^(?:[0-9A-Z]{5}|PGRST[0-9]{3})$/.test(code)
    ? code
    : "unknown";
}

export function createFormWebhookHandler(deps: FormDeliveryDependencies) {
  if (!deps.secret) throw new Error("FORM_WEBHOOK_SECRET is required");
  const log = deps.log ?? ((message: string) => console.error(message));

  async function report(stage: string, code: string): Promise<void> {
    // stage/code originate only from static labels and safeCode above.
    const detail = `Form delivery incomplete: stage=${stage}, code=${code}; retry/reconciliation required`;
    log(`[form-webhook] ${detail}`);
    try {
      const result = await deps.raiseAlert(detail);
      if (result.error) log("[form-webhook] delivery alert failed");
    } catch {
      log("[form-webhook] delivery alert unavailable");
    }
  }

  async function write(
    stage: string,
    insert: () => PromiseLike<WriteResult>,
  ): Promise<{ ok: boolean; duplicate: boolean }> {
    try {
      const { error } = await insert();
      if (!error) return { ok: true, duplicate: false };
      if (error.code === "23505") return { ok: true, duplicate: true };
      await report(stage, safeCode(error));
    } catch {
      // A network exception can mean the write succeeded but its response
      // was lost. Do not claim failure or success: ask for an idempotent retry.
      await report(stage, "unknown");
    }
    return { ok: false, duplicate: false };
  }

  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") {
      return json(405, { ok: false, error: "method_not_allowed" });
    }
    if ((new URL(req.url).searchParams.get("token") ?? "") !== deps.secret) {
      return json(401, { ok: false, error: "unauthorized" });
    }
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json(400, { ok: false, error: "invalid_json" });
    }

    const root = plainObject(body);
    const data = plainObject(root.data ?? root);
    const submissionId = data.submissionId ?? root.submissionId;
    // Never fall back to a generated ID: every retry would create a contact.
    // Reject instead of truncating/normalising so IDs cannot collide.
    if (
      typeof submissionId !== "string" ||
      !/^[a-zA-Z0-9_-]{1,200}$/.test(submissionId)
    ) {
      await report("payload", "invalid_submission_id");
      return json(400, { ok: false, error: "invalid_submission_id" });
    }

    let build: ReturnType<typeof buildFormSubmitRow>;
    let prospect: ReturnType<typeof buildProspectRow>;
    try {
      build = buildFormSubmitRow(body);
      prospect = buildProspectRow(body, build);
    } catch {
      await report("payload", "invalid_payload");
      return json(400, { ok: false, error: "invalid_payload" });
    }

    // Preserve each durable part even if the other fails. A subsequent
    // request re-attempts BOTH; a duplicate on one never skips the other.
    const crm = prospect
      ? await write("crm_prospects", () => deps.insertProspect(prospect!))
      : { ok: true, duplicate: false };
    const event = await write("events", () => deps.insertEvent(build.row));
    if (!crm.ok || !event.ok) {
      return json(503, { ok: false, error: "delivery_incomplete" });
    }
    return json(200, {
      ok: true,
      form_id: build.formId,
      submission_id: submissionId,
      ...(event.duplicate ? { dedup: true } : {}),
    });
  };
}
