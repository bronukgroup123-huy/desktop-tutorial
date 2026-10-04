import {
  assertEquals,
  assert,
  assertNotEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  generateGuardianToken,
  validateGuardianToken,
  hashToken,
} from "./token.ts";

Deno.env.set("GUARDIAN_JWT_SECRET", "a".repeat(64));

Deno.test("generateGuardianToken — повертає валідний JWT", async () => {
  const result = await generateGuardianToken("session-123", "guardian-456");
  assert(result.token.length > 100);
  assert(result.tokenHash.length === 64);
  assert(result.tokenPrefix.length === 8);
  assert(result.expiresAt > new Date());
});

Deno.test("validateGuardianToken — валідний токен проходить", async () => {
  const { token } = await generateGuardianToken("s1", "g1");
  const result = await validateGuardianToken(token);
  assert(result.valid);
  assertEquals(result.payload?.session_id, "s1");
  assertEquals(result.payload?.guardian_id, "g1");
  assertEquals(result.payload?.role, "guardian");
});

Deno.test("validateGuardianToken — підроблений токен не проходить", async () => {
  const result = await validateGuardianToken("fake.token.here");
  assert(!result.valid);
});

Deno.test("validateGuardianToken — токен з іншим секретом не проходить", async () => {
  const { token } = await generateGuardianToken("s1", "g1");
  Deno.env.set("GUARDIAN_JWT_SECRET", "b".repeat(64));
  const result = await validateGuardianToken(token);
  assert(!result.valid);
  Deno.env.set("GUARDIAN_JWT_SECRET", "a".repeat(64));
});

Deno.test("hashToken — детермінований", async () => {
  const h1 = await hashToken("test");
  const h2 = await hashToken("test");
  assertEquals(h1, h2);
  assertNotEquals(h1, await hashToken("test2"));
});
