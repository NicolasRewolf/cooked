import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { CookedEventRow } from "./events_row.ts";
import { createTrackHandler } from "./track_delivery.ts";

type Dependencies = Parameters<typeof createTrackHandler>[0];

const KEY = "synthetic-ingestion-key";
const SALT = "synthetic-anonymous-salt";
const NOW = "2026-11-04T08:00:00.000Z";
const ORIGIN = "https://www.jplouton-avocat.fr";
const UA =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1";

function event(overrides: Record<string, unknown> = {}) {
  return {
    name: "pageview",
    session_id: "synthetic-session",
    path: "/ressources",
    url: `${ORIGIN}/ressources`,
    occurred_at: NOW,
    ...overrides,
  };
}

function request(body: unknown = event(), init: RequestInit = {}): Request {
  const headers = new Headers({
    "content-type": "application/json",
    "x-cooked-key": KEY,
    "user-agent": UA,
    "x-forwarded-for": "203.0.113.7, 203.0.113.8",
    "cf-connecting-ip": "203.0.113.9",
    "x-real-ip": "203.0.113.10",
    origin: ORIGIN,
  });
  new Headers(init.headers).forEach((value, key) => headers.set(key, value));
  return new Request("https://example.invalid/track", {
    method: "POST",
    body: JSON.stringify(body),
    ...init,
    headers,
  });
}

function fake() {
  const writes: CookedEventRow[][] = [];
  const drops: { reason: string; n: number }[] = [];
  let at = NOW;
  const deps: Dependencies = {
    ingestKey: KEY,
    anonSalt: SALT,
    insertEvents(rows) {
      writes.push(structuredClone(rows));
      return Promise.resolve({ error: null });
    },
    recordDrop(reason, n) {
      drops.push({ reason, n });
      return Promise.resolve({ error: null });
    },
    now: () => new Date(at),
  };
  return { deps, writes, drops, setTime: (value: string) => at = value };
}

async function quiet(run: () => Promise<void>) {
  const { warn, error } = console;
  console.warn = () => {};
  console.error = () => {};
  try {
    await run();
  } finally {
    console.warn = warn;
    console.error = error;
  }
}

Deno.test("track delivery — invalid ingestion configuration fails at construction", () => {
  for (const ingestKey of ["", "too-short"]) {
    assertThrows(() => createTrackHandler({ ...fake().deps, ingestKey }));
  }
  for (const anonSalt of ["", "cooked-default-salt-CHANGE-ME-IN-DASHBOARD"]) {
    assertThrows(() => createTrackHandler({ ...fake().deps, anonSalt }));
  }
});

Deno.test("track delivery — preflight and method checks precede authentication", async () => {
  const f = fake();
  const handler = createTrackHandler(f.deps);
  for (const [method, status] of [["OPTIONS", 204], ["GET", 405]] as const) {
    const response = await handler(request(null, {
      method,
      body: null,
      headers: { "x-cooked-key": "" },
    }));
    assertEquals(response.status, status);
    assertEquals(response.headers.get("access-control-allow-origin"), ORIGIN);
    if (method === "OPTIONS") {
      assertEquals(await response.text(), "");
      assertEquals(
        response.headers.get("access-control-allow-methods"),
        "POST, OPTIONS",
      );
      assertEquals(response.headers.get("access-control-max-age"), "86400");
    } else {
      assertEquals(await response.json(), {
        ok: false,
        error: "method_not_allowed",
      });
    }
  }
  assertEquals(f.writes, []);
  assertEquals(f.drops, []);
});

Deno.test("track delivery — unauthorized requests fail before JSON parsing", async () => {
  const f = fake();
  const handler = createTrackHandler(f.deps);
  for (const key of [null, "wrong-ingestion-key"]) {
    const req = request(null, { body: "{invalid json" });
    if (key === null) req.headers.delete("x-cooked-key");
    else req.headers.set("x-cooked-key", key);
    const response = await handler(req);
    assertEquals(response.status, 401);
    assertEquals(await response.json(), { ok: false, error: "unauthorized" });
  }
  assertEquals(f.writes, []);
  assertEquals(f.drops, []);
});

Deno.test("track delivery — CORS retains configured origin fallback and wildcard", async () => {
  for (const allowedOrigin of [undefined, "https://configured.invalid", "*"]) {
    const f = fake();
    const handler = createTrackHandler({ ...f.deps, allowedOrigin });
    const response = await handler(request(event(), {
      headers: { origin: "https://different.invalid" },
    }));
    assertEquals(response.status, 200);
    assertEquals(
      response.headers.get("access-control-allow-origin"),
      allowedOrigin ?? ORIGIN,
    );
    assertEquals(response.headers.get("vary"), "Origin");
    assertEquals(response.headers.get("content-type"), "application/json");
    assertEquals(f.writes.length, 1);
  }
});

Deno.test("track delivery — JSON and batch validation run before bot rejection", async () => {
  const f = fake();
  const handler = createTrackHandler(f.deps);
  for (const ua of [UA, "Googlebot/2.1"]) {
    const response = await handler(request(null, {
      body: "{invalid json",
      headers: { "user-agent": ua },
    }));
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { ok: false, error: "invalid_json" });
  }
  const oversized = await handler(
    request(Array.from({ length: 51 }, () => event()), {
      headers: { "user-agent": "Googlebot/2.1" },
    }),
  );
  assertEquals(oversized.status, 400);
  assertEquals(await oversized.json(), {
    ok: false,
    error: "invalid_batch_size",
  });
  assertEquals(f.writes, []);
  assertEquals(f.drops, []);
});

Deno.test("track delivery — envelope, array and single event produce the same row", async () => {
  const f = fake();
  const handler = createTrackHandler(f.deps);
  for (const body of [{ events: [event()] }, [event()], event()]) {
    const response = await handler(request(body));
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { ok: true, inserted: 1 });
  }
  assertEquals(f.writes.length, 3);
  assertEquals(f.writes[0], f.writes[1]);
  assertEquals(f.writes[1], f.writes[2]);
});

Deno.test("track delivery — zero and 51 events fail, 50 events use one insert", async () => {
  const f = fake();
  const handler = createTrackHandler(f.deps);
  for (const count of [0, 51]) {
    const response = await handler(
      request({ events: Array.from({ length: count }, () => event()) }),
    );
    assertEquals(response.status, 400);
    assertEquals(await response.json(), {
      ok: false,
      error: "invalid_batch_size",
    });
  }
  assertEquals(f.writes, []);
  const response = await handler(
    request(Array.from({ length: 50 }, () => event())),
  );
  assertEquals(await response.json(), { ok: true, inserted: 50 });
  assertEquals(f.writes.map((rows) => rows.length), [50]);
  assertEquals(f.drops, []);
});

Deno.test("track delivery — mixed batches keep valid order and aggregate rejection reasons", () =>
  quiet(async () => {
    const f = fake();
    const handler = createTrackHandler(f.deps);
    const mixed = [
      event({ name: "cta_phone_click", session_id: "session-first" }),
      ...Array.from({ length: 24 }, () => null),
      ...Array.from({ length: 24 }, () => event({ name: "form_submit" })),
      event({ session_id: "session-last" }),
    ];
    for (let i = 0; i < 2; i++) {
      const response = await handler(request(mixed));
      assertEquals(await response.json(), { ok: true, inserted: 2 });
      assertEquals(f.writes[i].map((row) => row.session_id), [
        "session-first",
        "session-last",
      ]);
    }
    assertEquals(f.drops, []);
    const response = await handler(request([
      event(),
      null,
      {},
      event({ name: "form_submit" }),
      event({ name: "unknown" }),
    ]));
    assertEquals(await response.json(), { ok: true, inserted: 1 });
    assertEquals(f.drops, [
      { reason: "missing_fields", n: 50 },
      { reason: "disallowed_name", n: 50 },
    ]);
  }));

Deno.test("track delivery — wholly invalid payloads fail without losing their drop counts", () =>
  quiet(async () => {
    const f = fake();
    const handler = createTrackHandler(f.deps);
    const response = await handler(
      request([
        null,
        {},
        event({ name: "form_submit" }),
        event({ name: "unknown" }),
      ]),
    );
    assertEquals(response.status, 400);
    assertEquals(await response.json(), {
      ok: false,
      error: "no_valid_events",
    });
    for (const count of [50, 46]) {
      await handler(request(Array.from({ length: count }, () => event()), {
        headers: { "user-agent": "Googlebot/2.1" },
      }));
    }
    assertEquals(f.writes, []);
    assertEquals(f.drops, [
      { reason: "missing_fields", n: 2 },
      { reason: "disallowed_name", n: 2 },
      { reason: "bot_ua", n: 96 },
    ]);
  }));

Deno.test("track delivery — bots are acknowledged without inserts and flush every 100 drops", async () => {
  const f = fake();
  const handler = createTrackHandler(f.deps);
  for (let i = 0; i < 2; i++) {
    const response = await handler(
      request(Array.from({ length: 50 }, () => null), {
        headers: { "user-agent": "Googlebot/2.1" },
      }),
    );
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { ok: true, inserted: 0 });
    assertEquals(f.drops, i === 0 ? [] : [{ reason: "bot_ua", n: 100 }]);
  }
  assertEquals(f.writes, []);
});

Deno.test("track delivery — elapsed drop window flushes on the next rejection at 60 seconds", async () => {
  const f = fake();
  const handler = createTrackHandler(f.deps);
  const bot = () =>
    request(event(), { headers: { "user-agent": "Googlebot/2.1" } });
  await handler(bot());
  f.setTime("2026-11-04T08:00:59.999Z");
  await handler(bot());
  assertEquals(f.drops, []);
  f.setTime("2026-11-04T08:01:00.000Z");
  assertEquals(f.drops, []);
  await handler(bot());
  assertEquals(f.drops, [{ reason: "bot_ua", n: 3 }]);
  assertEquals(f.writes, []);
});

Deno.test("track delivery — drop audit failures do not change bot acknowledgement", () =>
  quiet(async () => {
    for (const rejects of [false, true]) {
      const f = fake();
      let calls = 0;
      f.deps.recordDrop = () => {
        calls++;
        return rejects
          ? Promise.reject(new Error("synthetic drop failure"))
          : Promise.resolve({ error: { message: "synthetic drop failure" } });
      };
      const handler = createTrackHandler(f.deps);
      for (let i = 0; i < 2; i++) {
        const response = await handler(
          request(Array.from({ length: 50 }, () => event()), {
            headers: { "user-agent": "Googlebot/2.1" },
          }),
        );
        assertEquals(response.status, 200);
        assertEquals(await response.json(), { ok: true, inserted: 0 });
      }
      assertEquals(calls, 1);
      assertEquals(f.writes, []);
    }
  }));

Deno.test("track delivery — browser identity survives and invalid IDs use the real daily IP hash", async () => {
  const f = fake();
  const response = await createTrackHandler(f.deps)(request([
    event({ anonymous_id: "browser-id-12345678" }),
    event({ anonymous_id: "invalid identity!" }),
    event(),
  ]));
  assertEquals(response.status, 200);
  assertEquals(f.writes[0].map((row) => row.anonymous_id), [
    "browser-id-12345678",
    "5fb45ac536b6631dd40cf5372386ed71",
    "5fb45ac536b6631dd40cf5372386ed71",
  ]);
});

Deno.test("track delivery — hashing before midnight and row time after midnight stay distinct", async () => {
  const f = fake();
  const before = "2026-11-03T23:59:59.999Z";
  const after = "2026-11-04T00:00:00.000Z";
  let times = [before];
  f.deps.now = () => new Date(times.shift() ?? after);
  const handler = createTrackHandler(f.deps);
  times = [before, after];
  await handler(request(event({ occurred_at: null })));
  assertEquals(f.writes[0][0].anonymous_id, "492298a35bdf33671f79062b89fa7857");
  assertEquals(f.writes[0][0].received_at, after);
  assertEquals(f.writes[0][0].occurred_at, after);
  assertEquals(times, []);
});

Deno.test("track delivery — real row builder still normalizes paths, timestamps and engagement", async () => {
  const f = fake();
  await createTrackHandler(f.deps)(request([
    event({
      name: "engagement_tick",
      path: "/caf%C3%A9/",
      url: `${ORIGIN}/caf%C3%A9/?utm_source=google&unrelated=discard#fragment`,
      title: "Unused title",
      occurred_at: "2026-10-01T00:00:00.000Z",
      props: { active_ms: 90000 },
    }),
    event({
      name: "click_internal",
      props: { target_path: "/caf%C3%A9/" },
      url: "https://outremer.jplouton-avocat.fr/ressources",
    }),
  ]));
  const [engagement, internal] = f.writes[0];
  assertEquals(engagement.path, "/café");
  assertEquals(engagement.url, `${ORIGIN}/caf%C3%A9/?utm_source=google`);
  assertEquals(engagement.title, null);
  assertEquals(engagement.occurred_at, NOW);
  assertEquals(engagement.received_at, NOW);
  assertEquals(engagement.props, { active_ms: 60000, clock_clamped: true });
  assertEquals([engagement.device_type, engagement.os, engagement.browser], [
    "mobile",
    "iOS",
    "Safari",
  ]);
  assertEquals(internal.props, {
    target_path: "/café",
    cooked_site: "outremer",
  });
});

Deno.test("track delivery — acknowledgement waits for the event insert to finish", async () => {
  const f = fake();
  let started!: () => void;
  const writeStarted = new Promise<void>((resolve) => started = resolve);
  let complete!: (result: { error: null }) => void;
  f.deps.insertEvents = () => {
    started();
    return new Promise<{ error: null }>((resolve) => complete = resolve);
  };
  let acknowledged = false;
  const response = createTrackHandler(f.deps)(request()).then((result) => {
    acknowledged = true;
    return result;
  });
  await writeStarted;
  assertEquals(acknowledged, false);
  complete({ error: null });
  assertEquals(await (await response).json(), { ok: true, inserted: 1 });
});

Deno.test("track delivery — insert errors keep the existing 500 response or thrown rejection without retries", () =>
  quiet(async () => {
    const f = fake();
    let calls = 0;
    f.deps.insertEvents = () => {
      calls++;
      return Promise.resolve({ error: { message: "synthetic insert error" } });
    };
    const response = await createTrackHandler(f.deps)(request());
    assertEquals(response.status, 500);
    assertEquals(await response.json(), {
      ok: false,
      error: "synthetic insert error",
    });
    assertEquals(calls, 1);
    f.deps.insertEvents = () => {
      calls++;
      return Promise.reject(new Error("synthetic connection failure"));
    };
    await assertRejects(
      () => createTrackHandler(f.deps)(request()),
      Error,
      "synthetic connection failure",
    );
    assertEquals(calls, 2);
  }));
