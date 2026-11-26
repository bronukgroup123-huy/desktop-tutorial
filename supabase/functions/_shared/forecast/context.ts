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
import { fetchWeatherSeriesCached, weatherForDate } from "./weather-cache.ts";
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

/** Радіус «поруч із ділянкою» для знахідок спільноти: ділянка до 10×10 км + запас. */
export const CROWD_RADIUS_M = 10_000;

/**
 * Знахідки спільноти поруч із точкою прогнозу за 7 днів: підтверджені — за видом, негативні звіти — разом
 * (SQL crowd_counts). Збій — без поправок: прогноз рахується з погоди й лісу, як і без знахідок.
 */
async function fetchCrowd(
  db: ForecastDbClient,
  input: ForecastInput
): Promise<CrowdData> {
  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const empty: CrowdData = { verifiedPicks7d: 0, negativeReports7d: 0, indicatorSpecies: [], verifiedBySpecies: {} };
  try {
    const { data, error } = await db.rpc("crowd_counts", {
      p_lat: input.lat,
      p_lng: input.lng,
      p_radius_m: CROWD_RADIUS_M,
      p_since: since,
    });
    if (error || !data || typeof data !== "object") return empty;
    const r = data as { verified?: Record<string, unknown>; negatives?: unknown };
    const bySpecies: Record<string, number> = {};
    for (const [k, v] of Object.entries(r.verified ?? {})) {
      const n = Number(v);
      if (Number.isFinite(n) && n > 0) bySpecies[k] = n;
    }
    return {
      verifiedPicks7d: Object.values(bySpecies).reduce((a, b) => a + b, 0),
      negativeReports7d: Number(r.negatives) || 0,
      indicatorSpecies: [],  // §12.5: Rule 5 anti-double-counting
      verifiedBySpecies: bySpecies,
    };
  } catch {
    return empty;
  }
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
    const [weatherSeries, crowd] = await Promise.all([
      // B2.6: погода з кешу по сітці (≤ 1 запит до Open-Meteo на клітинку за 3 год)
      fetchWeatherSeriesCached(db, input.lat, input.lng),
      fetchCrowd(db, input),
    ]);

    // Стан погоди саме на день прогнозу: вікна закінчуються цим днем.
    const dateStr = input.date.toISOString().slice(0, 10);
    const weather = weatherForDate(weatherSeries, dateStr);

    // 3. Кумулятивний GDD (CT-11) — з таблиці gdd_state, а не ковзне вікно
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
      weatherSeries,
    };
  }
}
