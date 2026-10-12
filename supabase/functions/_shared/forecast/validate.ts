// ============================================================================
// Forecast Engine — валідація входу Edge Function /forecast (group 8.6c)
//
// Чистий модуль БЕЗ supabase-js / Deno.serve — щоб unit-тести не тягли
// @types/node через esm.sh (конвенція db.ts / context.ts / flags.ts).
// ============================================================================

import type { ForecastInput } from "./types.ts";

export type ValidateResult =
  | { ok: true; input: ForecastInput }
  | { ok: false; status: number; error: string; message?: string };

/** Валідація body → ForecastInput (або error + HTTP-status). */
export function validateInput(body: unknown): ValidateResult {
  const b = (body ?? {}) as Record<string, unknown>;
  const { lat, lng, date, forestType, forestConfirmed, homeRegionId } = b;

  if (
    typeof lat !== "number" || !Number.isFinite(lat) ||
    typeof lng !== "number" || !Number.isFinite(lng) ||
    lat < -90 || lat > 90 ||
    lng < -180 || lng > 180
  ) {
    return {
      ok: false,
      status: 400,
      error: "invalid_coordinates",
      message: "lat/lng мають бути числами в межах [-90,90] / [-180,180]",
    };
  }

  const parsedDate =
    date === undefined || date === null || date === ""
      ? new Date()
      : new Date(String(date));
  if (Number.isNaN(parsedDate.getTime())) {
    return { ok: false, status: 400, error: "invalid_date" };
  }

  const input: ForecastInput = {
    lat,
    lng,
    date: parsedDate,
    forestType: (forestType ?? null) as ForecastInput["forestType"],
    forestConfirmed: forestConfirmed === true,
    homeRegionId: typeof homeRegionId === "number" ? homeRegionId : null,
  };
  return { ok: true, input };
}
