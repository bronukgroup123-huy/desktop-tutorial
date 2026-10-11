// ============================================================================
// Forecast Engine — DB helpers (без бізнес-логіки, group 8.1)
// ============================================================================

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
    .select("*")
    .eq("mushroom_type", mushroomType)
    .maybeSingle();

  if (error || !data) return null;
  return rowToRule(data);
}

export async function findAllRules(
  db: DbClient,
  mvpOnly = true
): Promise<SpeciesRule[]> {
  let query = db
    .from("expert_rules")
    .select("*")
    .order("legacy_id", { ascending: true });

  if (mvpOnly) {
    query = query.eq("mvp_stage", "mvp");
  }

  const { data, error } = await query;
  if (error || !data) return [];
  return data.map(rowToRule);
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
