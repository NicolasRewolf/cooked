// D4 — tests du row-builder form-webhook (_shared/form_row.ts).
// Verrouille le comportement iso de form-webhook/index.ts v12 : extraction
// objet, règle « nous rejoindre » (vecteurs partagés), spoof-guard hostname,
// stripPii, row form_submit.

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import vectors from "../../../contracts/recruitment_objet_vectors.json" with {
  type: "json",
};
import {
  buildFormSubmitRow,
  buildProspectRow,
  classifyIdentityKey,
  extractObjetDeMaDemande,
  extractProspectIdentity,
  isRecruitmentObjet,
  resolvePageSource,
  stripPii,
} from "./form_row.ts";

const NOW = "2026-07-10T09:00:00.000Z";
const UUID = "00000000-0000-4000-8000-000000000000";
const OPTS = { nowIso: NOW, uuid: () => UUID };

// ------------------------------------------- règle « nous rejoindre » (contrat)

for (const c of vectors.cases) {
  Deno.test(`isRecruitmentObjet — vecteur ${c.id}`, () => {
    assertEquals(isRecruitmentObjet(c.objet), c.recruitment);
  });
}

Deno.test("vecteurs — counts_as_macro = NOT recruitment sur tous les cas", () => {
  for (const c of vectors.cases) {
    assertEquals(c.counts_as_macro, !c.recruitment, c.id);
  }
});

// -------------------------------------------------- extractObjetDeMaDemande

Deno.test("extractObjet — champ direct field:objet_de_ma_demande", () => {
  assertEquals(
    extractObjetDeMaDemande({ "field:objet_de_ma_demande": "Divorce" }),
    "Divorce",
  );
});

Deno.test("extractObjet — champ plat objet_de_ma_demande", () => {
  assertEquals(
    extractObjetDeMaDemande({ objet_de_ma_demande: "Indemnisation" }),
    "Indemnisation",
  );
});

Deno.test("extractObjet — scan des clés field:* contenant objet+demande (casse ignorée)", () => {
  assertEquals(
    extractObjetDeMaDemande({ "field:04_Objet_de_ma_demande": "Pénal" }),
    "Pénal",
  );
  assertEquals(
    extractObjetDeMaDemande({ field_objet_demande: "Contrats" }),
    "Contrats",
  );
});

Deno.test("extractObjet — fallback submissions[] par label", () => {
  assertEquals(
    extractObjetDeMaDemande({
      submissions: [
        { label: "Email", value: "pii@example.com" },
        { label: "Objet de ma demande", value: "Divorce" },
      ],
    }),
    "Divorce",
  );
});

Deno.test("extractObjet — absent = null ; valeur vide directe ignorée", () => {
  assertEquals(extractObjetDeMaDemande({}), null);
  assertEquals(extractObjetDeMaDemande({ "field:autre": "x" }), null);
  assertEquals(
    extractObjetDeMaDemande({ "field:objet_de_ma_demande": "" }),
    null,
  );
});

Deno.test("extractObjet — quirk verrouillé : submissions avec value vide retourne '' (pas null)", () => {
  assertEquals(
    extractObjetDeMaDemande({
      submissions: [{ label: "Objet de ma demande", value: "" }],
    }),
    "",
  );
});

Deno.test("extractObjet — tronqué à 200 caractères", () => {
  assertEquals(
    extractObjetDeMaDemande({ "field:objet_de_ma_demande": "x".repeat(250) }),
    "x".repeat(200),
  );
});

// -------------------------------------------------- resolvePageSource (spoof)

Deno.test("resolvePageSource — hostname légitime www accepté", () => {
  assertEquals(
    resolvePageSource("https://www.jplouton-avocat.fr/honoraires-rendez-vous"),
    {
      url: "https://www.jplouton-avocat.fr/honoraires-rendez-vous",
      path: "/honoraires-rendez-vous",
      hostname: "www.jplouton-avocat.fr",
    },
  );
});

Deno.test("resolvePageSource — apex accepté", () => {
  assertEquals(resolvePageSource("https://jplouton-avocat.fr/contact"), {
    url: "https://jplouton-avocat.fr/contact",
    path: "/contact",
    hostname: "jplouton-avocat.fr",
  });
});

Deno.test("resolvePageSource — chemin relatif résolu sur le site principal", () => {
  assertEquals(resolvePageSource("/post/garde-a-vue"), {
    url: "https://www.jplouton-avocat.fr/post/garde-a-vue",
    path: "/post/garde-a-vue",
    hostname: "www.jplouton-avocat.fr",
  });
});

Deno.test("resolvePageSource — hostname forgé rejeté (url brute, path/hostname null)", () => {
  assertEquals(resolvePageSource("https://evil.example.com/phish"), {
    url: "https://evil.example.com/phish",
    path: null,
    hostname: null,
  });
});

Deno.test("resolvePageSource — protocol-relative //evil rejeté aussi", () => {
  assertEquals(resolvePageSource("//evil.example.com/phish"), {
    url: "//evil.example.com/phish",
    path: null,
    hostname: null,
  });
});

Deno.test("resolvePageSource — null = tout null", () => {
  assertEquals(resolvePageSource(null), { url: null, path: null, hostname: null });
});

// ---------------------------------------------------------------- stripPii

Deno.test("stripPii — seules les métadonnées whitelistées survivent", () => {
  const safe = stripPii({
    data: {
      formName: "Formulaire Contact",
      submissionId: "sub-1",
      submissionTime: "2026-07-10T08:00:00Z",
      "field:page_source": "/contact",
      "field:objet_de_ma_demande": "Divorce",
      "field:cooked_aid": "aid_12345678",
      "field:cooked_sid": "sid_12345678",
      "field:email": "pii@example.com",
      "field:téléphone": "0612345678",
      "field:message": "récit personnel très sensible",
    },
  });
  assertEquals(safe, {
    formName: "Formulaire Contact",
    submissionId: "sub-1",
    submissionTime: "2026-07-10T08:00:00Z",
    "field:page_source": "/contact",
    "field:objet_de_ma_demande": "Divorce",
    "field:cooked_aid": "aid_12345678",
    "field:cooked_sid": "sid_12345678",
  });
  assert(!("field:email" in safe));
});

Deno.test("stripPii — payload sans data ou null = {}", () => {
  assertEquals(stripPii({}), {});
  assertEquals(stripPii(null), {});
  assertEquals(stripPii("string"), {});
});

// --------------------------------------------------------- buildFormSubmitRow

Deno.test("buildFormSubmitRow — payload Wix complet : row iso au handler v12", () => {
  const { row, formId, submissionId } = buildFormSubmitRow(
    {
      data: {
        formName: "Formulaire Contact",
        submissionId: "sub-123",
        submissionTime: "2026-07-10T08:30:00.000Z",
        "field:page_source": "https://www.jplouton-avocat.fr/post/garde-a-vue",
        "field:objet_de_ma_demande": "Divorce",
        "field:cooked_aid": "aid_0123456789abcdef",
        "field:cooked_sid": "sid_0123456789abcdef",
        "field:email": "pii@example.com",
      },
    },
    OPTS,
  );
  assertEquals(formId, "Formulaire Contact");
  assertEquals(submissionId, "sub-123");
  assertEquals(row, {
    anonymous_id: "webhook-sub-123",
    session_id: "webhook-sub-123",
    name: "form_submit",
    url: "https://www.jplouton-avocat.fr/post/garde-a-vue",
    path: "/post/garde-a-vue",
    hostname: "www.jplouton-avocat.fr",
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
      form_id: "Formulaire Contact",
      submission_id: "sub-123",
      page_source: "https://www.jplouton-avocat.fr/post/garde-a-vue",
      objet_de_ma_demande: "Divorce",
      counts_as_macro: true,
      cooked_aid: "aid_0123456789abcdef",
      cooked_sid: "sid_0123456789abcdef",
      capture_source: "wix-webhook",
      payload_meta: {
        formName: "Formulaire Contact",
        submissionId: "sub-123",
        submissionTime: "2026-07-10T08:30:00.000Z",
        "field:page_source": "https://www.jplouton-avocat.fr/post/garde-a-vue",
        "field:objet_de_ma_demande": "Divorce",
        "field:cooked_aid": "aid_0123456789abcdef",
        "field:cooked_sid": "sid_0123456789abcdef",
      },
    },
    occurred_at: "2026-07-10T08:30:00.000Z",
    received_at: NOW,
  });
});

Deno.test("buildFormSubmitRow — payload minimal : fallbacks anon/uuid/now", () => {
  const { row, formId, submissionId } = buildFormSubmitRow({}, OPTS);
  assertEquals(formId, "wix-form-webhook");
  assertEquals(submissionId, null);
  assertEquals(row.anonymous_id, "webhook-anon");
  assertEquals(row.session_id, `webhook-${UUID}`);
  assertEquals(row.url, null);
  assertEquals(row.path, null);
  assertEquals(row.hostname, null);
  assertEquals(row.occurred_at, NOW);
  assertEquals(row.received_at, NOW);
  assertEquals(row.props.objet_de_ma_demande, null);
  assertEquals(row.props.counts_as_macro, true);
  assertEquals(row.props.payload_meta, {});
});

Deno.test("buildFormSubmitRow — objet « Nous rejoindre » : counts_as_macro=false", () => {
  const { row } = buildFormSubmitRow(
    {
      data: {
        submissionId: "sub-recrut",
        "field:objet_de_ma_demande": "Nous rejoindre (candidature)",
      },
    },
    OPTS,
  );
  assertEquals(row.props.counts_as_macro, false);
  assertEquals(row.props.objet_de_ma_demande, "Nous rejoindre (candidature)");
});

Deno.test("buildFormSubmitRow — champs au niveau racine (sans body.data)", () => {
  const { row, formId, submissionId } = buildFormSubmitRow(
    {
      formName: "Formulaire Divorce",
      submissionId: "sub-root",
      pageUrl: "https://www.jplouton-avocat.fr/divorce",
    },
    OPTS,
  );
  assertEquals(formId, "Formulaire Divorce");
  assertEquals(submissionId, "sub-root");
  assertEquals(row.path, "/divorce");
});

Deno.test("buildFormSubmitRow — priorité occurred_at : submissionTime > triggeredAt > submittedAt > now", () => {
  const t1 = buildFormSubmitRow(
    {
      data: { submissionTime: "2026-07-09T10:00:00.000Z" },
      triggeredAt: "2026-07-09T11:00:00.000Z",
    },
    OPTS,
  );
  assertEquals(t1.row.occurred_at, "2026-07-09T10:00:00.000Z");

  const t2 = buildFormSubmitRow(
    {
      data: { submissionTime: "not-a-date" },
      triggeredAt: "2026-07-09T11:00:00.000Z",
    },
    OPTS,
  );
  assertEquals(t2.row.occurred_at, "2026-07-09T11:00:00.000Z");

  const t3 = buildFormSubmitRow(
    { submittedAt: "2026-07-09T12:00:00.000Z" },
    OPTS,
  );
  assertEquals(t3.row.occurred_at, "2026-07-09T12:00:00.000Z");

  const t4 = buildFormSubmitRow({}, OPTS);
  assertEquals(t4.row.occurred_at, NOW);
});

Deno.test("buildFormSubmitRow — page_source forgée : url brute gardée, path/hostname null", () => {
  const { row } = buildFormSubmitRow(
    {
      data: {
        submissionId: "sub-spoof",
        "field:page_source": "https://evil.example.com/phish",
      },
    },
    OPTS,
  );
  assertEquals(row.url, "https://evil.example.com/phish");
  assertEquals(row.path, null);
  assertEquals(row.hostname, null);
  assertEquals(row.props.page_source, "https://evil.example.com/phish");
});

Deno.test("buildFormSubmitRow — fallback page_source : submission.pageInfo.url", () => {
  const { row } = buildFormSubmitRow(
    { data: { submission: { pageInfo: { url: "/post/x" } } } },
    OPTS,
  );
  assertEquals(row.path, "/post/x");
  assertEquals(row.hostname, "www.jplouton-avocat.fr");
});

Deno.test("buildFormSubmitRow — cooked_aid/sid invalides = null", () => {
  const { row } = buildFormSubmitRow(
    {
      data: {
        "field:cooked_aid": "short",
        "field:cooked_sid": "bad id with spaces!",
      },
    },
    OPTS,
  );
  assertEquals(row.props.cooked_aid, null);
  assertEquals(row.props.cooked_sid, null);
});

// ------------------------------------------------- v13 — Pont SECIB (identité)

Deno.test("classifyIdentityKey — slots de base, accents et préfixe field:", () => {
  assertEquals(classifyIdentityKey("field:e_mail"), "email");
  assertEquals(classifyIdentityKey("field:prenom"), "prenom");
  assertEquals(classifyIdentityKey("Prénom"), "prenom");
  assertEquals(classifyIdentityKey("field:nom"), "nom");
  assertEquals(classifyIdentityKey("field:telephone"), "telephone");
  assertEquals(classifyIdentityKey("Téléphone portable"), "telephone");
  assertEquals(classifyIdentityKey("first_name"), "prenom");
  assertEquals(classifyIdentityKey("last_name"), "nom");
});

Deno.test("classifyIdentityKey — clés à ignorer (jamais un slot identité)", () => {
  assertEquals(classifyIdentityKey("field:objet_de_ma_demande"), null);
  assertEquals(classifyIdentityKey("field:cooked_aid"), null);
  assertEquals(classifyIdentityKey("field:page_source"), null);
  assertEquals(classifyIdentityKey("field:message"), null);
  assertEquals(classifyIdentityKey("field:nom_de_l_entreprise"), null);
  assertEquals(classifyIdentityKey("formId"), null);
  assertEquals(classifyIdentityKey("submissionTime"), null);
});

Deno.test("extractProspectIdentity — champs field:* du payload Wix", () => {
  const ident = extractProspectIdentity({
    "field:nom": "Dupont",
    "field:prenom": "Marie",
    "field:e_mail": "marie.dupont@example.com",
    "field:telephone": "06 12 34 56 78",
    "field:objet_de_ma_demande": "Divorce",
    "field:cooked_aid": "aid_12345678",
  });
  assertEquals(ident.nom, "Dupont");
  assertEquals(ident.prenom, "Marie");
  assertEquals(ident.email, "marie.dupont@example.com");
  assertEquals(ident.telephone, "06 12 34 56 78");
  assert(ident.fieldsKeys.includes("field:nom"));
  assert(ident.fieldsKeys.includes("field:cooked_aid"));
});

Deno.test("extractProspectIdentity — garde-fous de valeurs", () => {
  const ident = extractProspectIdentity({
    "field:e_mail": "pas-un-email",       // sans @ → rejeté
    "field:telephone": "12",              // trop court → rejeté
    "field:nom": "aussi@un.email",        // email recopié dans nom → rejeté
    "field:prenom": "  ",                 // vide → rejeté
  });
  assertEquals(ident.email, null);
  assertEquals(ident.telephone, null);
  assertEquals(ident.nom, null);
  assertEquals(ident.prenom, null);
});

Deno.test("extractProspectIdentity — fallback submissions[] par label", () => {
  const ident = extractProspectIdentity({
    submissions: [
      { label: "Nom", value: "Martin" },
      { label: "E-mail", value: "j.martin@example.org" },
      { label: "Objet de ma demande", value: "Indemnisation" },
    ],
  });
  assertEquals(ident.nom, "Martin");
  assertEquals(ident.email, "j.martin@example.org");
  assertEquals(ident.prenom, null);
});

Deno.test("extractProspectIdentity — fallback contact Wix", () => {
  const ident = extractProspectIdentity({
    contact: {
      name: { first: "Paul", last: "Durand" },
      email: "p.durand@example.net",
      phone: "+33 7 98 76 54 32",
    },
  });
  assertEquals(ident.prenom, "Paul");
  assertEquals(ident.nom, "Durand");
  assertEquals(ident.email, "p.durand@example.net");
  assertEquals(ident.telephone, "+33 7 98 76 54 32");
});

Deno.test("buildProspectRow — row complète, métadonnées héritées de la build", () => {
  const body = {
    data: {
      submissionId: "sub-pont-1",
      submissionTime: "2026-08-10T10:00:00.000Z",
      "field:page_source": "/honoraires-rendez-vous",
      "field:objet_de_ma_demande": "Divorce",
      "field:cooked_aid": "aid_12345678",
      "field:nom": "Dupont",
      "field:e_mail": "marie.dupont@example.com",
    },
  };
  const build = buildFormSubmitRow(body, OPTS);
  const prospect = buildProspectRow(body, build);
  assert(prospect !== null);
  assertEquals(prospect!.wix_submission_id, "sub-pont-1");
  assertEquals(prospect!.occurred_at, "2026-08-10T10:00:00.000Z");
  assertEquals(prospect!.objet, "Divorce");
  assertEquals(prospect!.page_source_path, "/honoraires-rendez-vous");
  assertEquals(prospect!.cooked_aid, "aid_12345678");
  assertEquals(prospect!.nom, "Dupont");
  assertEquals(prospect!.email, "marie.dupont@example.com");
  assertEquals(prospect!.source, "form");
});

Deno.test("buildProspectRow — null quand aucune identité (rien à rapprocher)", () => {
  const body = {
    data: {
      submissionId: "sub-vide",
      "field:objet_de_ma_demande": "Autre",
    },
  };
  const build = buildFormSubmitRow(body, OPTS);
  assertEquals(buildProspectRow(body, build), null);
});

Deno.test("buildProspectRow — la row events reste sans PII (invariant v13)", () => {
  const body = {
    data: {
      submissionId: "sub-pii-guard",
      "field:nom": "Dupont",
      "field:e_mail": "marie.dupont@example.com",
      "field:telephone": "0612345678",
    },
  };
  const { row } = buildFormSubmitRow(body, OPTS);
  const serialized = JSON.stringify(row);
  assert(!serialized.includes("Dupont"));
  assert(!serialized.includes("marie.dupont@example.com"));
  assert(!serialized.includes("0612345678"));
});

Deno.test("classifyIdentityKey — « nombre de » ne pollue pas le slot nom", () => {
  assertEquals(classifyIdentityKey("field:nombre_de_personnes"), null);
});
