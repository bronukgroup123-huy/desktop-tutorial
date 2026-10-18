// ============================================================================
// Edge Function: me (group 9.5)
// GET   /me → профіль поточного користувача
// PATCH /me → онбординг (name, home_region_slug)
//   204 OPTIONS | 401 auth | 405 method | 400 invalid_* | 404 me_not_found /
//   region_not_found | 200 {data: profile}
// Логіка — у _shared/forecast/me-endpoint.ts (pure, тестована).
// ============================================================================

import { buildCorsHeaders } from "../_shared/cors.ts";
import { requireMushroomPicker } from "../_shared/guardian/auth.ts";
import { withErrorHandling } from "../_shared/guardian/errors.ts";
import { handleMeRequest } from "../_shared/forecast/me-endpoint.ts";
import type { MeDbClient } from "../_shared/forecast/me-endpoint.ts";

Deno.serve(
  withErrorHandling(async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
    }

    // JWT обов'язковий → { userId, db (service_role) }
    const { userId, db } = await requireMushroomPicker(req);

    return handleMeRequest(db as unknown as MeDbClient, userId, req);
  })
);
