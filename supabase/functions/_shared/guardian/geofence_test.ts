import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { detectForestExit } from "./geofence.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.test("detectForestExit — empty track → no exit", async () => {
  const db = createClient("http://localhost:54321", "service-key");
  const result = await detectForestExit(db, "fake-session");
  assertEquals(result.isOutsideForest, false);
  assertEquals(result.isConfirmedExit, false);
  assertEquals(result.consecutiveOutsideCount, 0);
});
