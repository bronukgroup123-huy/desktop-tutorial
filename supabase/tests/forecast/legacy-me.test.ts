import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { createMeHandler } from "../../functions/me/handler.ts";

function makeHandler() {
  const calls = { auth: 0, get: 0 };
  const handler = createMeHandler({
    getUserId: () => { calls.auth++; return Promise.resolve("u1"); },
    handleGet: () => { calls.get++; return Promise.resolve(new Response("{}", { status: 200 })); },
  });
  return { handler, calls };
}

Deno.test("legacy me: DELETE вимкнено → 405 ще до автентифікації", async () => {
  const { handler, calls } = makeHandler();
  const res = await handler(new Request("http://localhost/me", {
    method: "DELETE",
    headers: { Authorization: "Bearer valid-token" },
  }));
  assertEquals(res.status, 405);
  assertEquals((await res.json()).error, "method_not_allowed");
  assertEquals(res.headers.get("Allow"), "GET, OPTIONS");
  assertEquals(calls.auth, 0);
  assertEquals(calls.get, 0);
});

Deno.test("legacy me: PATCH / POST / PUT → 405", async () => {
  const { handler } = makeHandler();
  for (const method of ["PATCH", "POST", "PUT"]) {
    const res = await handler(new Request("http://localhost/me", { method, body: "{}" }));
    assertEquals(res.status, 405, method);
    await res.body?.cancel();
  }
});

Deno.test("legacy me: GET працює (експорт власних даних)", async () => {
  const { handler, calls } = makeHandler();
  const res = await handler(new Request("http://localhost/me", { method: "GET" }));
  assertEquals(res.status, 200);
  assertEquals(calls.auth, 1);
  assertEquals(calls.get, 1);
  await res.body?.cancel();
});

Deno.test("legacy me: OPTIONS → 204", async () => {
  const { handler } = makeHandler();
  assertEquals((await handler(new Request("http://localhost/me", { method: "OPTIONS" }))).status, 204);
});
