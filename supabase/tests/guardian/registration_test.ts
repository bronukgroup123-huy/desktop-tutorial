import { assertEquals, assertThrows } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { assertRegisteredPicker } from "../../functions/_shared/guardian/auth.ts";
import { AppError } from "../../functions/_shared/guardian/errors.ts";

// deno-lint-ignore no-explicit-any
const fakeDb = {} as any;

Deno.test("guardian: гість не може створити сесію / SOS → 403 registration_required (ADR-001)", () => {
  const err = assertThrows(() => assertRegisteredPicker({ userId: "g", db: fakeDb, isAnonymous: true }), AppError);
  assertEquals(err.status, 403);
  assertEquals(err.code, "registration_required");
});

Deno.test("guardian: зареєстрований користувач проходить перевірку", () => {
  assertRegisteredPicker({ userId: "u", db: fakeDb, isAnonymous: false });
});
