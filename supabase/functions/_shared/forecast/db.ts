// ============================================================================
// Forecast Engine — DB helpers (без бізнес-логіки, group 8.1)
// ============================================================================

import type { FruitingParams } from "./fruiting.ts";
import type { SpeciesRule, ForestZoneRef, Wave } from "./types.ts";

/**
 * Мінімальний структурний тип Supabase-клієнта.
 * Навмисно без import з supabase-js — щоб unit-тести не тягли @types/node
 * через esm.sh у Deno typecheck.
 */
export interface DbClient {
  from(table: string): {
    select(cols?: string): any;
    eq(column: string, value: unknown): any;
    maybeSingle(): Promise<{ data: unknown; error: unknown }>;
    order(column: string, opts?: { ascending?: boolean }): any;
  };
  rpc(fn: string, params: Record<string, unknown>): Promise<{ data: unknown; error: unknown }>;
}

// ============================================================================
// expert_rules
// ============================================================================

export async function findRulesByType(
  db: DbClient,
  mushroomType: string
): Promise<SpeciesRule | null> {
  const { data, error } = await db
    .from("expert_rules")
    .select("*, mushroom_catalog(edibility)")
    .eq("mushroom_type", mushroomType)
    .maybeSingle();

  if (error || !data) return null;
  return forecastableRows([data as Record<string, unknown>]).length ? rowToRule(data as Record<string, unknown>) : null;
}

/**
 * Які види прогноз може показати (BACKEND_PLAN B2.4 «Отруйні — ніколи»): лише їстівні й умовно їстівні
 * за довідником. Вид без запису в довіднику чи з невідомою їстівністю теж не показується.
 */
export const FORECASTABLE_EDIBILITY: readonly string[] = ["edible", "conditionally_edible"];

/** Їстівність виду з вкладеного `mushroom_catalog(edibility)` (PostgREST віддає об'єкт або масив). */
export function ruleEdibility(row: Record<string, unknown>): string | null {
  const c = row.mushroom_catalog;
  const one = Array.isArray(c) ? c[0] : c;
  const e = one && typeof one === "object" ? (one as { edibility?: unknown }).edibility : null;
  return typeof e === "string" ? e : null;
}

/** Рядки правил, які можна прогнозувати; решту відкидає з попередженням у лозі. */
export function forecastableRows<T extends Record<string, unknown>>(rows: T[]): T[] {
  return rows.filter((row) => {
    const ok = FORECASTABLE_EDIBILITY.includes(ruleEdibility(row) ?? "");
    if (!ok) console.warn(`[forecast] правило ${String(row.mushroom_type)} пропущено: вид не їстівний або без довідника`);
    return ok;
  });
}

export async function findAllRules(
  db: DbClient,
  mvpOnly = true
): Promise<SpeciesRule[]> {
  let query = db
    .from("expert_rules")
    .select("*, mushroom_catalog(edibility)")
    .order("legacy_id", { ascending: true });

  if (mvpOnly) {
    query = query.eq("mvp_stage", "mvp");
  }

  const { data, error } = await query;
  if (error || !data) return [];
  return forecastableRows(data as Record<string, unknown>[]).map(rowToRule);
}

// ============================================================================
// forest_zones
// ============================================================================

export async function findForestZoneByPoint(
  db: DbClient,
  lat: number,
  lng: number
): Promise<ForestZoneRef | null> {
  // PostgREST не вміє ST_Contains напряму — викликаємо RPC (group 8.2).
  const { data, error } = await db.rpc("find_zone_by_point", {
    lat,
    lng,
  });

  if (error || !data) return null;

  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null;

  return {
    id: String(row.id),
    forest_type: (row.forest_type as ForestZoneRef["forest_type"]) ?? null,
    stand_age_years: row.stand_age_years ?? null,
    stand_age_confidence: row.stand_age_confidence
      ? Number(row.stand_age_confidence)
      : null,
    relief_type: (row.relief_type as ForestZoneRef["relief_type"]) ?? null,
    light_type: (row.light_type as ForestZoneRef["light_type"]) ?? null,
  };
}

// ============================================================================
// regions
// ============================================================================

export interface RegionRow {
  id: number;
  name: string;
  koatuu: string | null;
  katottg: string | null;
}

export async function findRegionById(
  db: DbClient,
  regionId: number
): Promise<RegionRow | null> {
  const { data, error } = await db
    .from("regions")
    .select("id, name, koatuu, katottg")
    .eq("id", regionId)
    .maybeSingle();

  if (error || !data) return null;
  return data as RegionRow;
}

// ============================================================================
// Mapper: snake_case (БД) → camelCase
// ============================================================================

export function rowToRule(row: Record<string, unknown>): SpeciesRule {
  return {
    id: String(row.id),
    legacyId: numOrNull(row.legacy_id),
    mushroomType: String(row.mushroom_type),
    nameUa: String(row.name_ua),
    nameLat: String(row.name_lat),

    fruitingTempMin: numOrNull(row.fruiting_temp_min),
    fruitingTempMax: numOrNull(row.fruiting_temp_max),
    fruitingTempPeakMin: numOrNull(row.fruiting_temp_peak_min),
    fruitingTempPeakMax: numOrNull(row.fruiting_temp_peak_max),
    myceliumTempMin: numOrNull(row.mycelium_temp_min),
    myceliumTempMax: numOrNull(row.mycelium_temp_max),

    humidityMin: numOrNull(row.humidity_min),
    rain3dMin: numOrNull(row.rain_3d_min),
    rain1dMin: numOrNull(row.rain_1d_min),
    rain2dMin: numOrNull(row.rain_2d_min),
    droughtDaysMin: numOrNull(row.drought_days_min),
    daysAfterRainMin: numOrNull(row.days_after_rain_min),
    daysAfterRainMax: numOrNull(row.days_after_rain_max),
    waterloggedPenalty: numOrNull(row.waterlogged_penalty),
    droughtThenRain: Boolean(row.drought_then_rain),

    forestType: strArray(row.forest_type),
    habitatType: strArray(row.habitat_type),
    reliefType: (strArray(row.relief_type) ?? []) as SpeciesRule["reliefType"],
    altitudeMin: numOrNull(row.altitude_min),
    altitudeMax: numOrNull(row.altitude_max),
    soilPhMin: numOrNull(row.soil_ph_min),
    soilPhMax: numOrNull(row.soil_ph_max),
    lightPreference: (row.light_preference as SpeciesRule["lightPreference"]) ?? null,
    standAgeMin: numOrNull(row.stand_age_min),
    standAgeMax: numOrNull(row.stand_age_max),
    prefersLowland: Boolean(row.prefers_lowland),
    prefersHilltop: Boolean(row.prefers_hilltop),

    seasonStart: String(row.season_start),
    seasonEnd: String(row.season_end),
    waveSpring: Boolean(row.wave_spring),
    waveSummer1: Boolean(row.wave_summer1),
    waveSummer2: Boolean(row.wave_summer2),
    waveAutumn: Boolean(row.wave_autumn),
    waveLate: Boolean(row.wave_late),
    peakWaves: (strArray(row.peak_waves) ?? []) as Wave[],
    peakMonths: intArray(row.peak_months),

    indicatorSpecies: strArray(row.indicator_species),
    shockRequired: Boolean(row.shock_required),
    microrefugiumDry: strOrNull(row.microrefugium_dry),
    microrefugiumWet: strOrNull(row.microrefugium_wet),

    regionIds: intArray(row.region_ids),
    weight: numOrNull(row.weight) ?? 1.0,
    mvpStage: (row.mvp_stage as SpeciesRule["mvpStage"]) ?? "mvp",
    lastCalibratedAt: strOrNull(row.last_calibrated_at),

    fruiting: fruitingParams(row),
  };
}

const TRIGGERS = ["rain", "rain_cool", "spring_warm", "thaw"] as const;

/**
 * Параметри плодоношення з рядка правил; без колонок (стара БД, тестові набори) — середні
 * значення: дощ ≥ 15 мм за 3 дні, 70 градусо-днів, хвиля 9 днів, ґрунт — у межах плодоношення.
 */
export function fruitingParams(row: Record<string, unknown>): FruitingParams {
  const trigger = String(row.fruiting_trigger ?? "rain");
  const tMin = numOrNull(row.fruiting_temp_min);
  const tMax = numOrNull(row.fruiting_temp_max);
  return {
    trigger: (TRIGGERS as readonly string[]).includes(trigger) ? trigger as FruitingParams["trigger"] : "rain",
    triggerRainMm: numOrNull(row.trigger_rain_mm) ?? numOrNull(row.rain_3d_min) ?? 15,
    maturationDd: numOrNull(row.maturation_dd) ?? 70,
    ddBase: numOrNull(row.dd_base) ?? 4,
    flushDays: numOrNull(row.flush_days) ?? 9,
    soilTempMin: numOrNull(row.soil_temp_min) ?? (tMin !== null ? tMin + 2 : 8),
    soilTempMax: numOrNull(row.soil_temp_max) ?? (tMax ?? 22),
  };
}

// helpers

function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  return Number.isNaN(n) ? null : n;
}

function strOrNull(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  return String(v);
}

function strArray(v: unknown): string[] {
  if (Array.isArray(v)) return v.map(String);
  return [];
}

function intArray(v: unknown): number[] {
  if (Array.isArray(v)) return v.map((x) => Number(x)).filter((x) => !Number.isNaN(x));
  return [];
}
