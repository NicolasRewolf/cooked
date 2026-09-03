// D4 — tests du row-builder track (_shared/track_row.ts).
// Verrouille le comportement iso de track/index.ts v25 : gate, UA parsing,
// hash salé, clamp horloge ±48h, cap active_ms, target_path, outremer, row.

import {
  assert,
  assertEquals,
  assertMatch,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ALLOWED_EVENTS,
  buildEventRow,
  clientIp,
  dailySalt,
  hashAnonymous,
  isBotUa,
  parseUserAgent,
  type TrackRowContext,
} from "./track_row.ts";

const NOW = "2026-07-10T12:00:00.000Z";

function ctx(overrides: Partial<TrackRowContext> = {}): TrackRowContext {
  return {
    serverHash: "server-hash-0123456789abcdef",
    ua: "test-agent",
    device: { device_type: "desktop", os: "macOS", browser: "Chrome" },
    now: NOW,
    ...overrides,
  };
}

function baseEvent(overrides: Record<string, unknown> = {}) {
  return {
    name: "pageview",
    session_id: "sess-0001",
    url: "https://www.jplouton-avocat.fr/post/garde-a-vue",
    path: "/post/garde-a-vue",
    occurred_at: NOW,
    ...overrides,
  };
}

// ---------------------------------------------------------------- UA parsing

Deno.test("parseUserAgent — iPhone Safari (mobile ; os=macOS = comportement actuel, 'like Mac OS X' matche avant iOS)", () => {
  const ua =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";
  assertEquals(parseUserAgent(ua), {
    device_type: "mobile",
    os: "macOS",
    browser: "Safari",
  });
});

Deno.test("parseUserAgent — Android Chrome mobile", () => {
  const ua =
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36";
  assertEquals(parseUserAgent(ua), {
    device_type: "mobile",
    os: "Android",
    browser: "Chrome",
  });
});

Deno.test("parseUserAgent — iPad = tablet", () => {
  const ua =
    "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1";
  assertEquals(parseUserAgent(ua), {
    device_type: "tablet",
    os: "macOS",
    browser: "Safari",
  });
});

Deno.test("parseUserAgent — Windows Chrome desktop", () => {
  const ua =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
  assertEquals(parseUserAgent(ua), {
    device_type: "desktop",
    os: "Windows",
    browser: "Chrome",
  });
});

Deno.test("parseUserAgent — macOS Firefox desktop", () => {
  const ua =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:127.0) Gecko/20100101 Firefox/127.0";
  assertEquals(parseUserAgent(ua), {
    device_type: "desktop",
    os: "macOS",
    browser: "Firefox",
  });
});

Deno.test("parseUserAgent — Edge prioritaire sur Chrome", () => {
  const ua =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0";
  assertEquals(parseUserAgent(ua), {
    device_type: "desktop",
    os: "Windows",
    browser: "Edge",
  });
});

Deno.test("parseUserAgent — Opera (OPR/) prioritaire sur Chrome", () => {
  const ua =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 OPR/111.0.0.0";
  assertEquals(parseUserAgent(ua), {
    device_type: "desktop",
    os: "Windows",
    browser: "Opera",
  });
});

Deno.test("parseUserAgent — Googlebot desktop (bot connu)", () => {
  const ua =
    "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Googlebot/2.1; +http://www.google.com/bot.html) Chrome/126.0.0.0 Safari/537.36";
  assertEquals(parseUserAgent(ua), {
    device_type: "desktop",
    os: "unknown",
    browser: "Chrome",
  });
});

Deno.test("parseUserAgent — Googlebot smartphone (bot connu)", () => {
  const ua =
    "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)";
  assertEquals(parseUserAgent(ua), {
    device_type: "mobile",
    os: "Android",
    browser: "Chrome",
  });
});

Deno.test("parseUserAgent — UA vide = desktop/unknown/unknown", () => {
  assertEquals(parseUserAgent(""), {
    device_type: "desktop",
    os: "unknown",
    browser: "unknown",
  });
});

// -------------------------------------------------------------- hash & salt

Deno.test("dailySalt — date UTC + sel", () => {
  assertEquals(
    dailySalt("unit-salt", new Date("2026-07-10T23:59:00Z")),
    "2026-07-10|unit-salt",
  );
});

Deno.test("hashAnonymous — déterministe, 16 octets hex, valeur verrouillée", async () => {
  const at = new Date("2026-07-10T12:00:00Z");
  const h = await hashAnonymous("1.2.3.4", "test-ua", "unit-salt", at);
  // sha256("1.2.3.4|test-ua|2026-07-10|unit-salt") tronqué à 16 octets.
  assertEquals(h, "13f1801d11dff6bcc019f187549a12b9");
  assertMatch(h, /^[0-9a-f]{32}$/);
});

Deno.test("hashAnonymous — varie avec IP, sel et jour", async () => {
  const at = new Date("2026-07-10T12:00:00Z");
  const base = await hashAnonymous("1.2.3.4", "test-ua", "unit-salt", at);
  assertNotEquals(await hashAnonymous("5.6.7.8", "test-ua", "unit-salt", at), base);
  assertNotEquals(await hashAnonymous("1.2.3.4", "test-ua", "other-salt", at), base);
  assertNotEquals(
    await hashAnonymous("1.2.3.4", "test-ua", "unit-salt", new Date("2026-07-11T12:00:00Z")),
    base,
  );
});

// ------------------------------------------------------------------ clientIp

Deno.test("clientIp — x-forwarded-for, premier hop trimé", () => {
  const req = new Request("https://x/", {
    headers: { "x-forwarded-for": " 81.2.3.4 , 10.0.0.1" },
  });
  assertEquals(clientIp(req), "81.2.3.4");
});

Deno.test("clientIp — fallback cf-connecting-ip puis x-real-ip puis 0.0.0.0", () => {
  assertEquals(
    clientIp(new Request("https://x/", { headers: { "cf-connecting-ip": "9.9.9.9" } })),
    "9.9.9.9",
  );
  assertEquals(
    clientIp(new Request("https://x/", { headers: { "x-real-ip": "8.8.8.8" } })),
    "8.8.8.8",
  );
  assertEquals(clientIp(new Request("https://x/")), "0.0.0.0");
});

// ---------------------------------------------------------- gate des events

Deno.test("buildEventRow — les 11 events autorisés passent le gate", () => {
  for (const name of ALLOWED_EVENTS) {
    const r = buildEventRow(baseEvent({ name }), ctx());
    assert(r.ok, `${name} devrait passer`);
  }
});

Deno.test("buildEventRow — event non autorisé droppé (disallowed_name)", () => {
  for (const name of ["form_submit", "hack_event", "select *"]) {
    assertEquals(buildEventRow(baseEvent({ name }), ctx()), {
      ok: false,
      reason: "disallowed_name",
    });
  }
});

Deno.test("buildEventRow — name ou session_id manquant droppé (missing_fields)", () => {
  assertEquals(buildEventRow(baseEvent({ name: null }), ctx()), {
    ok: false,
    reason: "missing_fields",
  });
  assertEquals(buildEventRow(baseEvent({ session_id: undefined }), ctx()), {
    ok: false,
    reason: "missing_fields",
  });
  assertEquals(buildEventRow(null, ctx()), {
    ok: false,
    reason: "missing_fields",
  });
});

// -------------------------------------------------------- clamp horloge ±48h

Deno.test("buildEventRow — horloge à exactement 48h conservée (borne stricte)", () => {
  const r = buildEventRow(baseEvent({ occurred_at: "2026-07-08T12:00:00.000Z" }), ctx());
  assert(r.ok);
  assertEquals(r.row.occurred_at, "2026-07-08T12:00:00.000Z");
  assert(!("clock_clamped" in r.row.props));
});

Deno.test("buildEventRow — horloge passée > 48h clampée à now + props.clock_clamped", () => {
  const r = buildEventRow(baseEvent({ occurred_at: "2026-07-08T11:59:59.000Z" }), ctx());
  assert(r.ok);
  assertEquals(r.row.occurred_at, NOW);
  assertEquals(r.row.props.clock_clamped, true);
});

Deno.test("buildEventRow — horloge future > 48h clampée aussi", () => {
  const r = buildEventRow(baseEvent({ occurred_at: "2026-07-13T12:00:01.000Z" }), ctx());
  assert(r.ok);
  assertEquals(r.row.occurred_at, NOW);
  assertEquals(r.row.props.clock_clamped, true);
});

Deno.test("buildEventRow — occurred_at absent ou invalide = now, sans clock_clamped", () => {
  for (const occurred_at of [undefined, "not-a-date", 42]) {
    const r = buildEventRow(baseEvent({ occurred_at }), ctx());
    assert(r.ok);
    assertEquals(r.row.occurred_at, NOW);
    assert(!("clock_clamped" in r.row.props));
  }
});

Deno.test("buildEventRow — occurred_at avec offset re-sérialisé en ISO UTC", () => {
  const r = buildEventRow(
    baseEvent({ occurred_at: "2026-07-10T13:30:00+02:00" }),
    ctx(),
  );
  assert(r.ok);
  assertEquals(r.row.occurred_at, "2026-07-10T11:30:00.000Z");
});

// ------------------------------------------------------------- cap active_ms

Deno.test("buildEventRow — engagement_tick.active_ms cappé à 60000", () => {
  const r = buildEventRow(
    baseEvent({ name: "engagement_tick", props: { active_ms: 120000 } }),
    ctx(),
  );
  assert(r.ok);
  assertEquals(r.row.props.active_ms, 60000);
});

Deno.test("buildEventRow — active_ms ≤ 60000 inchangé ; autres events non cappés ; string ignorée", () => {
  const under = buildEventRow(
    baseEvent({ name: "engagement_tick", props: { active_ms: 59999 } }),
    ctx(),
  );
  assert(under.ok);
  assertEquals(under.row.props.active_ms, 59999);

  const otherEvent = buildEventRow(
    baseEvent({ name: "pageview", props: { active_ms: 999999 } }),
    ctx(),
  );
  assert(otherEvent.ok);
  assertEquals(otherEvent.row.props.active_ms, 999999);

  const asString = buildEventRow(
    baseEvent({ name: "engagement_tick", props: { active_ms: "120000" } }),
    ctx(),
  );
  assert(asString.ok);
  assertEquals(asString.row.props.active_ms, "120000");
});

// -------------------------------------------- click_internal.target_path

Deno.test("buildEventRow — click_internal.target_path canonicalisé (decode + NFC + trailing slash)", () => {
  const r = buildEventRow(
    baseEvent({
      name: "click_internal",
      props: { target_path: "/post/caf%C3%A9/" },
    }),
    ctx(),
  );
  assert(r.ok);
  assertEquals(r.row.props.target_path, "/post/café");
});

Deno.test("buildEventRow — target_path non-string ou autre event : intact", () => {
  const nonString = buildEventRow(
    baseEvent({ name: "click_internal", props: { target_path: 42 } }),
    ctx(),
  );
  assert(nonString.ok);
  assertEquals(nonString.row.props.target_path, 42);

  const otherEvent = buildEventRow(
    baseEvent({ name: "pageview", props: { target_path: "/post/caf%C3%A9/" } }),
    ctx(),
  );
  assert(otherEvent.ok);
  assertEquals(otherEvent.row.props.target_path, "/post/caf%C3%A9/");
});

// ---------------------------------------------------------- tagging outremer

Deno.test("buildEventRow — url outremer taguée props.cooked_site=outremer", () => {
  const r = buildEventRow(
    baseEvent({ url: "https://outremer.jplouton-avocat.fr/contact" }),
    ctx(),
  );
  assert(r.ok);
  assertEquals(r.row.hostname, "outremer.jplouton-avocat.fr");
  assertEquals(r.row.props.cooked_site, "outremer");
});

Deno.test("buildEventRow — site principal : pas de cooked_site", () => {
  const r = buildEventRow(baseEvent(), ctx());
  assert(r.ok);
  assertEquals(r.row.hostname, "www.jplouton-avocat.fr");
  assert(!("cooked_site" in r.row.props));
});

// ------------------------------------------------------------- row complète

Deno.test("buildEventRow — row complète iso au handler v25 (troncatures, coercions, fallbacks)", () => {
  const longUa = "u".repeat(600);
  const r = buildEventRow(
    {
      name: "pageview",
      session_id: "sess-full",
      anonymous_id: "not ok!", // invalide → fallback serverHash
      url: "https://www.jplouton-avocat.fr/post/foo/",
      path: "/post/foo/",
      title: "t".repeat(600),
      referrer: "https://www.google.com/search?q=avocat",
      utm_source: "s".repeat(150),
      utm_medium: "cpc",
      utm_campaign: null,
      viewport_width: 390,
      viewport_height: "844", // string → null
      props: { foo: "bar" },
      occurred_at: "2026-07-10T11:00:00.000Z",
    },
    ctx({ ua: longUa, device: { device_type: "mobile", os: "iOS", browser: "Safari" } }),
  );
  assert(r.ok);
  assertEquals(r.row, {
    anonymous_id: "server-hash-0123456789abcdef",
    session_id: "sess-full",
    name: "pageview",
    url: "https://www.jplouton-avocat.fr/post/foo/",
    path: "/post/foo",
    hostname: "www.jplouton-avocat.fr",
    title: null, // T-19 : title plus écrit (décision 03/09/2026)
    referrer: "https://www.google.com/search?q=avocat",
    referrer_hostname: "www.google.com",
    utm_source: "s".repeat(100),
    utm_medium: "cpc",
    utm_campaign: null,
    utm_term: null,
    utm_content: null,
    user_agent: "u".repeat(500),
    device_type: "mobile",
    os: "iOS",
    browser: "Safari",
    viewport_width: 390,
    viewport_height: null,
    props: { foo: "bar" },
    occurred_at: "2026-07-10T11:00:00.000Z",
    received_at: NOW,
  });
});

Deno.test("buildEventRow — anonymous_id browser valide conservé", () => {
  const r = buildEventRow(baseEvent({ anonymous_id: "aid_0123456789abcdef" }), ctx());
  assert(r.ok);
  assertEquals(r.row.anonymous_id, "aid_0123456789abcdef");
});

Deno.test("buildEventRow — props non-objet remplacées par {}", () => {
  for (const props of ["str", 42, [1, 2], null, undefined]) {
    const r = buildEventRow(baseEvent({ props }), ctx());
    assert(r.ok);
    assertEquals(r.row.props, {});
  }
});

// ─── n°5 (audit 25/07/2026) — isBotUa : taxonomie ua_bot iso refresh_noise_sessions ───

Deno.test("isBotUa — HeadlessChrome (84 % du bruit mesuré en prod)", () => {
  assert(isBotUa(
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/126.0.0.0 Safari/537.36",
  ));
});

Deno.test("isBotUa — Googlebot smartphone", () => {
  assert(isBotUa(
    "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
  ));
});

Deno.test("isBotUa — clients HTTP (curl, python-requests, Java)", () => {
  assert(isBotUa("curl/8.6.0"));
  assert(isBotUa("python-requests/2.32.0"));
  assert(isBotUa("Java/17.0.2"));
  assert(isBotUa("axios/1.7.2"));
});

Deno.test("isBotUa — previews sociaux (WhatsApp, facebookexternalhit)", () => {
  assert(isBotUa("WhatsApp/2.23.20.0"));
  assert(isBotUa("facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"));
});

Deno.test("isBotUa — insensible à la casse", () => {
  assert(isBotUa("Mozilla/5.0 SEMRUSHBOT-BA"));
});

Deno.test("isBotUa — humains : Chrome desktop, iPhone Safari, Android = false", () => {
  assert(!isBotUa(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  ));
  assert(!isBotUa(
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
  ));
  assert(!isBotUa(
    "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36",
  ));
});

Deno.test("isBotUa — UA vide = false (iso-comportement : jamais classé ua_bot en SQL)", () => {
  assert(!isBotUa(""));
});

// T-04 (mission 02/09/2026, constat a-01) — le bot Baidu à UA littéral « pc » et SEBot-WA sont droppés à l'ingestion ;
// un UA légitime contenant « pc » en sous-chaîne ne l'est pas (motif ancré).
Deno.test("isBotUa — UA littéral 'pc' (bot Baidu) = bot", () => {
  assertEquals(isBotUa("pc"), true);
  assertEquals(isBotUa("PC"), true);
});

Deno.test("isBotUa — SEBot-WA = bot", () => {
  assertEquals(isBotUa("SEBot-WA"), true);
});

Deno.test("isBotUa — 'pc' en sous-chaîne d'un UA légitime ≠ bot", () => {
  assertEquals(isBotUa("Mozilla/5.0 (Linux; Android 13; PC-T1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36"), false);
  assertEquals(isBotUa("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"), false);
});


// ------------------------------------------- T-19 / T-22 — url réduite aux paramètres de campagne, title non écrit
import { campaignOnlyUrl } from "./track_row.ts";

Deno.test("campaignOnlyUrl — garde utm/gclid/cooked_*, jette le reste et le fragment", () => {
  assertEquals(
    campaignOnlyUrl("https://www.jplouton-avocat.fr/post/x?utm_source=gmb&fbclid=1&foo=bar&cooked_aid=abc123&gclid=g#sec"),
    "https://www.jplouton-avocat.fr/post/x?utm_source=gmb&fbclid=1&cooked_aid=abc123&gclid=g",
  );
  assertEquals(campaignOnlyUrl("https://www.jplouton-avocat.fr/"), "https://www.jplouton-avocat.fr/");
  assertEquals(campaignOnlyUrl(null), null);
});

Deno.test("buildEventRow — title jamais écrit, url réduite", () => {
  const built = buildEventRow(
    { name: "pageview", url: "https://www.jplouton-avocat.fr/p?foo=1&utm_medium=cpc", path: "/p", title: "Titre", anonymous_id: "a1b2c3d4e5f6a1b2", session_id: "s1s1s1s1s1s1s1s1", occurred_at: NOW },
    ctx(),
  );
  assert(built.ok);
  if (built.ok) {
    assertEquals(built.row.title, null);
    assertEquals(built.row.url, "https://www.jplouton-avocat.fr/p?utm_medium=cpc");
  }
});
