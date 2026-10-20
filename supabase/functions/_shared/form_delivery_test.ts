import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createFormWebhookHandler,
  type FormDeliveryDependencies,
} from "./form_delivery.ts";

const SECRET = "synthetic-test-secret";
const SUBMISSION = "00000000-0000-4000-8000-000000000001";
const IDENTITY = "synthetic-prospect@example.invalid";
const payload = () => ({
  data: {
    submissionId: SUBMISSION,
    formName: "Test form",
    submissionTime: "2026-10-20T08:00:00.000Z",
    "field:objet_de_ma_demande": "Droit de la famille",
    "field:email": IDENTITY,
    "field:message": "Synthetic free text must not be persisted",
    "field:page_source": "/honoraires-rendez-vous",
  },
});

function request(body: unknown = payload(), token = SECRET): Request {
  return new Request(`https://example.invalid/form-webhook?token=${token}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function fake() {
  const events = new Map<string, unknown>();
  const prospects = new Map<string, unknown>();
  const alerts: string[] = [];
  const logs: string[] = [];
  const calls: string[] = [];
  const deps: FormDeliveryDependencies = {
    secret: SECRET,
    insertEvent(row) {
      calls.push("events");
      const id = (row.props as Record<string, unknown>).submission_id as string;
      const duplicate = events.has(id);
      if (!duplicate) events.set(id, row);
      return Promise.resolve({
        error: duplicate ? { code: "23505" } : null,
      });
    },
    insertProspect(row) {
      calls.push("crm");
      const id = row.wix_submission_id as string;
      const duplicate = prospects.has(id);
      if (!duplicate) prospects.set(id, row);
      return Promise.resolve({
        error: duplicate ? { code: "23505" } : null,
      });
    },
    raiseAlert(detail) {
      alerts.push(detail);
      return Promise.resolve({ error: null });
    },
    log(message) {
      logs.push(message);
    },
  };
  return { deps, events, prospects, alerts, logs, calls };
}

Deno.test("delivery — successful retry produces one analytics event and one confined prospect", async () => {
  const f = fake();
  const handler = createFormWebhookHandler(f.deps);
  const first = await handler(request());
  const second = await handler(request());
  assertEquals(first.status, 200);
  assertEquals(await second.json(), {
    ok: true,
    form_id: "Test form",
    submission_id: SUBMISSION,
    dedup: true,
  });
  assertEquals(f.events.size, 1);
  assertEquals(f.prospects.size, 1);
  assertEquals(f.calls, ["crm", "events", "crm", "events"]);
  assert(!JSON.stringify([...f.events.values()]).includes(IDENTITY));
  assert(!JSON.stringify([...f.events.values()]).includes("Synthetic free text"));
  assert(JSON.stringify([...f.prospects.values()]).includes(IDENTITY));
  assertEquals(f.alerts, []);
});

Deno.test("delivery — transient event failure returns 503, next request repairs only missing data", async () => {
  const f = fake();
  const insert = f.deps.insertEvent;
  let fail = true;
  f.deps.insertEvent = (row) => fail
    ? Promise.resolve({ error: { code: "08006", message: IDENTITY } })
    : insert(row);
  const handler = createFormWebhookHandler(f.deps);
  const failed = await handler(request());
  assertEquals(failed.status, 503);
  assertEquals(failed.headers.get("retry-after"), "60");
  assertEquals(await failed.json(), {
    ok: false,
    error: "delivery_incomplete",
  });
  assertEquals(f.events.size, 0);
  assertEquals(f.prospects.size, 1);
  fail = false;
  assertEquals((await handler(request())).status, 200);
  assertEquals(f.events.size, 1);
  assertEquals(f.prospects.size, 1);
  assert(f.alerts[0].includes("stage=events, code=08006"));
  assert(!JSON.stringify([f.alerts, f.logs]).includes(IDENTITY));
});

Deno.test("delivery — CRM failure remains retriable even when analytics event is already stored", async () => {
  const f = fake();
  const insert = f.deps.insertProspect;
  let fail = true;
  f.deps.insertProspect = (row) => fail
    ? Promise.resolve({ error: { code: "23514" } })
    : insert(row);
  const handler = createFormWebhookHandler(f.deps);
  assertEquals((await handler(request())).status, 503);
  assertEquals(f.events.size, 1);
  assertEquals(f.prospects.size, 0);
  fail = false;
  const repaired = await handler(request());
  assertEquals(repaired.status, 200);
  assertEquals((await repaired.json()).dedup, true);
  assertEquals(f.events.size, 1);
  assertEquals(f.prospects.size, 1);
  assert(f.alerts[0].includes("stage=crm_prospects"));
});

Deno.test("delivery — response lost after database commit is repaired without duplicate contacts", async () => {
  const f = fake();
  const insert = f.deps.insertEvent;
  let fail = true;
  f.deps.insertEvent = async (row) => {
    const result = await insert(row);
    if (fail) throw new Error(`network response lost ${IDENTITY}`);
    return result;
  };
  const handler = createFormWebhookHandler(f.deps);
  assertEquals((await handler(request())).status, 503);
  assertEquals(f.events.size, 1);
  fail = false;
  const retry = await handler(request());
  assertEquals(retry.status, 200);
  assertEquals((await retry.json()).dedup, true);
  assertEquals(f.events.size, 1);
  assert(!JSON.stringify([f.alerts, f.logs]).includes(IDENTITY));
});

Deno.test("delivery — an unavailable alert channel cannot turn database failure into success", async () => {
  const f = fake();
  f.deps.insertEvent = () => Promise.reject(new Error(IDENTITY));
  f.deps.raiseAlert = () => Promise.reject(new Error(IDENTITY));
  const response = await createFormWebhookHandler(f.deps)(request());
  assertEquals(response.status, 503);
  assert(f.logs.some((line) => line.endsWith("alert unavailable")));
  assert(!JSON.stringify(f.logs).includes(IDENTITY));
});

Deno.test("delivery — invalid/missing IDs reject before any durable write", async () => {
  for (const id of [undefined, null, "", " ", {}, 123, "x".repeat(201), "a\nb"]) {
    const f = fake();
    const body = { data: { ...payload().data, submissionId: id } };
    const response = await createFormWebhookHandler(f.deps)(request(body));
    assertEquals(response.status, 400);
    assertEquals(await response.json(), {
      ok: false,
      error: "invalid_submission_id",
    });
    assertEquals(f.calls, []);
    assertEquals(f.alerts.length, 1);
  }
});

Deno.test("delivery — top-level Wix payload keeps its stable submission ID", async () => {
  const f = fake();
  assertEquals(
    (await createFormWebhookHandler(f.deps)(request(payload().data))).status,
    200,
  );
  assertEquals(f.events.size, 1);
  assert(f.events.has(SUBMISSION));
});

Deno.test("delivery — no extracted identity requires only analytics acknowledgement", async () => {
  const f = fake();
  const { "field:email": _email, ...data } = payload().data;
  assertEquals(
    (await createFormWebhookHandler(f.deps)(request({ data }))).status,
    200,
  );
  assertEquals(f.calls, ["events"]);
  assertEquals(f.prospects.size, 0);
});

Deno.test("delivery — error codes are bounded, never reflected messages or identities", async () => {
  const f = fake();
  f.deps.insertEvent = () =>
    Promise.resolve({ error: { code: IDENTITY, message: IDENTITY } });
  const response = await createFormWebhookHandler(f.deps)(request());
  assertEquals(response.status, 503);
  assert(f.alerts[0].includes("code=unknown"));
  assert(!JSON.stringify([f.logs, f.alerts]).includes(IDENTITY));
});

Deno.test("delivery — builder diagnostics never print arbitrary hostnames or field labels", async () => {
  const f = fake();
  const logs: string[] = [];
  const originalLog = console.log;
  const originalWarn = console.warn;
  try {
    console.log = (...args: unknown[]) => logs.push(args.join(" "));
    console.warn = (...args: unknown[]) => logs.push(args.join(" "));
    const response = await createFormWebhookHandler(f.deps)(request({
      data: {
        submissionId: SUBMISSION,
        "field:page_source": "https://synthetic-private-name.invalid/",
        [`field:${IDENTITY}`]: "not a recognised identity",
      },
    }));
    assertEquals(response.status, 200);
    assertEquals(logs.length, 2);
    assert(!logs.join().includes(IDENTITY));
    assert(!logs.join().includes("synthetic-private-name"));
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
  }
});

Deno.test("delivery — auth/method/JSON validation precedes delivery", async () => {
  const f = fake();
  const handler = createFormWebhookHandler(f.deps);
  assertEquals((await handler(new Request("https://example.invalid"))).status, 405);
  assertEquals((await handler(request(payload(), "wrong"))).status, 401);
  assertEquals(
    (await handler(new Request(`https://example.invalid?token=${SECRET}`, {
      method: "POST",
      body: "{invalid",
    }))).status,
    400,
  );
  assertEquals(f.calls, []);
  assertEquals(f.alerts, []);
  assertThrows(() => createFormWebhookHandler({ ...f.deps, secret: "" }));
});
