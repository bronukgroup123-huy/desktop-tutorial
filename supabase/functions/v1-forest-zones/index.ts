// ============================================================================
// Edge Function: v1-forest-zones (Tier 2, Step 1)
// GET /v1/forest-zones?bbox=minLng,minLat,maxLng,maxLat&limit=5000
// Returns GeoJSON FeatureCollection of forest zones within bbox.
// 204 OPTIONS | 405 non-GET | 400 invalid_bbox | 200 FeatureCollection | 500 rpc_error
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { z } from "npm:zod@3";
import { buildCorsHeaders } from "../_shared/cors.ts";

const BBoxSchema = z.object({
  bbox: z.string().regex(/^-?\d+(\.\d+)?,-?\d+(\.\d+)?,-?\d+(\.\d+)?,-?\d+(\.\d+)?$/),
  limit: z.coerce.number().int().positive().max(10000).default(5000),
});

function parseBBox(bboxStr: string): [number, number, number, number] | null {
  const parts = bboxStr.split(",").map((p) => Number.parseFloat(p));
  if (parts.length !== 4 || parts.some((p) => Number.isNaN(p))) return null;
  const [minLng, minLat, maxLng, maxLat] = parts;
  if (minLng >= maxLng || minLat >= maxLat) return null;
  if (minLng < -180 || maxLng > 180 || minLat < -90 || maxLat > 90) return null;
  return [minLng, minLat, maxLng, maxLat];
}

function errorResponse(message: string, status: number, req: Request): Response {
  return new Response(JSON.stringify({ error: true, message }), {
    status,
    headers: { "Content-Type": "application/json", ...buildCorsHeaders(req) },
  });
}

Deno.serve(async (req: Request) => {
  // 1. CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: buildCorsHeaders(req) });
  }

  // 2. Method check
  if (req.method !== "GET") {
    return errorResponse("Method not allowed", 405, req);
  }

  // 3. Parse and validate query params
  const url = new URL(req.url);
  const queryParams = Object.fromEntries(url.searchParams.entries());

  const parseResult = BBoxSchema.safeParse(queryParams);
  if (!parseResult.success) {
    return errorResponse("Invalid bbox format. Expected: minLng,minLat,maxLng,maxLat", 400, req);
  }

  const { bbox, limit } = parseResult.data;
  const parsed = parseBBox(bbox);
  if (!parsed) {
    return errorResponse("Invalid bbox values. minLng < maxLng, minLat < maxLat, lng [-180,180], lat [-90,90]", 400, req);
  }

  const [minLng, minLat, maxLng, maxLat] = parsed;

  // 4. Supabase client with service role (RLS applied via SECURITY INVOKER on RPC)
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return errorResponse("Internal server configuration error", 500, req);
  }

  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  // 5. Call RPC
  const { data, error } = await supabase.rpc("get_forest_zones_geojson", {
    min_lng: minLng,
    min_lat: minLat,
    max_lng: maxLng,
    max_lat: maxLat,
    max_features: limit,
  });

  if (error) {
    console.error("RPC error:", error.message);
    return errorResponse("Failed to fetch forest zones", 500, req);
  }

  // 6. Log bbox size and feature count (no PII)
  const bboxArea = (maxLng - minLng) * (maxLat - minLat);
  const featureCount = Array.isArray(data?.features) ? data.features.length : 0;
  console.log(`bbox_area=${bboxArea.toFixed(6)} features=${featureCount} limit=${limit}`);

  // 7. Return GeoJSON FeatureCollection
  return new Response(JSON.stringify(data ?? { type: "FeatureCollection", features: [] }), {
    status: 200,
    headers: { "Content-Type": "application/geo+json", ...buildCorsHeaders(req) },
  });
});