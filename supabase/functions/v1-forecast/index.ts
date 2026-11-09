// ============================================================================
// Edge Function: v1-forecast (BACKEND_PLAN B2.1)
// POST /functions/v1/v1-forecast   Body: { lat, lng, date (YYYY-MM-DD), forestType? }
//
// JWT обов'язковий (гість має JWT — ADR-001). Прогноз лише в межах Home Region.
// Відповідь: { data: { regionName, date, forest, top1, alternative, warnings, noDataReason? } }
// — без числових ймовірностей (маніфест, Заборона №1).
// ============================================================================

import { ForecastEngine } from "../_shared/forecast/engine.ts";
import { loadFeatureFlags } from "../_shared/forecast/flags.ts";
import type { ForecastInput } from "../_shared/forecast/types.ts";
import {
  assertMethod,
  enforceRateLimit,
  handle,
  loadHomeRegionId,
  ok,
  readJson,
  requireHomeRegion,
  requireUser,
  serviceClient,
  supabaseTokenVerifier,
} from "../_shared/http.ts";
import {
  assertPointInHomeRegion,
  parseForecastBody,
  shapeSpecies,
} from "../_shared/v1/forecast.ts";
import { forestLabel, weatherBlock } from "../_shared/v1/forecast-labels.ts";

Deno.serve(handle(async (req) => {
  assertMethod(req, ["POST"]);
  const db = serviceClient();
  await enforceRateLimit(db, req, "v1-forecast");

  const user = await requireUser(req, supabaseTokenVerifier);
  const body = parseForecastBody(await readJson(req));
  const regionId = requireHomeRegion(await loadHomeRegionId(db, user.id));
  await assertPointInHomeRegion(db, body.lat, body.lng, regionId);

  const config = await loadFeatureFlags(db as unknown as Parameters<typeof loadFeatureFlags>[0]);
  const input: ForecastInput = {
    lat: body.lat,
    lng: body.lng,
    date: new Date(body.date + "T00:00:00Z"),
    forestType: (body.forestType ?? null) as ForecastInput["forestType"],
    forestConfirmed: body.forestType !== undefined && body.forestType !== "",
    homeRegionId: regionId,
  };

  const started = Date.now();
  const result = await ForecastEngine.forecast(
    input,
    db as unknown as Parameters<typeof ForecastEngine.forecast>[1],
    config,
  );
  const candidates = (result.top1 ? 1 : 0) + (result.alternative ? 1 : 0);
  console.log(`[v1-forecast] candidates=${candidates} duration_ms=${Date.now() - started}`);

  const data: Record<string, unknown> = {
    regionName: result.regionName,
    date: result.date,
    forest: result.forest,
    forest_label: forestLabel(input.forestType, null),
    top1: shapeSpecies(result.top1, result.weather),
    alternative: shapeSpecies(result.alternative, result.weather),
    weather: weatherBlock(result.weather),
    warnings: result.warnings,
  };
  if (result.noDataReason) data.noDataReason = result.noDataReason;
  return ok(data, req);
}));
