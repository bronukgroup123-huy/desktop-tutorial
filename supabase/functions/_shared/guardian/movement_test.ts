import { assertEquals, assert } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { analyzeMovement } from "./movement.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.test("analyzeMovement — no last_known_at → hasFreshData=false", async () => {
  const db = createClient("http://localhost:54321", "service-key");
  const result = await analyzeMovement(db, "fake-session", null);
  assertEquals(result.hasFreshData, false);
  assertEquals(result.isMoving, false);
  assertEquals(result.secondsSinceLastPing, null);
});

Deno.test("analyzeMovement — stale data → hasFreshData=false", async () => {
  const db = createClient("http://localhost:54321", "service-key");
  const oldTime = new Date(Date.now() - 30 * 60 * 1000).toISOString();
  const result = await analyzeMovement(db, "fake-session", oldTime);
  assertEquals(result.hasFreshData, false);
  assert(result.secondsSinceLastPing! > 15 * 60);
});
