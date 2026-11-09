import { assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  assertRegistered,
  bearerToken,
  handle,
  HttpError,
  requireHomeRegion,
  requireUser,
} from "../../functions/_shared/http.ts";
import { verifyAs, verifyNone } from "./mock-db.ts";

Deno.test("http: HttpError → { error, message } з тим самим статусом", async () => {
  const h = handle(() => Promise.reject(new HttpError(403, "outside_home_region", "Поза областю")));
  const res = await h(new Request("http://x/v1", { method: "GET" }));
  assertEquals(res.status, 403);
  assertEquals(await res.json(), { error: "outside_home_region", message: "Поза областю" });
});

Deno.test("http: HttpError без повідомлення → тільки { error }", async () => {
  const h = handle(() => Promise.reject(new HttpError(400, "invalid_bbox")));
  const res = await h(new Request("http://x/v1"));
  assertEquals(await res.json(), { error: "invalid_bbox" });
});

Deno.test("http: непередбачена помилка → 500 internal_error без деталей", async () => {
  const h = handle(() => Promise.reject(new Error("secret stack")));
  const res = await h(new Request("http://x/v1"));
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, "internal_error");
  assertEquals(JSON.stringify(body).includes("secret"), false);
});

Deno.test("http: OPTIONS → 204 до виклику обробника", async () => {
  let called = false;
  const h = handle(() => { called = true; return Promise.resolve(new Response()); });
  const res = await h(new Request("http://x/v1", { method: "OPTIONS" }));
  assertEquals(res.status, 204);
  assertEquals(called, false);
});

Deno.test("http: 429 передає Retry-After", async () => {
  const h = handle(() => Promise.reject(new HttpError(429, "rate_limited", "Зачекайте", { "Retry-After": "60" })));
  const res = await h(new Request("http://x/v1"));
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("Retry-After"), "60");
});

Deno.test("http: bearerToken", () => {
  assertEquals(bearerToken(new Request("http://x", { headers: { Authorization: "Bearer abc" } })), "abc");
  assertEquals(bearerToken(new Request("http://x", { headers: { Authorization: "Basic abc" } })), null);
  assertEquals(bearerToken(new Request("http://x")), null);
});

Deno.test("http: requireUser без токена → 401", async () => {
  const err = await assertRejects(() => requireUser(new Request("http://x"), verifyAs("u1")), HttpError);
  assertEquals(err.status, 401);
});

Deno.test("http: requireUser з недійсним токеном → 401", async () => {
  const r = new Request("http://x", { headers: { Authorization: "Bearer bad" } });
  const err = await assertRejects(() => requireUser(r, verifyNone), HttpError);
  assertEquals(err.code, "unauthorized");
});

Deno.test("http: гість → 403 registration_required (ADR-001)", () => {
  const err = assertThrows(() => assertRegistered({ id: "g", isAnonymous: true }), HttpError);
  assertEquals(err.status, 403);
  assertEquals(err.code, "registration_required");
  assertRegistered({ id: "u", isAnonymous: false }); // не кидає
});

Deno.test("http: без Home Region → 409 home_region_required", () => {
  const err = assertThrows(() => requireHomeRegion(null), HttpError);
  assertEquals(err.status, 409);
  assertEquals(requireHomeRegion(7), 7);
});
