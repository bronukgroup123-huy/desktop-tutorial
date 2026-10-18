// ============================================================================
// Edge Function: regions (group 9.2)
// GET / — публічний список областей для Flutter Home Region dropdown.
//   204 OPTIONS | 405 non-GET | 200 {data: [...]} | 500 db_error
// Логіка — у _shared/forecast/regions-endpoint.ts (pure, тестована).
// service_role-клієнт обходить RLS (regions_read — тільки authenticated).
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { handleRegionsRequest } from "../_shared/forecast/regions-endpoint.ts";
import { checkAndIncrementIpRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts";

Deno.serve(async (req: Request) => {
  // 1. CT-14: Rate limit per-IP (60 req/min for /regions)
  const ip = getClientIp(req);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return new Response(JSON.stringify({ error: "internal_error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
  const db = createClient(url, serviceKey, { auth: { persistSession: false } });

  const rl = await checkAndIncrementIpRateLimit(db, ip, "regions");
  if (!rl.allowed) {
    return rateLimitResponse(req, rl.retryAfter ?? 60);
  }

  return handleRegionsRequest(db, req);
});
