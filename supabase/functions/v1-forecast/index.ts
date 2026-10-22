// ============================================================================
// Edge Function: v1-forecast (Tier 2, Step 2)
// POST /v1/forecast
// Body: { lat, lng, date (YYYY-MM-DD), forestType? }
// Returns forecast with shaped labels/colors for Flutter client.
// 204 OPTIONS | 405 non-POST | 400 invalid_body | 200 {top1, alternative, ...} | 500
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import { z } from "npm:zod@3";
import { ForecastEngine } from "../_shared/forecast/engine.ts";
import { loadFeatureFlags } from "../_shared/forecast/flags.ts";
import { buildCorsHeaders } from "../_shared/cors.ts";
import type { ForecastInput, ScoredSpecies, ForecastResult } from "../_shared/forecast/types.ts";

const ForecastInputSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  forestType: z.string().optional(),
});

type ProbabilityLevel = "no_data" | "low" | "medium" | "high" | "peak";

const LEVEL_LABEL: Record<ProbabilityLevel, string> = {
  peak: "Пікова ймовірність",
  high: "Висока ймовірність",
  medium: "Середня ймовірність",
  low: "Низька ймовірність",
  no_data: "Недостатньо даних",
};

const LEVEL_COLOR: Record<ProbabilityLevel, string> = {
  peak: "#10b981",
  high: "#22c55e",
  medium: "#eab308",
  low: "#f97316",
  no_data: "#94a3b8",
};

function normalizeProbability(p: string): ProbabilityLevel {
  switch (p) {
    case "peak":
    case "high":
    case "medium":
    case "low":
    case "no_data":
      return p;
    default:
      return "no_data";
  }
}

function shapeSpecies(s: ScoredSpecies | null): unknown {
  if (!s) return null;

  const level: ProbabilityLevel = normalizeProbability(s.probability);

  return {
    mushroom_type: s.mushroom_type,
    name_ua: s.name_ua,
    score: s.score,
    probability: s.probability,
    level_label: LEVEL_LABEL[level],
    level_color: LEVEL_COLOR[level],
    when_label: s.wave ? `Хвиля: ${s.wave}` : "Весь сезон",
    where_label: s.where ?? "Ліс",
    why_labels: s.matched,
    matched: s.matched,
    missed: s.missed,
  };
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
  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405, req);
  }

  // 3. Parse and validate body
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("Invalid JSON body", 400, req);
  }

  const parseResult = ForecastInputSchema.safeParse(body);
  if (!parseResult.success) {
    return errorResponse("Invalid request body", 400, req);
  }

  const { lat, lng, date, forestType } = parseResult.data;

  // 4. Supabase service-role client
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return errorResponse("Internal server configuration error", 500, req);
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // 5. Feature flags
  const config = await loadFeatureFlags(supabase as unknown as Parameters<
    typeof loadFeatureFlags
  >[0]);

  // 6. ForecastInput
  const input: ForecastInput = {
    lat,
    lng,
    date: new Date(date + "T00:00:00Z"),
    forestType: (forestType ?? null) as any,
    forestConfirmed: forestType !== undefined && forestType !== "",
    homeRegionId: null,
  };

  // 7. Forecast engine call
  const startTime = Date.now();
  const result = await ForecastEngine.forecast(
    input,
    supabase as unknown as Parameters<typeof ForecastEngine.forecast>[1],
    config,
  );
  const durationMs = Date.now() - startTime;

  const candidateCount = (result.top1 ? 1 : 0) + (result.alternative ? 1 : 0);

  // 8. Log only count and duration — no PII, no coordinates
  console.log(`forecast candidates=${candidateCount} duration_ms=${durationMs}`);

  // 9. Shape response
  const response: Record<string, unknown> = {
    regionName: result.regionName,
    date: result.date,
    forest: result.forest,
    top1: shapeSpecies(result.top1),
    alternative: shapeSpecies(result.alternative),
    warnings: result.warnings,
  };
  if (result.noDataReason) {
    response.noDataReason = result.noDataReason;
  }

  // 10. Return
  return new Response(JSON.stringify(response), {
    status: 200,
    headers: { "Content-Type": "application/json", ...buildCorsHeaders(req) },
  });
});
