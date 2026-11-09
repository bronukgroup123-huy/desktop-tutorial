// ============================================================================
// Edge Function: v1-forest-zones (BACKEND_PLAN B1.2, ADR-015 §15.2)
// GET /functions/v1/v1-forest-zones?bbox=minLng,minLat,maxLng,maxLat&z=10&limit=5000
//
// JWT обов'язковий. Полігони лісів ТІЛЬКИ в межах Home Region користувача.
// Відповідь: { data: FeatureCollection } з type_label / type_color у properties.
// ============================================================================

import { handle, serviceClient, supabaseTokenVerifier } from "../_shared/http.ts";
import { handleForestZones } from "../_shared/v1/forest-zones.ts";

Deno.serve(handle((req) =>
  handleForestZones(req, { db: serviceClient(), verify: supabaseTokenVerifier })
));
