/**
 * D4 — row-builder pur pour la Edge Function `form-webhook`.
 *
 * Extraction STRICTEMENT iso-comportement de form-webhook/index.ts (v12) :
 * extraction objet_de_ma_demande, règle « nous rejoindre » (candidatures),
 * spoof-guard hostname sur page_source, PII stripping, construction de la
 * row form_submit.
 *
 * v13 (10/08/2026) — Pont SECIB : extraction en CLAIR de l'identité prospect
 * (nom/prénom/email/téléphone) vers la table dédiée crm_prospects (RLS
 * deny-all). La row form_submit dans `events`, elle, reste 100 % sans PII :
 * stripPii() est inchangé.
 *
 * Module pur : AUCUNE lecture de Deno.env — le handler garde l'auth token.
 * Vecteurs partagés de la règle « nous rejoindre » :
 * contracts/recruitment_objet_vectors.json (parité SQL :
 * form_submit_counts_as_macro, vérifiée en prod par ailleurs).
 */

import { type CookedEventRow, iso, s, validId } from "./events_row.ts";
import { canonicalPath } from "./canonical_path.ts";

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
    // T-18 (b-06) : même canonicalisation que le tracker et le SQL (decode → NFC → slash),
    // sinon un page_source « /post/itt-p%C3%A9nale… » ne rejoint jamais son pageview.
    return { url: u.toString(), path: canonicalPath(u.pathname), hostname: u.hostname };
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

  // T-18 : Wix envoie parfois « Prise de contact site-web » AVEC un espace final
  // (230 lignes vs 22 sans, 180 j au 04/09/2026) → deux form_id pour un formulaire. Trim.
  const formId =
    (s(d?.formName, 200) ??
      s(d?.formId, 200) ??
      s(body?.formName, 200) ??
      s(body?.formId, 200) ??
      "wix-form-webhook").trim() || "wix-form-webhook";

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

  // v13 : l'identité prospect part dans crm_prospects via buildProspectRow —
  // cette row events doit rester sans PII.
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

// ---------------------------------------------------------------------------
// v13 — Pont SECIB (10/08/2026) : identité prospect EN CLAIR → crm_prospects.
// Décision produit : rapprochement lisible avec les dossiers SECIB (le
// hachage a été proposé et refusé). Extraction heuristique des champs
// identité du payload Wix : clés field:*, fallback submissions[] par label,
// fallback objet contact Wix. Le texte libre (message, détails de la
// demande) est exclu VOLONTAIREMENT : seuls nom/prénom/email/téléphone
// sortent du payload.
// ---------------------------------------------------------------------------

export interface ProspectIdentity {
  nom: string | null;
  prenom: string | null;
  email: string | null;
  telephone: string | null;
  /** Clés field:* vues dans le payload — diagnostic des trous d'extraction. */
  fieldsKeys: string[];
}

type IdentitySlot = "nom" | "prenom" | "email" | "telephone";

function foldKey(key: string): string {
  return key
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase();
}

/** Classe une clé/label de champ Wix vers un slot identité (null = ignorer). */
export function classifyIdentityKey(rawKey: string): IdentitySlot | null {
  const k = foldKey(rawKey).replace(/^field[:_]/, "");
  if (
    k.includes("cooked") ||
    k.includes("objet") ||
    k.includes("demande") ||
    k.includes("page_source") ||
    k.includes("message") ||
    k.includes("societe") ||
    k.includes("entreprise") ||
    k.includes("nombre") // « nombre de … » contient « nom »
  ) {
    return null;
  }
  if (k.includes("mail")) return "email";
  // « prenom » avant « nom » : l'un contient l'autre.
  if (k.includes("prenom") || k.includes("first")) return "prenom";
  if (
    k.includes("portable") ||
    k.includes("mobile") ||
    k.includes("phone") ||
    k.includes("tel")
  ) {
    return "telephone";
  }
  if (k.includes("nom") || k.includes("last")) return "nom";
  return null;
}

/** Valide + borne une valeur candidate pour un slot (null = rejet). */
function identityValue(slot: IdentitySlot, value: unknown): string | null {
  if (value == null) return null;
  const str = String(value).trim();
  if (!str) return null;
  if (slot === "email") return str.includes("@") ? s(str, 200) : null;
  if (slot === "telephone") {
    const digits = str.replace(/\D/g, "");
    return digits.length >= 8 && digits.length <= 15 ? s(str, 50) : null;
  }
  // nom / prenom : jamais un email recopié dans le mauvais champ.
  return str.includes("@") ? null : s(str, 150);
}

export function extractProspectIdentity(
  d: Record<string, unknown>,
): ProspectIdentity {
  const out: ProspectIdentity = {
    nom: null,
    prenom: null,
    email: null,
    telephone: null,
    fieldsKeys: [],
  };

  for (const [key, value] of Object.entries(d)) {
    const kl = key.toLowerCase();
    if (
      (kl.startsWith("field:") || kl.startsWith("field_")) &&
      out.fieldsKeys.length < 60
    ) {
      out.fieldsKeys.push(key);
    }
    const slot = classifyIdentityKey(key);
    if (!slot || out[slot]) continue;
    const v = identityValue(slot, value);
    if (v) out[slot] = v;
  }

  const subs = d.submissions;
  if (Array.isArray(subs)) {
    for (const item of subs) {
      const row = item as { label?: unknown; value?: unknown };
      const slot = classifyIdentityKey(String(row.label ?? ""));
      if (!slot || out[slot]) continue;
      const v = identityValue(slot, row.value);
      if (v) out[slot] = v;
    }
  }

  const contact = d.contact as
    | {
      name?: { first?: unknown; last?: unknown };
      email?: unknown;
      phone?: unknown;
    }
    | undefined;
  if (contact && typeof contact === "object") {
    out.prenom ??= identityValue("prenom", contact.name?.first);
    out.nom ??= identityValue("nom", contact.name?.last);
    out.email ??= identityValue("email", contact.email);
    out.telephone ??= identityValue("telephone", contact.phone);
  }

  return out;
}

/**
 * Row crm_prospects depuis le payload Wix + la build form_submit.
 * null si aucune identité extraite (rien à rapprocher — le form_submit
 * lui-même vit déjà dans events).
 */
export function buildProspectRow(
  // deno-lint-ignore no-explicit-any
  body: any,
  build: FormSubmitBuild,
): Record<string, unknown> | null {
  const d = (body?.data ?? body ?? {}) as Record<string, unknown>;
  const ident = extractProspectIdentity(d);
  if (!ident.nom && !ident.prenom && !ident.email && !ident.telephone) {
    return null;
  }
  const props = build.row.props as Record<string, unknown>;
  return {
    occurred_at: build.row.occurred_at,
    source: "form",
    form_id: build.formId,
    wix_submission_id: build.submissionId,
    objet: props.objet_de_ma_demande ?? null,
    page_source_path: build.row.path,
    cooked_aid: props.cooked_aid ?? null,
    cooked_sid: props.cooked_sid ?? null,
    nom: ident.nom,
    prenom: ident.prenom,
    email: ident.email,
    telephone: ident.telephone,
    fields_keys: ident.fieldsKeys,
  };
}
