// ============================================================================
// Edge Function: catalog (group 9.3)
// GET / — довідник 326 видів грибів для Flutter.
//   204 OPTIONS | 405 non-GET | 400 invalid_* | 200 {data,total,limit,offset} | 500 db_error
// Логіка — у _shared/forecast/catalog-endpoint.ts (pure, тестована).
// service_role-клієнт обходить RLS (catalog_read — тільки authenticated).
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { handleCatalogRequest } from "../_shared/forecast/catalog-endpoint.ts";
import { checkAndIncrementIpRateLimit, getClientIp, rateLimitResponse } from "../_shared/rate-limit.ts";

Deno.serve(async (req: Request) => {
  // 1. CT-14: Rate limit per-IP (60 req/min for /catalog)
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

  const rl = await checkAndIncrementIpRateLimit(db, ip, "catalog");
  if (!rl.allowed) {
    return rateLimitResponse(req, rl.retryAfter ?? 60);
  }

  return handleCatalogRequest(db, req);
});
