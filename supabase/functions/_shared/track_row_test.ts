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
    title: "t".repeat(500),
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
