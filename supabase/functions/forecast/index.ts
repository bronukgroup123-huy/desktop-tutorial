// ============================================================================
// Edge Function: forecast (group 8.6c)
// POST / — повний прогноз: RegionGuard → context → score → alternatives.
// Сиблінг: forecast-weather (8.2). Engine: _shared/forecast/engine.ts (8.6b).
//
// Поріг відповідей (§15.1):
//   400 — invalid_json / invalid_coordinates / invalid_date
//   403 — outside_home_region (RegionGuard hard-fail)
//   405 — не POST
//   500 — internal_error
//   200 — ForecastResult (fallback та weather-unavailable — graceful, узгоджено 8.2)
// ============================================================================

import { buildCorsHeaders } from "../_shared/cors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ForecastEngine } from "../_shared/forecast/engine.ts";
import { loadFeatureFlags } from "../_shared/forecast/flags.ts";
import { validateInput } from "../_shared/forecast/validate.ts";
import type { ForecastDbClient } from "../_shared/forecast/context.ts";
import type { DbClient } from "../_shared/forecast/db.ts";

function json(data: unknown, status: number, req: Request): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...buildCorsHeaders(req), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  // 1. CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
  }

  // 2. Тільки POST
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405, req);
  }

  // 3. Парсинг body
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400, req);
  }

  // 4. Валідація
  const validated = validateInput(body);
  if (!validated.ok) {
    return json(
      { error: validated.error, message: validated.message },
      validated.status,
      req,
    );
  }

  // 5. Клієнт — service_role для читання expert_rules / regions (RLS)
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    console.error("forecast: missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");
    return json({ error: "internal_error", message: "server_misconfigured" }, 500, req);
  }
  // SupabaseClient satisfies both at runtime; structural mismatch at type level only
  const db = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  }) as unknown as ForecastDbClient & DbClient;

  // 6. Config + Engine
  try {
    const config = await loadFeatureFlags(db);
    const result = await ForecastEngine.forecast(validated.input, db, config);

    // 7. Мапінг noDataReason → HTTP статус
    if (result.noDataReason === "outside_home_region") {
      return json(
        {
          error: "outside_home_region",
          message: "Ви поза вашою областю. Прогноз обмежено.",
        },
        403,
        req,
      );
    }

    return json(result, 200, req);
  } catch (err) {
    console.error("forecast error:", err);
    return json(
      {
        error: "internal_error",
        message: err instanceof Error ? err.message : "unknown",
      },
      500,
      req,
    );
  }
});
