/**
 * D4 — row-builder pur pour la Edge Function `form-webhook`.
 *
 * Extraction STRICTEMENT iso-comportement de form-webhook/index.ts (v12) :
 * extraction objet_de_ma_demande, règle « nous rejoindre » (candidatures),
 * spoof-guard hostname sur page_source, PII stripping, construction de la
 * row form_submit.
 *
 * Module pur : AUCUNE lecture de Deno.env — le handler garde l'auth token.
 * Vecteurs partagés de la règle « nous rejoindre » :
 * contracts/recruitment_objet_vectors.json (parité SQL :
 * form_submit_counts_as_macro, vérifiée en prod par ailleurs).
 */

import { type CookedEventRow, iso, s, validId } from "./events_row.ts";

/** Champ Wix typologie — pas de PII, whitelisté dans props. */
export function extractObjetDeMaDemande(
  d: Record<string, unknown>,
): string | null {
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
export function isRecruitmentObjet(value: string | null): boolean {
  if (!value) return false;
  const n = value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .trim();
  return n.includes("nous rejoindre");
}

// Sprint 30 — hostname spoofing guard sur page_source.
export const ALLOWED_PAGE_SOURCE_HOSTS = new Set([
  "www.jplouton-avocat.fr",
  "jplouton-avocat.fr",
]);

export function resolvePageSource(raw: string | null): {
  url: string | null;
  path: string | null;
  hostname: string | null;
} {
  if (!raw) return { url: null, path: null, hostname: null };
  try {
    const u = new URL(raw, "https://www.jplouton-avocat.fr");
    if (!ALLOWED_PAGE_SOURCE_HOSTS.has(u.hostname)) {
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

// Sprint 30 — PII stripping (RGPD). On ne garde que les métadonnées non-PII.
export function stripPii(payload: unknown): Record<string, unknown> {
  const safe: Record<string, unknown> = {};
  const d2 = (payload as { data?: Record<string, unknown> })?.data ?? {};
  for (
    const key of [
      "formId",
      "formName",
      "submissionId",
      "submissionTime",
      "field:page_source",
      "field:objet_de_ma_demande",
      "field:cooked_aid",
      "field:cooked_sid",
    ]
  ) {
    if (key in d2) safe[key] = d2[key];
  }
  return safe;
}

export interface FormSubmitBuild {
  row: CookedEventRow;
  formId: string;
  submissionId: string | null;
}

/**
 * Construit la row form_submit depuis un payload Wix Automations brut.
 * `opts.nowIso` / `opts.uuid` : injection pour les tests uniquement — en
 * production les défauts reproduisent exactement l'ancien handler (deux
 * appels distincts à new Date().toISOString(), comme avant l'extraction).
 */
export function buildFormSubmitRow(
  // deno-lint-ignore no-explicit-any
  body: any,
  opts: { nowIso?: string; uuid?: () => string } = {},
): FormSubmitBuild {
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
    (opts.nowIso ?? new Date().toISOString());

  // Sprint 37 — attribution : champs cachés cooked_aid/cooked_sid (C5 _shared).
  const cookedAid =
    validId(d?.["field:cooked_aid"]) ?? validId(d?.cooked_aid) ?? null;
  const cookedSid =
    validId(d?.["field:cooked_sid"]) ?? validId(d?.cooked_sid) ?? null;

  const syntheticSession = "webhook-" +
    (submissionId || (opts.uuid ? opts.uuid() : crypto.randomUUID()));

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
      `[form-webhook] objet_de_ma_demande absent — field:* keys=${
        fieldKeys.join(",") || "(none)"
      }`,
    );
  }

  const safePayloadMeta = stripPii(body);

  const row: CookedEventRow = {
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
    received_at: opts.nowIso ?? new Date().toISOString(),
  };

  return { row, formId, submissionId };
}
