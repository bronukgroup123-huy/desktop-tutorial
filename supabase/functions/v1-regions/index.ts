// ============================================================================
// Edge Function: v1-regions (BACKEND_PLAN B1.1)
// GET /functions/v1/v1-regions/{slug}/geometry?detail=low|medium|high
//
// Публічний, з rate limit і ETag. Кордон області для маски «острова».
// ============================================================================

import { handle, serviceClient } from "../_shared/http.ts";
import { handleRegionGeometry } from "../_shared/v1/regions.ts";

Deno.serve(handle((req) =>
  handleRegionGeometry(req, {
    db: serviceClient(),
    forestsBaseUrl: Deno.env.get("FORESTS_BASE_URL") ?? undefined,
    basemapBaseUrl: Deno.env.get("BASEMAP_BASE_URL") ?? undefined,
  })
));
