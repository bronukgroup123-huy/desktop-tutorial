// ============================================================================
// Edge Function: v1-heatmap — теплова карта знахідок (ADR-010; BACKEND_PLAN B3.5)
// GET /functions/v1/v1-heatmap — логіка в `_shared/v1/heatmap.ts`, доступ — SQL `heatmap_cells`.
// ============================================================================

import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleHeatmap } from "../_shared/v1/heatmap.ts";

Deno.serve(handle((req) => handleHeatmap(req, { db: serviceClient(), verify: supabaseTokenVerifier })));
