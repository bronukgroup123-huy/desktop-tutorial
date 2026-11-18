// ============================================================================
// Edge Function: v1-air-alerts (BACKEND_PLAN B4.12, ADR-022 §22.5 п.5)
// GET /functions/v1/v1-air-alerts
//
// Повітряна тривога по областях з alerts.in.ua (секрет ALERTS_IN_UA_TOKEN). Без ключа —
// `available: false` (застосунок банер не показує). Публічний.
// ============================================================================

import { handle, serviceClient } from "../_shared/http.ts";
import { handleAirAlerts } from "../_shared/v1/air-alerts.ts";

Deno.serve(handle((req) =>
  handleAirAlerts(req, { db: serviceClient(), token: Deno.env.get("ALERTS_IN_UA_TOKEN") ?? undefined })
));
