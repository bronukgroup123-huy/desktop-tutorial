// ============================================================================
// Forecast Engine — ContextBuilder (group 8.2)
// Збирає контекст: погода, crowd, wave, forest_zone. Нічого не матчить.
// ============================================================================

import type {
  ForecastInput,
  ForecastContext,
  FeatureFlags,
  ForestZoneData,
  CrowdData,
} from "./types.ts";
import { fetchWeather } from "./weather.ts";
import { detectWave } from "./wave.ts";

// Реекспорт для зручності
export { fetchWeather } from "./weather.ts";
export { detectWave } from "./wave.ts";

// ────────────────────────────────────────────────────────────────────
// DB helpers
// ────────────────────────────────────────────────────────────────────

/**
 * Мінімальний структурний тип Supabase-клієнта.
 * Навмисно без import з supabase-js — щоб unit-тести не тягли @types/node
 * через esm.sh у Deno typecheck (див. db.ts, flags.ts).
 */
export interface ForecastDbClient {
  from(table: string): {
    select(cols?: string, opts?: Record<string, unknown>): any;
    eq(column: string, value: unknown): any;
    gte(column: string, value: unknown): any;
    maybeSingle?(): Promise<{ data: unknown; error: unknown }>;
    single?(): Promise<{ data: unknown; error: unknown }>;
  };
  rpc(
    fn: string,
    params: Record<string, unknown>
  ): Promise<{ data: unknown; error: unknown }>;
}

async function findForestZone(
  db: ForecastDbClient,
  lat: number,
  lng: number
): Promise<ForestZoneData | null> {
  const { data, error } = await db.rpc("find_zone_by_point", { lat, lng });

  if (error || !data) return null;

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null;

  return {
    standAgeYears: row.stand_age_years ?? null,
    standAgeSource: row.stand_age_source ?? null,
    standAgeConfidence: Number(row.stand_age_confidence) || 0,
    reliefType: (row.relief_type as ForestZoneData["reliefType"]) ?? null,
    lightType: row.light_type ?? null,
  };
}

async function fetchCrowd(
  db: ForecastDbClient,
  input: ForecastInput
): Promise<CrowdData> {
  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  const { count: picksCount } = await db
    .from("mushroom_picks")
    .select("*", { count: "exact", head: true })
    .eq("verification_status", "verified")
    .eq("is_negative", false)
    .gte("created_at", since);

  const { count: negativesCount } = await db
    .from("mushroom_picks")
    .select("*", { count: "exact", head: true })
    .eq("is_negative", true)
    .gte("created_at", since);

  return {
    verifiedPicks7d: picksCount ?? 0,
    negativeReports7d: negativesCount ?? 0,
    indicatorSpecies: [],  // §12.5: Rule 5 anti-double-counting
  };
}

/**
 * Отримати кумулятивний GDD для регіону на дату з таблиці gdd_state.
 * Повертає 0, якщо дані ще не обчислено (graceful degradation).
 */
async function fetchCumulativeGdd(
  db: ForecastDbClient,
  regionId: number | null,
  dateStr: string
): Promise<number> {
  if (!regionId) return 0;
  try {
    const { data, error } = await db.rpc("get_gdd_state", {
      p_region_id: regionId,
      p_date: dateStr,
    });
    if (error || data == null) return 0;
    const v = Number(data);
    return Number.isNaN(v) ? 0 : v;
  } catch {
    return 0;
  }
}

// ────────────────────────────────────────────────────────────────────
// ContextBuilder
// ────────────────────────────────────────────────────────────────────

export class ContextBuilder {
  static async build(
    input: ForecastInput,
    db: ForecastDbClient,
    config: FeatureFlags
  ): Promise<ForecastContext> {
    // 1. Forest zone (stand_age, relief, light)
    const forestZone = await findForestZone(db, input.lat, input.lng);

    const standAge = forestZone?.standAgeYears ?? null;
    const standAgeConfidence = forestZone?.standAgeConfidence ?? 0;

    // F-13, F-14 — feature flags
    const reliefType = config.relief_enabled
      ? (forestZone?.reliefType ?? null)
      : null;
    const lightType = config.light_enabled
      ? (forestZone?.lightType ?? null)
      : null;

    // 2. Weather (паралельно з crowd)
    const [weather, crowd] = await Promise.all([
      fetchWeather(input.lat, input.lng),
      fetchCrowd(db, input),
    ]);

    // 3. Кумулятивний GDD (CT-11) — з таблиці gdd_state, а не ковзне вікно
    const dateStr = input.date.toISOString().slice(0, 10);
    const cumulativeGdd = input.homeRegionId
      ? await fetchCumulativeGdd(db, input.homeRegionId, dateStr)
      : 0;

    // 4. Хвиля (GDD + latitude) — використовує кумулятивний GDD
    const wave = detectWave(input.date, input.lat, cumulativeGdd);

    // 4. FIX 2.6: розділені прапорці
    const forestTypeUnknown =
      !input.forestConfirmed ||
      input.forestType === null ||
      input.forestType === "any";

    const standAgeUnknown = standAge === null || standAgeConfidence < 0.5;

    // 5. Регіон — у 8.2 regions порожній (seed у 9.1)
    let regionName: string | null = null;
    if (input.homeRegionId) {
      const { data } = await db
        .from("regions")
        .select("name")
        .eq("id", input.homeRegionId)
        .maybeSingle();
      regionName = data?.name ?? null;
    }

    return {
      input,
      weather,
      crowd,
      wave,
      forestTypeUnknown,
      standAgeUnknown,
      standAge,
      standAgeConfidence,
      reliefType,
      lightType,
      cumulativeGdd,
      config,
      regionName,
      computedAt: new Date().toISOString(),
    };
  }
}
